--[[
	String library extension tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "StartsWith", function( Assert )
	Assert:True( string.StartsWith( "Test", "Te" ) )
	Assert:False( string.StartsWith( "Test", "te" ) )
end )

UnitTest:Test( "EndsWith", function( Assert )
	Assert:True( string.EndsWith( "Test", "est" ) )
	Assert:False( string.EndsWith( "Test", "abc" ) )
end )

UnitTest:Test( "PatternSafe", function( Assert )
	local Pattern = string.PatternSafe( ".*+-?()[]%^$\0" )
	Assert.Equals( "Pattern should be escaped", "%.%*%+%-%?%(%)%[%]%%%^%$%z", Pattern )
	Assert.True( "Should be able to search without error", pcall( string.find, ".*+-?()[]%^$", Pattern ) )
end )

UnitTest:Test( "ParseLocalDateTime - Date and time with seconds", function( Assert )
	local Timestamp, IsDateTime = string.ParseLocalDateTime( "2018-01-01T00:00:05" )

	Assert.True( "Should be parsed as a date-time", IsDateTime )
	Assert.Equals( "Should match expected timestamp", 1514764805, Timestamp )
end )

UnitTest:Test( "ParseLocalDateTime - Date and time without seconds", function( Assert )
	local Timestamp, IsDateTime = string.ParseLocalDateTime( "2018-01-01T00:00" )

	Assert.True( "Should be parsed as a date-time", IsDateTime )
	Assert.Equals( "Should match expected timestamp", 1514764800, Timestamp )
end )

UnitTest:Test( "ParseLocalDateTime - Time with seconds", function( Assert )
	local Timestamp, IsDateTime = string.ParseLocalDateTime( "T00:00:05", { year = 2018, month = 1, day = 1 } )

	Assert.False( "Should be parsed as a time", IsDateTime )
	Assert.Equals( "Should match expected timestamp", 1514764805, Timestamp )
end )

UnitTest:Test( "ParseLocalDateTime - Time without seconds", function( Assert )
	local Timestamp, IsDateTime = string.ParseLocalDateTime( "T00:00", { year = 2018, month = 1, day = 1 } )

	Assert.False( "Should be parsed as a time", IsDateTime )
	Assert.Equals( "Should match expected timestamp", 1514764800, Timestamp )
end )

do
	local InterpolationTests = {
		{
			Input = "{Value:Pluralise:singular|plural}",
			LangDef = {
				GetPluralForm = function( Value )
					return Value == 1 and 1 or 2
				end
			},
			Tests = {
				{
					Data = { Value = 0 },
					Expected = "plural"
				},
				{
					Data = { Value = 1 },
					Expected = "singular"
				},
				{
					Data = { Value = 2 },
					Expected = "plural"
				}
			}
		},
		{
			Input = "{Value:Pluralise:zero|one|two}",
			LangDef = {
				GetPluralForm = function( Value )
					return ( Value == 0 and 1 ) or ( Value == 1 and 2 ) or 3
				end
			},
			Tests = {
				{
					Data = { Value = 0 },
					Expected = "zero"
				},
				{
					Data = { Value = 1 },
					Expected = "one"
				},
				{
					Data = { Value = 2 },
					Expected = "two"
				},
				{
					Data = { Value = 3 },
					Expected = "two"
				}
			}
		}
	}

	for i = 1, #InterpolationTests do
		local Test = InterpolationTests[ i ]
		UnitTest:Test( Test.Input, function( Assert )
			local Tests = Test.Tests
			for j = 1, #Tests do
				Assert:Equals( Tests[ j ].Expected, string.Interpolate( Test.Input, Tests[ j ].Data,
					Test.LangDef ) )
			end
		end )
	end
end
