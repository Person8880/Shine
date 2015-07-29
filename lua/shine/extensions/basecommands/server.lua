--[[
	Shine basecommands plugin.
]]

local Shine = Shine
local Hook = Shine.Hook
local Call = Hook.Call

local Clamp = math.Clamp
local Floor = math.floor
local GetOwner = Server.GetOwner
local IsType = Shine.IsType
local Max = math.max
local Min = math.min
local Notify = Shared.Message
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

Plugin.DefaultConfig = {
	AllTalk = false,
	AllTalkPreGame = false,
	AllTalkSpectator = false,
	EjectVotesNeeded = 0.5,
	DisableLuaRun = false,
	Interp = 100,
	MoveRate = 30,
	TickRate = 30,
	SendRate = 20,
	BWLimit = Shine.IsNS2Combat and 35 or 25,
	FriendlyFire = false,
	FriendlyFireScale = 1,
	FriendlyFirePreGame = true
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

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
				return Shine:RunCommand( Client, "sh_say", false, ... )
			end

			return OldFunc( Client, ... )
		end

		return true, NewSay
	end
end )

function Plugin:CheckRateValues()
	local Fixed

	if self.Config.MoveRate ~= 30 then
		Shared.ConsoleCommand( StringFormat( "mr %s", self.Config.MoveRate ) )
	end

	if self.Config.TickRate > self.Config.MoveRate then
		self.Config.TickRate = self.Config.MoveRate
		Fixed = true
		Notify( "Tick rate cannot be more than move rate. Clamping to move rate." )
	end

	if self.Config.TickRate ~= Server.GetTickrate() then
		Shared.ConsoleCommand( StringFormat( "tickrate %s", self.Config.MoveRate ) )
	end

	if self.Config.SendRate > self.Config.TickRate then
		self.Config.SendRate = self.Config.TickRate - 10
		Fixed = true
		Notify( "Send rate cannot be more than tick rate. Clamping to tick rate - 10." )
	end

	if self.Config.SendRate ~= Server.GetSendrate() then
		Shared.ConsoleCommand( StringFormat( "sendrate %s", self.Config.SendRate ) )
	end

	local MinInterp = 2 / self.Config.SendRate * 1000
	if self.Config.Interp < MinInterp then
		self.Config.Interp = MinInterp
		Fixed = true
		Notify( StringFormat( "Interp cannot be less than %.2fms, clamping...",
			MinInterp ) )
	end

	if self.Config.Interp ~= 100 then
		Shared.ConsoleCommand( StringFormat( "interp %s", self.Config.Interp * 0.001 ) )
	end

	local BWLimit = self.Config.BWLimit * 1024
	if BWLimit ~= Server.GetBwLimit() then
		Shared.ConsoleCommand( StringFormat( "bwlimit %s", BWLimit ) )
	end

	if Fixed then
		Notify( "Fixed incorrect rate values, check your config." )
		self:SaveConfig( true )
	end
end

function Plugin:Initialise()
	self.Gagged = {}

	self:CreateCommands()

	self.SetEjectVotes = false

	self.Config.EjectVotesNeeded = Clamp( self.Config.EjectVotesNeeded, 0, 1 )
	self.Config.Interp = Max( self.Config.Interp, 0 )
	self.Config.MoveRate = Max( Floor( self.Config.MoveRate ), 5 )
	self.Config.TickRate = Max( Floor( self.Config.TickRate ), 5 )
	self.Config.BWLimit = Max( self.Config.BWLimit, 5 )
	self.Config.SendRate = Max( Floor( self.Config.SendRate ), 5 )

	self:CheckRateValues()

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
		Notify( Message )
		return
	end

	ServerAdminPrint( Client, Message )
end

local function NotifyError( Client, Message, Format, ... )
	if not Client then
		Notify( Format and StringFormat( Message, ... ) or Message )
		return
	end

	Shine:NotifyCommandError( Client, Message, Format, ... )
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

