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
