--[[
	Shine basecommands plugin.
]]

local Shine = Shine
local Hook = Shine.Hook
local Call = Hook.Call

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode

local Clamp = math.Clamp
local Floor = math.floor
local GetOwner = Server.GetOwner
local IsType = Shine.IsType
local Max = math.max
local pairs = pairs
local SharedTime = Shared.GetTime
local StringExplode = string.Explode
local StringFormat = string.format
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableShuffle = table.Shuffle
local TableSort = table.sort
local tostring = tostring

local Plugin = Plugin
Plugin.Version = "1.1"

Plugin.HasConfig = true
Plugin.ConfigName = "BaseCommands.json"

Plugin.Commands = {}

Plugin.DefaultConfig = {
	AllTalk = false,
	AllTalkPreGame = false,
	AllTalkSpectator = false,
	EjectVotesNeeded = 0.5,
	DisableLuaRun = false,
	Interp = 100,
	MoveRate = 30,
	FriendlyFire = false,
	FriendlyFireScale = 1,
	FriendlyFirePreGame = true
}

Plugin.CheckConfig = true

Hook.SetupClassHook( "Gamerules", "GetFriendlyFire", "GetFriendlyFire", "ActivePre" )
Hook.SetupGlobalHook( "GetFriendlyFire", "GetFriendlyFire", "ActivePre" )

local function TakeDamage( OldFunc, self, Damage, Attacker, Inflictor, Point, Direction, ArmourUsed, HealthUsed, DamageType, PreventAlert )
	local NewDamage, NewArmour, NewHealth = Call( "TakeDamage", self, Damage, Attacker, Inflictor, Point, Direction, ArmourUsed, HealthUsed, DamageType, PreventAlert )

	if NewDamage ~= nil then
		Damage = NewDamage
		ArmourUsed = NewArmour or ArmourUsed
		HealthUsed = NewHealth or HealthUsed
	end

	return OldFunc( self, Damage, Attacker, Inflictor, Point, Direction, ArmourUsed, HealthUsed, DamageType, PreventAlert )
end
Hook.SetupClassHook( "LiveMixin", "TakeDamage", "TakeDamage", TakeDamage )

--Override sv_say with sh_say.
Hook.Add( "NS2EventHook", "BaseCommandsOverrides", function( Name, OldFunc )
	if Name == "Console_sv_say" then
		local function NewSay( Client, ... )
			if Shine:IsExtensionEnabled( "basecommands" ) then
				return Shine:RunCommand( Client, "sh_say", ... )
			end

			return OldFunc( Client, ... )
		end

		return true, NewSay
	end
end )

function Plugin:Initialise()
	self.Gagged = {}

	self:CreateCommands()

	self.SetEjectVotes = false

	self.Config.EjectVotesNeeded = Clamp( self.Config.EjectVotesNeeded, 0, 1 )
	self.Config.Interp = Max( self.Config.Interp, 0 )
	self.Config.MoveRate = Max( self.Config.MoveRate, 5 )

	self.Enabled = true

	return true
end

function Plugin:GetFriendlyFire()
	if self.Config.FriendlyFire then
		return true
	end
end

function Plugin:TakeDamage( Ent, Damage, Attacker, Inflictor, Point, Direction, ArmourUsed, HealthUsed, DamageType, PreventAlert )
	if not self.Config.FriendlyFire then return end
	--Block friendly fire before a round starts.
	if not self.Config.FriendlyFirePreGame then
		local Gamerules = GetGamerules()
		local State = Gamerules and Gamerules:GetGameState()

		if State == kGameState.NotStarted or State == kGameState.PreGame then
			return
		end
	end

	--Nothing to do if the scale is 1.
	local Scale = self.Config.FriendlyFireScale
	if Scale == 1 then return end

	--We need an attacker.
	if not Attacker then return end

	--We need the entity being attacked, and the attacker to be on the same team.
	local EntTeam = Ent.GetTeamNumber and Ent:GetTeamNumber()
	if not EntTeam then return end

	local AttackerTeam = Attacker.GetTeamNumber and Attacker:GetTeamNumber()
	if not AttackerTeam then return end

	if EntTeam ~= AttackerTeam then return end

	Damage = Damage * Scale
	ArmourUsed = ArmourUsed * Scale
	HealthUsed = HealthUsed * Scale

	return Damage, ArmourUsed, HealthUsed
end

function Plugin:ClientConnect( Client )
	if self.Config.Interp ~= 100 then
		Shared.ConsoleCommand( StringFormat( "interp %s", self.Config.Interp * 0.001 ) )
	end
	if self.Config.MoveRate ~= 30 then
		Shared.ConsoleCommand( StringFormat( "mr %s", self.Config.MoveRate ) )
	end
end

function Plugin:Think()
	self.dt.AllTalk = self.Config.AllTalkPreGame

	if self.SetEjectVotes then return end

	local Gamerules = GetGamerules()

	if not Gamerules then return end

	if not Gamerules.team1 or not Gamerules.team2 then return end
	if not Gamerules.team1.ejectCommVoteManager or not Gamerules.team2.ejectCommVoteManager then return end

	Gamerules.team1.ejectCommVoteManager:SetTeamPercentNeeded( self.Config.EjectVotesNeeded )
	Gamerules.team2.ejectCommVoteManager:SetTeamPercentNeeded( self.Config.EjectVotesNeeded )

	self.SetEjectVotes = true