function Plugin:CreateInfoCommands()
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

			TableSort( CommandNames, function( CommandName1, CommandName2 )
				return CommandName1 < CommandName2
			end )

			History.Cache[ Query ] = CommandNames
		end

		local NumCommands = #CommandNames
		PageNumber = CommandsAppearOnPage( NumCommands, PageNumber ) and PageNumber or 1

		local FirstIndexToShow, LastIndexToShow = GetBoundaryIndexes( PageNumber )
		FirstIndexToShow = Min( FirstIndexToShow, NumCommands )
		LastIndexToShow = Min( LastIndexToShow, NumCommands )

		PrintToConsole( Client, StringFormat( "Available commands (%s-%s; %s total)%s:",
			FirstIndexToShow, LastIndexToShow, NumCommands,
			Search == nil and "" or StringFormat( " matching %q", Search ) ) )

		for i = 1, NumCommands do
			local CommandName = CommandNames[ i ]
			if CommandAppearsOnPage( i, PageNumber ) then
				local Command = Shine.Commands[ CommandName ]

				if Command then
					local ChatCommand = type( Command.ChatCmd ) == "string"
						and StringFormat( " (chat: !%s)", Command.ChatCmd ) or ""

					local HelpLine = StringFormat( "%s. %s%s: %s", i, CommandName,
						ChatCommand, Command.HelpString or "No help available." )

					PrintToConsole( Client, HelpLine )
				end
			end
		end

		History.Search = Query
		History.PageNumber = PageNumber

		Histories[ Client or "Console" ] = History

		local EndMessage = "End command list."
		if CommandsAppearOnPage( NumCommands, PageNumber + 1 ) then
			EndMessage = StringFormat(
				"There are more commands! Re-issue the \"sh_help%s\" command to view them.",
				Search == nil and "" or StringFormat( " %s", Search ) )
		end
		PrintToConsole( Client, EndMessage )
	end
	local HelpCommand = self:BindCommand( "sh_help", nil, Help, true )
	HelpCommand:AddParam{ Type = "string", TakeRestofLine = true, Optional = true }
	HelpCommand:Help( "<search text> View help info for available commands (omit <search text> to see all)." )

	local StringRep = string.rep

	local function PrintTableToConsole( Client, Columns, Data )
		local CharSizes = {}
		local RowData = {}
		local TotalLength = 0
		-- I really wish the console was a monospace font...
		local SpaceMultiplier = 1.5

		for i = 1, #Columns do
			local Column = Columns[ i ]

			Column.OldName = Column.OldName or Column.Name
			Column.Name = Column.OldName..StringRep( " ", 4 )

			local Name = Column.Name
			local Getter = Column.Getter

			local Rows = {}

			local Max = #Name
			for j = 1, #Data do
				local Entry = Data[ j ]

				local String = Getter( Entry )
				local StringLength = #String + 4
				if StringLength > Max then
					Max = StringLength
				end

				Rows[ j ] = String
			end

			for j = 1, #Rows do
				local Entry = Rows[ j ]
				local Diff = Max - #Entry
				if Diff > 0 then
					Rows[ j ] = Entry..StringRep( " ", Diff )
				end
			end

			TotalLength = TotalLength + Max

			local NameDiff = Max - #Name
			if NameDiff > 0 then
				Column.Name = Name..StringRep( " ", Floor( NameDiff * SpaceMultiplier ) )
			end

			RowData[ i ] = Rows
		end

		local TopRow = {}
		for i = 1, #Columns do
			TopRow[ i ] = Columns[ i ].Name
		end

		PrintToConsole( Client, TableConcat( TopRow, "" ) )
		PrintToConsole( Client, StringRep( "=", TotalLength ) )

		for i = 1, #Data do
			local Row = {}

			for j = 1, #RowData do
				Row[ j ] = RowData[ j ][ i ]
			end

			PrintToConsole( Client, TableConcat( Row, "" ) )
		end
	end

	local NameColumn = {
		Name = "Name",
		Getter = function( Entry )
			local Client = Entry[ 2 ]
			local Player = Client:GetControllingPlayer()
			return StringFormat( "'%s'", Player and Player:GetName() or "NSPlayer" )
		end
	}
	local SteamIDColumn = {
		Name = "Steam ID",
		Getter = function( Entry )
			local Client = Entry[ 2 ]
			local ID = Client:GetUserId()

			return StringFormat( "%s - %s", ID, Shine.NS2ToSteamID( ID ) )
		end
	}

	local function Status( Client )
		local CanSeeIPs = Shine:HasAccess( Client, "sh_status" )

		local GameIDs = Shine.GameIDs
		local SortTable = {}
		local Count = 0

		for Client, ID in GameIDs:Iterate() do
			Count = Count + 1
			SortTable[ Count ] = { ID, Client }
		end

		TableSort( SortTable, function( A, B )
			if A[ 1 ] < B[ 1 ] then return true end
			return false
		end )

		PrintToConsole( Client, StringFormat( "Showing %s:", Count == 1 and "1 connected player" or Count.." connected players" ) )

		local Columns = {
			{
				Name = "ID",
				Getter = function( Entry )
					return tostring( Entry[ 1 ] )
				end
			},
			NameColumn,
			SteamIDColumn,
			{
				Name = "Team",
				Getter = function( Entry )
					local Client = Entry[ 2 ]
					local Player = Client:GetControllingPlayer()
					return Shine:GetTeamName( Player and Player:GetTeamNumber() or 0, true )
				end
			}
		}
		if CanSeeIPs then
			Columns[ #Columns + 1 ] = {
				Name = "IP",
				Getter = function( Entry )
					return IPAddressToString( Server.GetClientAddress( Entry[ 2 ] ) )
				end
			}
		end

		PrintTableToConsole( Client, Columns, SortTable )
	end
	local StatusCommand = self:BindCommand( "sh_status", nil, Status, true )
	StatusCommand:Help( "Prints a list of all connected players and their relevant information." )

	local function Who( Client, Target )
		local Columns = {
			NameColumn,
			SteamIDColumn,
			{
				Name = "Group",
				Getter = function( Entry )
					local UserData = Shine:GetUserData( Entry[ 2 ] )

					return UserData and UserData.Group or "None"
				end
			},
			{
				Name = "Immunity",
				Getter = function( Entry )
					local UserData = Shine:GetUserData( Entry[ 2 ] )
					local GroupName = UserData and UserData.Group
					local GroupData = GroupName and Shine:GetGroupData( GroupName )

					return tostring( GroupData and GroupData.Immunity or 0 )
				end
			}
		}

		if not Target then
			local GameIDs = Shine.GameIDs
			local SortTable = {}
			local Count = 0

			for Client, ID in GameIDs:Iterate() do
				Count = Count + 1
				SortTable[ Count ] = { Client:GetUserId(), Client }
			end

			TableSort( SortTable, function( A, B )
				if A[ 1 ] < B[ 1 ] then return true end
				return false
			end )

			PrintTableToConsole( Client, Columns, SortTable )

			return
		end

		local Player = Target:GetControllingPlayer()
		if not Player then
			PrintToConsole( Client, "Unknown user." )

			return
		end

		local SortTable = {
			{ Target:GetUserId(), Target }
		}

		PrintTableToConsole( Client, Columns, SortTable )
	end
	local WhoCommand = self:BindCommand( "sh_who", nil, Who, true )
	WhoCommand:AddParam{ Type = "client", Optional = true, Default = false }
	WhoCommand:Help( "<optional player> Displays rank information about the given player, or all players." )

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
end

