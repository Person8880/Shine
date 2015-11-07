--[[
	Maths library extension tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "GenerateSequence", function( Assert )
	local Sequence = math.GenerateSequence( 18, { 1, 2 } )

	local Counts = {}
	for i = 1, #Sequence do
		Counts[ Sequence[ i ] ] = ( Counts[ Sequence[ i ] ] or 0 ) + 1
	end

	Assert:Equals( 9, Counts[ 1 ] )
	Assert:Equals( 9, Counts[ 2 ] )
end, nil, 100 )
