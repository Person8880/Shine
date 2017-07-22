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
Plugin.Version = "1.3"

Plugin.HasConfig = true
Plugin.ConfigName = "BaseCommands.json"

Plugin.DefaultConfig = {
	AllTalk = false,
	AllTalkPreGame = false,
	AllTalkSpectator = false,
	AllTalkLocal = false,
	EjectVotesNeeded = 0.5,
	DisableLuaRun = false,
	Interp = 100,
	MoveRate = 26,
	TickRate = 30,
	SendRate = 20,
	BWLimit = Shine.IsNS2Combat and 35 or 50,
	FriendlyFire = false,
	FriendlyFireScale = 1,
	FriendlyFirePreGame = true,
	GaggedPlayers = {},
	VoteSettings = {
		-- An example, but more can be added based on their vote name.
		VoteKickPlayer = {
			ConsiderAFKPlayersInVotes = true,
			AFKTimeInSeconds = 60
		}
	}
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

-- Don't add anything to the config from the vote module below.
Plugin.HandlesVoteConfig = true

Script.Load( Shine.GetModuleFile( "vote.lua" ), true )

function Plugin:OnFirstThink()
	Hook.SetupClassHook( "NS2Gamerules", "GetFriendlyFire", "GetFriendlyFire", "ActivePre" )
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
end

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

do
	-- This whole thing is a lovely hack. It'll break very easily if lua/Voting.lua changes.
	local function SetupStopVote()
		local Events = debug.getregistry()[ "Event.HookTable" ]
		if not Events then return end

		local UpdateServerEvents = Events.UpdateServer
		if not UpdateServerEvents then return end

		local VoteUpdateFunc
		for i = 1, #UpdateServerEvents do
			local Source = debug.getinfo( UpdateServerEvents[ i ], "S" ).source
			if Source == "@lua/Voting.lua" then
				VoteUpdateFunc = UpdateServerEvents[ i ]
				break
			end
		end

		if not VoteUpdateFunc then return end

		local ActiveVoteName
		local ActiveVoteData
		local ActiveVoteResults
		local ActiveVoteStartedAtTime
		local ActiveVoteID
		function Plugin:StopVote()
			if not ActiveVoteName then return false end

			Server.SendNetworkMessage( "VoteComplete", { voteId = ActiveVoteID }, true )

			ActiveVoteName = nil
			ActiveVoteData = nil
			ActiveVoteResults = nil
			ActiveVoteStartedAtTime = nil

			return true
		end

		Shine.JoinUpValues( VoteUpdateFunc, Plugin.StopVote, {
			activeVoteName = "ActiveVoteName",
			activeVoteData = "ActiveVoteData",
			activeVoteResults = "ActiveVoteResults",
			activeVoteStartedAtTime = "ActiveVoteStartedAtTime",
			activeVoteId = "ActiveVoteID"
		} )

		-- This is really, really bad. But there's no other way to solve it at the moment.
		local GetNumVotingPlayers
		local function OverrideVoteCount()
			local OldGetNumVotingPlayers = GetNumVotingPlayers
			GetNumVotingPlayers = function()
				if not Plugin.Enabled then return OldGetNumVotingPlayers() end

				local Settings = Plugin.Config.VoteSettings[ ActiveVoteName ]
				if not Settings or Settings.ConsiderAFKPlayersInVotes then
					return OldGetNumVotingPlayers()
				end

				return Plugin:GetNumNonAFKHumans( tonumber( Settings.AFKTimeInSeconds ) or 60 )
			end
		end
		Shine.JoinUpValues( VoteUpdateFunc, OverrideVoteCount, {
			activeVoteName = "ActiveVoteName",
			GetNumVotingPlayers = "GetNumVotingPlayers"
		} )
		OverrideVoteCount()
	end

	local function RegisterCustomVote()
		RegisterVoteType( "ShineCustomVote", { VoteQuestion = "string (64)" } )

		SetVoteSuccessfulCallback( "ShineCustomVote", 4, function( Data )
			Plugin:OnCustomVoteSuccess( Data )
		end )
	end

	local function HookVotes()
		RegisterCustomVote()
		SetupStopVote()
	end

	if RegisterVoteType then
		HookVotes()
	else
		Shine.Hook.Add( "PostLoadScript", "SetupCustomVote", function( Script )
			if Script ~= "lua/Voting.lua" then return end

			HookVotes()
		end )
	end
end

do
	local Validator = Shine.Validator()
	Validator:AddRule( {
		Matches = function( self, Config )
			return Config.MoveRate > Config.TickRate
		end,
		Fix = function( self, Config )
			Config.MoveRate = Config.TickRate
			Notify( "Move rate cannot be more than tick rate. Clamping to tick rate." )
		end
	} )
	Validator:AddRule( {
		Matches = function( self, Config )
			return Config.SendRate > Config.TickRate
		end,
		Fix = function( self, Config )
			Config.SendRate = Config.TickRate
			Notify( "Send rate cannot be more than tick rate. Clamping to tick rate." )
		end
	} )
	Validator:AddRule( {
		Matches = function( self, Config )
			return Config.SendRate > Config.MoveRate
		end,
		Fix = function( self, Config )
			Config.SendRate = Config.MoveRate
			Notify( "Send rate cannot be more than move rate. Clamping to move rate." )
		end
	} )
	Validator:AddRule( {
		Matches = function( self, Config )
			local MinInterp = 2 / Config.SendRate * 1000

			if Config.Interp < MinInterp then
				Config.Interp = MinInterp
				Notify( StringFormat( "Interp cannot be less than %.2fms, clamping...",
					MinInterp ) )
				return true
			end

			return false
		end
	} )

	local Rates = {
		{
			Key = "MoveRate", Default = 26, Command = "mr %s"
		},
		{
			Key = "TickRate", Default = function() return Server.GetTickrate() end, Command = "tickrate %s"
		},
		{
			Key = "SendRate", Default = function() return Server.GetSendrate() end, Command = "sendrate %s"
		},
		{
			Key = "Interp", Default = 100, Command = function( Value ) return StringFormat( "interp %s", Value * 0.001 ) end
		},
		{
			Key = "BWLimit",
			Transformer = function( Value ) return Value * 1024 end,
			Default = function() return Server.GetBwLimit() end,
			Command = "bwlimit %s",
			WarnIfBelow = 50
		}
	}

	local function Transform( Rate, Value )
		return Rate.Transformer and Rate.Transformer( Value ) or Value
	end

	function Plugin:CheckRateValues()
		if Validator:Validate( self.Config ) then
			Notify( "Fixed incorrect rate values, check your config." )
			self:SaveConfig( true )
		end

		for i = 1, #Rates do
			local Rate = Rates[ i ]
			local ConfigValue = Transform( Rate, self.Config[ Rate.Key ] )
			local Default = IsType( Rate.Default, "function" ) and Rate.Default() or Rate.Default

			if ConfigValue ~= Default then
				local Command = IsType( Rate.Command, "function" ) and Rate.Command( ConfigValue )
					or StringFormat( Rate.Command, ConfigValue )

				Shared.ConsoleCommand( Command )
			end

			if Rate.WarnIfBelow and ConfigValue < Transform( Rate, Rate.WarnIfBelow ) then
				Notify( StringFormat( "WARNING: %s is below the default of %s", Rate.Key, Rate.WarnIfBelow ) )
			end
		end
	end
end

function Plugin:Initialise()
	self.Gagged = self:LoadGaggedPlayers()

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

function Plugin:LoadGaggedPlayers()
	local GaggedPlayers = {}

	for ID, Gagged in pairs( self.Config.GaggedPlayers ) do
		if Gagged and tonumber( ID ) then
			GaggedPlayers[ tonumber( ID ) ] = true
		end
	end

	return GaggedPlayers
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

		if State <= kGameState.PreGame then
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

do
	local function IsPregameAllTalk( self, Gamerules )
		return self.Config.AllTalkPreGame and Gamerules:GetGameState() < kGameState.PreGame
	end

	local function IsSpectatorAllTalk( self, Listener )
		return self.Config.AllTalkSpectator and Listener:GetTeamNumber() == ( kSpectatorIndex or 3 )
	end

	-- Will need updating if it changes in NS2Gamerules...
	local MaxWorldSoundDistance = 30 * 30
	local DisableLocalAllTalkClients = {}

	function Plugin:RemoveAllTalkPreference( Client )
		DisableLocalAllTalkClients[ Client ] = nil
	end

	--[[
		Override voice chat to allow everyone to hear each other with alltalk on.
	]]
	function Plugin:CanPlayerHearPlayer( Gamerules, Listener, Speaker, ChannelType )
		local SpeakerClient = GetOwner( Speaker )

		if SpeakerClient and self:IsClientGagged( SpeakerClient ) then return false end
		if Listener:GetClientMuted( Speaker:GetClientIndex() ) then return false end

		if ChannelType and ChannelType ~= VoiceChannel.Global then
			local ListenerClient = GetOwner( Listener )

			-- Default behaviour for those that have chosen to disable it.
			if ( ListenerClient and DisableLocalAllTalkClients[ ListenerClient ] )
			or ( SpeakerClient and DisableLocalAllTalkClients[ SpeakerClient ] ) then
				return
			end

			-- Assume non-global means local chat, so "all-talk" means true if distance check passes.
			if self.Config.AllTalkLocal or self.Config.AllTalk or IsPregameAllTalk( self, Gamerules )
			or IsSpectatorAllTalk( self, Listener ) then
				return Listener:GetDistanceSquared( Speaker ) < MaxWorldSoundDistance
			end

			return
		end

		if self.Config.AllTalk or IsPregameAllTalk( self, Gamerules )
		or IsSpectatorAllTalk( self, Listener ) then
			return true
		end
	end

	function Plugin:ReceiveEnableLocalAllTalk( Client, Data )
		DisableLocalAllTalkClients[ Client ] = not Data.Enabled
	end
end

local function NotifyError( Client, TranslationKey, Data, Message, Format, ... )
	if not Client then
		Notify( Format and StringFormat( Message, ... ) or Message )
		return
	end

	Plugin:SendTranslatedError( Client, TranslationKey, Data )
end

local Histories = {}

function Plugin:ClientDisconnect( Client )
	Histories[ Client ] = nil

	if self.PluginClients then
		self.PluginClients[ Client ] = nil
	end

	self:RemoveAllTalkPreference( Client )
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

		Shine.PrintToConsole( Client, StringFormat( "Available commands (%s-%s; %s total)%s:",
			FirstIndexToShow, LastIndexToShow, NumCommands,
			Search == nil and "" or StringFormat( " matching %q", Search ) ) )

		for i = 1, NumCommands do
			local CommandName = CommandNames[ i ]
			if CommandAppearsOnPage( i, PageNumber ) then
				local Command = Shine.Commands[ CommandName ]

				if Command then
					local ChatCommand = ""
					if Command.ChatCmd then
						local ChatCommandString
						if IsType( Command.ChatCmd, "string" ) then
							ChatCommandString = Command.ChatCmd
						else
							ChatCommandString = TableConcat( Command.ChatCmd, " or !" )
						end

						ChatCommand = StringFormat( " (chat: !%s)", ChatCommandString )
					end

					local HelpLine = StringFormat( "%s. %s%s: %s", i, CommandName,
						ChatCommand, Command:GetHelp() or "No help available." )

					Shine.PrintToConsole( Client, HelpLine )
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
		Shine.PrintToConsole( Client, EndMessage )
	end
	local HelpCommand = self:BindCommand( "sh_help", nil, Help, true )
	HelpCommand:AddParam{ Type = "string", TakeRestofLine = true, Optional = true, Help = "search text" }
	HelpCommand:Help( "View help info for available commands (omit <search text> to see all)." )

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

		Shine.PrintToConsole( Client, StringFormat( "Showing %s:", Count == 1 and "1 connected player" or Count.." connected players" ) )

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

		Shine.PrintTableToConsole( Client, Columns, SortTable )
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

			Shine.PrintTableToConsole( Client, Columns, SortTable )

			return
		end

		local Player = Target:GetControllingPlayer()
		if not Player then
			Shine.PrintToConsole( Client, "Unknown user." )

			return
		end

		local SortTable = {
			{ Target:GetUserId(), Target }
		}

		Shine.PrintTableToConsole( Client, Columns, SortTable )
	end
	local WhoCommand = self:BindCommand( "sh_who", nil, Who, true )
	WhoCommand:AddParam{ Type = "client", Optional = true, Default = false }
	WhoCommand:Help( "Displays rank information about the given player, or all players." )

	local function ListMaps( Client )
		local Cycle = MapCycle_GetMapCycle()

		if not Cycle or not Cycle.maps then
			Shine.PrintToConsole( Client, "Unable to load map cycle list." )

			return
		end

		local Maps = Cycle.maps

		Shine.PrintToConsole( Client, "Installed maps:" )
		for i = 1, #Maps do
			local Map = Maps[ i ]
			local MapName = IsType( Map, "table" ) and Map.map or Map

			Shine.PrintToConsole( Client, StringFormat( "- %s", MapName ) )
		end
	end
	local ListMapsCommand = self:BindCommand( "sh_listmaps", nil, ListMaps )
	ListMapsCommand:Help( "Lists all installed maps on the server." )

	local function ListPlugins( Client )
		Shine.PrintToConsole( Client, "Loaded plugins:" )
		for Name, Table in SortedPairs( Shine.Plugins ) do
			if Table.Enabled then
				Shine.PrintToConsole( Client, StringFormat( "%s - version: %s", Name, Table.Version or "1.0" ) )
			end
		end
	end
	local ListPluginsCommand = self:BindCommand( "sh_listplugins", nil, ListPlugins, true )
	ListPluginsCommand:Help( "Lists all loaded plugins." )
end

function Plugin:CreateAdminCommands()
	local function RCon( Client, Command )
		Shared.ConsoleCommand( Command )
		Shine:Print( "%s ran console command: %s", true,
			Shine.GetClientInfo( Client ), Command )
	end
	local RConCommand = self:BindCommand( "sh_rcon", "rcon", RCon )
	RConCommand:AddParam{ Type = "string", TakeRestOfLine = true, Help = "command" }
	RConCommand:Help( "Executes a command on the server console." )

	local function SetPassword( Client, Password )
		Server.SetPassword( Password )
		Shine:AdminPrint( Client, "Password %s", true,
			Password ~= "" and "set to "..Password or "reset" )
	end
	local SetPasswordCommand = self:BindCommand( "sh_password", "password", SetPassword )
	SetPasswordCommand:AddParam{ Type = "string", TakeRestOfLine = true, Optional = true,
		Default = "", Help = "password" }
	SetPasswordCommand:Help( "Sets the server password. Leave password empty to reset." )

	if not self.Config.DisableLuaRun then
		local pcall = pcall

		local function RunLua( Client, Code )
			local Func, Err = loadstring( Code )

			if Func then
				local Success, Err = pcall( Func )
				if Success then
					Shine:Print( "%s ran: %s", true, Shine.GetClientInfo( Client ), Code )
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
		RunLuaCommand:AddParam{ Type = "string", TakeRestOfLine = true, Help = "Lua code" }
		RunLuaCommand:Help( "Runs a string of Lua code on the server. Be careful with this." )
	end

	local function SetCheats( Client, Enable )
		Shared.ConsoleCommand( "cheats "..( Enable and "1" or "0" ) )
		self:SendTranslatedMessage( Client, "CHEATS_TOGGLED", {
			Enabled = Enable
		} )
	end
	local SetCheatsCommand = self:BindCommand( "sh_cheats", "cheats", SetCheats )
	SetCheatsCommand:AddParam{ Type = "boolean", Optional = true, Default = function() return not Shared.GetCheatsEnabled() end }
	SetCheatsCommand:Help( "Enables or disables cheats mode." )

	local function Kick( Client, Target, Reason )
		local TargetPlayer = Target:GetControllingPlayer()
		local TargetName = TargetPlayer and TargetPlayer:GetName() or "<unknown>"

		Shine:Print( "%s kicked %s.%s", true,
			Shine.GetClientInfo( Client ),
			Shine.GetClientInfo( Target ),
			Reason ~= "" and " Reason: "..Reason or ""
		)

		do
			local KickMessage
			local KickerName = Shine.GetClientName( Client )
			if Reason ~= "" then
				KickMessage = StringFormat( "Kicked from server by %s: %s",
					KickerName, Reason )
			else
				KickMessage = StringFormat( "Kicked from server by %s.", KickerName )
			end

			Server.DisconnectClient( Target, KickMessage )
		end

		self:SendTranslatedMessage( Client, "ClientKicked", {
			TargetName = TargetName,
			Reason = Reason
		} )
	end
	local KickCommand = self:BindCommand( "sh_kick", "kick", Kick )
	KickCommand:AddParam{ Type = "client", NotSelf = true }
	KickCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "", Help = "reason" }
	KickCommand:Help( "Kicks the given player." )

	local function ChangeLevel( Client, MapName )
		MapCycle_ChangeMap( MapName )
	end
	local ChangeLevelCommand = self:BindCommand( "sh_changelevel", "map", ChangeLevel )
	ChangeLevelCommand:AddParam{ Type = "string", TakeRestOfLine = true,
		Error = "Please specify a map to change to.", Help = "map" }
	ChangeLevelCommand:Help( "Changes the map to the given level immediately." )

	local function CycleMap( Client )
		--The map vote plugin hooks this so we don't have to worry.
		MapCycle_CycleMap( Shared.GetMapName() )
	end
	local CycleMapCommand = self:BindCommand( "sh_cyclemap", "cyclemap", CycleMap )
	CycleMapCommand:Help( "Cycles the map to the next one in the map cycle." )

	local function LoadPlugin( Client, Name, Save )
		if Name == "basecommands" then
			Shine.PrintToConsole( Client, "You cannot reload the basecommands plugin." )
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
	LoadPluginCommand:AddParam{ Type = "string", Error = "Please specify a plugin to load.", Help = "plugin" }
	LoadPluginCommand:AddParam{ Type = "boolean", Optional = true, Default = false, Help = "save" }
	LoadPluginCommand:Help( "Loads or reloads a plugin." )

	local function UnloadPlugin( Client, Name, Save )
		if Name == "basecommands" then
			Shine.PrintToConsole( Client, "Unloading the basecommands plugin is ill-advised. If you wish to do so, remove it from the active plugins list in your config." )
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
	UnloadPluginCommand:AddParam{ Type = "string", Error = "Please specify a plugin to unload.", Help = "plugin" }
	UnloadPluginCommand:AddParam{ Type = "boolean", Optional = true, Default = false, Help = "save" }
	UnloadPluginCommand:Help( "Unloads a plugin." )

	local function SuspendPlugin( Client, Name )
		local Plugin = Shine.Plugins[ Name ]

		if not Plugin or not Plugin.Enabled then
			Shine.PrintToConsole( Client, StringFormat( "The plugin %s is not loaded or already suspended.", Name ) )

			return
		end

		Plugin:Suspend()

		Shine:AdminPrint( Client, StringFormat( "Plugin %s has been suspended.", Name ) )

		Shine:SendPluginData( nil )
	end
	local SuspendPluginCommand = self:BindCommand( "sh_suspendplugin", nil, SuspendPlugin )
	SuspendPluginCommand:AddParam{ Type = "string", TakeRestOfLine = true,
		Error = "Please specify a plugin to suspend.", Help = "plugin" }
	SuspendPluginCommand:Help( "Suspends a plugin." )

	local function ResumePlugin( Client, Name )
		local Plugin = Shine.Plugins[ Name ]

		if not Plugin or Plugin.Enabled or not Plugin.Suspended then
			Shine.PrintToConsole( Client, StringFormat( "The plugin %s is already running or is not suspended or not loaded.", Name ) )

			return
		end

		Plugin:Resume()

		Shine:AdminPrint( Client, StringFormat( "Plugin %s has been resumed.", Name ) )

		Shine:SendPluginData( nil )
	end
	local ResumePluginCommand = self:BindCommand( "sh_resumeplugin", nil, ResumePlugin )
	ResumePluginCommand:AddParam{ Type = "string", TakeRestOfLine = true,
		Error = "Please specify a plugin to resume.", Help = "plugin" }
	ResumePluginCommand:Help( "Resumes a plugin." )

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
	AutoBalanceCommand:AddParam{ Type = "number", Min = 1, Round = true, Optional = true, Default = 2, Help = "player amount" }
	AutoBalanceCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = 10, Help = "seconds" }
	AutoBalanceCommand:Help( "Enables or disables auto balance. Player amount and seconds are optional." )
