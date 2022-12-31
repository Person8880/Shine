--[[
	Shine basecommands plugin.
]]

local Shine = Shine
local Hook = Shine.Hook
local Call = Hook.Call

local IsType = Shine.IsType
local Min = math.min
local Notify = Shared.Message
local pairs = pairs
local SharedTime = Shared.GetTime
local StringExplode = string.Explode
local StringFind = string.find
local StringFormat = string.format
local StringLower = string.lower
local StringMatch = string.match
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableShuffle = table.Shuffle
local TableSort = table.sort
local tostring = tostring

local Plugin, PluginName = ...
Plugin.Version = "1.6"
Plugin.PrintName = "Base Commands"

Plugin.HasConfig = true
Plugin.ConfigName = "BaseCommands.json"

Plugin.DefaultConfig = {
	AllTalk = false,
	AllTalkPreGame = false,
	AllTalkSpectator = false,
	AllTalkLocal = false,
	EjectVotesNeeded = {
		{ FractionOfTeamToPass = 0.5 }
	},
	CommanderBotVoteDelayInSeconds = 300,
	CustomVotePrefix = "POLL: ",
	DisableLuaRun = false,
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

Shine.LoadPluginModule( "vote.lua", Plugin )
Shine.LoadPluginFile( PluginName, "gamerules.lua", Plugin )

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.4",
		Apply = function( Config )
			local EjectVotesNeeded = Config.EjectVotesNeeded
			if not IsType( EjectVotesNeeded, "number" ) then return end

			-- Update to a sequence with one entry that covers all commander durations.
			Config.EjectVotesNeeded = {
				{ FractionOfTeamToPass = EjectVotesNeeded }
			}
		end
	},
	{
		VersionTo = "1.5",
		Apply = function( Config )
			local function GetAndRemoveRate( Key )
				local Value = tonumber( Config[ Key ] ) or Plugin.DefaultConfig.Rates[ Key ]
				Config[ Key ] = nil
				return Value
			end

			Config.Rates = {
				ApplyRates = true,
				BWLimit = GetAndRemoveRate( "BWLimit" ),
				Interp = GetAndRemoveRate( "Interp" ),
				MoveRate = GetAndRemoveRate( "MoveRate" ),
				SendRate = GetAndRemoveRate( "SendRate" ),
				TickRate = GetAndRemoveRate( "TickRate" )
			}
		end
	}
}

-- Override sv_say with sh_say.
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
		local UpdateServerEvents = Hook.GetEventCallbacks( "UpdateServer" )
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

			local Name = ActiveVoteName

			ActiveVoteName = nil
			ActiveVoteData = nil
			ActiveVoteResults = nil
			ActiveVoteStartedAtTime = nil

			return true, Name
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

				-- Never skip spectators as the game allows them to vote...
				return Plugin:GetNumNonAFKHumans( tonumber( Settings.AFKTimeInSeconds ) or 60, false )
			end
		end
		Shine.JoinUpValues( VoteUpdateFunc, OverrideVoteCount, {
			activeVoteName = "ActiveVoteName",
			GetNumVotingPlayers = "GetNumVotingPlayers"
		} )
		OverrideVoteCount()
	end

	local function RegisterCustomVote()
		RegisterVoteType( "ShineCustomVote", {
			VoteQuestion = "string (128)"
		} )

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
		Shine.Hook.Add( "PostLoadScript:lua/Voting.lua", "SetupCustomVote", function( Reload )
			HookVotes()
		end )
	end
end