function Plugin:CreateAdminCommands()
	local function RCon( Client, Command )
		Shared.ConsoleCommand( Command )
		Shine:Print( "%s ran console command: %s", true,
			Shine.GetClientInfo( Client ), Command )
	end
	local RConCommand = self:BindCommand( "sh_rcon", "rcon", RCon )
	RConCommand:AddParam{ Type = "string", TakeRestOfLine = true }
	RConCommand:Help( "<command> Executes a command on the server console." )

	local function SetPassword( Client, Password )
		Server.SetPassword( Password )
		Shine:AdminPrint( Client, "Password %s", true,
			Password ~= "" and "set to "..Password or "reset" )
	end
	local SetPasswordCommand = self:BindCommand( "sh_password", "password", SetPassword )
	SetPasswordCommand:AddParam{ Type = "string", TakeRestOfLine = true, Optional = true, Default = "" }
	SetPasswordCommand:Help( "<password> Sets the server password." )

	if not self.Config.DisableLuaRun then
		local pcall = pcall

		local function RunLua( Client, Code )
			local Player = Client and Client:GetControllingPlayer()

			local Name = Player and Player:GetName() or "Console"

			local Func, Err = loadstring( Code )

			if Func then
				local Success, Err = pcall( Func )
				if Success then
					Shine:Print( "%s ran: %s", true, Name, Code )
					if Client then
						ServerAdminPrint( Client, "Lua run was successful." )
					end
				else
					local ErrMessage = StringFormat( "Lua run failed. Error: %s", Err )

					Shine:Print( ErrMessage )
					if Client then
						ServerAdminPrint( Client, ErrMessage )
					end
				end
			else
				local ErrMessage = StringFormat( "Lua run failed. Error: %s", Err )

				Shine:Print( ErrMessage )
				if Client then
					ServerAdminPrint( Client, ErrMessage )
				end
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

	local function ChangeLevel( Client, MapName )
		MapCycle_ChangeMap( MapName )
	end
	local ChangeLevelCommand = self:BindCommand( "sh_changelevel", "map", ChangeLevel )
	ChangeLevelCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a map to change to." }
	ChangeLevelCommand:Help( "<map> Changes the map to the given level immediately." )

	local function CycleMap( Client )
		--The map vote plugin hooks this so we don't have to worry.
		MapCycle_CycleMap()
	end
	local CycleMapCommand = self:BindCommand( "sh_cyclemap", "cyclemap", CycleMap )
	CycleMapCommand:Help( "Cycles the map to the next one in the map cycle." )

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

				Shine:AdminPrint( Client,
					StringFormat( "Plugin %s now set to enabled in config.", Name ) )

				return
			end

			Success, Err = Shine:EnableExtension( Name )
		end

		if Success then
			Shine:AdminPrint( Client, StringFormat( "Plugin %s loaded successfully.", Name ) )

			--Update all players with the plugins state.
			Shine:SendPluginData( nil )

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
		if Name == "basecommands" then
			Shine:AdminPrint( Client, "Unloading the basecommands plugin is ill-advised. If you wish to do so, remove it from the active plugins list in your config." )
			return
		end

		if not Shine.Plugins[ Name ] or not Shine.Plugins[ Name ].Enabled then
			--If it's already disabled and we want to save, just save.
			if Save and Shine.AllPlugins[ Name ] then
				Shine.Config.ActiveExtensions[ Name ] = false
				Shine:SaveConfig()

				Shine:AdminPrint( Client,
					StringFormat( "Plugin %s now set to disabled in config.", Name ) )

				return
			end

			Shine:AdminPrint( Client, StringFormat( "Plugin %s is not loaded.", Name ) )

			return
		end

		Shine:UnloadExtension( Name )

		Shine:AdminPrint( Client, StringFormat( "Plugin %s unloaded successfully.", Name ) )

		Shine:SendPluginData( nil )

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

		Shine:SendPluginData( nil )
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

		Shine:SendPluginData( nil )
	end
	local ResumePluginCommand = self:BindCommand( "sh_resumeplugin", nil, ResumePlugin )
	ResumePluginCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a plugin to resume." }
	ResumePluginCommand:Help( "<plugin> Resumes a plugin." )

	local function ReloadUsers( Client )
		Shine:AdminPrint( Client, "Reloading users..." )
		Shine:LoadUsers( Shine.Config.GetUsersFromWeb, true )
	end
	local ReloadUsersCommand = self:BindCommand( "sh_reloadusers", nil, ReloadUsers )
	ReloadUsersCommand:Help( "Reloads the user data, either from the web or locally depending on your config settings." )

	local function AutoBalance( Client, Enable, UnbalanceAmount, Delay )
		Server.SetConfigSetting( "auto_team_balance",
			Enable and {
				enabled_on_unbalance_amount = UnbalanceAmount,
				enabled_after_seconds = Delay
			} or nil )

		if Enable then
			Shine:AdminPrint( Client,
				"Auto balance enabled. Player unbalance amount: %s. Delay: %s.",
				true, UnbalanceAmount, Delay )
		else
			Shine:AdminPrint( Client, "Auto balance disabled." )
		end
	end
	local AutoBalanceCommand = self:BindCommand( "sh_autobalance", "autobalance", AutoBalance )
	AutoBalanceCommand:AddParam{ Type = "boolean", Error = "Please specify whether auto balance should be enabled." }
	AutoBalanceCommand:AddParam{ Type = "number", Min = 1, Round = true, Optional = true, Default = 2 }
	AutoBalanceCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = 10 }
	AutoBalanceCommand:Help( "<true/false> <player amount> <seconds> Enables or disables auto balance. Player amount and seconds are optional." )
