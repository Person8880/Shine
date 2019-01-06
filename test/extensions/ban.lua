--[[
	Bans plugin unit test.
]]

local UnitTest = Shine.UnitTest
local Plugin = UnitTest:LoadExtension( "ban" )
if not Plugin then return end

Plugin = UnitTest.MockOf( Plugin )

UnitTest:Test( "AddNS2BansIntoTable - Adds missing bans and updates existing ones", function( Assert )
	local VanillaBans = {
		{
			name = "Ignore as it has no id value", time = 0
		},
		{
			id = 123, name = "Test", reason = "Testing.", time = os.time() + 1000
		},
		{
			id = 456, name = "AnotherTest", reason = "More testing.", time = "not a number"
		},
		{
			id = 789,
			name = "WithDuration",
			reason = "Even more testing.",
			time = 1000,
			duration = 2000,
			bannerid = 123456,
			bannedby = "Someone"
		},
		{
			id = 987, name = "WithPermaBan", time = 0
		},
		{
			name = "An invalid ID", id = "abc"
		}
	}

	local OutputTable = {
		[ "123" ] = {
			UnbanTime = 0,
			Reason = "",
			Name = "Test"
		}
	}
	local VanillaIDs, Edited = Plugin:AddNS2BansIntoTable( VanillaBans, OutputTable )

	Assert.DeepEquals( "Should output all valid IDs", {
		[ "123" ] = true,
		[ "456" ] = true,
		[ "789" ] = true,
		[ "987" ] = true
	}, VanillaIDs )
	Assert.True( "Should be marked as edited", Edited )
	Assert.DeepEquals( "Should have added/updated the passed in table", {
		[ "123" ] = {
			-- Valid time values should be passed through as-is.
			UnbanTime = VanillaBans[ 2 ].time,
			BannerID = 0,
			BannedBy = "<unknown>",
			Name = "Test",
			Reason = "Testing.",
			-- Duration should be derived from the time.
			Duration = 1000
		},
		[ "456" ] = {
			-- Non-number values should be interpreted as 0.
			UnbanTime = 0,
			BannerID = 0,
			BannedBy = "<unknown>",
			Name = "AnotherTest",
			Reason = "More testing.",
			-- Duration should also be 0 in this case.
			Duration = 0
		},
		[ "789" ] = {
			UnbanTime = 1000,
			-- Should pick up on the banner values.
			BannerID = 123456,
			BannedBy = "Someone",
			Name = "WithDuration",
			Reason = "Even more testing.",
			-- Duration should be derived from the 'duration' field.
			Duration = 2000
		},
		[ "987" ] = {
			UnbanTime = 0,
			BannerID = 0,
			BannedBy = "<unknown>",
			Name = "WithPermaBan",
			-- Duration should be 0 as the time is 0.
			Duration = 0
		}
	}, OutputTable )
end )

UnitTest:Test( "AddNS2BansIntoTable - Does nothing if all bans match", function( Assert )
	local VanillaBans = {
		{
			name = "Ignore as it has no id value", time = 0
		},
		{
			id = 123,
			name = "Test",
			reason = "Testing.",
			time = os.time() + 100,
			duration = 1000,
			bannerid = 0,
			bannedby = "<unknown>"
		},
		{
			id = 456,
			name = "AnotherTest",
			reason = "More testing.",
			time = 0,
			duration = 0,
			bannerid = 0,
			bannedby = "<unknown>"
		},
		{
			name = "An invalid ID", id = "abc"
		}
	}

	local OutputTable = {
		[ "123" ] = {
			UnbanTime = VanillaBans[ 2 ].time,
			BannerID = 0,
			BannedBy = "<unknown>",
			Name = "Test",
			Reason = "Testing.",
			Duration = 1000
		},
		[ "456" ] = {
			UnbanTime = 0,
			BannerID = 0,
			BannedBy = "<unknown>",
			Name = "AnotherTest",
			Reason = "More testing.",
			Duration = 0
		}
	}
	local OriginalBans = table.Copy( OutputTable )

	local VanillaIDs, Edited = Plugin:AddNS2BansIntoTable( VanillaBans, OutputTable )
	Assert.Falsy( "Should not be marked as edited", Edited )
	Assert.DeepEquals( "Should output all valid IDs", {
		[ "123" ] = true,
		[ "456" ] = true
	}, VanillaIDs )
	Assert.DeepEquals( "Should have made no changes to the given table", OriginalBans, OutputTable )
end )
