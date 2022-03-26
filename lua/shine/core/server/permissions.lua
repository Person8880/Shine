--[[
	Shine permissions/user ranking system.
]]

local Shine = Shine

Shine.UserData = {}

local Decode = json.decode
local GetClientById = Server.GetClientById
local IsType = Shine.IsType
local next = next
local pairs = pairs
local StringLower = string.lower
local StringFormat = string.format
local TableDeepEquals = table.DeepEquals
local TableEmpty = table.Empty
local TableInsertUnique = table.InsertUnique
local TableRemove = table.remove
local TableRemoveByValue = table.RemoveByValue
local tonumber = tonumber
local tostring = tostring

local UserPath = "config://shine/UserConfig.json"
local BackupPath = "config://Shine_UserConfig.json"
local DefaultUsers = "config://ServerAdmin.json"

local CommandMapping = {
	sv_hasreserve = "sh_reservedslot",
	sv_rrall = "sh_rr",
	sv_afkimmune = "sh_afk",
	sv_randomall = "sh_forcerandom",
	sv_switchteam = "sh_setteam",
	sv_maps = "sh_listmaps",
	sv_randomon = "sh_enablerandom",
	sv_cancelmapvote = "sh_veto",
	sv_nick = "sh_rename",
	sv_reloadplugins = "sh_loadplugin",
	sv_dontrandom = "sh_randomimmune"
}

local function ConvertCommands( Commands )
	local Ret = {}

	for i = 1, #Commands do
		local Command = Commands[ i ]
		local Equivalent = CommandMapping[ Command ]

		if Equivalent then
			Ret[ i ] = Equivalent
		else
			Ret[ i ] = Command:gsub( "sv", "sh" )
		end
	end

	return Ret
end

--[[
	Converts the default/DAK style user file into one compatible with Shine.
]]
local function ConvertData( Data, Silent )
	if Data.groups then
		if not Silent then
			Shared.Message( "Converting user groups from NS2/DAK format to Shine format..." )
		end

		Data.Groups = Data.Groups or {}

		for Name, Vals in pairs( Data.groups ) do
			if IsType( Vals, "table" ) then
				if Vals.type or Vals.commands or Vals.level then
					Data.Groups[ Name ] = {
						IsBlacklist = Vals.type == "disallowed",
						Commands = Vals.commands and ConvertCommands( Vals.commands ) or {},
						Immunity = Vals.level or 10,
						Badge = Vals.badge,
						Badges = Vals.badges
					}
				-- Someone's called it "groups" without knowing it's case sensitive...
				elseif Vals.Commands and Vals.Immunity then
					Data.Groups[ Name ] = Vals
				end
			else
				Shared.Message( StringFormat(
					"Malformed group entry at key \"%s\" in \"groups\" table (expected table, got %s)",
					Name, type( Vals )
				) )
			end
		end

		Data.groups = nil
	end

	if Data.users then
		if not Silent then
			Shared.Message( "Converting users from NS2/DAK format to Shine format..." )
		end

		Data.Users = Data.Users or {}

		for Name, Vals in pairs( Data.users ) do
			if IsType( Vals, "table" ) then
				if Vals.id then
					Data.Users[ tostring( Vals.id ) ] = {
						Group = Vals.groups and Vals.groups[ 1 ],
						Immunity = Vals.level,
						Badge = Vals.badge,
						Badges = Vals.badges
					}
				-- Someone's called it "users" without knowing it's case sensitive...
				elseif Vals.Group or Vals.Immunity or Vals.Badge or Vals.Badges then
					Data.Users[ Name ] = Vals
				end
			else
				Shared.Message( StringFormat(
					"Malformed user entry at key \"%s\" in \"users\" table (expected table, got %s)",
					Name, type( Vals )
				) )
			end
		end

		Data.users = nil
	end

	return Data
end

-- Basic type-level validation. Other mistakes are handled more leniently.
local UserDataValidator = Shine.Validator()
UserDataValidator:AddFieldRule(
	"Groups",
	UserDataValidator.IsType( "table", {} ),
	UserDataValidator.AllKeyValuesSatisfy(
		UserDataValidator.IsType( "table" )
	)
)
UserDataValidator:AddFieldRule(
	"Users",
	UserDataValidator.IsType( "table", {} ),
	UserDataValidator.AllKeyValuesSatisfy(
		UserDataValidator.IsType( "table" )
	)
)
UserDataValidator:AddFieldRule(
	"DefaultGroup",
	UserDataValidator.IsAnyType( { "table", "nil" } )
)

local function ValidateUserData( UserData )
	return UserDataValidator:Validate( UserData )
end

Shine.UserDataReloadTriggerType = table.AsEnum( {
	-- Indicates the reload occurred due to the initial loading of remote user data.
	"INITIAL_WEB_LOAD",
	-- Indicates a standard reload.
	"RELOAD"
} )