end

function Plugin:CreateAllTalkCommands()
	local function GenerateAllTalkCommand( Command, ChatCommand, ConfigOption, CommandNotifyString, NotifyString )
		local function CommandFunc( Client, Enable )
			self.Config[ ConfigOption ] = Enable

			self:SaveConfig( true )

			local Enabled = Enable and "enabled" or "disabled"

			if Shine.Config.NotifyOnCommand then
				Shine:CommandNotify( Client, "%s %s.", true, Enabled, CommandNotifyString )
			else
				Shine:NotifyDualColour( nil, Enable and 0 or 255, Enable and 255 or 0, 0,
					"[All Talk]", 255, 255, 255, "%s has been %s.", true, NotifyString, Enabled )
			end
		end
		local Command = self:BindCommand( Command, ChatCommand, CommandFunc )
		Command:AddParam{ Type = "boolean", Optional = true,
			Default = function() return not self.Config[ ConfigOption ] end }
		Command:Help( StringFormat( "<true/false> Enables or disables %s.", CommandNotifyString ) )
	end

	GenerateAllTalkCommand( "sh_alltalk", "alltalk", "AllTalk", "all talk", "All talk" )
	GenerateAllTalkCommand( "sh_alltalkpregame", "alltalkpregame", "AllTalkPreGame",
		"all talk pre-game", "All talk pre-game" )
