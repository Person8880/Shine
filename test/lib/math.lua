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

UnitTest:Test( "StandardDeviation", function( Assert )
	-- Empty data should return 0, not nan.
	local Data = {}
	Assert:Equals( 0, math.StandardDeviation( Data ) )

	-- All identical values have a standard deviation of 0.
	Data = { 1000, 1000, 1000, 1000 }
	Assert:Equals( 0, math.StandardDeviation( Data ) )

	Data = { 1000, 1200, 1100, 900 }
	Assert:Equals( 112, math.ceil( math.StandardDeviation( Data ) ) )
end )

UnitTest:Test( "RoundTo", function( Assert )
	Assert:Equals( 2, math.RoundTo( 1, 2 ) )
	Assert:Equals( 3, math.RoundTo( 2, 3 ) )
	Assert:Equals( 0, math.RoundTo( 1, 3 ) )
	Assert:Equals( 90, math.RoundTo( 60, 90 ) )
end )
