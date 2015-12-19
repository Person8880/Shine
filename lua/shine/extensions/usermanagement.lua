--[[
	Shine user management plugin.

	All web requests follow the form:
	http://yoururl.com?operation=OPERATION_ID&data={"ID": "user/group ID","Data": {"User/Group data": "in here"}}
]]

local Shine = Shine

local Encode = json.encode
local Decode = json.decode
local StringFormat = string.format
local TableConcat = table.concat
local TableShallowMerge = table.ShallowMerge
local TableSort = table.sort
local tostring = tostring

local Plugin = {}

Plugin.PrintName = "User Management"
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "UserManagement.json"

Plugin.DefaultConfig = {
	-- Should the plugin send POST requests for changes made?
	SendActionsToURL = false,
	-- Where should the POST requests be sent to?
	APIURL = "",
	-- What extra arguments need to be provided?
	RequestArguments = {},
	-- How long should the plugin wait for a response before retrying?
	SubmitTimeout = 5,
	-- How many retries should it perform?
	MaxSubmitRetries = 3
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

do
	local function KeyMapping( Keys )
		local Map = {}
		for i = 1, #Keys do
			Map[ Keys[ i ] ] = Keys[ i ]
		end
		return Map
	end

	Plugin.Operation = KeyMapping{
		"EDIT_USER",
		"REMOVE_USER",

		"EDIT_GROUP",
		"REMOVE_GROUP"
	}
end

function Plugin:Initialise()
	self:CreateCommands()
	self.Enabled = true

	return true
end

function Plugin:SubmitOperation( OperationID, KeyValues, Revert )
	if not self.Config.SendActionsToURL then return end

	local Params = TableShallowMerge( self.Config.RequestArguments, {
		operation = OperationID,
		data = Encode( KeyValues )
	} )

	local function OnSuccess( Data )
		if not Data then
			self:Print( "Received no response for operation %s.", true, OperationID )
			return
		end

		local Decoded = Decode( Data )
		if not Decoded then
			self:Print( "Received invalid JSON in response for operation %s.", true, OperationID )
			return
		end

		if ( Decoded.success or Decoded.Success ) == false then
			Revert()
			self:Print( "Server rejected operation %s, reverting...", true, OperationID )
		end
	end

	local function OnFailure()
		self:Print( "Failed to submit %s after %i retries.", true, OperationID, self.Config.MaxSubmitRetries )
	end

	Shine.HTTPRequestWithRetry( self.Config.APIURL, "POST", Params,
		OnSuccess, OnFailure, self.Config.MaxSubmitRetries, self.Config.SubmitTimeout )
end

function Plugin:CreateCommands()
	local function SetField( Table, Field, Value )
		Table[ Field ] = Value
		Shine:SaveUsers( true )
	end

	local function FunctionCall( Func, ... )
		local Args = { ... }
		local NumArgs = select( "#", ... )
		return function()
			Func( unpack( Args, 1, NumArgs ) )
		end
	end

	local function CheckGroupExists( Client, GroupName )
		if not Shine:GetGroupData( GroupName ) then
			Shine:NotifyCommandError( Client, "No group named %s exists.", true, GroupName )
			return false
		end

		return true
	end

	local function CheckUserExists( Client, Target )
		if not Shine:GetUserData( Target ) then
			Shine:NotifyCommandError( Client, "No such user exists." )
			return false
		end

		return true
	end

	local function BuildHTTPData( ID, Data )
		return {
			ID = ID,
			Data = Data
		}
	end

	local Commands = {
		{
			ConCommand = "sh_setusergroup",
			ChatCommand = "setusergroup",
			PreCondition = function( Client, Target, GroupName )
				return CheckGroupExists( Client, GroupName )
			end,
			Action = function( Client, Target, GroupName )
				local Existing, ID = Shine:GetUserData( Target )
				local Undo

				if not Existing then
					Existing = Shine:CreateUser( Target, GroupName )
					Undo = FunctionCall( Shine.DeleteUser, Shine, ID )
				else
					local OldGroup = Existing.Group
					SetField( Existing, "Group", GroupName )
					Undo = FunctionCall( SetField, Existing, "Group", OldGroup )
				end

				Shine:AdminPrint( Client, "User %s now belongs to group %s.", true, ID, GroupName )

				return BuildHTTPData( ID, Existing ), Undo
			end,
			Operation = self.Operation.EDIT_USER,
			Params = {
				{ Type = { "client", "steamid" }, Error = "Please provide a user to set the group of." },
				{ Type = "string", Help = "group" }
			},
			Help = "Sets the group for the given user."
		},
		{
			ConCommand = "sh_setuserimmunity",
			ChatCommand = "setuserimmunity",
			PreCondition = CheckUserExists,
			Action = function( Client, Target, Immunity )
				local Existing, ID = Shine:GetUserData( Target )
				local OldImmunity = Existing.Immunity
				local Undo = FunctionCall( SetField, Existing, "Immunity", OldImmunity )

				SetField( Existing, "Immunity", Immunity )

				Shine:AdminPrint( Client, "User %s now has %s.", true, ID,
					Immunity and StringFormat( "immunity %i", Immunity ) or "no immunity" )

				return BuildHTTPData( ID, Existing ), Undo
			end,
			Operation = self.Operation.EDIT_USER,
			Params = {
				{ Type = { "client", "steamid" }, Error = "Please provide a user to set the immunity of." },
				{ Type = "number", Round = true, Optional = true, Help = "immunity" }
			},
			Help = "Sets the immunity level for a user. Omit the immunity value to reset it."
		},
		{
			ConCommand = "sh_removeuser",
			ChatCommand = "removeuser",
			PreCondition = CheckUserExists,
			Action = function( Client, Target )
				local User, ID = Shine:GetUserData( Target )
				local Undo = FunctionCall( Shine.ReinstateUser, Shine, ID, User )

				Shine:DeleteUser( Target )
				Shine:AdminPrint( Client, "Removed user %s.", true, ID )

				return BuildHTTPData( ID, User ), Undo
			end,
			Operation = self.Operation.REMOVE_USER,
			Params = {
				{ Type = { "client", "steamid" }, Error = "Please provide a user to remove." }
			},
			Help = "Removes the given user."
		},
		{
			ConCommand = "sh_creategroup",
			ChatCommand = "creategroup",
			PreCondition = function( Client, GroupName )
				if Shine:GetGroupData( GroupName ) then
					Shine:NotifyCommandError( Client, "A group with name '%s' already exists.", true, GroupName )
					return false
				end

				return true
			end,
			Action = function( Client, GroupName, Immunity, Blacklist )
				local NewGroup = Shine:CreateGroup( GroupName, Immunity, Blacklist )
				local Undo = FunctionCall( Shine.DeleteGroup, Shine, GroupName )

				Shine:AdminPrint( Client, "Group '%s' created. Immunity level %i. Commands are blacklist: %s.", true,
					GroupName, Immunity, Blacklist )

				return BuildHTTPData( GroupName, NewGroup ), Undo
			end,
			Operation = self.Operation.EDIT_GROUP,
			Params = {
				{ Type = "string", Error = "Please provide a name for the group.", Help = "groupname" },
				{ Type = "number", Optional = true, Default = 10, Help = "immunity" },
				{ Type = "boolean", Optional = true, Default = false, Help = "blacklist?" }
			},
			Help = "Creates a new group with the given name, immunity and blacklist setting."
		},
		{
			ConCommand = "sh_setgroupimmunity",
			ChatCommand = "setgroupimmunity",
			PreCondition = CheckGroupExists,
			Action = function( Client, GroupName, Immunity )
				local Group = Shine:GetGroupData( GroupName )
				local OldImmunity = Group.Immunity
				local Undo = FunctionCall( SetField, Group, "Immunity", OldImmunity )
				SetField( Group, "Immunity", Immunity )

				Shine:AdminPrint( Client, "Group '%s' now has immunity %i.", true, GroupName, Immunity )

				return BuildHTTPData( GroupName, Group ), Undo
			end,
			Operation = self.Operation.EDIT_GROUP,
			Params = {
				{ Type = "string", Error = "Please provide the name of the group to set immunity for.", Help = "groupname" },
				{ Type = "number", Error = "Please provide an immunity value.", Help = "immunity" }
			},
			Help = "Sets the immunity value for the given group."
		},
		{
			ConCommand = "sh_setgroupisblacklist",
			ChatCommand = "setgroupisblacklist",
			PreCondition = CheckGroupExists,
			Action = function( Client, GroupName, IsBlacklist )
				local Group = Shine:GetGroupData( GroupName )
				local OldIsBlacklist = Group.IsBlacklist
				local Undo = FunctionCall( SetField, Group, "IsBlacklist", OldIsBlacklist )
				SetField( Group, "IsBlacklist", IsBlacklist )

				Shine:AdminPrint( Client, "Group %s's commands are now a %s.", true,
					GroupName, IsBlacklist and "blacklist" or "whitelist" )

				return BuildHTTPData( GroupName, Group ), Undo
			end,
			Operation = self.Operation.EDIT_GROUP,
			Params = {
				{ Type = "string", Error = "Please provide the name of the group.", Help = "groupname" },
				{ Type = "boolean", Error = "Please provide whether the group's commands are a blacklist.", Help = "blacklist?" }
			},
			Help = "Sets whether the given group's commands are a blacklist or a whitelist."
		},
		{
			ConCommand = "sh_setgroupinheritance",
			ChatCommand = "setgroupinheritance",
			PreCondition = function( Client, GroupName, InheritGroup, Remove )
				return CheckGroupExists( Client, GroupName ) and ( Remove or CheckGroupExists( Client, InheritGroup ) )
			end,
			Action = function( Client, GroupName, InheritGroup, Remove )
				local Group = Shine:GetGroupData( GroupName )
				local Undo = FunctionCall( Remove and Shine.AddGroupInheritance or Shine.RemoveGroupInheritance,
					Shine, GroupName, InheritGroup )

				local Method = Remove and Shine.RemoveGroupInheritance or Shine.AddGroupInheritance
				Method( Shine, GroupName, InheritGroup )

				Shine:AdminPrint( Client, "Group '%s' now %s from %s.", true,
					GroupName, Remove and "no longer inherits" or "inherits", InheritGroup )

				return BuildHTTPData( GroupName, Group ), Undo
			end,
			Operation = self.Operation.EDIT_GROUP,
			Params = {
				{ Type = "string", Error = "Please provide the name of the group to edit.", Help = "groupname" },
				{ Type = "string", Error = "Please provide the name of the group being inherited.", Help = "inheriting group" },
				{ Type = "boolean", Optional = true, Default = false, Help = "remove?" }
			},
			Help = "Sets whether the given group inherits from the given inheriting group or not."
		},
		{
			ConCommand = "sh_setgroupaccess",
			ChatCommand = "setgroupaccess",
			PreCondition = CheckGroupExists,
			Action = function( Client, GroupName, Access, Revoke )
				local Group = Shine:GetGroupData( GroupName )
				local Undo = FunctionCall( Revoke and Shine.AddGroupAccess or Shine.RevokeGroupAccess,
					Shine, GroupName, Access )

				local Method = Revoke and Shine.RevokeGroupAccess or Shine.AddGroupAccess
				Method( Shine, GroupName, Access )

				Shine:AdminPrint( Client, "Group '%s' now %s to %s.", true,
					GroupName, Revoke and "no longer has access to" or "has access to", Access )

				return BuildHTTPData( GroupName, Group ), Undo
			end,
			Operation = self.Operation.EDIT_GROUP,
			Params = {
				{ Type = "string", Error = "Please provide a group name.", Help = "groupname" },
				{ Type = "string", Error = "Please provide an access string.", Help = "access string" },
				{ Type = "boolean", Optional = true, Default = false, Help = "revoke?" }
			},
			Help = "Sets whether the given group has access to the given access string."
		},
		{
			ConCommand = "sh_removegroup",
			ChatCommand = "removegroup",
			PreCondition = CheckGroupExists,
			Action = function( Client, GroupName )
				local Group = Shine:GetGroupData( GroupName )
				local Undo = FunctionCall( Shine.ReinstateGroup, Shine, GroupName, Group )

				Shine:DeleteGroup( GroupName )

				Shine:AdminPrint( Client, "Group '%s' has been deleted.", true, GroupName )

				return BuildHTTPData( GroupName, Group ), Undo
			end,
			Operation = self.Operation.REMOVE_GROUP,
			Params = {
				{ Type = "string", Error = "Please provide a group name.", Help = "groupname", TakeRestOfLine = true },
			},
			Help = "Deletes the given group."
		},
		{
			ConCommand = "sh_groupinfo",
			PreCondition = function() return true end,
			Action = function( Client, GroupName )
				if not GroupName then
					local Columns = {
						{
							Name = "Name",
							Getter = function( Entry )
								return StringFormat( "'%s'", Entry.Name )
							end
						},
						{
							Name = "Immunity",
							Getter = function( Entry )
								return tostring( Entry.Immunity )
							end
						},
						{
							Name = "Is Blacklist",
							Getter = function( Entry )
								return Entry.IsBlacklist and "Yes" or "No"
							end
						},
						{
							Name = "Inherits Groups",
							Getter = function( Entry )
								return Entry.InheritsFrom and StringFormat( "'%s'", TableConcat( Entry.InheritsFrom, "', '" ) ) or ""
							end
						}
					}

					local Data = {}
					for Group, GroupData in pairs( Shine.UserData.Groups ) do
						Data[ #Data + 1 ] = {
							Name = Group,
							Immunity = GroupData.Immunity,
							IsBlacklist = GroupData.IsBlacklist,
							InheritsFrom = GroupData.InheritsFrom
						}
					end

					TableSort( Data, function( A, B )
						local Comparison = 0
						if A.Immunity > B.Immunity then
							Comparison = -2
						elseif A.Immunity < B.Immunity then
							Comparison = 2
						end

						Comparison = Comparison + ( A.Name < B.Name and -1 or 1 )

						return Comparison < 0
					end )

					Shine.PrintTableToConsole( Client, Columns, Data )
					return
				end

				if not CheckGroupExists( GroupName ) then return end

				local Group = Shine:GetGroupData( GroupName )
				Shine.PrintToConsole( Client, StringFormat( "Displaying information for group '%s':", GroupName ) )
				Shine.PrintToConsole( Client, StringFormat( "Commands:\n%s", TableConcat( Group.Commands, ", " ) ) )
				Shine.PrintToConsole( Client, StringFormat( "Immunity: %i", Group.Immunity ) )
				Shine.PrintToConsole( Client, StringFormat( "Commands are a blacklist: %s", Group.IsBlacklist and "Yes" or "No" ) )
				if Group.InheritsFrom then
					Shine.PrintToConsole( Client, StringFormat( "Inherits from: %s", TableConcat( Group.InheritsFrom, ", " ) ) )
				else
					Shine.PrintToConsole( Client, "Group does not inherit from any other groups." )
				end
			end,
			Params = {
				{ Type = "string", TakeRestOfLine = true, Help = "groupname", Optional = true }
			},
			Help = "Displays information on the currently configured groups. Pass a group name to display more information."
		},
		{
			ConCommand = "sh_listusers",
			PreCondition = function() return true end,
			Action = function( Client )
				local Columns = {
					{
						Name = "ID",
						Getter = function( Entry )
							return StringFormat( "%s", Entry.ID )
						end
					},
					{
						Name = "Group",
						Getter = function( Entry )
							return StringFormat( "'%s'", Entry.Group )
						end
					},
					{
						Name = "Immunity",
						Getter = function( Entry )
							return tostring( Entry.Immunity or "None" )
						end
					}
				}

				local Data = {}
				for ID, UserData in pairs( Shine.UserData.Users ) do
					Data[ #Data + 1 ] = {
						ID = ID,
						Group = UserData.Group,
						Immunity = UserData.Immunity
					}
				end

				TableSort( Data, function( A, B )
					local Comparison = 0
					if A.Group > B.Group then
						Comparison = -2
					elseif A.Group < B.Group then
						Comparison = 2
					end

					Comparison = Comparison + ( ( A.Immunity or 0 ) < ( B.Immunity or 0 ) and -1 or 1 )

					return Comparison < 0
				end )

				Shine.PrintTableToConsole( Client, Columns, Data )
			end,
			Help = "Lists all users to the console."
		}
	}

	for i = 1, #Commands do
		local Command = Commands[ i ]
		local CommandObj = self:BindCommand( Command.ConCommand, Command.ChatCommand, function( ... )
			if not Command.PreCondition( ... ) then return end

			local KeyValues, Undo = Command.Action( ... )
			if not Command.Operation then return end

			self:SubmitOperation( Command.Operation, KeyValues, Undo )
		end )

		if Command.Params then
			for i = 1, #Command.Params do
				CommandObj:AddParam( Command.Params[ i ] )
			end
		end

		CommandObj:Help( Command.Help )
	end
end

Shine:RegisterExtension( "usermanagement", Plugin )
