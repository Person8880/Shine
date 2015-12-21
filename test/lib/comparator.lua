--[[
	Comparator object tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "FieldComparator", function( Assert )
	local Unsorted = {
		{
			SortField = "a"
		},
		{
			SortField = "z"
		},
		{
			SortField = "q"
		},
		{
			SortField = "e"
		},
		{
			SortField = "b"
		},
	}

	table.sort( Unsorted, Shine.Comparator( "Field", 1, "SortField" ):Compile() )

	local ExpectedOrder = { "a", "b", "e", "q", "z" }
	for i = 1, #Unsorted do
		Assert:Equals( ExpectedOrder[ i ], Unsorted[ i ].SortField )
	end
end, nil, 100 )

UnitTest:Test( "MethodComparator", function( Assert )
	local function SortMethod( self, Arg )
		return self.Value % Arg
	end

	local Unsorted = {
		{
			SortMethod = SortMethod,
			Value = 3
		},
		{
			SortMethod = SortMethod,
			Value = 5
		},
		{
			SortMethod = SortMethod,
			Value = 1
		}
	}

	table.sort( Unsorted, Shine.Comparator( "Method", 1, "SortMethod", 3 ):Compile() )

	local ExpectedOrder = { 3, 1, 5 }
	for i = 1, #Unsorted do
		Assert:Equals( ExpectedOrder[ i ], Unsorted[ i ].Value )
	end
end, nil, 100 )

UnitTest:Test( "NumberMethodComparator", function( Assert )
	local function SortMethod( self ) return self.Value end

	local Unsorted = {
		{
			SortMethod = SortMethod,
			Value = "3"
		},
		{
			SortMethod = SortMethod,
			Value = "5"
		},
		{
			SortMethod = SortMethod,
			Value = "1"
		}
	}

	table.sort( Unsorted, Shine.Comparator( "Method", 1, "SortMethod", nil, tonumber ):Compile() )

	local ExpectedOrder = { "1", "3", "5" }
	for i = 1, #Unsorted do
		Assert:Equals( ExpectedOrder[ i ], Unsorted[ i ].Value )
	end
end, nil, 100 )

UnitTest:Test( "ComposedComparator", function( Assert )
	local Unsorted = {
		{
			Name = "a",
			SubName = "z"
		},
		{
			Name = "a",
			SubName = "a"
		},
		{
			Name = "b",
			SubName = "a"
		},
		{
			Name = "c",
			SubName = "d"
		},
		{
			Name = "c",
			SubName = "a"
		}
	}

	local Comparators = {
		Shine.Comparator( "Field", 1, "SubName" ),
		Shine.Comparator( "Field", 1, "Name" )
	}

	table.sort( Unsorted, Shine.Comparator( "Composition", unpack( Comparators ) ):Compile() )

	local ExpectedOrder = {
		{
			Name = "a",
			SubName = "a"
		},
		{
			Name = "a",
			SubName = "z"
		},
		{
			Name = "b",
			SubName = "a"
		},
		{
			Name = "c",
			SubName = "a"
		},
		{
			Name = "c",
			SubName = "d"
		}
	}

	for i = 1, #Unsorted do
		Assert:Equals( ExpectedOrder[ i ].Name, Unsorted[ i ].Name )
		Assert:Equals( ExpectedOrder[ i ].SubName, Unsorted[ i ].SubName )
	end
end, nil, 100 )
