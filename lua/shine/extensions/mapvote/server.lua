--[[
	Shine map voting plugin.
]]

local Shine = Shine

local Clamp = math.Clamp
local Floor = math.floor
local GetOwner = Server.GetOwner
local IsType = Shine.IsType
local Max = math.max
local Notify = Shared.Message
local SharedTime = Shared.GetTime
local StringFormat = string.format
local TableHasValue = table.HasValue
local TableCount = table.Count

local Plugin = Plugin
Plugin.Version = "1.8"

Plugin.HasConfig = true
Plugin.ConfigName = "MapVote.json"
Plugin.PrintName = "Map Vote"

Plugin.DefaultConfig = {
	GetMapsFromMapCycle = true, --Get the valid votemaps directly from the mapcycle file.
	Maps = { --Valid votemaps if you do not wish to get them from the map cycle.
		ns2_veil = true,
		ns2_summit = true,
		ns2_docking = true,
		ns2_mineshaft = true,
		ns2_refinery = true,
		ns2_tram = true,
		ns2_descent = true,
		ns2_biodome = true,
		ns2_eclipse = true,
		ns2_kodiak = true
	},
	ForcedMaps = {}, --Maps that must always be in the vote list.
	DontExtend = {}, --Maps that should never have an extension option.
	IgnoreAutoCycle = {}, --Maps that should not be cycled to unless voted for.
	MinPlayers = 10, --Minimum number of players needed to begin a map vote.
	PercentToStart = 0.6, --Percentage of people needing to vote to change to start a vote.
	PercentToFinish = 0.8, --Percentage of people needing to vote in order to skip the rest of an RTV vote's time.

	MaxNominationsPerPlayer = 3, -- The maximum number of maps an individual player can nominate.

	VoteLength = 1, --Time in minutes a vote should last before failing.
	ChangeDelay = 10, --Time in seconds to wait before changing map after a vote (gives time for veto)
	VoteDelay = 10, --Time to wait in minutes after map change/vote fail before voting can occur.

	ShowVoteChoices = true, --Show who votes for what map.
	MaxOptions = 4, --Max number of options to provide.

	AllowExtend = true, --Allow going to the same map to be an option.
	ExtendTime = 15, --Time in minutes to extend the map.
	MaxExtends = 1, --Maximum number of map extensions.
	AlwaysExtend = true, --Always show an option to extend the map if not past the max extends.

	TieFails = false, --A tie means the vote fails.
	ChooseRandomOnTie = true, --Choose randomly between the tied maps. If not, a revote is called.
	MaxRevotes = 1, --Maximum number of revotes.

	EnableRTV = true, --Enables RTV voting.

	EnableNextMapVote = true, --Enables the vote to choose the next map.
	NextMapVote = 1, --How far into a game to begin a vote for the next map. Setting to 1 queues for the end of the map.
	RoundLimit = 0, --How many rounds should the map last for? This overrides time based cycling.

	ForceChange = 60, --How long left on the current map when a round ends that should force a change to the next map.
	CycleOnEmpty = false, --Should the map cycle when the server's empty and it's past the map's time limit?
	EmptyPlayerCount = 0, --How many players defines 'empty'?

	-- How many previous maps should be excluded from votes?
	ExcludeLastMaps = {
		Min = 0,
		Max = 0
	}
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.7",
		Apply = function( Config )
			local OldCount = Config.ExcludeLastMaps
			if IsType( OldCount, "number" ) then
				Config.ExcludeLastMaps = {
					Min = OldCount,
					Max = OldCount
				}
			end
		end
	}
}

Plugin.VoteTimer = "MapVote"
Plugin.NextMapTimer = "MapVoteNext"

local function IsTableArray( Table )
	local Count = #Table
	return Count > 0 and Count or nil
end

local function ConvertArrayToLookup( Table )
	local Count = IsTableArray( Table )
	if not Count then return end

	for i = 1, Count do
		Table[ Table[ i ] ] = true
		Table[ i ] = nil
	end
end

