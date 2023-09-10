--[[
	Name filter plugin tests.
]]

local UnitTest = Shine.UnitTest

local Plugin = UnitTest:LoadExtension( "namefilter" )
if not Plugin then return end

Plugin = UnitTest.MockOf( Plugin )
Plugin.Config.ForcedNames = {
	[ "123456" ] = "Test",
	[ "nil" ] = "Shouldn't be used"
}

local USER_ID = 123456
local MockClient = {
	GetUserId = function() return USER_ID end,
	GetIsVirtual = function() return USER_ID == 0 end
}
local MockPlayer = {
	GetClient = function() return MockClient end
}

UnitTest:Test( "EnforceName returns nil if client is nil", function( Assert )
	local Name = Plugin:EnforceName( nil )
	Assert.Nil( "Name should not be enforced", Name )
end )

UnitTest:Test( "EnforceName returns enforced name", function( Assert )
	local Name = Plugin:EnforceName( MockClient )
	Assert.Equals( "Name should be enforced", "Test", Name )
end )

USER_ID = 654321
UnitTest:Test( "EnforceName returns nothing when no name is enforced", function( Assert )
	local Name = Plugin:EnforceName( MockClient )
	Assert.Nil( "Name should be enforced", Name )
end )

local function SetFilters( Filters )
	Plugin.Config.Filters = Filters
	Plugin.Filters = Plugin:CompileFilters()
end

Plugin.Config.FilterAction = Plugin.FilterActionType.RENAME

SetFilters( {
	{ Pattern = "BannedN[a]+me" }
} )

USER_ID = 0
UnitTest:Test( "CheckPlayerName returns nothing for a bot", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "BannedNaaaame", "NSPlayer" )
	Assert.Nil( "Name should be accepted", Name )
end )

USER_ID = 654321
UnitTest:Test( "CheckPlayerName returns new name when pattern filter matches", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "BannedNaaaame", "NSPlayer" )
	Assert.Equals( "Name should be rejected", "NSPlayer654321", Name )
end )

UnitTest:Test( "CheckPlayerName returns nothing when pattern filter does not match", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "NotBanned", "NSPlayer" )
	Assert.Nil( "Name should be accepted", Name )
end )

SetFilters( {
	{ Pattern = "NotBan[" }
} )

UnitTest:Test( "CheckPlayerName returns nothing when pattern filter is invalid", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "NotBanned", "NSPlayer" )
	Assert.Nil( "Name should be accepted", Name )
	Assert.True( "Should have marked the filter as invalid", Plugin.InvalidFilters[ Plugin.Filters[ 1 ] ] )
end )

SetFilters( {
	{ Pattern = "BannedN[a]+me", Excluded = USER_ID }
} )

UnitTest:Test( "CheckPlayerName returns nothing when player matches the filter exclusion for a single user ID", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "BannedNaaaame", "NSPlayer" )
	Assert.Nil( "Name should be accepted", Name )
end )

SetFilters( {
	{ Pattern = "BannedN[a]+me", Excluded = { 123, "456", USER_ID } }
} )

UnitTest:Test( "CheckPlayerName returns nothing when player matches the filter exclusion for a list of user IDs", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "BannedNaaaame", "NSPlayer" )
	Assert.Nil( "Name should be accepted", Name )
end )

SetFilters( {
	{ Pattern = "BannedN[a]+me", Excluded = { [ "123" ] = true, [ "456" ] = true, [ tostring( USER_ID ) ] = true } }
} )

UnitTest:Test( "CheckPlayerName returns nothing when player matches the filter exclusion for a lookup of user IDs", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "BannedNaaaame", "NSPlayer" )
	Assert.Nil( "Name should be accepted", Name )
end )

SetFilters( {
	{ Pattern = "BannedN[a]+me", PlainText = true }
} )

UnitTest:Test( "CheckPlayerName returns new name when plain filter matches", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "BannedN[a]+me", "NSPlayer" )
	Assert.Equals( "Name should be rejected", "NSPlayer654321", Name )
end )

UnitTest:Test( "CheckPlayerName returns nothing when plain filter does not match", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "NotBannedName", "NSPlayer" )
	Assert.Nil( "Name should be accepted", Name )
end )
