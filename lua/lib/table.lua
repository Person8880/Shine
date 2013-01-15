--[[
	Shine table library.
]]

local Ceil = math.ceil
local pairs = pairs
local Random = math.random
local TableSort = table.sort

--[[
	Shuffles a table randomly.
]]
function table.Shuffle( Table )
	local SortTable = {}
	for i = 1, #Table do
		SortTable[ Table[ i ] ] = Random( 1, 100000 )
	end

	TableSort( Table, function( A, B )
		return SortTable[ A ] > SortTable[ B ]
	end )
end

--[[
	Chooses a random entry from the table 
	with each entry having equal probability of being picked.
]]
function table.ChooseRandom( Table )
	local Count = #Table
	local Interval = 1 / Count

	local Rand = Random()
	local InRange = math.InRange

	for i = 1, Count do
		local Lower = Interval * ( i - 1 )
		local Upper = i ~= Count and ( Interval * i ) or Ceil( Interval * i )

		if InRange( Lower, Rand, Upper ) then
			return Table[ i ]
		end
	end
end

local function istable( Table )
	return type( Table ) == "table"
end

--[[
	Prints a nicely formatted table structure to the console.
]]
function PrintTable( Table, Indent )
	Indent = Indent or 0

	local IndentString = string.rep( "\t", Indent )

	for k, v in pairs( Table ) do
		if istable( v ) then
			Print( IndentString..tostring( k )..":".."\n" )
			PrintTable( v, Indent + 2 )
		else
			Print( IndentString..tostring( k ).." = "..tostring( v ) )
		end
	end
end

local function CopyTable( Table, LookupTable )
	if not Table then return nil end
	
	local Copy = {}
	setmetatable( Copy, getmetatable( Table ) )

	for k, v in pairs( Table ) do
		if not istable( v ) then
			Copy[ k ] = v
		else
			LookupTable = LookupTable or {}
			LookupTable[ Table ] = Copy
			if LookupTable[ v ] then
				Copy[ k ] = LookupTable[ v ]
			else
				Copy[ k ] = CopyTable( v, LookupTable )
			end
		end
	end
	return Copy
end
table.Copy = CopyTable

local function Count( Table )
	local i = 0

	for k in pairs( Table ) do 
		i = i + 1 
	end

	return i
end
table.Count = Count

--[[
	Credit to Garry for most of this. (See GMod lua/includes/extensions/table.lua)
]]
local function PairsSorted( Table, Index )
	if Index == nil then
		Index = 1
	else
		for k, v in pairs( Table.__SortedIndex ) do
			if v == Index then
				Index = k + 1
				break
			end
		end	
	end
	
	local Key = Table.__SortedIndex[ Index ]
	if not Key then
		Table.__SortedIndex = nil
		return
	end
	
	Index = Index + 1
	
	return Key, Table[ Key ]
end

function RandomPairs( Table, Desc )
	local Count = Count( Table )
	Table = CopyTable( Table )
	
	local SortedIndex = {}
	local i = 1

	for k, v in pairs( Table ) do
		SortedIndex[ i ] = { Key = k, Rand = Random( 1, 1000 ) }
		i = i + 1
	end
	
	if Desc then
		TableSort( SortedIndex, function( A, B ) return A.Rand > B.Rand end )
	else
		TableSort( SortedIndex, function( A, B ) return A.Rand < B.Rand end )
	end
	
	for k, v in pairs( SortedIndex ) do
		SortedIndex[ k ] = v.Key
	end
	
	Table.__SortedIndex = SortedIndex

	return PairsSorted, Table, nil
end
