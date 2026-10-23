--!strict
--[[
	StudMath: pure helpers for the studded look. No requires.

	* upFace: which face of a part points up, from the Y components of its
	  RightVector, UpVector and LookVector. The island is made of rotated wedges,
	  so the face that looks up is often not "Top".
	* vivid: brighter, more saturated colour (channels 0..1), via HSV.
]]

local StudMath = {}

-- Returns "Top" | "Bottom" | "Right" | "Left" | "Front" | "Back", or nil when no face
-- points up within ~45 degrees (walls, tilted rocks).
function StudMath.upFace(rightY: number, upY: number, lookY: number): string?
	local faces = {
		{ "Top", upY },
		{ "Bottom", -upY },
		{ "Right", rightY },
		{ "Left", -rightY },
		{ "Front", lookY }, -- Front's normal is the LookVector
		{ "Back", -lookY },
	}
	local best, bestY = nil, 0.7
	for _, f in faces do
		if f[2] > bestY then
			best, bestY = f[1], f[2]
		end
	end
	return best
end

local function toHsv(r: number, g: number, b: number): (number, number, number)
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then
			h = ((g - b) / d) % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if max > 0 then d / max else 0, max
end

local function fromHsv(h: number, s: number, v: number): (number, number, number)
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, q
end

function StudMath.vivid(
	r: number,
	g: number,
	b: number,
	saturation: number,
	brightness: number
): (number, number, number)
	local h, s, v = toHsv(r, g, b)
	return fromHsv(h, math.clamp(s * saturation, 0, 1), math.clamp(v * brightness, 0, 1))
end

return StudMath
