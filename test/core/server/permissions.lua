--[[
	Permissions system unit test.
]]

local UnitTest = Shine.UnitTest
local OldUserData = Shine.UserData

Shine.UserData = {
	Users = {
		[ "123" ] = {
			Group = "SuperAdmin",
			Immunity = 25
		},
		[ "456" ] = {
			Group = "Admin"
		},
		[ "789" ] = {
			Group = "Member"
		},
		[ "100" ] = {
			Group = "Moderator"
		}
	},
	Groups = {
		SuperAdmin = {
			IsBlacklist = true,
			Commands = {
				"sh_randomimmune"
			},
			Immunity = 100
		},
		Admin = {
			IsBlacklist = true,
			InheritsFrom = { "SuperAdmin" },
			Commands = {
				"sh_loadplugin", "sh_unloadplugin"
			},
			Immunity = 50
		},
		Moderator = {
			IsBlacklist = false,
			InheritsFrom = { "Member" },
			Commands = {
				"sh_ban", "sh_slay"
			},
			Immunity = 25
		},
		Member = {
			IsBlacklist = false,
			Commands = {
				"sh_kick"
			},
			Immunity = 10
		}
	},
	DefaultGroup = {
		Badges = {
			[ "3" ] = {
				"defaultbadge"
			}
		}
	}
}

---- GETTER TESTS ----
UnitTest:Test( "GetUserData", function ( Assert )
	for ID in pairs( Shine.UserData.Users ) do
		Assert:Truthy( Shine:GetUserData( tonumber( ID ) ) )
	end

	Shine.UserData.Users[ "STEAM_0:0:100" ] = {}
	Assert:Truthy( Shine:GetUserData( 200 ) )

	Shine.UserData.Users[ "[U:1:300]" ] = {}
	Assert:Truthy( Shine:GetUserData( 300 ) )
end, function()
	Shine.UserData.Users[ "STEAM_0:0:100" ] = nil
	Shine.UserData.Users[ "[U:1:300]" ] = nil
end )

UnitTest:Test( "GetGroupData", function( Assert )
	for Name in pairs( Shine.UserData.Groups ) do
		Assert:Truthy( Shine:GetGroupData( Name ) )
	end
end )

UnitTest:Test( "GetDefaultGroup", function( Assert )
	Assert:Truthy( Shine:GetDefaultGroup() )
end )

UnitTest:Test( "GetDefaultImmunity", function( Assert )
	Assert:Equals( 0, Shine:GetDefaultImmunity() )
end )

UnitTest:Test( "GetUserImmunity", function( Assert )
	Assert:Equals( 25, Shine:GetUserImmunity( 123 ) )
	Assert:Equals( 50, Shine:GetUserImmunity( 456 ) )
end )

UnitTest:Test( "IsInGroup", function( Assert )
	Assert:Truthy( Shine:IsInGroup( { GetUserId = function() return 123 end }, "SuperAdmin" ) )
end )

---- GROUP PERMISSION TESTS ----
UnitTest:Test( "GetGroupPermission", function( Assert )
	local GroupName = "SuperAdmin"
	local GroupTable = Shine:GetGroupData( GroupName )

	Assert:Truthy( Shine:GetGroupPermission( GroupName, GroupTable, "sh_kick" ) )
	Assert:Truthy( Shine:GetGroupPermission( GroupName, GroupTable, "sh_loadplugin" ) )

	GroupName = "Admin"
	GroupTable = Shine:GetGroupData( GroupName )

	Assert:Truthy( Shine:GetGroupPermission( GroupName, GroupTable, "sh_kick" ) )
	Assert:Falsy( Shine:GetGroupPermission( GroupName, GroupTable, "sh_loadplugin" ) )

	GroupName = "Moderator"
	GroupTable = Shine:GetGroupData( GroupName )
	Assert:Truthy( Shine:GetGroupPermission( GroupName, GroupTable, "sh_kick" ) )
	Assert:Falsy( Shine:GetGroupPermission( GroupName, GroupTable, "sh_loadplugin" ) )

	GroupName = "Member"
	GroupTable = Shine:GetGroupData( GroupName )
	Assert:Truthy( Shine:GetGroupPermission( GroupName, GroupTable, "sh_kick" ) )
	Assert:Falsy( Shine:GetGroupPermission( GroupName, GroupTable, "sh_loadplugin" ) )
end )

