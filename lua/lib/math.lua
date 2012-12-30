--[[
	Shine maths library.
]]

local Floor = math.floor

function math.Clamp( Num, Low, Up )
	if Num < Low then return Low end
	if Num > Up then return Up end
	return Num
end

function math.Round( Number, DecimalPlaces )
	local Mult = 10 ^ ( DecimalPlaces or 0 )
	return Floor( Number * Mult + 0.5 ) / Mult
end

function math.InRange( Lower, Num, Upper )
	return Num > Lower and Num <= Upper
end