function Shine:RequestUsers( Reload )
	local Callbacks = {
		OnSuccess = function( Response, RequestError )
			if not Response or RequestError then
				self:Print(
					"Failed to retrieve users from server: %s. Using local file instead.",
					true,
					RequestError or "no response received"
				)
				return
			end

			-- Decode the JSON asynchronously to account for a possible large user data file. Decoding all at once
			-- may cause a noticeable freeze which can interrupt gameplay.
			Shine.DecodeJSONAsync( Response, function( UserData, Pos, Err )
				if not IsType( UserData, "table" ) or not next( UserData ) then
					-- Don't replace with a blank table if request failed when reloading.
					Err = Err or "received empty response"

					Shine.SystemNotifications:AddNotification( {
						ID = "Core_RemoteUserConfig_SyntaxErrors",
						Type = Shine.SystemNotifications.Type.WARNING,
						Message = {
							Source = "Core",
							TranslationKey = "WARNING_INVALID_JSON_IN_REMOTE_USER_CONFIG",
							Context = Err
						},
						Source = {
							Type = Shine.SystemNotifications.Source.CORE
						}
					} )

					if Reload then
						self:AdminPrint(
							nil,
							"Reloading user data from the web failed. User data has not been changed. Error: %s",
							true,
							Err
						)

						return
					end

					self:Print( "Loading from the web failed. Using local file instead. Error: %s", true, Err )

					return
				end

				self:Print( "Validating remote Shine user data..." )

				UserData = ConvertData( UserData, true )

				if ValidateUserData( UserData ) then
					Shine.SystemNotifications:AddNotification( {
						ID = "Core_RemoteUserConfig_ValidationErrors",
						Type = Shine.SystemNotifications.Type.WARNING,
						Message = {
							Source = "Core",
							TranslationKey = "WARNING_REMOTE_USER_CONFIG_VALIDATION_ERRORS",
							Context = ""
						},
						Source = {
							Type = Shine.SystemNotifications.Source.CORE
						}
					} )
				end

				if not TableDeepEquals( UserData, self.UserData ) then
					self.UserData = UserData

					-- Cache the current user data, so if we fail to load it on a later map we still have something to
					-- load.
					self:SaveUsers( true )
					self:Print( Reload and "Shine reloaded users from the web." or "Shine loaded users from web." )

					local TriggerType = self.UserDataReloadTriggerType[ Reload and "RELOAD" or "INITIAL_WEB_LOAD" ]

					self.Hook.Broadcast( "OnUserReload", TriggerType )
				else
					-- If the data hasn't changed, avoid calling the reload hook and saving the file to avoid
					-- unnecessary work.
					self:Print( "No changes in remote user data, continuing to use existing cached user data." )
				end
			end )
		end,
		OnFailure = function()
			self:Print( "All attempts to load users from the web failed. Using local file instead." )
		end
	}

	if self.Config.GetUsersWithPOST then
		self.HTTPRequestWithRetry( self.Config.UsersURL, "POST",
			self.Config.UserRetrieveArguments, Callbacks )
	else
		self.HTTPRequestWithRetry( self.Config.UsersURL, "GET", Callbacks )
	end
end

--[[
	Loads the Shine user data either from a local JSON file or from one hosted on a webserver.
	If retrieving the web users fails, it will fall back to a local file.
	If a local file does not exist, the default is created and used.
]]
function Shine:LoadUsers( Web, Reload )
	if Web then
		if Reload then
			self:RequestUsers( true )
		else
			-- Load the local data upfront.
			self:LoadUsers()
			-- Queue loading the up-to-date data.
			self.Hook.Add( "ClientConnect", "LoadUsers", function( Client )
				self.Hook.Remove( "ClientConnect", "LoadUsers" )
				self:RequestUsers()
			end, self.Hook.MAX_PRIORITY )
		end

		return
	end

	Shared.Message( "Loading Shine users..." )

	-- Check the default path.
	local UserFile, Pos, Err = self.LoadJSONFile( UserPath )
	local NeedsSaving = false

	if UserFile == false then
		UserFile, Pos, Err = self.LoadJSONFile( BackupPath ) -- Check the secondary path.

		if UserFile == false then
			UserFile, Pos, Err = self.LoadJSONFile( DefaultUsers ) -- Check the default NS2 users file.

			if not UserFile then
				self:GenerateDefaultUsers( true )

				return
			end

			UserFile = ConvertData( UserFile )
			NeedsSaving = true
		end
	end

	if not IsType( UserFile, "table" ) or not next( UserFile ) then
		Err = Err or "configuration is empty"

		Shared.Message( StringFormat( "The user data file is not valid JSON, unable to load user data. Error: %s",
			Err ) )

		-- Dummy data to avoid errors.
		if not Reload then
			self.UserData = { Groups = {}, Users = {} }
		end

		return
	end

	Shared.Message( "Validating Shine user data..." )

	if ValidateUserData( UserFile ) then
		NeedsSaving = true

		-- Warn about validation errors, but not about invalid JSON as if the user config can't be loaded, no one will
		-- have access to see the error message.
		Shine.SystemNotifications:AddNotification( {
			Type = Shine.SystemNotifications.Type.WARNING,
			Message = {
				Source = "Core",
				TranslationKey = "WARNING_USER_CONFIG_VALIDATION_ERRORS",
				Context = ""
			},
			Source = {
				Type = Shine.SystemNotifications.Source.CORE
			}
		} )
	end

	self.UserData = UserFile

	if NeedsSaving then
		self:SaveUsers()
	end

	if Reload then
		self.Hook.Broadcast( "OnUserReload", self.UserDataReloadTriggerType.RELOAD )
	end
end

--[[
	Saves the Shine user data to the JSON file.
]]
function Shine:SaveUsers( Silent )
	local Success, Err = self.SaveJSONFile( self.UserData, UserPath )

	if not Success then
		Shared.Message( "Error writing user file: "..Err )

		return
	end

	if not Silent then
		Shared.Message( "Saving Shine users..." )
	end
