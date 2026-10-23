local T = require("./TestKit")
local Config = require("../src/shared/Config")
local MapLayout = require("../src/shared/MapLayout")

local layout = MapLayout.build(Config)

local function count(kind: string): number
	local n = 0
	for _, p in layout.pieces do
		if p.kind == kind then
			n += 1
		end
	end
	return n
end

local function overlapsAny(r: MapLayout.Rect, list: { MapLayout.Rect }): boolean
	for _, other in list do
		if MapLayout.overlaps(r, other) then
			return true
		end
	end
	return false
end

T.describe("MapLayout", function()
	T.it("builds every kind of piece", function()
		T.eq(count("ground"), 1)
		T.truthy(count("path") >= 6, "paths")
		T.truthy(count("solid") > 50, "decorations")
		T.truthy(#layout.pieces < 2000, "part budget")
	end)

	T.it("garden footprints match PlotService's grid", function()
		local r = MapLayout.gardenFootprint(Config, 1)
		-- Slot 1: column 0, row 0 of a 4-wide grid; garden is 47 wide.
		T.near(r.minX, -1.5 * Config.World.gardenSpacing - 23.5)
		T.near(r.maxX - r.minX, 47)
		T.near(r.minZ, 0.5 * Config.World.gardenSpacing + 20 - 22)
	end)

	T.it("path tiles never overlap each other (no z-fighting)", function()
		for i, a in layout.paths do
			for j = i + 1, #layout.paths do
				T.truthy(not MapLayout.overlaps(a, layout.paths[j]), "paths " .. i .. " and " .. j)
			end
		end
	end)

	T.it("paths stay off the gardens, stands and stage", function()
		for i, r in layout.paths do
			T.truthy(not overlapsAny(r, layout.reserved.gardens), "path " .. i .. " on a garden")
		end
		local market, fair
		for _, p in layout.pieces do
			if p.name == "MarketPlaza" then
				market = MapLayout.footprint(p)
			elseif p.name == "FairPlaza" then
				fair = MapLayout.footprint(p)
			end
		end
		for _, s in layout.reserved.stands do
			T.truthy(MapLayout.overlaps(s, market), "stand sits on the market plaza")
		end
		T.truthy(MapLayout.overlaps(layout.reserved.stage, fair), "stage sits on the fair plaza")
	end)

	T.it("decorations stay clear of everything the game uses", function()
		local blocked = {}
		for _, list in { layout.reserved.gardens, layout.reserved.stands, layout.paths } do
			for _, r in list do
				table.insert(blocked, r)
			end
		end
		table.insert(blocked, layout.reserved.stage)
		table.insert(blocked, layout.reserved.spawn)
		for _, p in layout.pieces do
			if p.kind == "solid" then
				T.truthy(not overlapsAny(MapLayout.footprint(p), blocked), p.name .. " blocks the game")
			elseif p.kind == "onPlaza" then
				local fp = MapLayout.footprint(p)
				T.truthy(not overlapsAny(fp, layout.reserved.gardens), p.name .. " on a garden")
				T.truthy(not overlapsAny(fp, layout.reserved.stands), p.name .. " on a stand")
				T.truthy(not MapLayout.overlaps(fp, layout.reserved.stage), p.name .. " on the stage")
				T.truthy(not MapLayout.overlaps(fp, layout.reserved.spawn), p.name .. " on the spawn")
			end
		end
	end)

	T.it("everything fits inside the border", function()
		local b = layout.bounds
		for _, p in layout.pieces do
			local fp = MapLayout.footprint(p)
			T.truthy(
				fp.minX >= b.minX - 0.01
					and fp.maxX <= b.maxX + 0.01
					and fp.minZ >= b.minZ - 0.01
					and fp.maxZ <= b.maxZ + 0.01,
				p.name .. " outside the map"
			)
		end
	end)

	T.it("is the same every build", function()
		local again = MapLayout.build(Config)
		T.eq(#again.pieces, #layout.pieces)
		T.eq(again.pieces[#again.pieces].name, layout.pieces[#layout.pieces].name)
	end)
end)

return nil
