--[[
	Permissions system unit test.
]]

local UnitTest = Shine.UnitTest
local OldUserData = Shine.UserData
local OldSaveUsers = Shine.SaveUsers

Shine.SaveUsers = function() end

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

UnitTest:Test( "CreateGroup", function( Assert )
	local Group = Shine:CreateGroup( "Test", 15, true )
	Assert:Equals( 15, Group.Immunity )
	Assert:True( Group.IsBlacklist )
	Assert:Equals( Group, Shine.UserData.Groups.Test )
end )

UnitTest:Test( "ReinstateGroup", function( Assert )
	local Group = {}
	Shine:ReinstateGroup( "Test", Group )

	Assert:Equals( Group, Shine.UserData.Groups.Test )
end )

UnitTest:Test( "DeleteGroup", function( Assert )
	Shine.UserData.Groups.Test = nil

	Assert:False( Shine:DeleteGroup( "Test" ) )

	Shine.UserData.Groups.Test = {}
	Assert:True( Shine:DeleteGroup( "Test" ) )
	Assert:Nil( Shine.UserData.Groups.Test )
end )

UnitTest:Test( "CreateUser", function( Assert )
	local User = Shine:CreateUser( 123456, "Test" )
	Assert:Equals( "Test", User.Group )
	Assert:Equals( User, Shine.UserData.Users[ "123456" ] )
end )

UnitTest:Test( "ReinstateUser", function( Assert )
	local User = {}
	Assert:True( Shine:ReinstateUser( 123456, User ) )
	Assert:Equals( User, Shine.UserData.Users[ "123456" ] )
end )

UnitTest:Test( "DeleteUser", function( Assert )
	Shine.UserData.Users[ "123456" ] = nil

	Assert:False( Shine:DeleteUser( 123456 ) )

	Shine.UserData.Users[ "123456" ] = {}
	Assert:True( Shine:DeleteUser( 123456 ) )
	Assert:Nil( Shine.UserData.Users[ "123456" ] )
end )

UnitTest:Test( "AddGroupInheritance", function( Assert )
	local Group = {}
	Shine.UserData.Groups.Test = Group

	Assert:True( Shine:AddGroupInheritance( "Test", "Member" ) )
	Assert:ArrayEquals( { "Member" }, Group.InheritsFrom )

	Assert:False( Shine:AddGroupInheritance( "Test", "Member" ) )
	Assert:ArrayEquals( { "Member" }, Group.InheritsFrom )

	Assert:True( Shine:AddGroupInheritance( "Test", "Moderator" ) )
	Assert:ArrayEquals( { "Member", "Moderator" }, Group.InheritsFrom )
end )

UnitTest:Test( "RemoveGroupInheritance", function( Assert )
	local Group = {
		InheritsFrom = { "Member", "Moderator" }
	}
	Shine.UserData.Groups.Test = Group

	Assert:True( Shine:RemoveGroupInheritance( "Test", "Member" ) )
	Assert:ArrayEquals( { "Moderator" }, Group.InheritsFrom )

	Assert:False( Shine:RemoveGroupInheritance( "Test", "Member" ) )
end )

UnitTest:Test( "AddGroupAccess", function( Assert )
	local Group = {
		Commands = {}
	}
	Shine.UserData.Groups.Test = Group

	Assert:True( Shine:AddGroupAccess( "Test", "sh_test" ) )
	Assert:ArrayEquals( { "sh_test" }, Group.Commands )

	Assert:True( Shine:AddGroupAccess( "Test", "sh_test2" ) )
	Assert:ArrayEquals( { "sh_test", "sh_test2" }, Group.Commands )
end )

UnitTest:Test( "RevokeGroupAccess", function( Assert )
	local Group = {
		Commands = { "sh_test", "sh_test2" }
	}
	Shine.UserData.Groups.Test = Group

	Assert:True( Shine:RevokeGroupAccess( "Test", "sh_test" ) )
	Assert:ArrayEquals( { "sh_test2" }, Group.Commands )

	Assert:True( Shine:RevokeGroupAccess( "Test", "sh_test2" ) )
	Assert:ArrayEquals( {}, Group.Commands )
end )

Shine.UserData = OldUserData
Shine.SaveUsers = OldSaveUsers