Script.Load( Shine.GetPluginFile( "mapvote", "cycle.lua" ) )
Script.Load( Shine.GetPluginFile( "mapvote", "voting.lua" ) )

function Plugin:Initialise()
	self.Config.ForceChange = Max( self.Config.ForceChange, 0 )
	self.Config.RoundLimit = Max( self.Config.RoundLimit, 0 )
	self.Config.NextMapVote = Clamp( self.Config.NextMapVote, 0, 1 )
	self.Config.PercentToFinish = Clamp( self.Config.PercentToFinish, 0, 1 )
	self.Config.PercentToStart = Clamp( self.Config.PercentToStart, 0, 1 )
	self.Config.VoteLength = Max( self.Config.VoteLength, 0.25 )
	self.Config.ExcludeLastMaps.Min = Max( tonumber( self.Config.ExcludeLastMaps.Min ) or 0, 0 )

	self.Round = 0

	self.Vote = self.Vote or {}
	self.Vote.NextVote = self.Vote.NextVote or ( SharedTime() + ( self.Config.VoteDelay * 60 ) )
	self.Vote.Nominated = {} -- Table of nominated maps.
	self.Vote.NominationTracker = {} -- Tracks the amount of times someone's nominated a map.
	self.Vote.Votes = 0 -- Number of map votes that have taken place.
	self.Vote.Voted = {} -- Table of players that have voted for a map.
	self.Vote.TotalVotes = 0 -- Number of votes in the current map vote.

	self.StartingVote = Shine:CreateVote( function() return self:GetVotesNeededToStart() end,
		function() self:StartVote() end )

	self.NextMap = {}
	self.NextMap.Extends = 0

	local Cycle = MapCycle_GetMapCycle and MapCycle_GetMapCycle()
	if not Cycle then
		Cycle = Shine.LoadJSONFile( "config://MapCycle.json" )
	end

	self:SetupMaps( Cycle )

	local MapCount = #self.MapChoices
	if MapCount == 0 then
		return false, "No maps configured in the map cycle"
	end

	local AllowVotes = MapCount > 1

	if not AllowVotes then
		self.Config.EnableRTV = false
	end

	self.MapCycle = Cycle or {}
	self.MapCycle.time = tonumber( self.MapCycle.time ) or 30

	if self.Config.EnableNextMapVote and AllowVotes then
		if self.Config.NextMapVote == 1 or self.Config.RoundLimit > 0 then
			self.VoteOnEnd = true
		else
			local Time = SharedTime()
			local CycleTime = Cycle and ( Cycle.time * 60 ) or 1800

			self:CreateTimer( self.NextMapTimer,
				( CycleTime * self.Config.NextMapVote ) - Time, 1, function()
				local Players = Shine.GetAllPlayers()
				if #Players > 0 then
					self:StartVote( true )
				end
			end )
		end
	end

	do
		local ForcedMaps = self.Config.ForcedMaps
		local Count = IsTableArray( ForcedMaps )
		local MaxOptions = self.Config.MaxOptions

		if Count then
			self.ForcedMapCount = Clamp( Count, 0, MaxOptions )

			for i = 1, Count do
				local Map = ForcedMaps[ i ]

				if IsType( Map, "string" ) then
					ForcedMaps[ Map ] = true
				end

				ForcedMaps[ i ] = nil
			end
		else
			self.ForcedMapCount = Clamp( TableCount( ForcedMaps ), 0, MaxOptions )
		end

		self.MaxNominations = Max( MaxOptions - self.ForcedMapCount - 1, 0 )
	end

	ConvertArrayToLookup( self.Config.DontExtend )
	ConvertArrayToLookup( self.Config.IgnoreAutoCycle )

	self:LoadLastMaps()
	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:SetupFromMapData( Data )
	if tonumber( Data.time or Data.Time ) then
		self.MapCycle.time = tonumber( Data.time or Data.Time )
	end

	if tonumber( Data.rounds or Data.Rounds ) then
		self.Config.RoundLimit = Max( tonumber( Data.rounds or Data.Rounds ), 0 )
	end