end

function Plugin:CreateGameplayCommands()
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
					255, 255, 255, "Friendly fire has been %s.", true,
					Enable and "enabled" or "disabled" )
			end
		end
	end
	local FriendlyFireCommand = self:BindCommand( "sh_friendlyfire", { "ff", "friendlyfire" }, FriendlyFire )
	FriendlyFireCommand:AddParam{ Type = "number", Min = 0, Error = "Please specify a scale, or 0 for off." }
	FriendlyFireCommand:Help( "<scale> Sets the friendly fire scale. Use 0 to disable friendly fire." )

	local function ResetGame( Client )
		local Gamerules = GetGamerules()
		if not Gamerules then return end

		Gamerules:ResetGame()

		Shine:CommandNotify( Client, "reset the game." )
	end
	local ResetGameCommand = self:BindCommand( "sh_reset", "reset", ResetGame )
	ResetGameCommand:Help( "Resets the game round." )

	local function ReadyRoom( Client, Targets )
		local Gamerules = GetGamerules()
		if not Gamerules then return end

		local TargetCount = #Targets

		for i = 1, TargetCount do
			local Player = Targets[ i ]:GetControllingPlayer()
			if Player then
				Gamerules:JoinTeam( Player, kTeamReadyRoom, nil, true )
			end
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

	if not Shine.IsNS2Combat then
		local function HiveTeams( Client )
			--Force even teams is such an overconfident term...
			Shine:CommandNotify( Client, "shuffled the teams using the Hive skill shuffler." )
			ForceEvenTeams()
		end
		local HiveShuffle = self:BindCommand( "sh_hiveteams", { "hiveteams" }, HiveTeams )
		HiveShuffle:Help( "Runs NS2's Hive skill team shuffler." )
	end

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

	if not Shine.IsNS2Combat then
		local function Eject( Client, Target )
			local Player = Target:GetControllingPlayer()

			if not Player then return end

			if Player:isa( "Commander" ) then
				Player:Eject()

				Shine:CommandNotify( Client, "ejected %s.", true, Player:GetName() or "<unknown>" )
			else
				NotifyError( Client, "%s is not a commander.", true, Player:GetName() )
			end
		end
		local EjectCommand = self:BindCommand( "sh_eject", "eject", Eject )
		EjectCommand:AddParam{ Type = "client" }
		EjectCommand:Help( "<player> Ejects the given commander." )
	end
