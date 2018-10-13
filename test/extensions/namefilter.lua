--[[
	Name filter plugin tests.
]]

local UnitTest = Shine.UnitTest

local Plugin = UnitTest:LoadExtension( "namefilter" )
if not Plugin then return end

Plugin = UnitTest.MockOf( Plugin )
Plugin.Config.ForcedNames = {
	[ "123456" ] = "Test"
}

local USER_ID = 123456
local MockClient = {
	GetUserId = function() return USER_ID end
}
local MockPlayer = {
	GetClient = function() return MockClient end
}

UnitTest:Test( "EnforceName returns enforced name", function( Assert )
	local Name = Plugin:EnforceName( MockClient )
	Assert.Equals( "Name should be enforced", "Test", Name )
end )

USER_ID = 654321
UnitTest:Test( "EnforceName returns nothing when no name is enforced", function( Assert )
	local Name = Plugin:EnforceName( MockClient )
	Assert.Nil( "Name should be enforced", Name )
end )

Plugin.Config.FilterAction = Plugin.FilterActionType.RENAME
Plugin.Config.Filters = {
	{ Pattern = "BannedN[a]+me" }
}

UnitTest:Test( "CheckPlayerName returns new name when pattern filter matches", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "BannedNaaaame", "NSPlayer" )
	Assert.NotEquals( "Name should be rejected", "BannedNaaaame", Name )
end )

UnitTest:Test( "CheckPlayerName returns nothing when pattern filter does not match", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "NotBanned", "NSPlayer" )
	Assert.Nil( "Name should be accepted", Name )
end )

Plugin.Config.Filters = {
	{ Pattern = "BannedN[a]+me", PlainText = true }
}
UnitTest:Test( "CheckPlayerName returns new name when plain filter matches", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "BannedN[a]+me", "NSPlayer" )
	Assert.NotEquals( "Name should be rejected", "BannedN[a]+me", Name )
end )

UnitTest:Test( "CheckPlayerName returns nothing when plain filter does not match", function( Assert )
	local Name = Plugin:CheckPlayerName( MockPlayer, "NotBannedName", "NSPlayer" )
	Assert.Nil( "Name should be accepted", Name )
end )
