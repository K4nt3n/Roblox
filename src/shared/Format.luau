--!strict
--[[
	Format: display helpers shared by UI and server messages. No requires.
]]

local Format = {}

local SUFFIXES = { "K", "M", "B", "T" }

local function withCommas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return if n < 0 then "-" .. out else out
end
Format.withCommas = withCommas

-- 950 -> "950", 12500 -> "12.5K", 3400000 -> "3.4M"
function Format.coins(n: number): string
	local abs = math.abs(n)
	if abs < 10000 then
		return withCommas(n)
	end
	local i = 0
	while abs >= 1000 and i < #SUFFIXES do
		abs /= 1000
		i += 1
	end
	local text = if abs >= 100 then string.format("%d", math.floor(abs)) else string.format("%.1f", abs)
	text = text:gsub("%.0$", "")
	return (if n < 0 then "-" else "") .. text .. SUFFIXES[i]
end

-- 0.42 -> "0.42 kg", 12.34 -> "12.3 kg", 1234.5 -> "1,235 kg"
function Format.weight(kg: number): string
	if kg < 10 then
		return string.format("%.2f kg", kg)
	elseif kg < 100 then
		return string.format("%.1f kg", kg)
	end
	return withCommas(math.floor(kg + 0.5)) .. " kg"
end

-- 45 -> "45s", 125 -> "2m 05s", 3720 -> "1h 02m", 90000 -> "1d 1h"
function Format.duration(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s < 60 then
		return string.format("%ds", s)
	elseif s < 3600 then
		return string.format("%dm %02ds", s // 60, s % 60)
	elseif s < 86400 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	end
	return string.format("%dd %dh", s // 86400, (s % 86400) // 3600)
end

return Format