end

function Plugin:SetGameState( Gamerules, NewState, OldState )
	self.dt.Gamestate = NewState
end

--[[
	Override voice chat to allow everyone to hear each other with alltalk on.
]]
function Plugin:CanPlayerHearPlayer( Gamerules, Listener, Speaker )
	local SpeakerClient = GetOwner( Speaker )

	if SpeakerClient and self:IsClientGagged( SpeakerClient ) then return false end
	if Listener:GetClientMuted( Speaker:GetClientIndex() ) then return false end

	if self.Config.AllTalkPreGame and GetGamerules():GetGameState() == kGameState.NotStarted then return true end
	if self.Config.AllTalk then return true end

	if self.Config.AllTalkSpectator then
		local ListenerTeam = Listener:GetTeamNumber()

		if ListenerTeam == ( kSpectatorIndex or 3 ) then
			return true
		end
	end
end

--[[
	Helper for printing when the client may be the server console.
]]
local function PrintToConsole( Client, Message )
	if not Client then
		return Notify( Message )
	end

	ServerAdminPrint( Client, Message )
end

local Histories = {}

function Plugin:ClientDisconnect( Client )
	Histories[ Client ] = nil

	if self.PluginClients then
		self.PluginClients[ Client ] = nil
	end
end

--[[
	Empty search histories when user data is reloaded as their permissions
	may have changed.
]]
function Plugin:OnUserReload()
	TableEmpty( Histories )
end