end

--[[
	Generates the default users and groups.
	Optionally saves the default settings to a local JSON file.
]]
function Shine:GenerateDefaultUsers( Save )
	self.UserData = {
		Groups = {
			SuperAdmin = { IsBlacklist = true, Commands = {}, Immunity = 100 },
			Admin = { IsBlacklist = false, Commands = { "sh_kick", "sh_ban" }, Immunity = 50 },
			Mod = { IsBlacklist = false, Commands = { "sh_kick" }, Immunity = 10 }
		},
		Users = {
			[ "90000000000001" ] = { Group = "Mod", Immunity = 2 }
		}
	}

	if Save then
		self:SaveUsers()
	end
end

--[[
	We need to load the users after loading the configuration file.
	This ensures we know whether we should be getting them from the web or not.
]]
Shine.Hook.Add( "PostloadConfig", "LoadShineUsers", function()
	local WebUsers = Shine.Config.GetUsersFromWeb
	Shine:LoadUsers( WebUsers )

	if WebUsers and Shine.Config.RefreshUsers then
		Shine.Timer.Create( "UserRefresh", Shine.Config.RefreshInterval or 60, -1, function()
			Shine:RequestUsers( true )
		end )
	end
end )

--[[
	Game IDs handling.
]]
do
	local GameIDs = Shine.Map()
	Shine.GameIDs = GameIDs

	local GameID = 0
	local HumanPlayerCount = 0
	local function GetHumanPlayerCount()
		return HumanPlayerCount
	end
	Shine.GetHumanPlayerCount = GetHumanPlayerCount

	Shine.Hook.Add( "ClientConnect", "AssignGameID", function( Client )
		-- Make sure the same client isn't seen twice.
		if GameIDs:Get( Client ) then return true end

		GameID = GameID + 1
		GameIDs:Add( Client, GameID )
		Client.ShineGameID = GameID

		HumanPlayerCount = HumanPlayerCount + ( Client:GetIsVirtual() and 0 or 1 )
	end, Shine.Hook.MAX_PRIORITY )

	Shine.Hook.Add( "ClientDisconnect", "AssignGameID", function( Client )
		if not GameIDs:Remove( Client ) then return true end

		HumanPlayerCount = HumanPlayerCount - ( Client:GetIsVirtual() and 0 or 1 )
	end, Shine.Hook.MAX_PRIORITY )
end

local function GetIDFromClient( Client )
	if IsType( Client, "number" ) then
		-- It's an NS2ID
		return Client
	end

	if IsType( Client, "string" ) then
		-- It might be an NS2ID as a string
		return tonumber( Client )
	end

	-- It might be a client
	return Client.GetUserId and Client:GetUserId()
end

--[[
	Gets the user data table for the given client/NS2ID.
	Input: Client or NS2ID.
	Output: User data table if they are registered in UserConfig.json, user ID.
]]
function Shine:GetUserData( Client )
	if not self.UserData then return nil end
	if not self.UserData.Users then return nil end

	local ID = GetIDFromClient( Client )
	if not ID then return nil end

	local User = self.UserData.Users[ tostring( ID ) ]
	if not User then
		--Try the STEAM_0:X:YYYY format
		local SteamID = self.NS2ToSteamID( ID )
		User = self.UserData.Users[ SteamID ]
		if User then
			return User, SteamID
		end

		--Try the [U:1:YYYY] format
		local Steam3ID = self.NS2ToSteam3ID( ID )
		User = self.UserData.Users[ Steam3ID ]

		if User then
			return User, Steam3ID
		end

		return nil, ID
	end

	return User, ID
end

--[[
	Returns a list of all known group names.
]]
function Shine:GetGroupNames()
	if not self.UserData or not self.UserData.Groups then return {} end
	return Shine.Set( self.UserData.Groups ):AsList()
end

--[[
	Gets the group data table for the given group name.
	Input: Group name.
	Output: Group data table if it exists, nil otherwise.
]]
function Shine:GetGroupData( GroupName )
	if not GroupName then return self:GetDefaultGroup() end
	if not self.UserData then return nil end
	if not self.UserData.Groups then return nil end

	return self.UserData.Groups[ GroupName ]
end

--[[
	Gets the group data table for the default group if it exists.
]]
function Shine:GetDefaultGroup()
	if not self.UserData then return nil end
	if not self.UserData.DefaultGroup then return nil end

	self.UserData.DefaultGroup.InheritsFrom = nil
	self.UserData.DefaultGroup.InheritFromDefault = nil

	return self.UserData.DefaultGroup
end

--[[
	Gets the default immunity value. Usually 0.
]]
function Shine:GetDefaultImmunity()
	local DefaultGroup = self:GetDefaultGroup()

	if DefaultGroup then
		return tonumber( DefaultGroup.Immunity ) or 0
	end

	return 0
end

--[[
	Gets a client's immunity value.
	Input: Client or NS2ID.
	Output: Immunity value, 0 if they have no group/user.
]]
function Shine:GetUserImmunity( Client )
	if not Client then return 0 end
	if not self.UserData then return 0 end
	if not self.UserData.Groups then return 0 end

	local Data = self:GetUserData( Client )
	if not Data then
		return self:GetDefaultImmunity()
	end

	if Data.Immunity then return tonumber( Data.Immunity ) or 0 end

	local Group = Data.Group
	local GroupData = self.UserData.Groups[ Group ]

	if not GroupData then
		return self:GetDefaultImmunity()
	end

	return tonumber( GroupData.Immunity ) or 0