end

function Plugin:OnFirstThink()
	local CurMap = Shared.GetMapName()

	local ConfigData = self.Config.Maps[ CurMap ]
	if IsType( ConfigData, "table" ) then
		self:SetupFromMapData( ConfigData )
		return
	end

	local Choices = self.MapChoices
	for i = 1, #Choices do
		local Data = Choices[ i ]

		if IsType( Data, "table" ) and Data.map == CurMap then
			self:SetupFromMapData( Data )

			break
		end
	end
end

function Plugin:ForcePlayersIntoReadyRoom()
	local Gamerules = GetGamerules()

	local function MoveToReadyRoom( Player )
		Gamerules:JoinTeam( Player, 0, nil, true )
	end

	Gamerules.team1:ForEachPlayer( MoveToReadyRoom )
	Gamerules.team2:ForEachPlayer( MoveToReadyRoom )
end

function Plugin:EndGame()
	self:SimpleTimer( 10, function()
		local Time = SharedTime()

		local Cycle = self.MapCycle
		local CycleTime = Cycle and ( Cycle.time * 60 ) or 1800

		if not CycleTime then return end

		local ExtendTime = self.NextMap.ExtendTime
		local TimeLeft = CycleTime - Time

		if ExtendTime then
			TimeLeft = ExtendTime - Time
		end

		local Key = "TimeLeftNotify"
		local Message = {}
		local Gamerules = GetGamerules()

		if self.Config.RoundLimit > 0 then
			self.Round = self.Round + 1

			Key = "RoundLeftNotify"

			--Prevent time based cycling from passing.
			if Gamerules then
				Gamerules.timeToCycleMap = nil
			end

			if self.Round >= self.Config.RoundLimit then
				TimeLeft = 0
				Message.Duration = 0
			else
				local RoundsLeft = self.Config.RoundLimit - self.Round
				Message.Duration = RoundsLeft
			end
		end

		if TimeLeft <= self.Config.ForceChange then
			if not self:VoteStarted() and not self.VoteOnEnd then
				self:SendTranslatedNotify( nil, "MapCycling", {
					MapName = self:GetNextMap()
				} )

				self:ForcePlayersIntoReadyRoom()
				self.CyclingMap = true

				Gamerules.timeToCycleMap = Time + 30

				return
			end

			if self.VoteOnEnd then
				self:StartVote( true )
				self:ForcePlayersIntoReadyRoom()
			end

			return
		end

		--Don't say anything if there's more than an hour left.
		if TimeLeft > 3600 then
			return
		end

		--Round the time down to the nearest 30 seconds.
		if TimeLeft > 30 then
			TimeLeft = TimeLeft - ( TimeLeft % 30 )
		end

		if not Message.Duration then
			Message.Duration = Floor( TimeLeft )
		end

		self:SendTranslatedNotify( nil, Key, Message )
	end )
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	local IsEndVote = self:IsEndVote()

	if not ( self.CyclingMap or IsEndVote ) then return end
	if not Player then return end
	if ShineForce then return end
	if NewTeam == 0 then return end

	if Shine:CanNotify( GetOwner( Player ) ) then
		self:SendTranslatedNotify( Player, "TeamSwitchFail", {
			IsEndVote = IsEndVote or false
		} )
	end

	return false
end

function Plugin:CanExtend()
	local CurMap = Shared.GetMapName()

	return self.Config.AllowExtend and self.NextMap.Extends < self.Config.MaxExtends
		and not self.Config.DontExtend[ CurMap ]
end

