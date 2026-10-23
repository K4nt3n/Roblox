--!strict
--[[
	MapLayout: pure description of the studded world map. No requires, no Roblox
	services; server/Map/MapBuilder turns the pieces into Parts.

	Everything is derived from Config so the map wraps the layout the game already
	uses: PlotService's garden grid (Config.World), the shop/market/fair stands and
	the Fair Day stage (Config.FairDay.stagePosition).

	  z (south)
	  ^   back lane
	  |   [garden][garden][garden][garden]   <- garden slots, lanes between columns
	  |   [garden][garden][garden][garden]
	  |   ===== garden lane ===== (lamps)
	  |   market plaza: stands, spawn, flower beds
	  |   fair path + "Fair" arch
	  |   fair plaza: stage, tents, bunting, white fence   pond (west)
	  +----------------------------------------> x

	Piece kinds:
	  "ground"   the grass slab (top at y = 0)
	  "path"     flat walkable tiles (top at y = 0.2); never overlap each other
	  "solid"    decoration; must stay off paths, gardens, stands, stage and spawn
	  "onPlaza"  decoration that stands on a plaza on purpose (tents, bunting, beds)
	  "attached" sits on a game part on purpose (stand awnings)
]]

local MapLayout = {}

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }
export type Color = { number }
export type Piece = {
	group: string,
	name: string,
	kind: string,
	pos: { number }, -- center
	size: { number },
	color: Color,
	yaw: number?, -- degrees around Y
	shape: string?, -- "Block" (default) | "Wedge" | "Cylinder"
	studs: boolean?,
	collide: boolean?,
	neon: boolean?,
	light: boolean?,
	text: string?,
}
export type Layout = {
	pieces: { Piece },
	bounds: Rect,
	spawn: { number },
	-- Areas the game itself uses; decorations must stay out of them.
	reserved: { gardens: { Rect }, stands: { Rect }, stage: Rect, spawn: Rect },
	paths: { Rect },
}

local PATH_TOP = 0.2
local PATH_THICK = 0.4

local function rect(minX: number, maxX: number, minZ: number, maxZ: number): Rect
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

function MapLayout.rect(minX: number, maxX: number, minZ: number, maxZ: number): Rect
	return rect(minX, maxX, minZ, maxZ)
end

-- Strict overlap: rects that only touch along an edge do not overlap.
function MapLayout.overlaps(a: Rect, b: Rect): boolean
	return a.minX < b.maxX and b.minX < a.maxX and a.minZ < b.maxZ and b.minZ < a.maxZ
end

function MapLayout.grow(r: Rect, by: number): Rect
	return rect(r.minX - by, r.maxX + by, r.minZ - by, r.maxZ + by)
end

-- Top-down footprint of a piece (yaw is only ever a multiple of 90).
function MapLayout.footprint(p: Piece): Rect
	local sx, sz = p.size[1], p.size[3]
	local yaw = (p.yaw or 0) % 180
	if math.abs(yaw - 90) < 1 then
		sx, sz = sz, sx
	end
	return rect(p.pos[1] - sx / 2, p.pos[1] + sx / 2, p.pos[3] - sz / 2, p.pos[3] + sz / 2)
end

-- Mirrors PlotService's fallback grid and garden size. The rect covers the garden base,
-- the champion pad and the spot GetSpawnCFrame puts the player on.
function MapLayout.gardenFootprint(config: any, slot: number): Rect
	local w = config.World
	local col = (slot - 1) % 4
	local row = (slot - 1) // 4
	local cx = (col - 1.5) * w.gardenSpacing
	local cz = (row + 0.5) * w.gardenSpacing + 20
	local rows = math.ceil(config.Plots.maxPlots / w.plotsPerRow)
	local width = w.plotsPerRow * (w.plotSize + w.plotGap) + w.plotGap
	local depth = rows * (w.plotSize + w.plotGap) + w.plotGap
	local championSize = w.plotSize * 1.6
	local padCenter = depth / 2 + 4 + championSize / 2 + 2
	local spawnZ = padCenter + (championSize + 4) / 2 + 4
	return rect(cx - width / 2, cx + width / 2, cz - (depth + 8) / 2, cz + spawnZ + 1)
end

local function union(rects: { Rect }): Rect
	local r = rect(math.huge, -math.huge, math.huge, -math.huge)
	for _, x in rects do
		r.minX = math.min(r.minX, x.minX)
		r.maxX = math.max(r.maxX, x.maxX)
		r.minZ = math.min(r.minZ, x.minZ)
		r.maxZ = math.max(r.maxZ, x.maxZ)
	end
	return r