end

local PermissionCache = {}

function Shine:CreateGroup( GroupName, Immunity, Blacklist )
	Shine.TypeCheck( GroupName, "string", 1, "CreateGroup" )
	Shine.TypeCheck( Immunity, { "number", "nil" }, 2, "CreateGroup" )
	Shine.TypeCheck( Blacklist, { "boolean", "nil" }, 3, "CreateGroup" )

	local Group = {
		Immunity = Immunity or 10,
		IsBlacklist = Blacklist or false,
		Commands = {}
	}

	self.UserData.Groups[ GroupName ] = Group
	self:SaveUsers( true )

	Shine.Hook.Broadcast( "OnGroupCreated", GroupName, Group )

	return Group
end

function Shine:ReinstateGroup( GroupName, Group )
	Shine.TypeCheck( GroupName, "string", 1, "ReinstateGroup" )
	Shine.TypeCheck( Group, "table", 2, "ReinstateGroup" )

	self.UserData.Groups[ GroupName ] = Group
	self:SaveUsers( true )

	Shine.Hook.Broadcast( "OnGroupCreated", GroupName, Group )

	return true
end

function Shine:DeleteGroup( GroupName )
	local DeletedGroup = self.UserData.Groups[ GroupName ]
	if not DeletedGroup then return false end

	self.UserData.Groups[ GroupName ] = nil
	self:SaveUsers( true )

	PermissionCache[ GroupName ] = nil

	Shine.Hook.Broadcast( "OnGroupDeleted", GroupName, DeletedGroup )

	return true
end

function Shine:CreateUser( Client, GroupName )
	local ID = GetIDFromClient( Client )
	if not ID then return nil end

	local User = {
		Group = GroupName
	}

	self.UserData.Users[ tostring( ID ) ] = User
	self:SaveUsers( true )

	Shine.Hook.Broadcast( "OnUserCreated", ID, User )

	return User
end

function Shine:ReinstateUser( Client, User )
	local ID = GetIDFromClient( Client )
	if not ID then return false end

	self.UserData.Users[ tostring( ID ) ] = User
	self:SaveUsers( true )

	Shine.Hook.Broadcast( "OnUserCreated", ID, User )

	return true
end

function Shine:DeleteUser( Client )
	local ID = GetIDFromClient( Client )
	ID = ID and tostring( ID ) or Client

	local DeletedUser = self.UserData.Users[ ID ]
	if not DeletedUser then return false end

	self.UserData.Users[ ID ] = nil
	self:SaveUsers( true )

	Shine.Hook.Broadcast( "OnUserDeleted", ID, DeletedUser )

	return true
end

local function InitialPermissions()
	return {
		Commands = {},
		Denied = {}
	}
end

local function ToBool( Flag )
	-- Someone is bound to make this mistake...
	return Flag == true or Flag == "true"
end

local function AddCommand( Entry, Permissions, Blacklist )
	if IsType( Entry, "string" ) then
		if Blacklist or not Permissions.Commands[ Entry ] then
			Permissions.Commands[ Entry ] = true
		end
		return
	end

	if not IsType( Entry, "table" ) then return end

	local Command = Entry.Command
	if not Command then return end

	if Entry.Denied then
		-- This entry is explicitly a denial.
		if Blacklist then
			-- Not really expected in blacklists, but treat it as a normal entry.
			Permissions.Commands[ Command ] = true
			return
		end

		-- For whitelists, an explicit denial allows blocking access to commands
		-- that are allowed by default.
		if not Permissions.Commands[ Command ] then
			Permissions.Denied[ Command ] = true
		end

		return
	end

	local Allowed = Entry.Allowed
	-- Blacklists should take the lowest allowed entry,
	-- whitelists should take the highest.
	if Blacklist then
		Permissions.Commands[ Command ] = Allowed or true
	elseif not Permissions.Commands[ Command ] then
		Permissions.Commands[ Command ] = Allowed or true
	end
end

--[[
	Checks a command list table for the given command name,
	taking into account table entries with argument restrictions.
]]
local function GetGroupPermissions( GroupName, GroupTable )
	-- -1 denotes the default group, as JSON can't have a number key of -1.
	GroupName = GroupName or -1

	local Permissions = PermissionCache[ GroupName ]

	if not Permissions then
		Permissions = InitialPermissions()

		for i = 1, #GroupTable.Commands do
			AddCommand( GroupTable.Commands[ i ], Permissions, ToBool( GroupTable.IsBlacklist ) )
		end

		PermissionCache[ GroupName ] = Permissions
	end

	return Permissions
end

local Printed = {}
local function PrintOnce( Message, Format, ... )
	local MessageText = Format and StringFormat( Message, ... ) or Message
	if Printed[ MessageText ] then return end

	Printed[ MessageText ] = true

	Shine:Print( MessageText )
end

local function IsGroupAllowedToHaveNoCommands( GroupTable )
	-- A group that inherits is allowed to omit a list of commands.
	return IsType( GroupTable.InheritsFrom, "table" ) or GroupTable.InheritFromDefault
end