end

function Plugin:CreateAllTalkCommands()
	local function GenerateAllTalkCommand( Command, ChatCommand, ConfigOption, CommandNotifyString, NotifyString )
		local function CommandFunc( Client, Enable )
			self.Config[ ConfigOption ] = Enable
			self:SaveConfig( true )

			if Shine.Config.NotifyOnCommand then
				self:SendTranslatedMessage( Client, CommandNotifyString, {
					Enabled = Enable
				} )
			else
				Shine:TranslatedNotifyDualColour( nil, Enable and 0 or 255, Enable and 255 or 0, 0,
					"ALL_TALK_TAG", 255, 255, 255, NotifyString..( Enable and "ENABLED" or "DISABLED" ),
					self.__Name )
			end
		end
		local Command = self:BindCommand( Command, ChatCommand, CommandFunc )
		Command:AddParam{ Type = "boolean", Optional = true,
			Default = function() return not self.Config[ ConfigOption ] end }
		Command:Help( StringFormat( "Enables or disables %s.", CommandNotifyString ) )
	end

	GenerateAllTalkCommand( "sh_alltalk", "alltalk", "AllTalk", "ALLTALK_TOGGLED", "ALLTALK_NOTIFY_" )
	GenerateAllTalkCommand( "sh_alltalkpregame", "alltalkpregame", "AllTalkPreGame",
		"ALLTALK_PREGAME_TOGGLED", "ALLTALK_PREGAME_NOTIFY_" )
	GenerateAllTalkCommand( "sh_alltalklocal", "alltalklocal", "AllTalkLocal", "ALLTALK_LOCAL_TOGGLED",
		"ALLTALK_LOCAL_NOTIFY_" )