end

function Plugin:CreateMessageCommands()
	local function AdminSay( Client, Message )
		Shine:Notify( nil, "All",
			( Client and Shine.Config.ChatName ) or Shine.Config.ConsoleName, Message )
	end
	local AdminSayCommand = self:BindCommand( "sh_say", "say", AdminSay, false, true )
	AdminSayCommand:AddParam{ Type = "string", MaxLength = kMaxChatLength, TakeRestOfLine = true, Error = "Please specify a message." }
	AdminSayCommand:Help( "<message> Sends a message to everyone." )

	local function AdminTeamSay( Client, Team, Message )
		local Players = GetEntitiesForTeam( "Player", Team )

		Shine:Notify( Players, "Team",
			( Client and Shine.Config.ChatName ) or Shine.Config.ConsoleName, Message )
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

		Shine.ScreenText.Add( 3, {
			X = 0.5, Y = 0.25,
			Text = Message,
			Duration = 6,
			R = Colour[ 1 ], G = Colour[ 2 ], B = Colour[ 3 ],
			Alignment = 1,
			Size = 2,
			FadeIn = 1
		} )
		Shine:AdminPrint( nil, "CSay from %s[%s]: %s", true, PlayerName, ID, Message )
	end
	local CSayCommand = self:BindCommand( "sh_csay", "csay", CSay )
	CSayCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a message to send.", MaxLength = 128 }
	CSayCommand:Help( "<message> Displays a message in the centre of all player's screens." )

	local function GagPlayer( Client, Target, Duration )
		self.Gagged[ Target ] = Duration == 0 and true or SharedTime() + Duration

		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"
		local ID = Client and Client:GetUserId() or 0

		local TargetPlayer = Target:GetControllingPlayer()
		local TargetName = TargetPlayer and TargetPlayer:GetName() or "<unknown>"
		local TargetID = Target:GetUserId() or 0
		local DurationString = string.TimeToString( Duration )

		Shine:AdminPrint( nil, "%s[%s] gagged %s[%s]%s", true, PlayerName, ID, TargetName, TargetID,
			Duration == 0 and "" or " for "..DurationString )

		Shine:CommandNotify( Client, "gagged %s %s.", true, TargetName,
			Duration == 0 and "until map change" or "for "..DurationString )
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
			NotifyError( Client, "%s is not gagged.", true, TargetName )

			return
		end

		self.Gagged[ Target ] = nil

		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"
		local ID = Client and Client:GetUserId() or 0

		Shine:AdminPrint( nil, "%s[%s] ungagged %s[%s]", true, PlayerName, ID, TargetName, TargetID )

		Shine:CommandNotify( Client, "ungagged %s.", true, TargetName )
	end
	local UngagCommand = self:BindCommand( "sh_ungag", "ungag", UngagPlayer )
	UngagCommand:AddParam{ Type = "client" }
	UngagCommand:Help( "<player> Stops silencing the given player's chat." )

	do
		local StartVote

		local function CustomVote( Client, VoteQuestion )
			if not Client then return end

			StartVote = StartVote or Shine.GetUpValue( RegisterVoteType, "StartVote", true )
			if not StartVote then return end

			StartVote( "ShineCustomVote", Client, { VoteQuestion = VoteQuestion } )
		end
		local CustomVoteCommand = self:BindCommand( "sh_customvote", "customvote", CustomVote )
		CustomVoteCommand:AddParam{ Type = "string", TakeRestOfLine = true }
		CustomVoteCommand:Help( "<question> Starts a vote with the given question." )
	end