--[[
	Verifies the given group has a commands table.
	Inputs: Group name, group table.
	Output: True if the group has a commands table, false otherwise.
]]
local function VerifyGroup( GroupName, GroupTable )
	if not IsType( GroupTable.Commands, "table" ) then
		if GroupName and IsGroupAllowedToHaveNoCommands( GroupTable ) then
			GroupTable.Commands = {}
			return true
		end

		if GroupName then
			PrintOnce( "Group with ID %s has a missing/incorrect \"Commands\" list! It should be a list of commands.",
				true, GroupName )
		else
			PrintOnce( "The default group has a missing/incorrect \"Commands\" list! It should be a list of commands." )
		end

		return false
	end

	return true
end

--[[
	Adds all commands in the commands table to the table of
	permissions being built. Will add argument restrictions to the table
	if they are set, otherwise just adds the command as 'true'.

	Whitelists take the first occurrence of the command, blacklists take
	the last occurrence.
]]
local function AddPermissionsToTable( Commands, Permissions, Blacklist )
	for i = 1, #Commands do
		AddCommand( Commands[ i ], Permissions, Blacklist )
	end
end

--[[
	Recursively builds permissions table from all inherited groups,
	and their inherited groups, and their inherited groups and...

	Inputs: Current group name, current group table, blacklist setting,
	permissions table to build.
]]
local function BuildPermissions( self, GroupName, GroupTable, Blacklist, Permissions, Processed )
	Processed = Processed or {}

	-- Avoid cycles!
	if Processed[ GroupName ] then return end

	Processed[ GroupName ] = true

	local InheritGroups = GroupTable.InheritsFrom
	local InheritFromDefault = GroupTable.InheritFromDefault
	local TopLevelCommands = GroupTable.Commands

	if ToBool( GroupTable.IsBlacklist ) == Blacklist then
		if IsType( TopLevelCommands, "table" ) then
			AddPermissionsToTable( TopLevelCommands, Permissions, Blacklist )
		elseif not IsGroupAllowedToHaveNoCommands( GroupTable ) then
			PrintOnce( "Group with ID %s has a missing/incorrect \"Commands\" list! It should be a list of commands.",
				true, GroupName )
		end
	end

	-- Inherit from the default group, which cannot inherit from others.
	if InheritFromDefault then
		local DefaultGroup = self:GetDefaultGroup()

		if not DefaultGroup then
			PrintOnce( "Group with ID %s inherits from the default group, but no default group exists!", true, GroupName )
		else
			if not Processed[ DefaultGroup ] then
				Processed[ DefaultGroup ] = true

				if VerifyGroup( nil, DefaultGroup ) and ToBool( DefaultGroup.IsBlacklist ) == Blacklist then
					AddPermissionsToTable( DefaultGroup.Commands, Permissions, Blacklist )
				end
			end
		end
	end

	if not InheritGroups then return end

	for i = 1, #InheritGroups do
		local Name = InheritGroups[ i ]

		if Name then
			local InheritedGroup = self:GetGroupData( Name )

			if not InheritedGroup then
				PrintOnce( "Group with ID %s inherits from a non-existent group (%s)!",
					true, GroupName, Name )
			else
				BuildPermissions( self, Name, InheritedGroup, Blacklist, Permissions, Processed )
			end
		end
	end
end

do
	local DEFAULT_GROUP_KEY = -1
	local function IterateGroups( Name, Seen, Consumer, Context )
		local Key = Name
		if Key == nil then
			Key = DEFAULT_GROUP_KEY
		end

		if Seen[ Key ] then return end

		local Group = Shine:GetGroupData( Name )
		if not Group then return end

		Seen[ Key ] = true

		if Consumer( Group, Name, Context ) then return true end

		local InheritGroups = Key ~= DEFAULT_GROUP_KEY and Group.InheritsFrom
		if InheritGroups then
			for i = 1, #InheritGroups do
				if IterateGroups( InheritGroups[ i ], Seen, Consumer, Context ) then
					return true
				end
			end
		end

		if Group.InheritFromDefault and not Seen[ DEFAULT_GROUP_KEY ] then
			Seen[ DEFAULT_GROUP_KEY ] = true

			local DefaultGroup = Shine:GetDefaultGroup()
			if DefaultGroup then
				if Consumer( DefaultGroup, nil, Context ) then
					return true
				end
			end
		end
	end

	--[[
		Iterates the given group and all groups that it inherits from recursively, visiting each group in the tree
		exactly once.

		Inputs:
			1. Starting group name (can be nil to start at the default group).
			2. Consumer function called for each group in the tree with the group table, name (nil for the default
			group) and context value. Return true in this function to stop iterating.
			3. Optional context value to pass to the consumer function (to avoid the need for a closure).
	]]
	function Shine:IterateGroupTree( StartingGroupName, Consumer, Context )
		Shine.AssertAtLevel( Shine.IsCallable( Consumer ), "Consumer must be callable!", 3 )
		return IterateGroups( StartingGroupName, {}, Consumer, Context )
	end
end

function Shine:AddGroupInheritance( GroupName, InheritGroup )
	Shine.TypeCheck( GroupName, "string", 1, "AddGroupInheritance" )
	Shine.TypeCheck( InheritGroup, "string", 2, "AddGroupInheritance" )

	local Group = self:GetGroupData( GroupName )
	if not Group then return false end

	local InheritsFrom = Group.InheritsFrom
	if not InheritsFrom then
		InheritsFrom = {}
		Group.InheritsFrom = InheritsFrom
	end

	if not TableInsertUnique( InheritsFrom, InheritGroup ) then
		return false
	end

	self:SaveUsers( true )

	PermissionCache[ GroupName ] = nil

	Shine.Hook.Broadcast( "OnGroupInheritanceAdded", GroupName, Group, InheritGroup )

	return true
