--[[
	Shine maths library.
]]

local TableRandom = table.ChooseRandom
local TableRemove = table.remove

local Floor = math.floor
local Max = math.max
local Min = math.min
local Random = math.random

local function Clamp( Number, Lower, Upper )
	if Number < Lower then return Lower end
	if Number > Upper then return Upper end
	return Number
end
math.Clamp = Clamp

function math.ClampEx( Number, Lower, Upper )
	if not Number then return nil end
	if not Lower and not Upper then
		return Number
	end

	if Lower and Upper then
		return Clamp( Number, Lower, Upper )
	end

	if Lower then
		return Max( Number, Lower )
	end

	return Min( Number, Upper )
end

function math.Round( Number, DecimalPlaces )
	local Mult = 10 ^ ( DecimalPlaces or 0 )
	return Floor( Number * Mult + 0.5 ) / Mult
end

--[[
	Determines if the given number lies between the given lower and upper bound.
	Lower < Num <= Upper.
]]
function math.InRange( Lower, Num, Upper )
	return Num > Lower and Num <= Upper
end

--[[
	Generates a random sequence of numbers of the given length,
	ensuring no number goes over Length / Options in amount.

	For instance, math.GenerateSequence( 18, { 1, 2 } ) would generate something like:
	112122122212122111
]]
function math.GenerateSequence( Length, Nums )
	local Entries = #Nums
	local Max = Length / Entries

	local Sequence = {}
	local Count = {}

	for i = 1, #Nums do
		Count[ Nums[ i ] ] = 0
	end

	for i = 1, Length do
		local Option, Index = TableRandom( Nums )

		if Count[ Option ] >= Max then
			TableRemove( Nums, Index )

			Option = TableRandom( Nums )
		end

		Count[ Option ] = Count[ Option ] + 1

		Sequence[ i ] = Option
	end

	return Sequence
end

--[[
	Performs an easing of the given progress to the given power.

	This is power easing, not sine, exponential or otherwise.
]]
function math.EaseInOut( Progress, Power )
	if Progress < 0.5 then
		Progress = Progress * 2
		return ( Progress ^ Power ) * 0.5
	end

	Progress = 2 * ( 1 - Progress )

	return 1 - ( Progress ^ Power ) * 0.5
end

--[[
	Performs easing inward only.
]]
function math.EaseIn( Progress, Power )
	return Progress ^ Power
end

--[[
	Performs easing outward only.
]]
function math.EaseOut( Progress, Power )
	Progress = 1 - Progress
	return 1 - Progress ^ Power
end
