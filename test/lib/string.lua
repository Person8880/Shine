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

UnitTest:Test( "Explode - Handles pattern-based separators", function( Assert )
	local ExplodedText = string.Explode( "thisssssissssasssstesssst", "s+" )
	Assert.ArrayEquals( "Should have applied the separator as a pattern", {
		"thi", "i", "a", "te", "t"
	}, ExplodedText )
end )

UnitTest:Test( "Explode - Handles non-pattern based separators", function( Assert )
	local ExplodedText = string.Explode( "Test.Thing.More.Things", ".", true )
	Assert.ArrayEquals( "Should have applied the separator as plain text", {
		"Test", "Thing", "More", "Things"
	}, ExplodedText )
end )

UnitTest:Test( "Explode - Handles edge case where separator is at start/end", function( Assert )
	local ExplodedText = string.Explode( "/some/path/to/things/", "/", true )
	Assert.ArrayEquals( "Should have applied the separator as plain text", {
		"", "some", "path", "to", "things", ""
	}, ExplodedText )
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
			Input = "{Value:Lower}",
			Tests = {
				{
					Data = { Value = "TESTING" },
					Expected = "testing"
				},
				{
					Data = { Value = "testing" },
					Expected = "testing"
				}
			}
		},
		{
			Input = "{Value:Upper}",
			Tests = {
				{
					Data = { Value = "TESTING" },
					Expected = "TESTING"
				},
				{
					Data = { Value = "testing" },
					Expected = "TESTING"
				}
			}
		},
		{
			Input = "{Value:Format:%.2f}",
			Tests = {
				{
					Data = { Value = 0 },
					Expected = "0.00"
				}
			}
		},
		{
			Input = "{Value:Abs}",
			Tests = {
				{
					Data = { Value = -5 },
					Expected = "5"
				},
				{
					Data = { Value = 5 },
					Expected = "5"
				}
			}
		},
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
		},
		{
			Input = "{Value:EnsureSentence}",
			Tests = {
				{
					Data = { Value = "This is a sentence." },
					Expected = "This is a sentence."
				},
				{
					Data = { Value = "This is a sentence!" },
					Expected = "This is a sentence!"
				},
				{
					Data = { Value = "This is a sentence?" },
					Expected = "This is a sentence?"
				},
				{
					Data = { Value = "This is a sentence" },
					Expected = "This is a sentence."
				},
				{
					Data = { Value = "This is a sentence.   " },
					Expected = "This is a sentence."
				},
				{
					Data = { Value = "This is a sentence   " },
					Expected = "This is a sentence."
				},
				{
					Data = { Value = "This is a sentence:" },
					Expected = "This is a sentence."
				},
				{
					Data = { Value = "This is a sentence;" },
					Expected = "This is a sentence."
				},
				{
					Data = { Value = "This is a sentence," },
					Expected = "This is a sentence."
				}
			}
		}
	}

	for i = 1, #InterpolationTests do
		local Test = InterpolationTests[ i ]
		UnitTest:Test( "Interpolate - "..Test.Input, function( Assert )
			local Tests = Test.Tests
			for j = 1, #Tests do
				Assert:Equals( Tests[ j ].Expected, string.Interpolate( Test.Input, Tests[ j ].Data,
					Test.LangDef ) )
			end
		end )
	end
end

do
	local StringFormat = string.format

	local CaseFormatTestCases = {
		UPPER_CAMEL = {
			Value = "TestWithACRONYMValue",
			Expected = {
				LOWER_CAMEL = "testWithACRONYMValue",
				UPPER_UNDERSCORE = "TEST_WITH_ACRONYM_VALUE",
				LOWER_UNDERSCORE = "test_with_acronym_value",
				HYPHEN = "test-with-acronym-value"
			}
		},
		LOWER_CAMEL = {
			Value = "testWithACRONYMValue",
			Expected = {
				UPPER_CAMEL = "TestWithACRONYMValue",
				UPPER_UNDERSCORE = "TEST_WITH_ACRONYM_VALUE",
				LOWER_UNDERSCORE = "test_with_acronym_value",
				HYPHEN = "test-with-acronym-value"
			}
		},
		UPPER_UNDERSCORE = {
			Value = "TEST_WITH_ACRONYM_VALUE",
			Expected = {
				UPPER_CAMEL = "TestWithAcronymValue",
				LOWER_CAMEL = "testWithAcronymValue",
				LOWER_UNDERSCORE = "test_with_acronym_value",
				HYPHEN = "test-with-acronym-value"
			}
		},
		LOWER_UNDERSCORE = {
			Value = "test_with_acronym_value",
			Expected = {
				UPPER_CAMEL = "TestWithAcronymValue",
				LOWER_CAMEL = "testWithAcronymValue",
				UPPER_UNDERSCORE = "TEST_WITH_ACRONYM_VALUE",
				HYPHEN = "test-with-acronym-value"
			}
		},
		HYPHEN = {
			Value = "test-with-acronym-value",
			Expected = {
				UPPER_CAMEL = "TestWithAcronymValue",
				LOWER_CAMEL = "testWithAcronymValue",
				UPPER_UNDERSCORE = "TEST_WITH_ACRONYM_VALUE",
				LOWER_UNDERSCORE = "test_with_acronym_value"
			}
		}
	}

	for Key, TestCase in pairs( CaseFormatTestCases ) do
		for TargetFormat, ExpectedValue in pairs( TestCase.Expected ) do
			if TargetFormat ~= Key then
				UnitTest:Test( StringFormat( "TransformCase %s -> %s", Key, TargetFormat ), function( Assert )
					Assert.Equals(
						StringFormat( "Transformation from %s to %s did not match expected value", Key, TargetFormat ),
						ExpectedValue,
						string.TransformCase(
							TestCase.Value, string.CaseFormatType[ Key ], string.CaseFormatType[ TargetFormat ]
						)
					)
				end )
			end
		end
	end
end

UnitTest:Test( "ToBase64", function( Assert )
	Assert:Equals( "dA==", string.ToBase64( "t" ) )
	Assert:Equals( "dGU=", string.ToBase64( "te" ) )
	Assert:Equals( "dGVz", string.ToBase64( "tes" ) )
	Assert:Equals( "dGVzdA==", string.ToBase64( "test" ) )
	Assert:Equals( "dGVzdGk=", string.ToBase64( "testi" ) )
	Assert:Equals( "dGVzdGlu", string.ToBase64( "testin" ) )
	Assert:Equals( "dGVzdGluZw==", string.ToBase64( "testing" ) )
end )

UnitTest:Test( "FromBase64", function( Assert )
	Assert:Equals( "t", string.FromBase64( "dA==" ) )
	Assert:Equals( "te", string.FromBase64( "dGU=" ) )
	Assert:Equals( "tes", string.FromBase64( "dGVz" ) )
	Assert:Equals( "test", string.FromBase64( "dGVzdA==" ) )
	Assert:Equals( "test", string.FromBase64( "dGVzdA==" ) )
	Assert:Equals( "testi", string.FromBase64( "dGVzdGk=" ) )
	Assert:Equals( "testin", string.FromBase64( "dGVzdGlu" ) )
	Assert:Equals( "testing", string.FromBase64( "dGVzdGluZw==" ) )
end )
