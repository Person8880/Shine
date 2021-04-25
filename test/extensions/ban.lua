--[[
	Bans plugin unit test.
]]

local UnitTest = Shine.UnitTest
local Plugin = UnitTest:LoadExtension( "ban" )
if not Plugin then return end

Plugin = UnitTest.MockPlugin( Plugin )

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

do
	function Plugin:CheckFamilySharing( SteamID, CacheOnly )
		return false, 12345
	end

	local Kicked = {}
	function Plugin:KickForFamilySharingWhenBanned( Client, Sharer )
		Kicked[ Client ] = "Banned"
	end

	function Plugin:KickForFamilySharing( Client, Sharer )
		Kicked[ Client ] = "NotBanned"
	end

	UnitTest:Before( function()
		Kicked = {}
		Plugin.IsClientImmuneToFamilySharingChecks = function() return false end
	end )

	UnitTest:Test( "ClientConnect - Does nothing if Config.CheckFamilySharing = false", function( Assert )
		function Plugin:CheckFamilySharing( SteamID, CacheOnly )
			return true, 12345
		end

		Plugin.Config.CheckFamilySharing = false

		local MockClient = UnitTest.MakeMockClient( 123 )
		Plugin:ClientConnect( MockClient )

		Assert.Nil( "Should not have kicked the client", Kicked[ MockClient ] )
	end )

	UnitTest:Test( "ClientConnect - Does nothing if the connecting client is immune to checks", function( Assert )
		Plugin.IsClientImmuneToFamilySharingChecks = function() return true end
		Plugin.Config.CheckFamilySharing = true

		function Plugin:CheckFamilySharing( SteamID, CacheOnly )
			return true, 12345
		end

		local MockClient = UnitTest.MakeMockClient( 123 )
		Plugin:ClientConnect( MockClient )

		Assert.Nil( "Should not have kicked the client", Kicked[ MockClient ] )
	end )

	UnitTest:Test( "ClientConnect - Does nothing if Config.CheckFamilySharing = true and the client is not family sharing", function( Assert )
		Plugin.Config.CheckFamilySharing = true

		function Plugin:CheckFamilySharing( SteamID, CacheOnly )
			return false
		end

		local MockClient = UnitTest.MakeMockClient( 123 )
		Plugin:ClientConnect( MockClient )

		Assert.Nil( "Should not have kicked the client", Kicked[ MockClient ] )
	end )

	UnitTest:Test( "ClientConnect - Kicks the client if Config.CheckFamilySharing = true and the client is family sharing with a banned account", function( Assert )
		Plugin.Config.CheckFamilySharing = true

		function Plugin:CheckFamilySharing( SteamID, CacheOnly )
			return true, 12345
		end

		local MockClient = UnitTest.MakeMockClient( 123 )
		Plugin:ClientConnect( MockClient )

		Assert.Equals( "Should have kicked the client due to the sharer being banned", "Banned", Kicked[ MockClient ] )
	end )

	UnitTest:Test( "ClientConnect - Kicks the client if Config.AlwaysBlockFamilySharedPlayers = true and the client is family sharing", function( Assert )
		Plugin.Config.CheckFamilySharing = true
		Plugin.Config.AlwaysBlockFamilySharedPlayers = true

		function Plugin:CheckFamilySharing( SteamID, CacheOnly )
			return false, 12345
		end

		local MockClient = UnitTest.MakeMockClient( 123 )
		Plugin:ClientConnect( MockClient )

		Assert.Equals( "Should have kicked the client due to sharing, even though the sharer is not banned",
			"NotBanned", Kicked[ MockClient ] )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Does nothing if the client is not banned and CheckFamilySharing = false", function( Assert )
		Plugin.Config.CheckFamilySharing = false
		Plugin.Config.Banned = {}

		Assert.Nil( "Client should not be rejected", Plugin:CheckConnectionAllowed( 123 ) )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Rejects the client if they are banned", function( Assert )
		Plugin.Config.CheckFamilySharing = false
		Plugin.Config.Banned = {
			[ "123" ] = {
				BannedBy = "Test",
				Duration = 120,
				UnbanTime = os.time() + 120,
				Reason = "Testing."
			}
		}

		local Allowed, Reason = Plugin:CheckConnectionAllowed( 123 )
		Assert.False( "Client should be rejected", Allowed )
		Assert:Equals( "Banned from server by Test for 2 minutes: Testing.", Reason )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Does nothing if the client's ban has expired", function( Assert )
		Plugin.Config.CheckFamilySharing = false
		Plugin.Config.Banned = {
			[ "123" ] = {
				BannedBy = "Test",
				Duration = 120,
				UnbanTime = 1,
				Reason = "Testing."
			}
		}

		Assert.Nil( "Client should not be rejected", Plugin:CheckConnectionAllowed( 123 ) )
		Assert.Nil( "Expired ban should be removed", Plugin.Config.Banned[ "123" ] )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Does nothing if the client is not banned and not family sharing", function( Assert )
		Plugin.Config.CheckFamilySharing = true
		Plugin.Config.Banned = {}

		function Plugin:CheckFamilySharing( SteamID, CacheOnly )
			return false
		end

		Assert.Nil( "Client should not be rejected", Plugin:CheckConnectionAllowed( 123 ) )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Does nothing if the client is not banned and is immune to family sharing checks", function( Assert )
		Plugin.IsClientImmuneToFamilySharingChecks = function() return true end
		Plugin.Config.CheckFamilySharing = true
		Plugin.Config.Banned = {}

		function Plugin:CheckFamilySharing( SteamID, CacheOnly )
			return true, 12345
		end

		Assert.Nil( "Client should not be rejected", Plugin:CheckConnectionAllowed( 123 ) )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Rejects the client if they are family sharing with a banned account", function( Assert )
		Plugin.Config.CheckFamilySharing = true
		Plugin.Config.Banned = {}

		function Plugin:CheckFamilySharing( SteamID, CacheOnly )
			return true, 12345
		end

		local Allowed, Reason = Plugin:CheckConnectionAllowed( 123 )
		Assert.False( "Client should be rejected", Allowed )
		Assert:Equals( "Family sharing with a banned account.", Reason )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Rejects the client if they are family sharing and AlwaysBlockFamilySharedPlayers = true", function( Assert )
		Plugin.Config.CheckFamilySharing = true
		Plugin.Config.AlwaysBlockFamilySharedPlayers = true
		Plugin.Config.Banned = {}

		function Plugin:CheckFamilySharing( SteamID, CacheOnly )
			return false, 12345
		end

		local Allowed, Reason = Plugin:CheckConnectionAllowed( 123 )
		Assert.False( "Client should be rejected", Allowed )
		Assert:Equals( "Family sharing is not permitted here.", Reason )
	end )

	local OldGetClientByNS2ID = Shine.GetClientByNS2ID
	local MockClient
	Shine.GetClientByNS2ID = function( ID )
		if ID == MockClient:GetUserId() then
			return MockClient
		end
	end

	UnitTest:Test( "CheckConnectionAllowed - Does nothing if response is delayed but client is not family sharing", function( Assert )
		Plugin.Config.CheckFamilySharing = true
		Plugin.Config.AlwaysBlockFamilySharedPlayers = false

		function Plugin:CheckFamilySharing( SteamID, CacheOnly, Callback )
			return Callback( false )
		end

		MockClient = UnitTest.MakeMockClient( 123 )

		Assert.Nil( "Should not make a decision when result is delayed", Plugin:CheckConnectionAllowed( 123 ) )
		Assert.Nil( "Should not have kicked the client", Kicked[ MockClient ] )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Does nothing if response is delayed and client is family sharing with an account that is not banned", function( Assert )
		Plugin.Config.CheckFamilySharing = true
		Plugin.Config.AlwaysBlockFamilySharedPlayers = false

		function Plugin:CheckFamilySharing( SteamID, CacheOnly, Callback )
			return Callback( false, 12345 )
		end

		MockClient = UnitTest.MakeMockClient( 123 )

		Assert.Nil( "Should not make a decision when result is delayed", Plugin:CheckConnectionAllowed( 123 ) )
		Assert.Nil( "Should not have kicked the client", Kicked[ MockClient ] )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Kicks the client if response is delayed and client is family sharing with an account that is banned", function( Assert )
		Plugin.Config.CheckFamilySharing = true
		Plugin.Config.AlwaysBlockFamilySharedPlayers = false

		function Plugin:CheckFamilySharing( SteamID, CacheOnly, Callback )
			return Callback( true, 12345 )
		end

		MockClient = UnitTest.MakeMockClient( 123 )

		Assert.Nil( "Should not make a decision when result is delayed", Plugin:CheckConnectionAllowed( 123 ) )
		Assert.Equals( "Should have kicked the client", "Banned", Kicked[ MockClient ] )
	end )

	UnitTest:Test( "CheckConnectionAllowed - Kicks the client if response is delayed and client is family sharing when AlwaysBlockFamilySharedPlayers = true", function( Assert )
		Plugin.Config.CheckFamilySharing = true
		Plugin.Config.AlwaysBlockFamilySharedPlayers = true

		function Plugin:CheckFamilySharing( SteamID, CacheOnly, Callback )
			return Callback( false, 12345 )
		end

		MockClient = UnitTest.MakeMockClient( 123 )

		Assert.Nil( "Should not make a decision when result is delayed", Plugin:CheckConnectionAllowed( 123 ) )
		Assert.Equals( "Should have kicked the client", "NotBanned", Kicked[ MockClient ] )
	end )

	Shine.GetClientByNS2ID = OldGetClientByNS2ID

	UnitTest:ResetState()
end