end

function Shine:RemoveGroupInheritance( GroupName, InheritGroup )
	Shine.TypeCheck( GroupName, "string", 1, "RemoveGroupInheritance" )
	Shine.TypeCheck( InheritGroup, "string", 2, "RemoveGroupInheritance" )

	local Group = self:GetGroupData( GroupName )
	if not Group then return false end
	if not Group.InheritsFrom then return false end

	if not TableRemoveByValue( Group.InheritsFrom, InheritGroup ) then
		return false
	end

	if #Group.InheritsFrom == 0 then
		Group.InheritsFrom = nil
	end

	PermissionCache[ GroupName ] = nil
	self:SaveUsers( true )

	Shine.Hook.Broadcast( "OnGroupInheritanceRemoved", GroupName, Group, InheritGroup )

	return true
end

do
	local TableHasValue = table.HasValue

	local function ForEachInheritingGroup( GroupName, Action )
		for Name, Group in pairs( Shine.UserData.Groups ) do
			if IsType( Group.InheritsFrom, "table" ) and TableHasValue( Group.InheritsFrom, GroupName ) then
				Action( Name )
			end
		end
	end

	local function IsEntryForRight( Entry, AccessRight )
		return Entry == AccessRight or ( IsType( Entry, "table" )
			and Entry.Command == AccessRight )
	end

	local function IsAllowedEntry( Entry, AccessRight )
		return Entry == AccessRight or ( IsType( Entry, "table" )
			and Entry.Command == AccessRight and not Entry.Denied )
	end

	local function FlushPermissionsCacheRecursively( GroupName )
		if PermissionCache[ GroupName ] then
			PermissionCache[ GroupName ] = nil
			ForEachInheritingGroup( GroupName, FlushPermissionsCacheRecursively )
		end
	end

	function Shine:AddGroupAccess( GroupName, AccessRight )
		local Group = self:GetGroupData( GroupName )
		if not Group then return false end

		Shine.TypeCheck( AccessRight, "string", 2, "AddGroupAccess" )

		if ToBool( Group.IsBlacklist ) then
			-- For a blacklist group, remove the access right from the commands list.
			local Found
			for i = #Group.Commands, 1, -1 do
				local Entry = Group.Commands[ i ]
				if IsEntryForRight( Entry, AccessRight ) then
					Found = true
					TableRemove( Group.Commands, i )
				end
			end

			if not Found then return false end

			FlushPermissionsCacheRecursively( GroupName )
		else
			-- For a whitelist, add the command if its not already present, and remove any
			-- entries that deny it.
			for i = #Group.Commands, 1, -1 do
				local Entry = Group.Commands[ i ]
				if IsAllowedEntry( Entry, AccessRight ) then
					return false
				end

				if IsType( Entry, "table" ) and Entry.Denied then
					TableRemove( Group.Commands, i )
				end
			end

			Group.Commands[ #Group.Commands + 1 ] = AccessRight

			FlushPermissionsCacheRecursively( GroupName )
		end

		self:SaveUsers( true )

		Shine.Hook.Broadcast( "OnGroupAccessGranted", GroupName, Group, AccessRight )

		return true
	end

	function Shine:RevokeGroupAccess( GroupName, AccessRight )
		local Group = self:GetGroupData( GroupName )
		if not Group then return false end

		Shine.TypeCheck( AccessRight, "string", 2, "RevokeGroupAccess" )

		if ToBool( Group.IsBlacklist ) then
			-- For a blacklist, add the right to the commands list if it's not already there.
			for i = 1, #Group.Commands do
				local Entry = Group.Commands[ i ]
				if IsEntryForRight( Entry, AccessRight ) then
					-- Already blocked.
					return false
				end
			end

			Group.Commands[ #Group.Commands + 1 ] = AccessRight

			FlushPermissionsCacheRecursively( GroupName )
		else
			-- For a whitelist, remove all entries for the given right that allow it.
			local Found
			for i = #Group.Commands, 1, -1 do
				local Entry = Group.Commands[ i ]
				if IsAllowedEntry( Entry, AccessRight ) then
					Found = true
					TableRemove( Group.Commands, i )
				end
			end

			if not Found then return false end

			FlushPermissionsCacheRecursively( GroupName )
		end

		self:SaveUsers( true )

		Shine.Hook.Broadcast( "OnGroupAccessRevoked", GroupName, Group, AccessRight )

		return true
	end
end

Shine.Hook.Add( "OnUserReload", "FlushPermissionCache", function()
	TableEmpty( PermissionCache )
end )

local AccessLevel = {
	DENIED = 0,
	ABSTAIN = 1,
	ALLOWED = 2
}

local function GetAccess( Permissions, Command, Blacklist )
	if Blacklist then
		if not Permissions.Commands[ Command ] then
			return AccessLevel.ALLOWED
		end

		if IsType( Permissions.Commands[ Command ], "table" ) then
			return AccessLevel.ALLOWED, Permissions.Commands[ Command ]
		end

		return AccessLevel.DENIED
	end

	-- Explicit denial of a usually allowed command.
	if Permissions.Denied[ Command ] then
		return AccessLevel.DENIED
	end

	-- Return the allowed arguments.
	if IsType( Permissions.Commands[ Command ], "table" ) then
		return AccessLevel.ALLOWED, Permissions.Commands[ Command ]
	else
		return Permissions.Commands[ Command ] and AccessLevel.ALLOWED or AccessLevel.ABSTAIN
	end
end

--[[
	Checks all inherited groups to determine command access.
	Inputs: Group name, group table, command name.
	Output: True if allowed.
]]
local function GetPermissionInheritance( self, GroupName, GroupTable, Command )
	local InheritGroups = GroupTable.InheritsFrom
	local InheritFromDefault = GroupTable.InheritFromDefault

	if not InheritFromDefault then
		if not IsType( InheritGroups, "table" ) then
			PrintOnce( "Group with ID %s has a non-array entry for \"InheritsFrom\"!",
				true, GroupName )
			if IsType( InheritGroups, "string" ) then
				-- May have forgotten the brackets, so assume it's a single group name.
				GroupTable.InheritsFrom = { InheritGroups }
			else
				-- Don't try to inherit again.
				GroupTable.InheritsFrom = nil
			end
		else
			if #InheritGroups == 0 then
				PrintOnce( "Group with ID %s has an empty \"InheritsFrom\" entry!",
					true, GroupName )
			end
		end
	end

	local Blacklist = ToBool( GroupTable.IsBlacklist )
	local Permissions = PermissionCache[ GroupName ]

	if not Permissions then
		Permissions = InitialPermissions()

		BuildPermissions( self, GroupName, GroupTable, Blacklist, Permissions )

		PermissionCache[ GroupName ] = Permissions
	end

	return GetAccess( Permissions, Command, Blacklist )
end

local function IsCommandPermitted( Command, GrantedLevel, Restrictions )
	if Command.NoPerm then
		-- Commands that are default allowed to all must be explicitly denied.
		return GrantedLevel ~= AccessLevel.DENIED, Restrictions
	end

	-- Otherwise it's enough for them not to be listed in a whitelist.
	return GrantedLevel == AccessLevel.ALLOWED, Restrictions
end

--[[
	Gets whether the given group has the given permission.
	Inputs: Group name, group table, command.
	Output: True/false permission, allowed arguments if set.
]]
function Shine:GetGroupPermission( GroupName, GroupTable, ConCommand )
	if not VerifyGroup( GroupName, GroupTable ) then return false end

	local Command = self.Commands[ ConCommand ]
	if not Command then return false end

	if GroupName and ( GroupTable.InheritsFrom or GroupTable.InheritFromDefault ) then
		return IsCommandPermitted( Command, GetPermissionInheritance( self, GroupName, GroupTable, ConCommand ) )
	end

	local GroupPermissions = GetGroupPermissions( GroupName, GroupTable )
	local GrantedLevel, Restrictions = GetAccess( GroupPermissions, ConCommand, ToBool( GroupTable.IsBlacklist ) )

	return IsCommandPermitted( Command, GrantedLevel, Restrictions )
end

--[[
	Determines if the given client has permission to run the given command.
	Inputs: Client or Steam ID, command name (sh_*).
	Output: True if allowed.
]]
function Shine:GetPermission( Client, ConCommand )
	local Command = self.Commands[ ConCommand ]

	if not Command then return false end
	if not Client then return true end

	local User, ID = self:GetUserData( Client )

	if not User then
		local DefaultGroup = self:GetDefaultGroup()
		if not DefaultGroup then
			return Command.NoPerm or false
		end

		return self:GetGroupPermission( nil, DefaultGroup, ConCommand )
	end

	local UserGroup = User.Group
	local GroupTable = self:GetGroupData( UserGroup )

	if not GroupTable then
		PrintOnce( "User with ID %s belongs to a non-existent group (%s)!",
			true, ID, UserGroup )

		return Command.NoPerm or false
	end

	return self:GetGroupPermission( UserGroup, GroupTable, ConCommand )
end

--[[
	Gets whether the given group has raw acccess to the given permission.
	Inputs: Group name, group table, command, allow by default flag.
	Output: True/false permission.
]]
function Shine:GetGroupAccess( GroupName, GroupTable, ConCommand, AllowByDefault )
	if not VerifyGroup( GroupName, GroupTable ) then return false end

	-- If the access right is allowed by default, then abstaining from a decision
	-- is enough to indicate access. Otherwise it must be explicitly allowed.
	local MinimumLevel = AllowByDefault and AccessLevel.ABSTAIN or AccessLevel.ALLOWED

	if GroupName and ( GroupTable.InheritsFrom or GroupTable.InheritFromDefault ) then
		return GetPermissionInheritance( self, GroupName, GroupTable, ConCommand ) >= MinimumLevel
	end

	local GroupPermissions = GetGroupPermissions( GroupName, GroupTable )
	return GetAccess( GroupPermissions, ConCommand, ToBool( GroupTable.IsBlacklist ) ) >= MinimumLevel
end

--[[
	Determines if the given client has raw access to the given command.
	Unlike get permission, this looks specifically for a user group with explicit permission.
	It also does not require the command to exist.

	Inputs: Client or Steam ID, command name (sh_*), allow by default flag.
	Output: True if explicitly allowed.
]]
function Shine:HasAccess( Client, ConCommand, AllowByDefault )
	if not Client then return true end

	local User, ID = self:GetUserData( Client )

	if not User then
		local DefaultGroup = self:GetDefaultGroup()
		if not DefaultGroup then
			return AllowByDefault or false
		end

		return self:GetGroupAccess( nil, DefaultGroup, ConCommand, AllowByDefault )
	end

	local UserGroup = User.Group
	local GroupTable = self:GetGroupData( UserGroup )

	if not GroupTable then
		PrintOnce( "User with ID %s belongs to a non-existent group (%s)!",
			true, ID, UserGroup )
		return false
	end

	return self:GetGroupAccess( UserGroup, GroupTable, ConCommand, AllowByDefault )
end

local function GetGroupAndImmunity( self, Groups, User, ID )
	if not User then
		local DefaultGroup = self:GetDefaultGroup()

		if not DefaultGroup then
			return nil
		end

		return DefaultGroup, tonumber( DefaultGroup.Immunity ) or 0
	end

	local Group = Groups[ User.Group or -1 ]
	if not Group then
		PrintOnce( "User with ID %s belongs to a non-existent group (%s)!",
			true, ID, tostring( User.Group ) )
		return nil
	end

	-- Read from the user's immunity first, then the groups.
	local Immunity = tonumber( User.Immunity or Group.Immunity )
	if not Immunity then
		PrintOnce( "User with ID %s belongs to a group with an empty or incorrect immunity value! (Group: %s)",
			true, ID, tostring( User.Group ) )
		return nil
	end

	return Group, Immunity
end

--[[
	Determines if the given client can use a command on the given target client.
	Inputs: Client (or Steam ID) calling, target client (or Steam ID).
	Output: True if allowed.
]]
function Shine:CanTarget( Client, Target )
	-- Console can target all.
	if not Client then return true end
	-- Cannot target nil targets.
	if not Target then return false end
	-- Can always target yourself.
	if Client == Target then return true end
	if not self.UserData then return false end

	local Users = self.UserData.Users
	local Groups = self.UserData.Groups
	if not Users or not Groups then return false end

	local ID = GetIDFromClient( Client )
	local TargetID = GetIDFromClient( Target )

	if not ID then return false end
	if not TargetID then return false end
	if ID == TargetID then return true end

	local User
	local TargetUser

	User, ID = self:GetUserData( ID )
	TargetUser, TargetID = self:GetUserData( TargetID )

	local TargetGroup, TargetImmunity = GetGroupAndImmunity( self, Groups, TargetUser, TargetID )
	if not TargetGroup or TargetGroup.CanAlwaysTarget then
		return true
	end

	local Group, Immunity = GetGroupAndImmunity( self, Groups, User, ID )
	if not Group then
		-- No user and no default group means can only target negative immunity groups.
		return TargetImmunity < 0
	end

	-- Both guests in the default group.
	if Group == TargetGroup and Group == self:GetDefaultGroup() then
		return true
	end

	if self.Config.EqualsCanTarget then
		return Immunity >= TargetImmunity
	end

	return Immunity > TargetImmunity
end

--[[
	Determines if the given client is in the given user group.
	Inputs: Client (or Steam ID), group name.
	Output: Boolean result.
]]
function Shine:IsInGroup( Client, Group )
	if not Client then return false end

	if Client.GetIsVirtual and Client:GetIsVirtual() then
		return StringLower( Group ) == "guest"
	end

	if not self.UserData then return false end
	local UserData = self.UserData.Users
	if not UserData then return false end

	local GroupTable = self.UserData.Groups and self.UserData.Groups[ Group ]
	if not GroupTable then return false end

	local ID = GetIDFromClient( Client )
	if not ID then return false end

	local User = self:GetUserData( ID )

	if User then
		return User.Group == Group
	end

	return StringLower( Group ) == "guest"
end

-- Deny vote kicks on players that are above in immunity level.
Shine.Hook.Add( "NS2StartVote", "ImmunityCheck", function( VoteName, Client, Data )
	if VoteName ~= "VoteKickPlayer" then return end

	local Target = Data.kick_client
	if not Target then return end

	local TargetClient = GetClientById( Target )
	if not TargetClient then return end

	if not Shine:CanTarget( Client, TargetClient ) then
		Shine:SendTranslatedCommandError( Client, "ERROR_CANT_TARGET", {
			PlayerName = TargetClient:GetControllingPlayer():GetName()
		}, nil, false )

		return false, false
	end
end )

Shine.Hook.Add( "NS2StartVote", "AccessCheck", function( VoteName, Client, Data )
	-- Derive access right from the vote name in the form sh_ns2_<votename>
	local AccessRight = "sh_ns2_"..StringLower( VoteName )

	-- Vote access is allowed by default, so the client must be explicitly denied
	-- access to block the vote.
	if not Shine:HasAccess( Client, AccessRight, true ) then
		Shine:SendTranslatedCommandError( Client, "COMMAND_NO_PERMISSION", {
			CommandName = VoteName
		}, nil, false )

		return false, false
	end
end, -10 )

do
	local StringFind = string.find

	local function BuildReplacementCommandChecker( OldGetClientCanRunCommand )
		return function( Client, CommandName, PrintWarning )
			if Shine:HasAccess( Client, CommandName ) then return true end

			return OldGetClientCanRunCommand( Client, CommandName, PrintWarning )
		end
	end

	Shine.Hook.Add( "PostLoadScript:lua/ServerAdmin.lua", "OverrideSVCommandPermissions", function( Reload )
		local OldGetClientCanRunCommand = GetClientCanRunCommand
		if not OldGetClientCanRunCommand then return end

		GetClientCanRunCommand = BuildReplacementCommandChecker( OldGetClientCanRunCommand )
	end )
end
