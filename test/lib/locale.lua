--[[
	Locale tests.
]]

local StringFormat = string.format
local UnitTest = Shine.UnitTest

UnitTest:Test( "All locale files are valid JSON", function( Assert )
	local Files = {}
	Shared.GetMatchingFileNames( "locale/*.json", true, Files )

	for i = 1, #Files do
		local File = Files[ i ]
		local Keys, Pos, Err = Shine.LoadJSONFile( File )
		if not Keys then
			Assert.Truthy( StringFormat( "Invalid JSON in locale file %s: %s %s", File, Pos, Err ), Keys )
		end
	end
end )
