--[[
	Shine table library.
]]

local Random = math.random
local TableSort = table.sort

function table.Shuffle( Table )
	TableSort( Table, function( A, B )
		return Random( 1, 100 ) > 50
	end )
end