end

-- Small deterministic hash so the map looks hand-placed but is identical every build.
local function hash(a: number, b: number): number
	local n = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return n - math.floor(n)
end

function MapLayout.build(config: any): Layout
	local m = config.Map
	local c = m.colors
	local pieces: { Piece } = {}
	local paths: { Rect } = {}

	local function add(p: Piece): Piece
		table.insert(pieces, p)
		return p
	end

	local function block(
		group: string,
		name: string,
		kind: string,
		x: number,
		y: number,
		z: number,
		sx: number,
		sy: number,
		sz: number,
		color: Color,
		extra: { [string]: any }?
	): Piece
		local p: Piece = {
			group = group,
			name = name,
			kind = kind,
			pos = { x, y, z },
			size = { sx, sy, sz },
			color = color,
			studs = true,
		}
		if extra then
			for k, v in extra do
				(p :: any)[k] = v
			end
		end
		return add(p)
	end

	local function tile(group: string, name: string, r: Rect, color: Color)
		table.insert(paths, r)
		block(
			group,
			name,
			"path",
			(r.minX + r.maxX) / 2,
			PATH_TOP - PATH_THICK / 2,
			(r.minZ + r.maxZ) / 2,
			r.maxX - r.minX,
			PATH_THICK,
			r.maxZ - r.minZ,
			color
		)
	end

	---------------------------------------------------------------------------
	-- What the game already places
	---------------------------------------------------------------------------
	local gardens: { Rect } = {}
	for slot = 1, config.World.gardenSlots do
		table.insert(gardens, MapLayout.gardenFootprint(config, slot))
	end
	local g = union(gardens)

	local stands: { Rect } = {}
	for _, def in config.World.stands do
		local x, z = def.position[1], def.position[3]
		table.insert(stands, rect(x - 5, x + 5, z - 2, z + 2)) -- PlotService stands are 10 x 6 x 4
	end
	local s = union(stands)
	local standTop = 6

	local sp = config.FairDay.stagePosition
	local stage = rect(sp[1] - 18, sp[1] + 18, sp[3] - 9, sp[3] + 9) -- floor is 36 x 18

	---------------------------------------------------------------------------
	-- Paths
	---------------------------------------------------------------------------
	local lw = m.laneWidth
	-- Column edges of the garden grid, west to east.
	local columns: { Rect } = {}
	for col = 0, 3 do
		local inCol = {}
		for slot, r in gardens do
			if (slot - 1) % 4 == col then
				table.insert(inCol, r)
			end
		end
		if #inCol > 0 then
			table.insert(columns, union(inCol))
		end
	end

	local laneMaxZ = g.minZ - 2
	local laneMinZ = laneMaxZ - lw
	local laneMinX = g.minX - 2 - lw
	local laneMaxX = g.maxX + 2 + lw
	local backMinZ = g.maxZ + 2
	local backMaxZ = backMinZ + lw

	tile("Paths", "GardenLane", rect(laneMinX, laneMaxX, laneMinZ, laneMaxZ), c.path)
	tile("Paths", "BackLane", rect(laneMinX, laneMaxX, backMinZ, backMaxZ), c.path)
	tile("Paths", "WestLane", rect(laneMinX, laneMinX + lw, laneMaxZ, backMinZ), c.path)
	tile("Paths", "EastLane", rect(laneMaxX - lw, laneMaxX, laneMaxZ, backMinZ), c.path)
	local centerLaneX: number? = nil
	for i = 1, #columns - 1 do
		local left, right = columns[i].maxX, columns[i + 1].minX
		local width = math.min(lw, right - left - 4)
		if width >= 4 then
			local mid = (left + right) / 2
			tile("Paths", "ColumnLane" .. i, rect(mid - width / 2, mid + width / 2, laneMaxZ, backMinZ), c.path)
			if not centerLaneX or math.abs(mid) < math.abs(centerLaneX) then
				centerLaneX = mid
			end
		end
	end

	-- Market plaza: around the stands, up to the garden lane.
	local market = rect(math.min(s.minX - 20, -50), math.max(s.maxX + 20, 50), s.minZ - 12, laneMinZ)
	tile("Market", "MarketPlaza", market, c.plaza)

	-- Fair plaza around the stage, joined to the market by a short path.
	local fairPathLen = 12
	local fair = rect(stage.minX - 42, stage.maxX + 42, stage.minZ - 26, market.minZ - fairPathLen)
	if fair.maxZ < stage.maxZ + 10 then
		-- The stage was moved close to the market: shrink the path instead of overlapping.
		fair.maxZ = math.min(stage.maxZ + 10, market.minZ)
	end
	local fairPathHalf = 8
	tile("Fair", "FairPlaza", fair, c.fairPlaza)
	if fair.maxZ < market.minZ then
		tile("Fair", "FairPath", rect(-fairPathHalf, fairPathHalf, fair.maxZ, market.minZ), c.path)
	end

	-- Spawn: on the market plaza between the stands and the garden lane.
	local spawn = { (market.minX + market.maxX) / 2, 0.5, (s.maxZ + market.maxZ) / 2 }
	local spawnRect = rect(spawn[1] - 4, spawn[1] + 4, spawn[3] - 4, spawn[3] + 4)

	---------------------------------------------------------------------------
	-- Ground and border
	---------------------------------------------------------------------------
	local bounds = rect(laneMinX - 24, laneMaxX + 24, fair.minZ - 24, backMaxZ + 20)
	local bw, bd = bounds.maxX - bounds.minX, bounds.maxZ - bounds.minZ
	local bcx, bcz = (bounds.minX + bounds.maxX) / 2, (bounds.minZ + bounds.maxZ) / 2
	block("Ground", "Grass", "ground", bcx, -1, bcz, bw, 2, bd, c.grass)

	local hedgeH, hedgeT = 5, 4
	block("Border", "HedgeNorth", "solid", bcx, hedgeH / 2, bounds.minZ + hedgeT / 2, bw, hedgeH, hedgeT, c.hedge)
	block("Border", "HedgeSouth", "solid", bcx, hedgeH / 2, bounds.maxZ - hedgeT / 2, bw, hedgeH, hedgeT, c.hedge)
	block(
		"Border",
		"HedgeWest",
		"solid",
		bounds.minX + hedgeT / 2,
		hedgeH / 2,
		bcz,
		hedgeT,
		hedgeH,
		bd - hedgeT * 2,
		c.hedge
	)
	block(
		"Border",
		"HedgeEast",
		"solid",
		bounds.maxX - hedgeT / 2,
		hedgeH / 2,
		bcz,
		hedgeT,
		hedgeH,
		bd - hedgeT * 2,
		c.hedge
	)

	---------------------------------------------------------------------------
	-- Market: stand awnings, flower beds, spawn pad
	---------------------------------------------------------------------------
	for i, def in config.World.stands do
		local x, z = def.position[1], def.position[3]
		for strip = 0, 4 do
			block(
				"Market",
				def.name .. "Awning" .. strip,
				"attached",
				x - 4 + strip * 2,
				standTop + 0.3,
				z + 1,
				2,
				0.6,
				6,
				if (strip + i) % 2 == 0 then c.stripeA else c.stripeB,
				{ collide = false }
			)
		end
	end

	local bedIndex = 0
	local function flowerBed(x: number, z: number, along: string)
		bedIndex += 1
		local bx, bz = if along == "z" then 3 else 6, if along == "z" then 6 else 3
		block("Market", "FlowerBed" .. bedIndex, "onPlaza", x, PATH_TOP + 0.3, z, bx, 0.6, bz, c.soil)
		for f = -1, 1 do
			local fx = if along == "z" then x else x + f * 2
			local fz = if along == "z" then z + f * 2 else z
			local color = c.flowers[(bedIndex + f + 1) % #c.flowers + 1]
			block("Market", "Flower" .. bedIndex .. "_" .. (f + 2), "onPlaza", fx, PATH_TOP + 1.1, fz, 1, 1, 1, color, {
				collide = false,
			})
		end
	end
	-- Along the west and east edges of the market plaza, and the north edge beside the fair path.
	for z = market.minZ + 6, market.maxZ - 6, 10 do
		flowerBed(market.minX + 2.5, z, "z")
		flowerBed(market.maxX - 2.5, z, "z")
	end
	for x = fairPathHalf + 6, market.maxX - 10, 10 do
		flowerBed(x, market.minZ + 2.5, "x")
		flowerBed(-x, market.minZ + 2.5, "x")
	end

	---------------------------------------------------------------------------
	-- Arches
	---------------------------------------------------------------------------
	local function arch(name: string, x: number, z: number, span: number, label: string)
		local h = 12
		block("Arches", name .. "PillarW", "solid", x - span / 2 - 1, h / 2, z, 2, h, 2, c.archPillar)
		block("Arches", name .. "PillarE", "solid", x + span / 2 + 1, h / 2, z, 2, h, 2, c.archPillar)
		block("Arches", name .. "Sign", "attached", x, h + 1.5, z, span + 6, 3, 1.2, c.archBeam, { text = label })
	end
	if centerLaneX then
		arch("GardenArch", centerLaneX, laneMaxZ + 1.5, lw, "Gardens")
	end
	arch("FairArch", 0, fair.maxZ + 1, fairPathHalf * 2, "Veggie Fair")

	---------------------------------------------------------------------------
	-- Fair plaza: fence, tents, bunting
	---------------------------------------------------------------------------
	local function fenceRun(name: string, x1: number, z1: number, x2: number, z2: number)
		local len = math.max(math.abs(x2 - x1), math.abs(z2 - z1))
		if len < 2 then
			return
		end
		local alongX = math.abs(x2 - x1) >= math.abs(z2 - z1)
		local mx, mz = (x1 + x2) / 2, (z1 + z2) / 2
		local sx, sz = if alongX then len else 0.4, if alongX then 0.4 else len
		block("Fence", name .. "RailLow", "solid", mx, 1.2, mz, sx, 0.4, sz, c.fence)
		block("Fence", name .. "RailHigh", "solid", mx, 2.4, mz, sx, 0.4, sz, c.fence)
		local posts = math.max(1, math.floor(len / 4))
		for i = 0, posts do
			local t = i / posts
			block(
				"Fence",
				name .. "Post" .. i,
				"solid",
				x1 + (x2 - x1) * t,
				1.5,
				z1 + (z2 - z1) * t,
				0.8,
				3,
				0.8,
				c.fence
			)
		end
	end
	-- Just outside the plaza edge; the north side leaves a gap for the fair path and arch.
	local f = MapLayout.grow(fair, 1)
	local gap = fairPathHalf + 2
	fenceRun("FenceSouthSide", f.minX, f.minZ, f.maxX, f.minZ)
	fenceRun("FenceWest", f.minX, f.minZ, f.minX, f.maxZ)
	fenceRun("FenceEast", f.maxX, f.minZ, f.maxX, f.maxZ)
	fenceRun("FenceNorthW", f.minX, f.maxZ, -gap, f.maxZ)
	fenceRun("FenceNorthE", gap, f.maxZ, f.maxX, f.maxZ)

	local function tent(name: string, x: number, z: number, accent: Color)
		local w, d, h, roof = 12, 10, 5, 4
		block("Fair", name .. "Base", "onPlaza", x, PATH_TOP + h / 2, z, w, h, d, c.stripeB)
		block("Fair", name .. "Door", "onPlaza", x, PATH_TOP + 1.75, z + d / 2 + 0.05, 4, 3.5, 0.1, accent, {
			studs = false,
			collide = false,
		})
		for strip = 0, w / 2 - 1 do
			local sx = x - w / 2 + 1 + strip * 2
			local color = if strip % 2 == 0 then accent else c.stripeB
			for side = 0, 1 do
				block(
					"Fair",
					name .. "Roof" .. strip .. "_" .. side,
					"onPlaza",
					sx,
					PATH_TOP + h + roof / 2,
					z + (if side == 0 then d / 4 else -d / 4),
					2,
					roof,
					d / 2,
					color,
					{ shape = "Wedge", yaw = if side == 0 then 0 else 180, studs = false }
				)
			end
		end
	end
	local stageX, stageZ = (stage.minX + stage.maxX) / 2, (stage.minZ + stage.maxZ) / 2
	tent("TentWest", stage.minX - 18, stageZ + 2, c.stripeA)
	tent("TentEast", stage.maxX + 18, stageZ + 2, c.tentB)

	-- Bunting behind the stage: two striped poles and a row of hanging flags.
	local poleZ = stage.minZ - 3
	local poleH = 14
	for side, px in { stage.minX - 2, stage.maxX + 2 } do
		block("Fair", "BuntingPole" .. side, "onPlaza", px, PATH_TOP + poleH / 2, poleZ, 1, poleH, 1, c.stripeA)
	end
	local flagCount = math.floor((stage.maxX - stage.minX + 4) / 2.5)
	for i = 1, flagCount - 1 do
		local t = i / flagCount
		local fx = stage.minX - 2 + (stage.maxX - stage.minX + 4) * t
		local sag = math.sin(t * math.pi) * 2
		block(
			"Fair",
			"Flag" .. i,
			"onPlaza",
			fx,
			PATH_TOP + poleH - 1.5 - sag,
			poleZ,
			1.4,
			1.8,
			0.2,
			c.flags[(i - 1) % #c.flags + 1],
			{ collide = false, studs = false }
		)
	end
	block(
		"Fair",
		"BuntingRope",
		"onPlaza",
		stageX,
		PATH_TOP + poleH - 0.5,
		poleZ,
		stage.maxX - stage.minX + 4,
		0.2,
		0.2,
		c.lampPost,
		{
			collide = false,
			studs = false,
		}
	)

	---------------------------------------------------------------------------
	-- Pond (west of the fair)
	---------------------------------------------------------------------------
	local pond = rect(bounds.minX + 14, f.minX - 10, fair.minZ + 4, fair.maxZ - 4)
	if pond.maxX - pond.minX >= 16 and pond.maxZ - pond.minZ >= 16 then
		local px, pz = (pond.minX + pond.maxX) / 2, (pond.minZ + pond.maxZ) / 2
		local pw, pd = pond.maxX - pond.minX, pond.maxZ - pond.minZ
		block("Pond", "Rim", "solid", px, 0, pz, pw + 4, 0.6, pd + 4, c.plaza)
		block("Pond", "Water", "solid", px, 0.25, pz, pw, 0.5, pd, c.water)
		for i = 1, 3 do
			local lx = pond.minX + pw * (0.25 * i)
			local lz = pond.minZ + pd * (0.3 + 0.2 * (i % 2))
			block("Pond", "LilyPad" .. i, "solid", lx, 0.8, lz, 0.2, 3, 3, c.lily, {
				shape = "Cylinder",
				collide = false,
				studs = false,
			})
		end
	end

	---------------------------------------------------------------------------
	-- Lamps along the garden lane
	---------------------------------------------------------------------------
	local lampZ = laneMinZ - 2
	local lampStep = 32
	local lampIndex = 0
	local function lamp(x: number, z: number)
		lampIndex += 1
		block("Lamps", "LampPost" .. lampIndex, "solid", x, 3.5, z, 1, 7, 1, c.lampPost)
		block("Lamps", "LampHead" .. lampIndex, "solid", x, 7.75, z, 2, 1.5, 2, c.lampLight, {
			neon = true,
			light = true,
			studs = false,
		})
	end
	for x = 0, laneMaxX, lampStep do
		if x > market.maxX + 2 then
			lamp(x, lampZ)
			lamp(-x, lampZ)
		end
	end

	---------------------------------------------------------------------------
	-- Trees on every free patch of grass
	---------------------------------------------------------------------------
	local reserved: { Rect } = {}
	for _, list in { gardens, stands, paths } do
		for _, r in list do
			table.insert(reserved, r)
		end
	end
	table.insert(reserved, stage)
	table.insert(reserved, spawnRect)
	table.insert(reserved, MapLayout.grow(pond, 2))
	for _, p in pieces do
		if p.kind == "solid" or p.kind == "onPlaza" then
			table.insert(reserved, MapLayout.footprint(p))
		end
	end

	local treeIndex = 0
	local function tree(x: number, z: number, big: boolean)
		treeIndex += 1
		local n = "Tree" .. treeIndex
		local trunkH = if big then 7 else 5
		local leaf = if big then 9 else 7
		block("Trees", n .. "Trunk", "solid", x, trunkH / 2, z, 2, trunkH, 2, c.trunk)
		block("Trees", n .. "Leaves", "solid", x, trunkH + leaf / 2 - 1, z, leaf, leaf - 2, leaf, c.leaves)
		block("Trees", n .. "Top", "solid", x, trunkH + leaf - 1.5, z, leaf - 4, 3, leaf - 4, c.leavesLight)
	end
	local step = 22
	local inner = MapLayout.grow(bounds, -(hedgeT + 7))
	for x = inner.minX, inner.maxX, step do
		for z = inner.minZ, inner.maxZ, step do
			local r = hash(x, z)
			local tx = x + (r - 0.5) * 6
			local tz = z + (hash(z, x) - 0.5) * 6
			local big = r > 0.5
			local half = (if big then 9 else 7) / 2 + 1.5
			local spot = rect(tx - half, tx + half, tz - half, tz + half)
			local free = r < 0.85
			for _, res in reserved do
				if not free then
					break
				end
				if MapLayout.overlaps(spot, res) then
					free = false
				end
			end
			if free then
				tree(tx, tz, big)
				table.insert(reserved, spot)
			end
		end
	end

	---------------------------------------------------------------------------
	-- Spawn pad marker (MapBuilder makes this one a SpawnLocation)
	---------------------------------------------------------------------------
	block("Market", "Spawn", "attached", spawn[1], spawn[2], spawn[3], 8, 1, 8, c.spawn)

	return {
		pieces = pieces,
		bounds = bounds,
		spawn = spawn,
		reserved = { gardens = gardens, stands = stands, stage = stage, spawn = spawnRect },
		paths = paths,
	}
end

return MapLayout
