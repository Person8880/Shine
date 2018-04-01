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
	Rounds a value to a given modulus.
]]
function math.RoundTo( Number, Modulus )
	local Diff = Number % Modulus
	if Diff >= Modulus * 0.5 then
		return Number + Modulus - Diff
	end
	return Number - Diff
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

		Count[ Option ] = Count[ Option ] + 1

		if Count[ Option ] >= Max then
			TableRemove( Nums, Index )
		end

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

do
	local Sqrt = math.sqrt
	local TableAverage = table.Average

	--[[
		Computes the standard deviation of a table of values.
	]]
	function math.StandardDeviation( Values )
		local Sum = 0
		local Count = #Values
		if Count == 0 then return 0, 0 end

		local Average = TableAverage( Values )
		for i = 1, Count do
			Sum = Sum + ( Values[ i ] - Average ) ^ 2
		end

		return Sqrt( Sum / Count ), Average
	end
end
