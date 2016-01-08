--[[
	Stable merge sort.
]]

local Floor = math.floor

local function Merge( Table, Min, Centre, Max, Comparator )
	local Left = {}
	local Right = {}

	for i = Min, Centre do
		Left[ i - Min + 1 ] = Table[ i ]
	end

	for i = Centre + 1, Max do
		Right[ i - Centre ] = Table[ i ]
	end

	local LeftIndex = 1
	local RightIndex = 1
	local NumberLeft = #Left
	local NumberRight = #Right

	for i = Min, Max do
		if NumberLeft < LeftIndex then
			Table[ i ] = Right[ RightIndex ]
			RightIndex = RightIndex + 1
		elseif NumberRight < RightIndex then
			Table[ i ] = Left[ LeftIndex ]
			LeftIndex = LeftIndex + 1
		else
			if Comparator( Left[ LeftIndex ], Right[ RightIndex ] ) <= 0 then
				Table[ i ] = Left[ LeftIndex ]
				LeftIndex = LeftIndex + 1
			else
				Table[ i ] = Right[ RightIndex ]
				RightIndex = RightIndex + 1
			end
		end
	end
end

local function NaturalOrder( A, B )
	return A == B and 0 or ( A < B and -1 or 1 )
end

--[[
	Performs an inline sort of the given table using the merge sort algorithm.

	Lua's table.sort() is not guaranteed to place elements with equal precedence
	in the same order each time. This produces a sorting that is always identical
	every time it is run.

	The comparator takes two values, A and B, and should return a single number:
	- Negative if value A belongs before the value B
	- 0 if the values have equal precedence
	- Positive if the value A belongs after the value B.

	This is not the same as for Lua's standard table.sort, which expects a boolean return value.
]]
local function MergeSort( Table, Comparator, Start, End )
	Comparator = Comparator or NaturalOrder
	Start = Start or 1
	End = End or #Table

	if Start >= End then return end

	local Centre = Floor( ( Start + End ) * 0.5 )
	MergeSort( Table, Comparator, Start, Centre )
	MergeSort( Table, Comparator, Centre + 1, End )
	Merge( Table, Start, Centre, End, Comparator )
end
table.MergeSort = MergeSort