end

function Plugin:CreateGameplayCommands()
	local function FriendlyFire( Client, Scale )
		local OldState = self.Config.FriendlyFire
		local OldScale = self.Config.FriendlyFireScale
		local Enable = Scale > 0

		if Enable then
			self.Config.FriendlyFire = true
			self.Config.FriendlyFireScale = Scale
		else
			self.Config.FriendlyFire = false
		end

		self:SaveConfig( true )

		if OldState ~= self.Config.FriendlyFire or OldScale ~= self.Config.FriendlyFireScale then
			if Shine.Config.NotifyOnCommand then
				self:SendTranslatedMessage( Client, "FRIENDLY_FIRE_SCALE", {
					Scale = Scale
				} )
			else
				Shine:TranslatedNotifyDualColour( nil, Enable and 0 or 255, Enable and 255 or 0, 0, "FF_TAG",
					255, 255, 255, Enable and "FRIENDLY_FIRE_ENABLED" or "FRIENDLY_FIRE_DISABLED",
					self.__Name )
			end
		end
	end
	local FriendlyFireCommand = self:BindCommand( "sh_friendlyfire", { "ff", "friendlyfire" }, FriendlyFire )
	FriendlyFireCommand:AddParam{ Type = "number", Min = 0, Error = "Please specify a scale, or 0 for off.", Help = "scale" }
	FriendlyFireCommand:Help( "Sets the friendly fire scale. Use 0 to disable friendly fire." )

	local function ResetGame( Client )
		local Gamerules = GetGamerules()
		if not Gamerules then return end

		Gamerules:ResetGame()

		self:SendTranslatedMessage( Client, "RESET_GAME" )
	end
	local ResetGameCommand = self:BindCommand( "sh_reset", "reset", ResetGame )
	ResetGameCommand:Help( "Resets the game round." )

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

		self:SendTranslatedMessage( Client, "RANDOM_TEAM", {
			TargetCount = NumPlayers
		} )
	end
	local ForceRandomCommand = self:BindCommand( "sh_forcerandom", "forcerandom", ForceRandom )
	ForceRandomCommand:AddParam{ Type = "clients" }
	ForceRandomCommand:Help( "Forces the given player(s) onto a random team." )

	local function ChangeTeam( Client, Targets, Team )
		local Gamerules = GetGamerules()
		if not Gamerules then return end

		local TargetCount = #Targets
		if TargetCount == 0 then return end

		for i = 1, TargetCount do
			local Player = Targets[ i ]:GetControllingPlayer()

			if Player then
				Gamerules:JoinTeam( Player, Team, nil, true )
			end
		end

		self:SendTranslatedMessage( Client, "ChangeTeam", {
			TargetCount = TargetCount,
			Team = Team
		} )
	end
	local ChangeTeamCommand = self:BindCommand( "sh_setteam", { "team", "setteam" }, ChangeTeam )
	ChangeTeamCommand:AddParam{ Type = "clients" }
	ChangeTeamCommand:AddParam{ Type = "team", Error = "Please specify a team to move to." }
	ChangeTeamCommand:Help( "Sets the given player(s) onto the given team." )

	local function ReadyRoom( Client, Targets )
		ChangeTeam( Client, Targets, kTeamReadyRoom )
	end
	local ReadyRoomCommand = self:BindCommand( "sh_rr", "rr", ReadyRoom )
	ReadyRoomCommand:AddParam{ Type = "clients" }
	ReadyRoomCommand:Help( "<players> Sends the given player(s) to the ready room." )

	if not Shine.IsNS2Combat then
		local function HiveTeams( Client )
			--Force even teams is such an overconfident term...
			self:SendTranslatedMessage( Client, "HIVE_TEAMS", {} )
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

		self:SendTranslatedMessage( Client, "FORCE_START", {} )
	end
	local ForceRoundStartCommand = self:BindCommand( "sh_forceroundstart", "forceroundstart", ForceRoundStart )
	ForceRoundStartCommand:Help( "Forces the round to start." )

	if not Shine.IsNS2Combat then
		local function Eject( Client, Target )
			local Player = Target:GetControllingPlayer()
			if not Player then return end

			if Player:isa( "Commander" ) then
				Player:Eject()

				self:SendTranslatedMessage( Client, "PLAYER_EJECTED", {
					TargetName = Player:GetName() or "<unknown>"
				} )
			else
				NotifyError( Client, "ERROR_NOT_COMMANDER", {
					TargetName = Player:GetName()
				}, "%s is not a commander.", true, Player:GetName() )
			end
		end
		local EjectCommand = self:BindCommand( "sh_eject", "eject", Eject )
		EjectCommand:AddParam{ Type = "client" }
		EjectCommand:Help( "Ejects the given commander." )
	end