function Plugin:CreateCommands()
	local function NotifyError( Player, Key, Data, Message, Format, ... )
		if Player then
			if not Data or not next( Data ) then
				self:NotifyTranslatedError( Player, Key )
			else
				self:SendTranslatedError( Player, Key, Data )
			end
		else
			Notify( Format and StringFormat( Message, ... ) or Message )
		end
	end

	local function GetPlayerData( Client )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		return Player, PlayerName
	end

	local function Nominate( Client, Map )
		local SteamID = Client and Client:GetUserId() or "Console"
		local Player, PlayerName = GetPlayerData( Client )

		-- Verify the user hasn't nominated too many, and use their Steam ID to prevent rejoining resetting it.
		local NominationCount = self.Vote.NominationTracker[ SteamID ] or 0
		if NominationCount >= self.Config.MaxNominationsPerPlayer then
			NotifyError( Player, "NOMINATE_DENIED", nil, "You have reached the limit of nominations permitted." )
			return
		end

		if not self.Config.Maps[ Map ] then
			NotifyError( Player, "MAP_NOT_ON_LIST", {
				MapName = Map
			}, "%s is not on the map list.", true, Map )

			return
		end

		if not self:CanExtend() and Shared.GetMapName() == Map then
			NotifyError( Player, "NOMINATE_FAIL", nil, "You cannot nominate the current map." )

			return
		end

		local Nominated = self.Vote.Nominated

		if self.Config.ForcedMaps[ Map ] or TableHasValue( Nominated, Map ) then
			NotifyError( Player, "ALREADY_NOMINATED", {
				MapName = Map
			}, "%s has already been nominated.", true, Map )

			return
		end

		local Count = #Nominated

		-- Approximate the maps that will be available by just taking the forced maps as chosen.
		local TotalMapsAvailable = Shine.Set( self.Config.Maps ):GetCount()
		local TotalForcedMaps = Shine.Set( self.Config.ForcedMaps ):GetCount()
		local LastMaps = self:GetBlacklistedLastMaps( TotalMapsAvailable - TotalForcedMaps, TotalForcedMaps )
		if TableHasValue( LastMaps, Map ) then
			NotifyError( Player, "RECENTLY_PLAYED", {
				MapName = Map
			}, "%s was recently played and cannot be voted for yet.", true, Map )
			return
		end

		if Count >= self.MaxNominations then
			NotifyError( Player, "NOMINATIONS_FULL", nil, "Nominations are full." )

			return
		end

		if self:VoteStarted() then
			NotifyError( Player, "VOTE_FAIL_IN_PROGRESS", nil, "A vote is already in progress." )

			return
		end

		self.Vote.NominationTracker[ SteamID ] = NominationCount + 1

		Nominated[ Count + 1 ] = Map

		self:SendTranslatedNotify( nil, "NOMINATED_MAP", {
			TargetName = PlayerName,
			MapName = Map
		} )
	end
	local NominateCommand = self:BindCommand( "sh_nominate", "nominate", Nominate, true )
	NominateCommand:AddParam{ Type = "string", Error = "Please specify a map name to nominate.", Help = "mapname" }
	NominateCommand:Help( "Nominates a map for the next map vote." )

	local function VoteToChange( Client )
		local Player, PlayerName = GetPlayerData( Client )

		if not self.Config.EnableRTV then
			NotifyError( Player, "RTV_DISABLED", nil, "RTV has been disabled." )

			return
		end

		local Success, Err, Key, Data = self:CanStartVote()

		if not Success then
			NotifyError( Player, Key, Data, Err )

			return
		end

		Success, Err, Key, Data = self:AddStartVote( Client )
		if Success then
			if self:TimerExists( self.VoteTimer ) then return end

			local VotesNeeded = self.StartingVote:GetVotesNeeded()

			self:SendTranslatedNotify( nil, "RTV_VOTED", {
				TargetName = PlayerName,
				VotesNeeded = VotesNeeded
			} )

			return
		end

		NotifyError( Player, Key, Data, Err )
	end
	local StartVoteCommand = self:BindCommand( "sh_votemap", { "rtv", "votemap", "mapvote" },
		VoteToChange, true )
	StartVoteCommand:Help( "Begin a vote to change the map." )

	local function ShowVoteChoice( PlayerName, Map, Revote )
		local NumForThis = self.Vote.VoteList[ Map ]
		local NumTotal = self.Vote.TotalVotes

		self:SendTranslatedNotify( nil, "PLAYER_VOTED", {
			TargetName = PlayerName,
			Revote = Revote or false,
			MapName = Map,
			Votes = NumForThis,
			TotalVotes = NumTotal
		} )
	end

	local function ShowVoteToPlayer( Player, Map, Revote )
		local NumForThis = self.Vote.VoteList[ Map ]
		local NumTotal = self.Vote.TotalVotes

		self:SendTranslatedNotify( Player, "PLAYER_VOTED_PRIVATE", {
			Revote = Revote or false,
			MapName = Map,
			Votes = NumForThis,
			TotalVotes = NumTotal
		} )
	end

	local function Vote( Client, Map )
		local Player, PlayerName = GetPlayerData( Client )

		if not self:VoteStarted() then
			NotifyError( Player, "NO_VOTE_IN_PROGRESS", nil, "There is no map vote in progress." )

			return
		end

		local Success, Err, Key, Data = self:AddVote( Client, Map )

		if Success then
			if self.Config.ShowVoteChoices then
				ShowVoteChoice( PlayerName, Err )
			else
				ShowVoteToPlayer( Client, Map )
			end

			return
		end

		if Err == "already voted" then
			local Success, Err, Key, Data = self:AddVote( Client, Map, true )

			if Success then
				if self.Config.ShowVoteChoices then
					ShowVoteChoice( PlayerName, Err, true )
				else
					ShowVoteToPlayer( Client, Map, true )
				end

				return
			end

			NotifyError( Player, Key, Data, Err )

			return
		end

		NotifyError( Player, Key, Data, Err )
	end
	local VoteCommand = self:BindCommand( "sh_vote", "vote", Vote, true )
	VoteCommand:AddParam{ Type = "string", Error = "Please specify a map to vote for.", Help = "mapname" }
	VoteCommand:Help( "Vote for a particular map in the active map vote." )

	local function Veto( Client )
		local Player, PlayerName = GetPlayerData( Client )

		if not self.Vote.CanVeto then
			NotifyError( Player, "NO_CHANGE_IN_PROGRESS", nil, "There is no map change in progress." )

			return
		end

		self.Vote.Veto = true
		self:SendTranslatedNotify( nil, "VETO", {
			TargetName = PlayerName
		} )
	end
	local VetoCommand = self:BindCommand( "sh_veto", "veto", Veto )
	VetoCommand:Help( "Cancels a map change from a successful map vote." )

	local function ForceVote( Client )
		local Player, PlayerName = GetPlayerData( Client )

		if not self:VoteStarted() then
			self:StartVote( nil, true )

			Shine:Print( "%s forced a map vote.", true, Shine.GetClientInfo( Client ) )

			self:SendTranslatedMessage( Client, "FORCED_VOTE", {} )
		else
			NotifyError( Client, "CANT_FORCE", nil, "Unable to start a new vote, a vote is already in progress." )
		end
	end
	local ForceVoteCommand = self:BindCommand( "sh_forcemapvote", "forcemapvote", ForceVote )
	ForceVoteCommand:Help( "Forces a map vote to start, if possible." )

	local function NotifyConsole( Message, Format, ... )
		Notify( Format and StringFormat( Message, ... ) or Message )
	end

	local function TimeLeft( Client )
		local Cycle = self.MapCycle
		local CycleTime = Cycle and ( Cycle.time * 60 ) or 1800
		local ExtendTime = self.NextMap.ExtendTime
		local TimeLeft = ExtendTime and ( ExtendTime - SharedTime() ) or ( CycleTime - SharedTime() )

		if Client then
			local Message = {}
			if self.Config.RoundLimit > 0 then
				Message.Rounds = true
				Message.Duration = self.Config.RoundLimit - self.Round
			else
				Message.Rounds = false
				if not CycleTime then
					Message.Duration = -1
				else
					Message.Duration = Floor( TimeLeft )
				end
			end

			self:SendTranslatedNotify( Client, "TimeLeftCommand", Message )

			return
		end

		if self.Config.RoundLimit > 0 then
			local RoundsLeft = self.Config.RoundLimit - self.Round

			if RoundsLeft > 1 then
				local RoundMessage = StringFormat( "are %i rounds", RoundsLeft )

				NotifyConsole( "There %s remaining.", true, RoundMessage )
			else
				NotifyConsole( "The map will cycle on round end." )
			end

			return
		end

		if not CycleTime then
			NotifyConsole( "The server does not have a map cycle. No timelimit given." )

			return
		end

		local Message = "%s remaining on this map."

		if TimeLeft <= 0 then
			Message = "Map will change on round end."
		end

		NotifyConsole( Message, true, string.TimeToString( TimeLeft ) )
	end
	local TimeLeftCommand = self:BindCommand( "sh_timeleft", "timeleft", TimeLeft, true )
	TimeLeftCommand:Help( "Displays the remaining time for the current map." )

	local function NextMap( Client )
		local Map = self:GetNextMap() or "unknown"

		if Client then
			self:SendTranslatedNotify( Client, "NextMapCommand", {
				MapName = Map
			} )

			return
		end

		NotifyConsole( "The next map is currently set to %s.", true, Map )
	end
	local NextMapCommand = self:BindCommand( "sh_nextmap", "nextmap", NextMap, true )
	NextMapCommand:Help( "Displays the next map in the cycle or the next map voted for." )

	local function AddTime( Client, Time )
		if Time == 0 then return end

		self.MapCycle.time = self.MapCycle.time + Time

		Time = Time * 60

		self:SendTranslatedMessage( Client, "MAP_EXTENDED_TIME", {
			Duration = Time
		} )
	end
	local AddTimeCommand = self:BindCommand( "sh_addtimelimit", "addtimelimit", AddTime )
	AddTimeCommand:AddParam{ Type = "time", Units = "minutes", TakeRestOfLine = true,
		Error = "Please specify a time to add." }
	AddTimeCommand:Help( "Adds the given time to the current map's time limit." )

	local function SetTime( Client, Time )
		self.MapCycle.time = Time

		Time = Time * 60
		self:SendTranslatedMessage( Client, "SET_MAP_TIME", {
			Duration = Time
		} )
	end
	local SetTimeCommand = self:BindCommand( "sh_settimelimit", "settimelimit", SetTime )
	SetTimeCommand:AddParam{ Type = "time", Units = "minutes", Min = 0, TakeRestOfLine = true,
		Error = "Please specify the map time." }
	SetTimeCommand:Help( "Sets the current map's time limit." )

	local function AddRounds( Client, Rounds )
		if Rounds == 0 then return end

		self.Config.RoundLimit = self.Config.RoundLimit + Rounds
		self:SendTranslatedMessage( Client, "MAP_EXTENDED_ROUNDS", {
			Duration = Rounds
		} )
	end
	local AddRoundsCommand = self:BindCommand( "sh_addroundlimit", "addroundlimit", AddRounds )
	AddRoundsCommand:AddParam{ Type = "number", Round = true,
		Error = "Please specify the amount of rounds to add.", Help = "rounds" }
	AddRoundsCommand:Help( "Adds the given number of rounds to the round limit." )

	local function SetRounds( Client, Rounds )
		self.Config.RoundLimit = Rounds
		self:SendTranslatedMessage( Client, "SET_MAP_ROUNDS", {
			Duration = Rounds
		} )
	end
	local SetRoundsCommand = self:BindCommand( "sh_setroundlimit", "setroundlimit", SetRounds )
	SetRoundsCommand:AddParam{ Type = "number", Round = true, Min = 0,
		Error = "Please specify a round limit.", Help = "rounds" }
	SetRoundsCommand:Help( "Sets the round limit." )
end

function Plugin:Cleanup()
	if self:VoteStarted() then
		self:NotifyTranslated( nil, "PLUGIN_DISABLED" )

		--Remember to clean up client side vote text/menu entries...
		self:EndVote()
	end

	self.BaseClass.Cleanup( self )
end