UnitTest:Test( "GetGroupAccess", function( Assert )
	local GroupName = "SuperAdmin"
	local GroupTable = Shine:GetGroupData( GroupName )

	Assert:Truthy( Shine:GetGroupAccess( GroupName, GroupTable, "sh_kick" ) )
	Assert:Falsy( Shine:GetGroupAccess( GroupName, GroupTable, "sh_randomimmune" ) )

	GroupName = "Admin"
	GroupTable = Shine:GetGroupData( GroupName )

	Assert:Truthy( Shine:GetGroupAccess( GroupName, GroupTable, "sh_kick" ) )
	Assert:Falsy( Shine:GetGroupAccess( GroupName, GroupTable, "sh_randomimmune" ) )

	GroupName = "Moderator"
	GroupTable = Shine:GetGroupData( GroupName )
	Assert:Truthy( Shine:GetGroupAccess( GroupName, GroupTable, "sh_kick" ) )
	Assert:Falsy( Shine:GetGroupAccess( GroupName, GroupTable, "sh_randomimmune" ) )

	GroupName = "Member"
	GroupTable = Shine:GetGroupData( GroupName )
	Assert:Truthy( Shine:GetGroupAccess( GroupName, GroupTable, "sh_kick" ) )
	Assert:Falsy( Shine:GetGroupAccess( GroupName, GroupTable, "sh_randomimmune" ) )
end )

---- USER PERMISSION TESTS ----
UnitTest:Test( "Default group targeting", function( Assert )
	Assert:Truthy( Shine:CanTarget( 999, 998 ) )
	Assert:Falsy( Shine:CanTarget( 999, 123 ) )
	Assert:Truthy( Shine:CanTarget( 123, 999 ) )
end )

UnitTest:Test( "Immunity between users", function( Assert )
	Assert:Falsy( Shine:CanTarget( 123, 456 ) )
	Assert.Truthy( "Per-user immunity value should be used", Shine:CanTarget( 456, 123 ) )

	Assert:Falsy( Shine:CanTarget( 789, 456 ) )
	Assert:Truthy( Shine:CanTarget( 456, 789 ) )
end )

UnitTest:Test( "Default group user permissions", function( Assert )
	Assert:Falsy( Shine:GetPermission( 999, "sh_kick" ) )
	Assert:Falsy( Shine:HasAccess( 999, "sh_kick" ) )
end )

UnitTest:Test( "Blacklist", function( Assert )
	Assert:Truthy( Shine:GetPermission( 123, "sh_kick" ) )
	Assert:Falsy( Shine:HasAccess( 123, "sh_randomimmune" ) )
end )

UnitTest:Test( "Whitelist", function( Assert )
	Assert:Truthy( Shine:GetPermission( 789, "sh_kick" ) )
	Assert:Falsy( Shine:GetPermission( 789, "sh_ban" ) )
end )

UnitTest:Test( "Blacklist inheritance", function( Assert )
	Assert:Truthy( Shine:GetPermission( 456, "sh_kick" ) )
	Assert:Falsy( Shine:HasAccess( 456, "sh_randomimmune" ) )
	Assert:Falsy( Shine:GetPermission( 456, "sh_loadplugin" ) )
end )

UnitTest:Test( "Whitelist inheritance", function( Assert )
	Assert:Truthy( Shine:GetPermission( 100, "sh_kick" ) )
	Assert:Truthy( Shine:GetPermission( 100, "sh_ban" ) )
	Assert:Truthy( Shine:GetPermission( 100, "sh_slay" ) )
end )

Shine.UserData = OldUserData