end

function Plugin:CreateMessageCommands()
	local function AdminSay( Client, Message )
		Shine:Notify( nil, "All",
			( Client and Shine.Config.ChatName ) or Shine.Config.ConsoleName, Message )
	end
	local AdminSayCommand = self:BindCommand( "sh_say", "say", AdminSay, false, true )
	AdminSayCommand:AddParam{ Type = "string", MaxLength = kMaxChatLength * 4 + 1, TakeRestOfLine = true,
		Error = "Please specify a message.", Help = "message" }
	AdminSayCommand:Help( "Sends a message to everyone." )

	local function AdminTeamSay( Client, Team, Message )
		local Players = GetEntitiesForTeam( "Player", Team )

		Shine:Notify( Players, "Team",
			( Client and Shine.Config.ChatName ) or Shine.Config.ConsoleName, Message )
	end
	local AdminTeamSayCommand = self:BindCommand( "sh_teamsay", "teamsay", AdminTeamSay, false, true )
	AdminTeamSayCommand:AddParam{ Type = "team", Error = "Please specify a team." }
	AdminTeamSayCommand:AddParam{ Type = "string", TakeRestOfLine = true, MaxLength = kMaxChatLength * 4 + 1,
		Error = "Please specify a message.", Help = "message" }
	AdminTeamSayCommand:Help( "Sends a message to everyone on the given team." )

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
	PMCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a message to send.",
		MaxLength = kMaxChatLength * 4 + 1, Help = "message" }
	PMCommand:Help( "Sends a private message to the given player." )

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
			FadeIn = 1,
			IgnoreFormat = true
		} )
		Shine:AdminPrint( nil, "CSay from %s: %s", true, Shine.GetClientInfo( Client ), Message )
	end
	local CSayCommand = self:BindCommand( "sh_csay", "csay", CSay )
	CSayCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a message to send.",
		MaxLength = 128, Help = "message" }
	CSayCommand:Help( "Displays a message in the centre of all player's screens." )

	local function GagPlayer( Client, Target, Duration )
		self.Gagged[ Target:GetUserId() ] = Duration == 0 and true or SharedTime() + Duration

		local TargetPlayer = Target:GetControllingPlayer()
		local TargetName = TargetPlayer and TargetPlayer:GetName() or "<unknown>"
		local DurationString = string.TimeToString( Duration )

		Shine:AdminPrint( nil, "%s gagged %s%s", true,
			Shine.GetClientInfo( Client ),
			Shine.GetClientInfo( Target ),
			Duration == 0 and "" or " for "..DurationString )

		self:SendTranslatedMessage( Client, "PLAYER_GAGGED", {
			TargetName = TargetName,
			Duration = Duration
		} )
	end
	local GagCommand = self:BindCommand( "sh_gag", "gag", GagPlayer )
	GagCommand:AddParam{ Type = "client" }
	GagCommand:AddParam{ Type = "time", Round = true, Min = 0, Max = 1800, Optional = true, Default = 0 }
	GagCommand:Help( "Silences the given player's chat. If no duration is given, it will hold for the remainder of the map." )

	local function GagID( Client, ID )
		self.Config.GaggedPlayers[ tostring( ID ) ] = true
		self:SaveConfig()

		self.Gagged[ ID ] = true

		Shine:AdminPrint( nil, "%s gagged %s permanently.", true,
			Shine.GetClientInfo( Client ), ID )
	end
	self:BindCommand( "sh_gagid", "gagid", GagID )
		:AddParam{ Type = "steamid" }
		:Help( "Silences the given Steam ID's chat permanently until ungagged, persisting between map changes." )

	local function UngagID( Client, ID )
		local IDAsString = tostring( ID )
		if not self.Config.GaggedPlayers[ IDAsString ] then
			NotifyError( Client, "ERROR_NOT_GAGGED", {
				TargetName = IDAsString
			}, "%s is not gagged.", true, IDAsString )

			return
		end

		self.Gagged[ ID ] = nil
		self.Config.GaggedPlayers[ IDAsString ] = nil
		self:SaveConfig()

		Shine:AdminPrint( nil, "%s ungagged %s.", true,
			Shine.GetClientInfo( Client ), IDAsString )
	end
	self:BindCommand( "sh_ungagid", "ungagid", UngagID )
		:AddParam{ Type = "steamid" }
		:Help( "Stops silencing the given Steam ID's chat if they have been gagged with sh_gagid." )

	local function UngagPlayer( Client, Target )
		local TargetPlayer = Target:GetControllingPlayer()
		local TargetName = TargetPlayer and TargetPlayer:GetName() or "<unknown>"
		local TargetID = Target:GetUserId() or 0

		if not self.Gagged[ TargetID ] then
			NotifyError( Client, "ERROR_NOT_GAGGED", {
				TargetName = TargetName
			}, "%s is not gagged.", true, TargetName )

			return
		end

		self.Gagged[ TargetID ] = nil

		local IDAsString = tostring( TargetID )
		if self.Config.GaggedPlayers[ IDAsString ] then
			self.Config.GaggedPlayers[ IDAsString ] = nil
			self:SaveConfig()
		end

		Shine:AdminPrint( nil, "%s ungagged %s", true,
			Shine.GetClientInfo( Client ),
			Shine.GetClientInfo( Target ) )

		self:SendTranslatedMessage( Client, "PLAYER_UNGAGGED", {
			TargetName = TargetName
		} )
	end
	local UngagCommand = self:BindCommand( "sh_ungag", "ungag", UngagPlayer )
	UngagCommand:AddParam{ Type = "client" }
	UngagCommand:Help( "Stops silencing the given player's chat." )

	do
		local StartVote

		local function CustomVote( Client, VoteQuestion )
			if not Client then return end

			StartVote = StartVote or Shine.StartNS2Vote
			if not StartVote then return end

			StartVote( "ShineCustomVote", Client, { VoteQuestion = VoteQuestion } )
		end
		local CustomVoteCommand = self:BindCommand( "sh_customvote", "customvote", CustomVote )
		CustomVoteCommand:AddParam{ Type = "string", TakeRestOfLine = true, Help = "question" }
		CustomVoteCommand:Help( "Starts a vote with the given question." )
	end

	local function StopVote( Client )
		if self.StopVote and self:StopVote() then
			Shine:AdminPrint( nil, "%s stopped the current vote.", true, Shine.GetClientInfo( Client ) )
			self:SendTranslatedMessage( Client, "VOTE_STOPPED", {} )
		else
			self:NotifyTranslatedCommandError( Client, "ERROR_NO_VOTE_IN_PROGRESS" )
		end
	end
	local StopVoteCommand = self:BindCommand( "sh_stopvote", "stopvote", StopVote )
	StopVoteCommand:Help( "Stops the current vanilla vote." )