end

function Plugin:CreatePerformanceCommands()
	local function Interp( Client, NewInterp )
		local MinInterp = 2 / self.Config.SendRate * 1000
		if NewInterp < MinInterp then
			NotifyError( Client, "Interp is constrained by send rate to be %.2fms minimum.",
				true, MinInterp )
			return
		end

		self.Config.Interp = NewInterp

		Shared.ConsoleCommand( StringFormat( "interp %s", NewInterp * 0.001 ) )

		self:SaveConfig( true )
	end
	local InterpCommand = self:BindCommand( "sh_interp", "interp", Interp )
	InterpCommand:AddParam{ Type = "number", Min = 0 }
	InterpCommand:Help( "<time in ms> Sets the interpolation time and saves it." )

	local function TickRate( Client, NewRate )
		if NewRate > self.Config.MoveRate then
			NotifyError( Client, "Tick rate cannot be greater than move rate (%i).",
				true, self.Config.MoveRate )
			return
		end

		self.Config.TickRate = NewRate

		Shared.ConsoleCommand( StringFormat( "tickrate %s", NewRate ) )

		self:SaveConfig( true )
	end
	local TickRateCommand = self:BindCommand( "sh_tickrate", "tickrate", TickRate )
	TickRateCommand:AddParam{ Type = "number", Min = 10, Round = true }
	TickRateCommand:Help( "<rate> Sets the max server tickrate and saves it." )

	local function BWLimit( Client, NewLimit )
		self.Config.BWLimit = NewLimit

		Shared.ConsoleCommand( StringFormat( "bwlimit %s", NewLimit * 1024 ) )

		self:SaveConfig( true )
	end
	local BWLimitCommand = self:BindCommand( "sh_bwlimit", "bwlimit", BWLimit )
	BWLimitCommand:AddParam{ Type = "number", Min = 10 }
	BWLimitCommand:Help( "<limit in kbytes> Sets the bandwidth limit per player and saves it." )

	local function SendRate( Client, NewRate )
		if NewRate > self.Config.TickRate then
			NotifyError( Client, "Send rate cannot be greater than tick rate (%i).",
				true, self.Config.TickRate )
			return
		end

		self.Config.SendRate = NewRate

		Shared.ConsoleCommand( StringFormat( "sendrate %s", NewRate ) )

		self:SaveConfig( true )
	end
	local SendRateCommand = self:BindCommand( "sh_sendrate", "sendrate", SendRate )
	SendRateCommand:AddParam{ Type = "number", Min = 10, Round = true }
	SendRateCommand:Help( "<rate> Sets the rate of updates sent to clients and saves it." )

	local function MoveRate( Client, NewRate )
		self.Config.MoveRate = NewRate

		Shared.ConsoleCommand( StringFormat( "mr %s", NewRate ) )

		self:SaveConfig( true )
	end
	local MoveRateCommand = self:BindCommand( "sh_moverate", "moverate", MoveRate )
	MoveRateCommand:AddParam{ Type = "number", Min = 5, Round = true }
	MoveRateCommand:Help( "<rate> Sets the move rate and saves it." )
end

function Plugin:CreateCommands()
	self:CreateInfoCommands()
	self:CreateAdminCommands()
	self:CreateAllTalkCommands()
	self:CreateGameplayCommands()
	self:CreateMessageCommands()
	self:CreatePerformanceCommands()
end

function Plugin:OnCustomVoteSuccess( Data )

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
	if not Shine:GetPermission( Client, "sh_loadplugin" )
	and not Shine:GetPermission( Client, "sh_unloadplugin" ) then
		return
	end

	self:SendNetworkMessage( Client, "PluginTabAuthed", {}, true )

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