local function Help( Client, Search )
	local PageSize = 25
	
	local function GetBoundaryIndexes( PageNumber )
		local LastIndexToShow = PageSize * PageNumber
		local FirstIndexToShow = LastIndexToShow - ( PageSize - 1 )

		return FirstIndexToShow, LastIndexToShow
	end

	local function CommandsAppearOnPage( TotalCommandsCount, PageNumber )
		local FirstIndexToShow, LastIndexToShow = GetBoundaryIndexes( PageNumber )

		return FirstIndexToShow <= TotalCommandsCount
	end

	local function CommandAppearsOnPage( Index, PageNumber )
		local LastIndexToShow = PageSize * PageNumber
		local FirstIndexToShow = LastIndexToShow - ( PageSize - 1 )

		return Index >= FirstIndexToShow and Index <= LastIndexToShow
	end

	local Query = tostring( Search )

	local History = Histories[ Client or "Console" ] or {}
	local PageNumber = History.Search == Query and ( ( History.PageNumber or 0 ) + 1 ) or 1

	History.Cache = History.Cache or {}
	local CommandNames = History.Cache[ Query ]

	if not CommandNames then
		CommandNames = {}
		local Count = 0

		for CommandName, CommandData in pairs( Shine.Commands ) do
			if Shine:GetPermission( Client, CommandName ) and CommandName ~= "sh_help" then
				if Search == nil or CommandName:find( Search ) then
					Count = Count + 1
					CommandNames[ Count ] = CommandName
				end
			end
		end

		TableSort( CommandNames, function( CommandName1, CommandName2 ) return CommandName1 < CommandName2 end )

		History.Cache[ Query ] = CommandNames
	end

	PageNumber = CommandsAppearOnPage( #CommandNames, PageNumber ) and PageNumber or 1

	local FirstIndexToShow, LastIndexToShow = GetBoundaryIndexes( PageNumber )
	FirstIndexToShow = FirstIndexToShow <= #CommandNames and FirstIndexToShow or #CommandNames
	LastIndexToShow = LastIndexToShow <= #CommandNames and LastIndexToShow or #CommandNames

	PrintToConsole( Client, StringFormat( "Available commands (%s-%s; %s total)%s:", 
		FirstIndexToShow, LastIndexToShow, #CommandNames, ( Search == nil and "" or " matching \"" .. Search .. "\"" ) ) )

	for i = 1, #CommandNames do
		local CommandName = CommandNames[ i ]
		if CommandAppearsOnPage( i, PageNumber ) then
			local Command = Shine.Commands[ CommandName ]

			if Command then
				local HelpLine = StringFormat( "%s. %s%s: %s", i, CommandName, 
					( type( Command.ChatCmd ) == "string" and StringFormat( " (chat: !%s)", Command.ChatCmd ) or "" ), 
					Command.Help or "No help available." )

				PrintToConsole( Client, HelpLine )
			end
		end
	end

	History.Search = Query
	History.PageNumber = PageNumber

	Histories[ Client or "Console" ] = History

	local EndMessage = "End command list."
	if CommandsAppearOnPage( #CommandNames, PageNumber + 1 ) then
		EndMessage = StringFormat( "There are more commands! Re-issue the \"sh_help%s\" command to view them.", 
			( Search == nil and "" or StringFormat( " %s", Search ) ) )
	end
	PrintToConsole( Client, EndMessage )
end

function Plugin:CreateCommands()
	local HelpCommand = self:BindCommand( "sh_help", nil, Help, true )
	HelpCommand:AddParam{ Type = "string", TakeRestofLine = true, Optional = true }
	HelpCommand:Help( "<search text> View help info for available commands (omit <search text> to see all)." )

	local function RCon( Client, Command )
		Shared.ConsoleCommand( Command )
		Shine:Print( "%s ran console command: %s", true, Client and Client:GetControllingPlayer():GetName() or "Console", Command )
	end
	local RConCommand = self:BindCommand( "sh_rcon", "rcon", RCon )
	RConCommand:AddParam{ Type = "string", TakeRestOfLine = true }
	RConCommand:Help( "<command> Executes a command on the server console." )

	local function SetPassword( Client, Password )
		Server.SetPassword( Password )
		Shine:AdminPrint( Client, "Password %s", true, Password ~= "" and "set to "..Password or "reset" )
	end
	local SetPasswordCommand = self:BindCommand( "sh_password", "password", SetPassword )
	SetPasswordCommand:AddParam{ Type = "string", TakeRestOfLine = true, Optional = true, Default = "" }
	SetPasswordCommand:Help( "<password> Sets the server password." )

	if not self.Config.DisableLuaRun then
		local function RunLua( Client, Code )
			local Player = Client and Client:GetControllingPlayer()

			local Name = Player and Player:GetName() or "Console"

			local Func, Err = loadstring( Code )

			if Func then
				Func()
				Shine:Print( "%s ran: %s", true, Name, Code )
			else
				Shine:Print( "Lua run failed. Error: %s", true, Err )
			end
		end
		local RunLuaCommand = self:BindCommand( "sh_luarun", "luarun", RunLua, false, true )
		RunLuaCommand:AddParam{ Type = "string", TakeRestOfLine = true }
		RunLuaCommand:Help( "Runs a string of Lua code on the server. Be careful with this." )
	end

	local function SetCheats( Client, Enable )
		Shared.ConsoleCommand( "cheats "..( Enable and "1" or "0" ) )
		Shine:CommandNotify( Client, "%s cheats.", true, Enable and "enabled" or "disabled" )
	end
	local SetCheatsCommand = self:BindCommand( "sh_cheats", "cheats", SetCheats )
	SetCheatsCommand:AddParam{ Type = "boolean", Optional = true, Default = function() return not Shared.GetCheatsEnabled() end }
	SetCheatsCommand:Help( "Enables or disables cheats mode." )

	local function AllTalk( Client, Enable )
		self.Config.AllTalk = Enable

		self:SaveConfig( true )

		local Enabled = Enable and "enabled" or "disabled"

		if Shine.Config.NotifyOnCommand then
			Shine:CommandNotify( Client, "%s all-talk.", true, Enabled )
		else
			Shine:NotifyDualColour( nil, Enable and 0 or 255, Enable and 255 or 0, 0, "[All Talk]",
				255, 255, 255, "All talk has been %s.", true, Enabled )
		end
	end
	local AllTalkCommand = self:BindCommand( "sh_alltalk", "alltalk", AllTalk )
	AllTalkCommand:AddParam{ Type = "boolean", Optional = true, Default = function() return not self.Config.AllTalk end }
	AllTalkCommand:Help( "<true/false> Enables or disables all talk, which allows everyone to hear each others voice chat regardless of team." )

	local function FriendlyFire( Client, Scale )
		local OldState = self.Config.FriendlyFire
		local Enable = Scale > 0

		if Enable then
			self.Config.FriendlyFire = true
			self.Config.FriendlyFireScale = Scale
		else
			self.Config.FriendlyFire = false
		end

		self:SaveConfig( true )

		if OldState ~= self.Config.FriendlyFire then
			if Shine.Config.NotifyOnCommand then
				Shine:CommandNotify( Client, "set friendly fire scale to %s.", true, Scale )
			else
				Shine:NotifyDualColour( nil, Enable and 0 or 255, Enable and 255 or 0, 0, "[FF]",
					255, 255, 255, "Friendly fire has been %s.", true, Enable and "enabled" or "disabled" )
			end
		end
	end
	local FriendlyFireCommand = self:BindCommand( "sh_friendlyfire", { "ff", "friendlyfire" }, FriendlyFire )
	FriendlyFireCommand:AddParam{ Type = "number", Min = 0, Error = "Please specify a scale, or 0 for off." }
	FriendlyFireCommand:Help( "<scale> Sets the friendly fire scale. Use 0 to disable friendly fire." )

	local function Kick( Client, Target, Reason )
		local TargetPlayer = Target:GetControllingPlayer()
		local TargetName = TargetPlayer and TargetPlayer:GetName() or "<unknown>"

		Shine:Print( "%s kicked %s.%s", true,
			Client and Client:GetControllingPlayer():GetName() or "Console",
			TargetName,
			Reason ~= "" and " Reason: "..Reason or ""
		)
		Server.DisconnectClient( Target )

		if Reason == "" then
			Shine:CommandNotify( Client, "kicked %s.", true, TargetName )
		else
			Shine:CommandNotify( Client, "kicked %s (%s).", true, TargetName, Reason )
		end
	end
	local KickCommand = self:BindCommand( "sh_kick", "kick", Kick )
	KickCommand:AddParam{ Type = "client", NotSelf = true }
	KickCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "" }
	KickCommand:Help( "<player> Kicks the given player." )

	local function Status( Client )
		local CanSeeIPs = Shine:HasAccess( Client, "sh_status" )

		local GameIDs = Shine.GameIDs
		local SortTable = {}
		local Count = 0

		for Client, ID in pairs( GameIDs ) do
			Count = Count + 1
			SortTable[ Count ] = { ID, Client }
		end

		TableSort( SortTable, function( A, B )
			if A[ 1 ] < B[ 1 ] then return true end
			return false
		end )

		PrintToConsole( Client, StringFormat( "Showing %s:", Count == 1 and "1 connected player" or Count.." connected players" ) )
		PrintToConsole( Client, StringFormat( "ID\t\tName\t\t\t\tSteam ID\t\t\t\t\t\t\t\t\t\t\t\tTeam%s", CanSeeIPs and "\t\t\t\t\t\tIP" or "" ) )
		PrintToConsole( Client, "=============================================================================" )

		for i = 1, #SortTable do
			local Data = SortTable[ i ]

			local GameID = Data[ 1 ]
			local PlayerClient = Data[ 2 ]

			local Player = PlayerClient:GetControllingPlayer()

			if Player then
				local ID = PlayerClient:GetUserId()

				PrintToConsole( Client, StringFormat( "%s\t\t'%s'\t\t%s\t%s\t\t'%s'%s",
					GameID,
					Player:GetName(),
					ID,
					Shine.NS2ToSteamID( ID ),
					Shine:GetTeamName( Player:GetTeamNumber(), true ),
					CanSeeIPs and "\t\t"..IPAddressToString( Server.GetClientAddress( PlayerClient ) ) or "" ) )
			end
		end
	end
	local StatusCommand = self:BindCommand( "sh_status", nil, Status, true )
	StatusCommand:Help( "Prints a list of all connected players and their relevant information." )

	local function Who( Client, Target )
		if not Target then
			local GameIDs = Shine.GameIDs
			local SortTable = {}
			local Count = 0

			for Client, ID in pairs( GameIDs ) do
				Count = Count + 1
				SortTable[ Count ] = { Client:GetUserId(), Client }
			end

			TableSort( SortTable, function( A, B )
				if A[ 1 ] < B[ 1 ] then return true end
				return false
			end )

			PrintToConsole( Client, "Name\t\t\t\tSteam ID\t\t\t\t\t\t\t\t\t\t\t\tGroup\t\t\t\t\tImmunity" )
			PrintToConsole( Client, "=============================================================================" )

			for i = 1, #SortTable do
				local Data = SortTable[ i ]

				local ID = Data[ 1 ]
				local PlayerClient = Data[ 2 ]

				local Player = PlayerClient:GetControllingPlayer()
				if Player then
					local UserData = Shine:GetUserData( PlayerClient )

					local GroupName = UserData and UserData.Group
					local GroupData = GroupName and Shine:GetGroupData( GroupName )

					PrintToConsole( Client, StringFormat( "'%s'\t\t%s\t\t%s\t'%s'\t\t%s",
						Player:GetName(),
						ID,
						Shine.NS2ToSteamID( ID ),
						GroupName or "None",
						GroupData and GroupData.Immunity or 0 ) )
				end
			end
		
			return
		end
		
		local Player = Target:GetControllingPlayer()
		if not Player then
			PrintToConsole( Client, "Unknown user." )

			return
		end

		PrintToConsole( Client, "Name\t\t\t\tSteam ID\t\t\t\t\t\t\t\t\t\t\t\tGroup\t\t\t\t\tImmunity" )
		PrintToConsole( Client, "=============================================================================" )

		local UserData = Shine:GetUserData( Target )
		local ID = Target:GetUserId()

		local GroupName = UserData and UserData.Group
		local GroupData = GroupName and Shine:GetGroupData( GroupName )

		PrintToConsole( Client, StringFormat( "'%s'\t\t%s\t\t%s\t'%s'\t\t%s",
			Player:GetName(),
			ID,
			Shine.NS2ToSteamID( ID ),
			GroupName or "-None-",
			GroupData and GroupData.Immunity or 0 ) )
	end
	local WhoCommand = self:BindCommand( "sh_who", nil, Who, true )
	WhoCommand:AddParam{ Type = "client", Optional = true, Default = false }
	WhoCommand:Help( "<optional player> Displays rank information about the given player, or all players." )

	local function ChangeLevel( Client, MapName )
		MapCycle_ChangeMap( MapName )
	end
	local ChangeLevelCommand = self:BindCommand( "sh_changelevel", "map", ChangeLevel )
	ChangeLevelCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a map to change to." }
	ChangeLevelCommand:Help( "<map> Changes the map to the given level immediately." )

	local IsType = Shine.IsType

	local function ListMaps( Client )
		local Cycle = MapCycle_GetMapCycle()

		if not Cycle or not Cycle.maps then
			Shine:AdminPrint( Client, "Unable to load map cycle list." )

			return
		end

		local Maps = Cycle.maps

		Shine:AdminPrint( Client, "Installed maps:" )
		for i = 1, #Maps do
			local Map = Maps[ i ]
			local MapName = IsType( Map, "table" ) and Map.map or Map
			
			Shine:AdminPrint( Client, StringFormat( "- %s", MapName ) )
		end
	end
	local ListMapsCommand = self:BindCommand( "sh_listmaps", nil, ListMaps )
	ListMapsCommand:Help( "Lists all installed maps on the server." )

	local function ResetGame( Client )
		local Gamerules = GetGamerules()
		if not Gamerules then return end

		Gamerules:ResetGame()

		Shine:CommandNotify( Client, "reset the game." )
	end
	local ResetGameCommand = self:BindCommand( "sh_reset", "reset", ResetGame )
	ResetGameCommand:Help( "Resets the game round." )

	local function LoadPlugin( Client, Name, Save )
		if Name == "basecommands" then
			Shine:AdminPrint( Client, "You cannot reload the basecommands plugin." )
			return
		end

		local PluginTable = Shine.Plugins[ Name ]
		local Success, Err

		if not PluginTable then
			Success, Err = Shine:LoadExtension( Name )
		else
			--If it's already enabled and we're saving, then just save the config option, don't reload.
			if PluginTable.Enabled and Save then
				Shine.Config.ActiveExtensions[ Name ] = true
				Shine:SaveConfig()

				Shine:AdminPrint( Client, StringFormat( "Plugin %s now set to enabled in config.", Name ) )

				return
			end

			Success, Err = Shine:EnableExtension( Name )
		end
		
		if Success then
			Shine:AdminPrint( Client, StringFormat( "Plugin %s loaded successfully.", Name ) )

			--Update all players with the plugins state.
			Shine:SendPluginData( nil, Shine:BuildPluginData() )

			if Save then
				Shine.Config.ActiveExtensions[ Name ] = true
				Shine:SaveConfig()
			end
		else
			Shine:AdminPrint( Client, StringFormat( "Plugin %s failed to load. Error: %s", Name, Err ) )
		end
	end
	local LoadPluginCommand = self:BindCommand( "sh_loadplugin", nil, LoadPlugin )
	LoadPluginCommand:AddParam{ Type = "string", Error = "Please specify a plugin to load." }
	LoadPluginCommand:AddParam{ Type = "boolean", Optional = true, Default = false }
	LoadPluginCommand:Help( "<plugin> Loads or reloads a plugin." )

	local function UnloadPlugin( Client, Name, Save )
		if Name == "basecommands" and Shine.Plugins[ Name ] and Shine.Plugins[ Name ].Enabled then
			Shine:AdminPrint( Client, "Unloading the basecommands plugin is ill-advised. If you wish to do so, remove it from the active plugins list in your config." )
			return
		end

		if not Shine.Plugins[ Name ] or not Shine.Plugins[ Name ].Enabled then
			--If it's already disabled and we want to save, just save.
			if Save and Shine.AllPlugins[ Name ] then
				Shine.Config.ActiveExtensions[ Name ] = false
				Shine:SaveConfig()

				Shine:AdminPrint( Client, StringFormat( "Plugin %s now set to disabled in config.", Name ) )

				return
			end

			Shine:AdminPrint( Client, StringFormat( "Plugin %s is not loaded.", Name ) )
			
			return
		end

		Shine:UnloadExtension( Name )

		Shine:AdminPrint( Client, StringFormat( "Plugin %s unloaded successfully.", Name ) )

		Shine:SendPluginData( nil, Shine:BuildPluginData() )

		if Save then
			Shine.Config.ActiveExtensions[ Name ] = false
			Shine:SaveConfig()
		end
	end
	local UnloadPluginCommand = self:BindCommand( "sh_unloadplugin", nil, UnloadPlugin )
	UnloadPluginCommand:AddParam{ Type = "string", Error = "Please specify a plugin to unload." }
	UnloadPluginCommand:AddParam{ Type = "boolean", Optional = true, Default = false }
	UnloadPluginCommand:Help( "<plugin> Unloads a plugin." )

	local function SuspendPlugin( Client, Name )
		local Plugin = Shine.Plugins[ Name ]

		if not Plugin or not Plugin.Enabled then
			Shine:AdminPrint( Client, StringFormat( "The plugin %s is not loaded or already suspended.", Name ) )

			return
		end

		Plugin:Suspend()

		Shine:AdminPrint( Client, StringFormat( "Plugin %s has been suspended.", Name ) )

		Shine:SendPluginData( nil, Shine:BuildPluginData() )
	end
	local SuspendPluginCommand = self:BindCommand( "sh_suspendplugin", nil, SuspendPlugin )
	SuspendPluginCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a plugin to suspend." }
	SuspendPluginCommand:Help( "<plugin> Suspends a plugin." )

	local function ResumePlugin( Client, Name )
		local Plugin = Shine.Plugins[ Name ]

		if not Plugin or Plugin.Enabled or not Plugin.Suspended then
			Shine:AdminPrint( Client, StringFormat( "The plugin %s is already running or is not suspended or not loaded.", Name ) )

			return
		end

		Plugin:Resume()

		Shine:AdminPrint( Client, StringFormat( "Plugin %s has been resumed.", Name ) )

		Shine:SendPluginData( nil, Shine:BuildPluginData() )
	end
	local ResumePluginCommand = self:BindCommand( "sh_resumeplugin", nil, ResumePlugin )
	ResumePluginCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a plugin to resume." }
	ResumePluginCommand:Help( "<plugin> Resumes a plugin." )

	local function ListPlugins( Client )
		Shine:AdminPrint( Client, "Loaded plugins:" )
		for Name, Table in pairs( Shine.Plugins ) do
			if Table.Enabled then
				Shine:AdminPrint( Client, StringFormat( "%s - version: %s", Name, Table.Version or "1.0" ) )
			end
		end
	end
	local ListPluginsCommand = self:BindCommand( "sh_listplugins", nil, ListPlugins )
	ListPluginsCommand:Help( "Lists all loaded plugins." )

	local function ReloadUsers( Client )
		Shine:AdminPrint( Client, "Reloading users..." )
		Shine:LoadUsers( Shine.Config.GetUsersFromWeb, true )
	end
	local ReloadUsersCommand = self:BindCommand( "sh_reloadusers", nil, ReloadUsers )
	ReloadUsersCommand:Help( "Reloads the user data, either from the web or locally depending on your config settings." )

	local function ReadyRoom( Client, Targets )
		local Gamerules = GetGamerules()
		if not Gamerules then return end

		local TargetCount = #Targets

		for i = 1, TargetCount do
			Gamerules:JoinTeam( Targets[ i ]:GetControllingPlayer(), kTeamReadyRoom, nil, true )
		end

		if TargetCount > 0 then
			local Players = TargetCount == 1 and "1 player" or TargetCount.." players"
			Shine:CommandNotify( Client, "moved %s to the ready room.", true, Players )
		end
	end
	local ReadyRoomCommand = self:BindCommand( "sh_rr", "rr", ReadyRoom )
	ReadyRoomCommand:AddParam{ Type = "clients" }
	ReadyRoomCommand:Help( "<players> Sends the given player(s) to the ready room." )

	local function ForceRandom( Client, Targets )
		local Gamerules = GetGamerules()

		if not Gamerules then return end

		TableShuffle( Targets )

		local NumPlayers = #Targets
		if NumPlayers == 0 then return end

		local TeamSequence = math.GenerateSequence( NumPlayers, { 1, 2 } )
		local TeamMembers = {
			{},
			{}
		}

		local TargetList = {}

		for i = 1, NumPlayers do
			local Player = Targets[ i ]:GetControllingPlayer()

			if Player then
				TargetList[ Player ] = true
				Targets[ i ] = Player
			end
		end

		local Players = Shine.GetAllPlayers()

		for i = 1, #Players do
			local Player = Players[ i ]

			if Player and not TargetList[ Player ] then
				local TeamTable = TeamMembers[ Player:GetTeamNumber() ]

				if TeamTable then
					TeamTable[ #TeamTable + 1 ] = Player
				end
			end
		end

		for i = 1, NumPlayers do
			local Player = Targets[ i ]

			local TeamTable = TeamMembers[ TeamSequence[ i ] ]

			TeamTable[ #TeamTable + 1 ] = Player
		end

		Shine.EvenlySpreadTeams( Gamerules, TeamMembers )

		local PlayerString = NumPlayers == 1 and "1 player" or NumPlayers.." players"

		Shine:CommandNotify( Client, "placed %s onto a random team.", true, PlayerString )
	end
	local ForceRandomCommand = self:BindCommand( "sh_forcerandom", "forcerandom", ForceRandom )
	ForceRandomCommand:AddParam{ Type = "clients" }
	ForceRandomCommand:Help( "<players> Forces the given player(s) onto a random team." )

	local function ChangeTeam( Client, Targets, Team )
		local Gamerules = GetGamerules()
		if not Gamerules then return end

		local TargetCount = #Targets

		for i = 1, TargetCount do
			local Player = Targets[ i ]:GetControllingPlayer()

			if Player then
				Gamerules:JoinTeam( Player, Team, nil, true )
			end
		end

		if TargetCount > 0 then
			local Players = TargetCount == 1 and "1 player" or TargetCount.." players"
			Shine:CommandNotify( Client, "moved %s to the %s.", true, Players, Shine:GetTeamName( Team ) )
		end
	end
	local ChangeTeamCommand = self:BindCommand( "sh_setteam", { "team", "setteam" }, ChangeTeam )
	ChangeTeamCommand:AddParam{ Type = "clients" }
	ChangeTeamCommand:AddParam{ Type = "team", Error = "Please specify a team to move to." }
	ChangeTeamCommand:Help( "<players> <team name> Sets the given player(s) onto the given team." )

	local function AutoBalance( Client, Enable, UnbalanceAmount, Delay )
		Server.SetConfigSetting( "auto_team_balance", Enable and { enabled_on_unbalance_amount = UnbalanceAmount, enabled_after_seconds = Delay } or nil )
		if Enable then
			Shine:AdminPrint( Client, "Auto balance enabled. Player unbalance amount: %s. Delay: %s.", true, UnbalanceAmount, Delay )
		else
			Shine:AdminPrint( Client, "Auto balance disabled." )
		end
	end
	local AutoBalanceCommand = self:BindCommand( "sh_autobalance", "autobalance", AutoBalance )
	AutoBalanceCommand:AddParam{ Type = "boolean", Error = "Please specify whether auto balance should be enabled." }
	AutoBalanceCommand:AddParam{ Type = "number", Min = 1, Round = true, Optional = true, Default = 2 }
	AutoBalanceCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = 10 }
	AutoBalanceCommand:Help( "<true/false> <player amount> <seconds> Enables or disables auto balance. Player amount and seconds are optional." )

	local function ForceRoundStart( Client )
		local Gamerules = GetGamerules()
		Gamerules:ResetGame()
		Gamerules:SetGameState( kGameState.Countdown )

		local Players = Shine.GetAllPlayers()

		for i = 1, #Players do
			local Player = Players[ i ]
			if Player and Player.ResetScores then
				Player:ResetScores()
			end
		end

		Gamerules.countdownTime = kCountDownLength
		Gamerules.lastCountdownPlayed = nil

		Shine:CommandNotify( Client, "forced the round to start." )
	end
	local ForceRoundStartCommand = self:BindCommand( "sh_forceroundstart", "forceroundstart", ForceRoundStart )
	ForceRoundStartCommand:Help( "Forces the round to start." )

	local function Eject( Client, Target )
		local Player = Target:GetControllingPlayer()

		if not Player then return end

		if Player:isa( "Commander" ) then
			Player:Eject()

			Shine:CommandNotify( Client, "ejected %s.", true, Player:GetName() or "<unknown>" )
		else
			if Client then
				Shine:NotifyError( Client, "%s is not a commander.", true, Player:GetName() )
			else
				Shine:Print( "%s is not a commander.", true, Player:GetName() )
			end
		end
	end
	local EjectCommand = self:BindCommand( "sh_eject", "eject", Eject )
	EjectCommand:AddParam{ Type = "client" }
	EjectCommand:Help( "<player> Ejects the given commander." )

	local function AdminSay( Client, Message )
		Shine:Notify( nil, "All", ( Client and Shine.Config.ChatName ) or Shine.Config.ConsoleName, Message )
	end
	local AdminSayCommand = self:BindCommand( "sh_say", "say", AdminSay, false, true )
	AdminSayCommand:AddParam{ Type = "string", MaxLength = kMaxChatLength, TakeRestOfLine = true, Error = "Please specify a message." }
	AdminSayCommand:Help( "<message> Sends a message to everyone." )

	local function AdminTeamSay( Client, Team, Message )
		local Players = GetEntitiesForTeam( "Player", Team )

		Shine:Notify( Players, "Team", ( Client and Shine.Config.ChatName ) or Shine.Config.ConsoleName, Message )
	end
	local AdminTeamSayCommand = self:BindCommand( "sh_teamsay", "teamsay", AdminTeamSay, false, true )
	AdminTeamSayCommand:AddParam{ Type = "team", Error = "Please specify a team." }
	AdminTeamSayCommand:AddParam{ Type = "string", TakeRestOfLine = true, MaxLength = kMaxChatLength, Error = "Please specify a message." }
	AdminTeamSayCommand:Help( "<team name> <message> Sends a message to everyone on the given team." )

	local function PM( Client, Target, Message )
		if not Client then
			Shine:Notify( Target, "PM", Shine.Config.ConsoleName, Message )
			return
		end

		local Immunity = Shine:GetUserImmunity( Client )
		local TargetImmunity = Shine:GetUserImmunity( Target )

		if TargetImmunity >= Immunity or not Shine.Config.NotifyAnonymous then
			local Player = Client:GetControllingPlayer()
			local Name = Player and Player:GetName() or Shine.Config.ChatName

			Shine:Notify( Target, "PM", Name, Message )
		else
			Shine:Notify( Target, "PM", Shine.Config.ChatName, Message )
		end
	end
	local PMCommand = self:BindCommand( "sh_pm", "pm", PM )
	PMCommand:AddParam{ Type = "client", IgnoreCanTarget = true }
	PMCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a message to send.", MaxLength = kMaxChatLength }
	PMCommand:Help( "<player> <message> Sends a private message to the given player." )

	local Colours = {
		white = { 255, 255, 255 },
		red = { 255, 0, 0 },
		orange = { 255, 160, 0 },
		yellow = { 255, 255, 0 },
		green = { 0, 255, 0 },
		lightblue = { 0, 255, 255 },
		blue = { 0, 0, 255 },
		purple = { 255, 0, 255 }
	}

	local function CSay( Client, Message )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"
		local ID = Client and Client:GetUserId() or "N/A"

		local Words = StringExplode( Message, " " )
		local Colour = Colours[ Words[ 1 ] ]

		if Colour then
			Message = TableConcat( Words, " ", 2 )
		else
			Colour = Colours.white
		end

		Shine:SendText( nil, Shine.BuildScreenMessage( 3, 0.5, 0.25, Message, 6, Colour[ 1 ], Colour[ 2 ], Colour[ 3 ], 1, 2, 1 ) )
		Shine:AdminPrint( nil, "CSay from %s[%s]: %s", true, PlayerName, ID, Message )
	end
	local CSayCommand = self:BindCommand( "sh_csay", "csay", CSay )
	CSayCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a message to send.", MaxLength = 128 }
	CSayCommand:Help( "<message> Displays a message in the centre of all player's screens." )

	local function GagPlayer( Client, Target, Duration )
		self.Gagged[ Target ] = Duration == 0 and true or SharedTime() + Duration

		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"
		local ID = Client:GetUserId() or 0

		local TargetPlayer = Target:GetControllingPlayer()
		local TargetName = TargetPlayer and TargetPlayer:GetName() or "<unknown>"
		local TargetID = Target:GetUserId() or 0
		local DurationString = string.TimeToString( Duration )

		Shine:AdminPrint( nil, "%s[%s] gagged %s[%s]%s", true, PlayerName, ID, TargetName, TargetID,
			Duration == 0 and "" or " for "..DurationString )

		Shine:CommandNotify( Client, "gagged %s %s.", true, TargetName, Duration == 0 and "until map change" or "for "..DurationString )
	end
	local GagCommand = self:BindCommand( "sh_gag", "gag", GagPlayer )
	GagCommand:AddParam{ Type = "client" }
	GagCommand:AddParam{ Type = "number", Round = true, Min = 0, Max = 1800, Optional = true, Default = 0 }
	GagCommand:Help( "<player> <duration> Silences the given player's chat. If no duration is given, it will hold for the remainder of the map." )

	local function UngagPlayer( Client, Target )
		local TargetPlayer = Target:GetControllingPlayer()
		local TargetName = TargetPlayer and TargetPlayer:GetName() or "<unknown>"
		local TargetID = Target:GetUserId() or 0

		if not self.Gagged[ Target ] then
			Shine:NotifyError( Client, "%s is not gagged.", true, TargetName )

			return
		end

		self.Gagged[ Target ] = nil

		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"
		local ID = Client:GetUserId() or 0

		Shine:AdminPrint( nil, "%s[%s] ungagged %s[%s]", true, PlayerName, ID, TargetName, TargetID )

		Shine:CommandNotify( Client, "ungagged %s.", true, TargetName )
	end
	local UngagCommand = self:BindCommand( "sh_ungag", "ungag", UngagPlayer )
	UngagCommand:AddParam{ Type = "client" }
	UngagCommand:Help( "<player> Stops silencing the given player's chat." )

	local function Interp( Client, NewInterp )
		self.Config.Interp = NewInterp

		Shared.ConsoleCommand( StringFormat( "interp %s", NewInterp * 0.001 ) )
	
		self:SaveConfig( true )
	end
	local InterpCommand = self:BindCommand( "sh_interp", "interp", Interp )
	InterpCommand:AddParam{ Type = "number", Min = 0 }
	InterpCommand:Help( "<time in ms> Sets the interpolation time and saves it." )

	local function MoveRate( Client, NewRate )
		self.Config.MoveRate = NewRate

		Shared.ConsoleCommand( StringFormat( "mr %s", NewRate ) )

		self:SaveConfig( true )
	end
	local MoveRateCommand = self:BindCommand( "sh_moverate", "moverate", MoveRate )
	MoveRateCommand:AddParam{ Type = "number", Min = 5 }
	MoveRateCommand:Help( "<rate> Sets the move rate and saves it." )
end

function Plugin:IsClientGagged( Client )
	local GagData = self.Gagged[ Client ]

	if not GagData then return false end

	if GagData == true then return true end
	if GagData > SharedTime() then return true end

	self.Gagged[ Client ] = nil

	return false
end

--[[
	Facilitates the gag command.
]]
function Plugin:PlayerSay( Client, Message )
	if self:IsClientGagged( Client ) then
		return ""
	end
end

function Plugin:ReceiveRequestMapData( Client, Data )
	if not Shine:GetPermission( Client, "sh_changelevel" ) then return end
	
	local Cycle = MapCycle_GetMapCycle()

	if not Cycle or not Cycle.maps then
		return
	end

	local Maps = Cycle.maps

	for i = 1, #Maps do
		local Map = Maps[ i ]
		local IsTable = IsType( Map, "table" )

		local MapName = IsTable and Map.map or Map
		
		self:SendNetworkMessage( Client, "MapData", { Name = MapName }, true )
	end
end

function Plugin:ReceiveRequestPluginData( Client, Data )
	if not Shine:GetPermission( Client, "sh_loadplugin" ) then return end

	self.PluginClients = self.PluginClients or {}
	
	self.PluginClients[ Client ] = true

	local Plugins = Shine.AllPlugins

	for Plugin in pairs( Plugins ) do
		local Enabled = Shine:IsExtensionEnabled( Plugin )
		self:SendNetworkMessage( Client, "PluginData", { Name = Plugin, Enabled = Enabled }, true )
	end
end

function Plugin:OnPluginLoad( Name, Plugin, Shared )
	if Shared then return end
	
	local Clients = self.PluginClients

	if not Clients then return end
	
	for Client in pairs( Clients ) do
		self:SendNetworkMessage( Client, "PluginData", { Name = Name, Enabled = true }, true )
	end
end

function Plugin:OnPluginUnload( Name, Shared )
	if Shared then return end
	
	local Clients = self.PluginClients

	if not Clients then return end
	
	for Client in pairs( Clients ) do
		self:SendNetworkMessage( Client, "PluginData", { Name = Name, Enabled = false }, true )
	end
end