end

function Plugin:CreatePerformanceCommands()
	local function Interp( Client, NewInterp )
		local MinInterp = 2 / self.Config.SendRate * 1000
		if NewInterp < MinInterp then
			NotifyError( Client, "ERROR_INTERP_CONSTRAINT", {
				Rate = MinInterp
			}, "Interp is constrained by send rate to be %.2fms minimum.", true, MinInterp )
			return
		end

		self.Config.Interp = NewInterp

		Shared.ConsoleCommand( StringFormat( "interp %s", NewInterp * 0.001 ) )

		Shine:AdminPrint( Client, "%s set interp to %.2fms", true,
			Shine.GetClientInfo( Client ),
			NewInterp )

		self:SaveConfig( true )
	end
	local InterpCommand = self:BindCommand( "sh_interp", "interp", Interp )
	InterpCommand:AddParam{ Type = "number", Min = 0, Help = "time in ms" }
	InterpCommand:Help( "Sets the interpolation time and saves it." )

	local function AddAdditionalInfo( Command, ConfigKey, Units )
		Command.GetAdditionalInfo = function()
			return StringFormat( " - Current value: %i%s", self.Config[ ConfigKey ], Units )
		end
	end

	AddAdditionalInfo( InterpCommand, "Interp", "ms" )

	local function TickRate( Client, NewRate )
		if NewRate < self.Config.MoveRate then
			NotifyError( Client, "ERROR_TICKRATE_CONSTRAINT", {
				Rate = self.Config.MoveRate
			}, "Tick rate cannot be less than move rate (%i).", true, self.Config.MoveRate )
			return
		end

		self.Config.TickRate = NewRate

		Shared.ConsoleCommand( StringFormat( "tickrate %s", NewRate ) )

		Shine:AdminPrint( Client, "%s set tick rate to %i/s", true,
			Shine.GetClientInfo( Client ),
			NewRate )

		self:SaveConfig( true )
	end
	local TickRateCommand = self:BindCommand( "sh_tickrate", "tickrate", TickRate )
	TickRateCommand:AddParam{ Type = "number", Min = 10, Round = true, Help = "rate" }
	TickRateCommand:Help( "Sets the max server tickrate and saves it." )

	AddAdditionalInfo( TickRateCommand, "TickRate", "/s" )

	local function BWLimit( Client, NewLimit )
		self.Config.BWLimit = NewLimit

		Shared.ConsoleCommand( StringFormat( "bwlimit %s", NewLimit * 1024 ) )

		Shine:AdminPrint( Client, "%s set bandwidth limit to %.2fkb/s", true,
			Shine.GetClientInfo( Client ),
			NewLimit )

		self:SaveConfig( true )
	end
	local BWLimitCommand = self:BindCommand( "sh_bwlimit", "bwlimit", BWLimit )
	BWLimitCommand:AddParam{ Type = "number", Min = 10, Help = "limit in kbytes" }
	BWLimitCommand:Help( "Sets the bandwidth limit per player and saves it." )

	AddAdditionalInfo( BWLimitCommand, "BWLimit", "kb/s" )

	local function SendRate( Client, NewRate )
		if NewRate > self.Config.TickRate then
			NotifyError( Client, "ERROR_SENDRATE_CONSTRAINT", {
				Rate = self.Config.TickRate
			}, "Send rate cannot be greater than tick rate (%i).", true, self.Config.TickRate )
			return
		end

		if NewRate > self.Config.MoveRate then
			NotifyError( Client, "ERROR_SENDRATE_MOVE_CONSTRAINT", {
				Rate = self.Config.MoveRate
			}, "Send rate cannot be greater than move rate (%i).", true, self.Config.MoveRate )
			return
		end

		self.Config.SendRate = NewRate

		Shared.ConsoleCommand( StringFormat( "sendrate %s", NewRate ) )

		Shine:AdminPrint( Client, "%s set send rate to %i/s", true,
			Shine.GetClientInfo( Client ),
			NewRate )

		self:SaveConfig( true )
	end
	local SendRateCommand = self:BindCommand( "sh_sendrate", "sendrate", SendRate )
	SendRateCommand:AddParam{ Type = "number", Min = 10, Round = true, Help = "rate" }
	SendRateCommand:Help( "Sets the rate of updates sent to clients and saves it." )

	AddAdditionalInfo( SendRateCommand, "SendRate", "/s" )

	local function MoveRate( Client, NewRate )
		if NewRate > self.Config.TickRate then
			NotifyError( Client, "ERROR_MOVERATE_CONSTRAINT", {
				Rate = self.Config.TickRate
			}, "Move rate cannot be greater than tick rate (%i).", true, self.Config.TickRate )
			return
		end

		if NewRate < self.Config.SendRate then
			NotifyError( Client, "ERROR_MOVERATE_SENDRATE_CONSTRAINT", {
				Rate = self.Config.SendRate
			}, "Move rate cannot be less than send rate (%i).", true, self.Config.SendRate )
			return
		end

		self.Config.MoveRate = NewRate

		Shared.ConsoleCommand( StringFormat( "mr %s", NewRate ) )

		Shine:AdminPrint( Client, "%s set move rate to %i/s", true,
			Shine.GetClientInfo( Client ),
			NewRate )

		self:SaveConfig( true )
	end
	local MoveRateCommand = self:BindCommand( "sh_moverate", "moverate", MoveRate )
	MoveRateCommand:AddParam{ Type = "number", Min = 5, Round = true, Help = "rate" }
	MoveRateCommand:Help( "Sets the move rate and saves it." )

	AddAdditionalInfo( MoveRateCommand, "MoveRate", "/s" )
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
	local ID = Client:GetUserId()
	local GagData = self.Gagged[ ID ]

	if not GagData then return false end

	if GagData == true then return true end
	if GagData > SharedTime() then return true end

	self.Gagged[ ID ] = nil

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

function Plugin:OnPluginUnload( Name, Plugin, Shared )
	if Shared then return end

	local Clients = self.PluginClients

	if not Clients then return end

	for Client in pairs( Clients ) do
		self:SendNetworkMessage( Client, "PluginData", { Name = Name, Enabled = false }, true )
	end
end
