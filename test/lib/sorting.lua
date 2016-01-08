--[[
	Sorting tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Simple MergeSort", function( Assert )
	local Data = { 1, 5, 7, 2, 7, 8, 3, 1 }
	table.MergeSort( Data, function( A, B )
		return A == B and 0 or ( A < B and -1 or 1 )
	end )

	Assert:ArrayEquals( { 1, 1, 2, 3, 5, 7, 7, 8 }, Data )
end )

UnitTest:Test( "MergeSort stability", function( Assert )
	local Unsorted = {
		{
			Name = "a"
		},
		{
			Name = "c"
		},
		{
			Name = "b"
		},
		{
			Name = "a"
		},
		{
			Name = "c"
		}
	}

	local ExpectedResult = {
		Unsorted[ 1 ], Unsorted[ 4 ], Unsorted[ 3 ], Unsorted[ 2 ], Unsorted[ 5 ]
	}

	table.MergeSort( Unsorted, Shine.Comparator( "Field", 1, "Name" ):CompileStable() )

	Assert:ArrayEquals( ExpectedResult, Unsorted )
end, nil, 100 )