do
	local Validator = Shine.Validator()
	Validator:AddFieldRule( "EjectVotesNeeded", Validator.AllValuesSatisfy(
		Validator.ValidateField( "FractionOfTeamToPass", Validator.IsType( "number" ) ),
		Validator.ValidateField( "FractionOfTeamToPass", Validator.Clamp( 0, 1 ) ),
		Validator.ValidateField( "MaxSecondsAsCommander", Validator.IsAnyType( { "number", "nil" } ) ),
		Validator.ValidateField( "MaxSecondsAsCommander", Validator.Min( 0 ) )
	) )

	Validator:AddFieldRule( "VoteSettings", Validator.AllKeyValuesSatisfy(
		Validator.ValidateField( "ConsiderAFKPlayersInVotes", Validator.IsType( "boolean", true ) ),
		Validator.ValidateField( "AFKTimeInSeconds", Validator.IsType( "number", 60 ) ),
		Validator.ValidateField( "AFKTimeInSeconds", Validator.Min( 0 ) )
	) )

	Validator:AddRule( {
		Matches = function( self, Config )
			local EjectVotesNeeded = Config.EjectVotesNeeded
			-- Sort in ascending order of time.
			TableSort( EjectVotesNeeded, function( A, B )
				-- Push entry with no time limit to the end.
				if not A.MaxSecondsAsCommander then
					return false
				end
				if not B.MaxSecondsAsCommander then
					return true
				end

				return A.MaxSecondsAsCommander < B.MaxSecondsAsCommander
			end )

			local LastEntry = EjectVotesNeeded[ #EjectVotesNeeded ]
			if not LastEntry or LastEntry.MaxSecondsAsCommander then
				-- No final entry or final entry has a time limit, so need to extend it to account
				-- for all remaining time values.
				EjectVotesNeeded[ #EjectVotesNeeded ] = {
					FractionOfTeamToPass = LastEntry and LastEntry.FractionOfTeamToPass or 0.5
				}
				Notify( "Entries in EjectVotesNeeded do not cover all possible time values, correcting..." )

				return true
			end

			return false
		end
	} )
	Plugin.ConfigValidator = Validator

	-- Load after default validator to ensure validators merge.
	Shine.LoadPluginFile( PluginName, "rates.lua", Plugin )
	Shine.LoadPluginModule( "logger.lua", Plugin )
end

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	self.Gagged = self:LoadGaggedPlayers()

	self:CreateCommands()
	self:UpdateVanillaConfig()

	self.SetEjectVotes = false
	self.dt.AllTalk = self.Config.AllTalk
	self.dt.AllTalkPreGame = self.Config.AllTalkPreGame

	self:CheckRateValues()
	self:AttemptToConfigureGamerules( GetGamerules and GetGamerules() )

	self.Enabled = true

	return true
end

function Plugin:UpdateVanillaConfig()
	if not Server.SetConfigSetting then return end

	if self.Config.AllTalkPreGame and Server.GetConfigSetting( "pregamealltalk" ) then
		self:Print( "Disabling vanilla pregamealltalk, AllTalkPreGame is enabled." )
		-- Disable vanilla pregame all-talk to avoid it broadcasting voice during the 'PreGame' state.
		Server.SetConfigSetting( "pregamealltalk", false )
		Server.SaveConfigSettings()
	end
end

function Plugin:OnFirstThink()
	self:UpdateVanillaConfig()

	Hook.SetupClassHook( "NS2Gamerules", "GetFriendlyFire", "GetFriendlyFire", "ActivePre" )
	Hook.SetupGlobalHook( "GetFriendlyFire", "GetFriendlyFire", "ActivePre", { OverrideWithoutWarning = true } )

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

do
	local GetClientForPlayer = Shine.GetClientForPlayer

	function Plugin:IsPregameAllTalk( Gamerules )
		return self.Config.AllTalkPreGame and Gamerules:GetGameState() < kGameState.PreGame
	end

	function Plugin:IsSpectatorAllTalk( Listener )
		return self.Config.AllTalkSpectator and Listener:GetTeamNumber() == ( kSpectatorIndex or 3 )
	end

	-- Will need updating if it changes in NS2Gamerules...
	local MaxWorldSoundDistance = 30 * 30
	local DisableLocalAllTalkClients = {}

	function Plugin:RemoveAllTalkPreference( Client )
		DisableLocalAllTalkClients[ Client ] = nil
	end

	function Plugin:IsLocalAllTalkDisabled( Client )
		return DisableLocalAllTalkClients[ Client ]
	end

	local function GetPlayerOrigin( Player )
		if Player:isa( "Spectator" ) then
			-- If the player is spectating a player, their origin is not updated, so we need to use
			-- the origin of the player being followed instead.
			local Client = Player:GetClient()
			local FollowingPlayer = Client and Client:GetSpectatingPlayer()
			if FollowingPlayer then
				return FollowingPlayer:GetOrigin()
			end
		end
		return Player:GetOrigin()
	end

	function Plugin:ArePlayersInLocalVoiceRange( Speaker, Listener )
		return GetPlayerOrigin( Listener ):GetDistanceSquared( GetPlayerOrigin( Speaker ) ) < MaxWorldSoundDistance
	end

	function Plugin:CanPlayerHearLocalVoice( Gamerules, Listener, Speaker, SpeakerClient )
		local ListenerClient = GetClientForPlayer( Listener )

		-- Default behaviour for those that have chosen to disable it.
		if self:IsLocalAllTalkDisabled( ListenerClient )
		or self:IsLocalAllTalkDisabled( SpeakerClient ) then
			return
		end

		-- Assume non-global means local chat, so "all-talk" means true if distance check passes.
		if self.Config.AllTalkLocal or self.Config.AllTalk or self:IsPregameAllTalk( Gamerules )
		or self:IsSpectatorAllTalk( Listener ) then
			return self:ArePlayersInLocalVoiceRange( Speaker, Listener )
		end
	end

	function Plugin:CanPlayerHearGlobalVoice( Gamerules, Listener, Speaker, SpeakerClient )
		if self.Config.AllTalk or self:IsPregameAllTalk( Gamerules )
		or self:IsSpectatorAllTalk( Listener ) then
			return true
		end
	end

	--[[
		Override voice chat to allow everyone to hear each other with alltalk on.
	]]
	function Plugin:CanPlayerHearPlayer( Gamerules, Listener, Speaker, ChannelType )
		local SpeakerClient = GetClientForPlayer( Speaker )

		if SpeakerClient and self:IsClientGagged( SpeakerClient ) then return false end
		if Listener:GetClientMuted( Speaker:GetClientIndex() ) then return false end

		if ChannelType and ChannelType ~= VoiceChannel.Global then
			return self:CanPlayerHearLocalVoice( Gamerules, Listener, Speaker, SpeakerClient )
		end

		return self:CanPlayerHearGlobalVoice( Gamerules, Listener, Speaker, SpeakerClient )
	end

	function Plugin:ReceiveEnableLocalAllTalk( Client, Data )
		DisableLocalAllTalkClients[ Client ] = not Data.Enabled
	end

	local ALLTALK_TYPES = {
		AllTalk = "ALLTALK_NOTIFY_",
		AllTalkLocal = "ALLTALK_LOCAL_NOTIFY_",
		AllTalkPreGame = "ALLTALK_PREGAME_NOTIFY_"
	}

	function Plugin:NotifyAllTalkState( Type, Enable )
		Shine.AssertAtLevel( ALLTALK_TYPES[ Type ], "Invalid all talk type: %s", 3, Type )

		Shine:TranslatedNotifyDualColour( nil, Enable and 0 or 255, Enable and 255 or 0, 0,
			"ALL_TALK_TAG", 255, 255, 255, ALLTALK_TYPES[ Type ]..( Enable and "ENABLED" or "DISABLED" ),
			self.__Name )
	end

	function Plugin:IsAllTalkEnabled( Type )
		Shine.AssertAtLevel( ALLTALK_TYPES[ Type ], "Invalid all talk type: %s", 3, Type )

		return self.Config[ Type ]
	end

	function Plugin:SetAllTalkEnabled( Type, Enabled, DontSave )
		Shine.AssertAtLevel( ALLTALK_TYPES[ Type ], "Invalid all talk type: %s", 3, Type )

		Enabled = Enabled and true or false
		self.Config[ Type ] = Enabled
		self.dt[ Type ] = Enabled

		if not DontSave then
			self:SaveConfig( true )
		end

		Shine.Hook.Broadcast( "OnAllTalkStateChange", Type, Enabled )
	end
end

local function NotifyError( Client, TranslationKey, Data, Message, Format, ... )
	if not Client then
		Notify( Format and StringFormat( Message, ... ) or Message )
		return
	end

	if not Data then
		Plugin:NotifyTranslatedCommandError( Client, TranslationKey )
		return
	end

	Plugin:SendTranslatedCommandError( Client, TranslationKey, Data )
end

local Histories = {}

function Plugin:ClientDisconnect( Client )
	Histories[ Client ] = nil

	if self.PluginClients then
		self.PluginClients:Remove( Client )
	end

	self:RemoveAllTalkPreference( Client )
	self:SimpleTimer( 0, function()
		self:UpdateVotesOnDisconnect()
	end )

	if self.CommanderLogins then
		self.CommanderLogins[ Client ] = nil
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
		if not IsType( Cycle, "table" ) or not IsType( Cycle.maps, "table" ) then
			Shine.PrintToConsole( Client, "Unable to load map cycle list." )
			return
		end

		Shine.PrintToConsole( Client, "Available maps:" )

		local Maps = Cycle.maps
		for i = 1, #Maps do
			local Map = Maps[ i ]
			local MapName = IsType( Map, "table" ) and Map.map or Map
			if IsType( MapName, "string" ) then
				Shine.PrintToConsole( Client, StringFormat( "- %s", MapName ) )
			end
		end
	end
	local ListMapsCommand = self:BindCommand( "sh_listmaps", nil, ListMaps, true )
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

	local StringRep = string.rep
	local function PrintSeparator( Client )
		Shine.PrintToConsole( Client, StringRep( "=", 24 ) )
	end
	local function GetSlotSummary( Client )
		Shine.PrintToConsole( Client,
			StringFormat( "%d / %d total clients (%d max player slot(s) | %d max spectator slot(s))",
				Server.GetNumClientsTotal(),
				Server.GetMaxPlayers() + Server.GetMaxSpectators(),
				Server.GetMaxPlayers(),
				Server.GetMaxSpectators()
			)
		)

		PrintSeparator( Client )

		Shine.PrintToConsole( Client, "PLAYER SLOTS" )
		Shine.PrintToConsole( Client, StringFormat( "%d total player slot(s) occupied (including connecting players)",
			Server.GetNumPlayersTotal() ) )
		Shine.PrintToConsole( Client, StringFormat( "%d player slot(s) in use (excluding connecting players)",
			Server.GetNumPlayers() ) )

		PrintSeparator( Client )

		Shine.PrintToConsole( Client, "SPECTATOR SLOTS" )
		Shine.PrintToConsole( Client, StringFormat( "%d connected spectator(s)",
			Server.GetNumSpectators() ) )

		local function IsSpectator( Client )
			return Client:GetIsSpectator()
		end

		local NumClientsMarkedAsSpec = Shine.Stream( Shine.GetAllClients() )
			:Filter( IsSpectator )
			:GetCount()
		Shine.PrintToConsole( Client, StringFormat( "%d marked as spectator(s)",
			NumClientsMarkedAsSpec ) )

		PrintSeparator( Client )

		Shine.PrintToConsole( Client, "RESERVED SLOTS" )
		Shine.PrintToConsole( Client, StringFormat( "%d player slot(s) currently reserved",
			Server.GetReservedSlotLimit() ) )

		local ClientsWithReservedAccess = Shine.Stream( Shine.GetAllClients() )
			:Filter( function( Client )
				return GetHasReservedSlotAccess( Client:GetUserId() )
			end )

		local NumClientsWithReservedAccess = ClientsWithReservedAccess:GetCount()
		local NumSpectatingReservedClients = ClientsWithReservedAccess
			:Filter( IsSpectator )
			:GetCount()

		Shine.PrintToConsole( Client,
			StringFormat( "%d connected player(s) with reserved slot access (%d spectator(s), %d player(s))",
				NumClientsWithReservedAccess,
				NumSpectatingReservedClients,
				NumClientsWithReservedAccess - NumSpectatingReservedClients
			)
		)
	end
	local SlotSummaryCommand = self:BindCommand( "sh_slotsummary", nil, GetSlotSummary )
	SlotSummaryCommand:Help( "Displays a summary of player/spectator/reserved slot usage." )
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
				local Success, Err = pcall( Func, Client )
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
		local MatchingMaps = Shine.FindMapNamesMatching( MapName )
		if #MatchingMaps == 0 then
			NotifyError( Client, "UNKNOWN_MAP_NAME", {
				MapName = MapName
			}, "%s is not a known map name.", true, MapName )
			return
		end

		if #MatchingMaps > 1 then
			-- More than one map matches, so ask for a more precise name.
			NotifyError( Client, "UNCLEAR_MAP_NAME", {
				MapName = MapName
			}, "%s matches multiple maps, a more precise name is required.", true, MapName )
			return
		end

		MapCycle_ChangeMap( MatchingMaps[ 1 ] )
	end
	local ChangeLevelCommand = self:BindCommand( "sh_changelevel", "map", ChangeLevel )
	ChangeLevelCommand:AddParam{
		Type = "string",
		TakeRestOfLine = true,
		Error = "Please specify a map to change to.", Help = "map",
		AutoCompletions = function()
			return Shine.GetKnownMapNames()
		end
	}
	ChangeLevelCommand:Help( "Changes the map to the given level immediately." )

	local function CycleMap( Client )
		--The map vote plugin hooks this so we don't have to worry.
		MapCycle_CycleMap( Shared.GetMapName() )
	end
	local CycleMapCommand = self:BindCommand( "sh_cyclemap", "cyclemap", CycleMap )
	CycleMapCommand:Help( "Cycles the map to the next one in the map cycle." )

	local function ReloadMap( Client )
		MapCycle_ChangeMap( Shared.GetMapName() )
	end
	local ReloadMapCommand = self:BindCommand( "sh_reloadmap", "reloadmap", ReloadMap )
	ReloadMapCommand:Help( "Reloads the current map." )

	do
		local function SaveEnabledState( Name, PluginTable )
			if PluginTable.IsBeta then
				Shine.Config.ActiveExtensions[ Name ] = nil
				Shine.Config.ActiveBetaExtensions[ Name ] = true
			else
				Shine.Config.ActiveExtensions[ Name ] = true
			end
			Shine:SaveConfig()

			-- Notify admins of the change in plugin state. This results in a second message as the plugin hook will
			-- have sent one already, but this ensures that the ConfiguredAsEnabled flag is correct.
			self:SendPluginStateUpdate( Name, true )
		end

		local function LoadPlugin( Client, Name, Save )
			Name = StringLower( Name )

			if Name == "basecommands" then
				local Message = "You cannot reload the basecommands plugin."
				Shine.PrintToConsole( Client, Message )
				if Client then
					Shine:SendNotification( Client, Shine.NotificationType.ERROR, Message, true )
				end

				return
			end

			local PluginTable = Shine.Plugins[ Name ]
			local Success, Err

			if not PluginTable then
				Success, Err = Shine:LoadExtension( Name )
			else
				-- If it's already enabled and we're saving, then just save the config option, don't reload.
				if PluginTable.Enabled and Save then
					SaveEnabledState( Name, PluginTable )

					local Message = StringFormat( "Plugin '%s' now set to enabled in config.", Name )
					Shine:SendAdminNotification( Client, Shine.NotificationType.INFO, Message )

					return
				end

				Success, Err = Shine:EnableExtension( Name )
			end

			if Success then
				local Message = StringFormat( "Plugin '%s' loaded successfully.", Name )
				Shine:SendAdminNotification( Client, Shine.NotificationType.INFO, Message )

				-- Update all players with the plugins state.
				Shine:SendPluginData( nil )

				if Save then
					SaveEnabledState( Name, Shine.Plugins[ Name ] )
				end
			else
				local Message = StringFormat( "Plugin '%s' failed to load. Error: %s", Name, Err )
				Shine:SendAdminNotification( Client, Shine.NotificationType.ERROR, Message )
			end
		end
		local LoadPluginCommand = self:BindCommand( "sh_loadplugin", nil, LoadPlugin )
		LoadPluginCommand:AddParam{ Type = "string", Error = "Please specify a plugin to load.", Help = "plugin" }
		LoadPluginCommand:AddParam{ Type = "boolean", Optional = true, Default = false, Help = "save" }
		LoadPluginCommand:Help( "Loads or reloads a plugin." )
	end

	local function UnloadPlugin( Client, Name, Save )
		Name = StringLower( Name )

		if Name == "basecommands" then
			local Message = "Unloading the basecommands plugin is ill-advised. If you wish to do so, remove it from the active plugins list in your config."
			Shine.PrintToConsole( Client, Message )
			if Client then
				Shine:SendNotification( Client, Shine.NotificationType.ERROR, Message, true )
			end
			return
		end

		local PluginTable = Shine.Plugins[ Name ]
		if not PluginTable or not PluginTable.Enabled then
			-- If it's already disabled and we want to save, just save.
			if Save and Shine.AllPlugins[ Name ] then
				Shine.Config.ActiveExtensions[ Name ] = false
				Shine:SaveConfig()

				self:SendPluginStateUpdate( Name, false )

				local Message = StringFormat( "Plugin '%s' now set to disabled in config.", Name )
				Shine:SendAdminNotification( Client, Shine.NotificationType.INFO, Message )

				return
			end

			local Message = StringFormat( "Plugin '%s' is not loaded.", Name )
			Shine:SendAdminNotification( Client, Shine.NotificationType.ERROR, Message )

			return
		end

		Shine:UnloadExtension( Name )

		local Message = StringFormat( "Plugin '%s' unloaded successfully.", Name )
		Shine:SendAdminNotification( Client, Shine.NotificationType.INFO, Message )

		Shine:SendPluginData( nil )

		if Save then
			Shine.Config.ActiveExtensions[ Name ] = false
			Shine:SaveConfig()

			self:SendPluginStateUpdate( Name, false )
		end
	end
	local UnloadPluginCommand = self:BindCommand( "sh_unloadplugin", nil, UnloadPlugin )
	UnloadPluginCommand:AddParam{ Type = "string", Error = "Please specify a plugin to unload.", Help = "plugin" }
	UnloadPluginCommand:AddParam{ Type = "boolean", Optional = true, Default = false, Help = "save" }
	UnloadPluginCommand:Help( "Unloads a plugin." )

	local function SuspendPlugin( Client, Name )
		Name = StringLower( Name )

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
		Name = StringLower( Name )

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
	local function GenerateAllTalkCommand( Command, ChatCommand, ConfigOption, CommandNotifyString, HelpName )
		local function CommandFunc( Client, Enable )
			self:SetAllTalkEnabled( ConfigOption, Enable )

			if Shine.Config.NotifyOnCommand then
				self:SendTranslatedMessage( Client, CommandNotifyString, {
					Enabled = Enable
				} )
			else
				self:NotifyAllTalkState( ConfigOption, Enable )
			end
		end
		local Command = self:BindCommand( Command, ChatCommand, CommandFunc )
		Command:AddParam{ Type = "boolean", Optional = true,
			Default = function() return not self.Config[ ConfigOption ] end }
		Command:Help( StringFormat( "Enables or disables %s.", HelpName ) )
	end

	GenerateAllTalkCommand( "sh_alltalk", "alltalk", "AllTalk", "ALLTALK_TOGGLED", "global all talk" )
	GenerateAllTalkCommand( "sh_alltalkpregame", "alltalkpregame", "AllTalkPreGame",
		"ALLTALK_PREGAME_TOGGLED", "all talk in the pregame" )
	GenerateAllTalkCommand( "sh_alltalklocal", "alltalklocal", "AllTalkLocal",
		"ALLTALK_LOCAL_TOGGLED", "local all talk" )
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

	local function ChangeTeam( Client, Targets, Team, ForceChange )
		local Gamerules = GetGamerules()
		if not Gamerules then return end

		local TargetCount = #Targets
		if TargetCount == 0 then return end

		local SuccessfulMoves = 0
		for i = 1, TargetCount do
			local Player = Targets[ i ]:GetControllingPlayer()

			if Player and Gamerules:JoinTeam( Player, Team, ForceChange, true ) then
				SuccessfulMoves = SuccessfulMoves + 1
			end
		end

		if SuccessfulMoves > 0 then
			self:SendTranslatedMessage( Client, "ChangeTeam", {
				TargetCount = SuccessfulMoves,
				Team = Team
			} )
		end

		if TargetCount > SuccessfulMoves then
			local NumFailed = TargetCount - SuccessfulMoves
			NotifyError( Client, "ERROR_SET_TEAM_FAILED", {
				TargetCount = NumFailed,
				Team = Team
			}, "Failed to move %s player%s to team %s.", true, NumFailed, NumFailed == 1 and "" or "s", Team )
		end
	end
	local ChangeTeamCommand = self:BindCommand( "sh_setteam", { "team", "setteam" }, ChangeTeam )
	ChangeTeamCommand:AddParam{ Type = "clients" }
	ChangeTeamCommand:AddParam{ Type = "team", Error = "Please specify a team to move to." }
	ChangeTeamCommand:AddParam{ Type = "boolean", Optional = true, Default = false, Help = "force" }
	ChangeTeamCommand:Help( "Sets the given player(s) onto the given team." )

	local function ReadyRoom( Client, Targets )
		ChangeTeam( Client, Targets, kTeamReadyRoom )
	end
	local ReadyRoomCommand = self:BindCommand( "sh_rr", "rr", ReadyRoom )
	ReadyRoomCommand:AddParam{ Type = "clients" }
	ReadyRoomCommand:Help( "<players> Sends the given player(s) to the ready room." )

	local function HiveTeams( Client )
		--Force even teams is such an overconfident term...
		self:SendTranslatedMessage( Client, "HIVE_TEAMS", {} )
		ForceEvenTeams()
	end
	local HiveShuffle = self:BindCommand( "sh_hiveteams", { "hiveteams" }, HiveTeams )
	HiveShuffle:Help( "Runs NS2's Hive skill team shuffler." )

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
		local Words = StringExplode( Message, " ", true )
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
		if Target:GetIsVirtual() then
			NotifyError( Client, "ERROR_GAG_BOT", nil, "Bots cannot be gagged" )
			return
		end

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

		local Target = Shine.GetClientByNS2ID( ID )
		if Target then
			self:SendTranslatedMessage( Client, "PLAYER_GAGGED_PERMANENTLY", {
				TargetName = Shine.GetClientName( Target )
			} )
		end
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

	local function ListGags( Client )
		if not next( self.Gagged ) then
			Shine.PrintToConsole( Client, "No players are currently gagged." )
			return
		end

		local Now = SharedTime()

		local ClientsByNS2ID = Shine.GetAllClientsByNS2ID()
		local GaggedPlayers = self.Config.GaggedPlayers
		local Columns = {
			{
				Name = "Name"
			},
			{
				Name = "NS2ID"
			},
			{
				Name = "Remaining Time",
				Getter = function( Entry )
					if Entry.Expiry == math.huge then
						if GaggedPlayers[ Entry.NS2ID ] then
							return "Permanent"
						end
						return "Until the end of the current map"
					end
					return string.TimeToString( Entry.Expiry - Now )
				end
			}
		}

		local Data = {}
		for ID, Expiry in pairs( self.Gagged ) do
			local IsTemporary = IsType( Expiry, "number" )
			if not IsTemporary or Expiry > Now then
				local Client = ClientsByNS2ID[ ID ]
				local Player = Client and Client:GetControllingPlayer()

				Data[ #Data + 1 ] = {
					Name = Player and Player.GetName and Player:GetName() or "",
					NS2ID = tostring( ID ),
					Expiry = IsTemporary and Expiry or math.huge
				}
			end
		end

		TableSort( Data, function( A, B )
			if A.Expiry == B.Expiry and A.Expiry == math.huge then
				if GaggedPlayers[ A.NS2ID ] and not GaggedPlayers[ B.NS2ID ] then
					return false
				end
				if GaggedPlayers[ B.NS2ID ] and not GaggedPlayers[ A.NS2ID ] then
					return true
				end
				return A.NS2ID < B.NS2ID
			end
			return A.Expiry < B.Expiry
		end )

		Shine.PrintTableToConsole( Client, Columns, Data )
	end
	self:BindCommand( "sh_listgags", nil, ListGags )
		:Help( "Lists all gagged players to the console." )

	local function CustomVote( Client, VoteQuestion )
		if not Client then return end

		StartVote( "ShineCustomVote", Client, {
			VoteQuestion = self.Config.CustomVotePrefix..VoteQuestion
		} )
	end
	local CustomVoteCommand = self:BindCommand( "sh_customvote", "customvote", CustomVote )
	CustomVoteCommand:AddParam{ Type = "string", TakeRestOfLine = true, Help = "question" }
	CustomVoteCommand:Help( "Starts a vote with the given question." )

	local function StopVote( Client )
		if self.StopVote then
			local Success, VoteName = self:StopVote()
			if Success then
				Shine:AdminPrint( nil, "%s stopped the current vote (%s).", true,
					Shine.GetClientInfo( Client ), VoteName )

				self:SendTranslatedMessage( Client, "VOTE_STOPPED", {} )
				return
			end
		end

		self:NotifyTranslatedCommandError( Client, "ERROR_NO_VOTE_IN_PROGRESS" )
	end
	local StopVoteCommand = self:BindCommand( "sh_stopvote", "stopvote", StopVote )
	StopVoteCommand:Help( "Stops the current vanilla vote." )
end

function Plugin:CreatePerformanceCommands()
	local function Interp( Client, NewInterp )
		local MinInterp = 2 / self.Config.Rates.SendRate * 1000
		if NewInterp < MinInterp then
			NotifyError( Client, "ERROR_INTERP_CONSTRAINT", {
				Rate = MinInterp
			}, "Interp is constrained by send rate to be %.2fms minimum.", true, MinInterp )
			return
		end

		self.Config.Rates.Interp = NewInterp

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
			return StringFormat( " - Current value: %i%s", self.Config.Rates[ ConfigKey ], Units )
		end
	end

	AddAdditionalInfo( InterpCommand, "Interp", "ms" )

	local function TickRate( Client, NewRate )
		if NewRate < self.Config.Rates.MoveRate then
			NotifyError( Client, "ERROR_TICKRATE_CONSTRAINT", {
				Rate = self.Config.Rates.MoveRate
			}, "Tick rate cannot be less than move rate (%i).", true, self.Config.Rates.MoveRate )
			return
		end

		self.Config.Rates.TickRate = NewRate

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
		self.Config.Rates.BWLimit = NewLimit

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
		if NewRate > self.Config.Rates.TickRate then
			NotifyError( Client, "ERROR_SENDRATE_CONSTRAINT", {
				Rate = self.Config.Rates.TickRate
			}, "Send rate cannot be greater than tick rate (%i).", true, self.Config.Rates.TickRate )
			return
		end

		if NewRate > self.Config.Rates.MoveRate then
			NotifyError( Client, "ERROR_SENDRATE_MOVE_CONSTRAINT", {
				Rate = self.Config.Rates.MoveRate
			}, "Send rate cannot be greater than move rate (%i).", true, self.Config.Rates.MoveRate )
			return
		end

		self.Config.Rates.SendRate = NewRate

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
		if NewRate > self.Config.Rates.TickRate then
			NotifyError( Client, "ERROR_MOVERATE_CONSTRAINT", {
				Rate = self.Config.Rates.TickRate
			}, "Move rate cannot be greater than tick rate (%i).", true, self.Config.Rates.TickRate )
			return
		end

		if NewRate < self.Config.Rates.SendRate then
			NotifyError( Client, "ERROR_MOVERATE_SENDRATE_CONSTRAINT", {
				Rate = self.Config.Rates.SendRate
			}, "Move rate cannot be less than send rate (%i).", true, self.Config.Rates.SendRate )
			return
		end

		self.Config.Rates.MoveRate = NewRate

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

local function IsPluginConfiguredAsEnabled( Plugin )
	return not not ( Shine.Config.ActiveExtensions[ Plugin ] or Shine.Config.ActiveBetaExtensions[ Plugin ] )
end

function Plugin:ReceiveRequestPluginData( Client, Data )
	if not Shine:GetPermission( Client, "sh_loadplugin" ) and not Shine:GetPermission( Client, "sh_unloadplugin" ) then
		return
	end

	self:SendNetworkMessage( Client, "PluginTabAuthed", {}, true )

	self.PluginClients = self.PluginClients or Shine.UnorderedSet()
	self.PluginClients:Add( Client )

	for Plugin in pairs( Shine.AllPlugins ) do
		local Enabled = Shine:IsExtensionEnabled( Plugin )
		self:SendNetworkMessage(
			Client,
			"PluginData",
			{
				Name = Plugin,
				Enabled = Enabled,
				ConfiguredAsEnabled = IsPluginConfiguredAsEnabled( Plugin )
			},
			true
		)
	end
end

function Plugin:SendPluginStateUpdate( Name, Enabled )
	local Clients = self.PluginClients
	if not Clients or Clients:GetCount() == 0 then return end

	self:SendNetworkMessage(
		Clients:AsList(),
		"PluginData",
		{
			Name = Name,
			Enabled = Enabled,
			ConfiguredAsEnabled = IsPluginConfiguredAsEnabled( Name )
		},
		true
	)
end

function Plugin:OnPluginLoad( Name, Plugin, Shared )
	-- Shared plugins are already updated on every client, and the admin menu listens for it. Only need to network
	-- server-side plugin changes here.
	if Shared then return end

	self:SendPluginStateUpdate( Name, true )
end

function Plugin:OnPluginUnload( Name, Plugin, Shared )
	if Shared then return end

	self:SendPluginStateUpdate( Name, false )
end
