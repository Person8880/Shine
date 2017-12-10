--[[
	Shine tournament mode

	TODO:
	- Best of X mode?
]]

local Shine = Shine

local StringFormat = string.format
local TableCopy = table.Copy
local TableEmpty = table.Empty

local Plugin = Plugin
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "TournamentMode.json"
Plugin.DefaultConfig = {
	CountdownTime = 15, -- How long should the game wait after team are ready to start?
	ForceTeams = false, -- Force teams to stay the same.
	EveryoneReady = false -- Should the plugin require every player to be ready?
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

-- Don't allow the pregame or readyroom plugins to load with us.
Plugin.Conflicts = {
	DisableThem = {
		"pregame",
		"readyroom"
	}
}

Plugin.CountdownTimer = "Countdown"
Plugin.FiveSecondTimer = "5SecondCount"

Plugin.EnabledGamemodes = {
	[ "ns2" ] = true
}

function Plugin:GetServerConfigSettings()
	return {
		AutoBalance = Server.GetConfigSetting( "auto_team_balance" ),
		EndOnTeamUnbalance = Server.GetConfigSetting( "end_round_on_team_unbalance" ),
		ForceEvenTeamsOnJoin = Server.GetConfigSetting( "force_even_teams_on_join" )
	}
end

function Plugin:RestoreConfigSettings()
	if not self.OriginalServerConfig then return end

	Server.SetConfigSetting( "auto_team_balance", self.OriginalServerConfig.AutoBalance )
	Server.SetConfigSetting( "end_round_on_team_unbalance", self.OriginalServerConfig.EndOnTeamUnbalance )
	Server.SetConfigSetting( "force_even_teams_on_join", self.OriginalServerConfig.ForceEvenTeamsOnJoin )

	self.OriginalServerConfig = nil
end

function Plugin:SetupServerConfig()
	if self.OriginalServerConfig then return end

	self.OriginalServerConfig = self:GetServerConfigSettings()

	local AutoBalance = TableCopy( self.OriginalServerConfig.AutoBalance )
	AutoBalance.enabled = false

	Server.SetConfigSetting( "auto_team_balance", AutoBalance )
	Server.SetConfigSetting( "end_round_on_team_unbalance", false )
	Server.SetConfigSetting( "force_even_teams_on_join", false )
end

function Plugin:Initialise()
	self.TeamMembers = {}
	self.ReadyStates = { false, false }
	self.TeamNames = {}
	self.NextReady = {}
	self.TeamScores = { 0, 0 }

	if self.Config.EveryoneReady then
		self.ReadiedPlayers = {}
	end

	self.dt.MarineScore = 0
	self.dt.AlienScore = 0

	self.dt.AlienName = ""
	self.dt.MarineName = ""

	-- We've been reactivated, we can disable autobalance here and now.
	if self.Enabled ~= nil then
		self:SetupServerConfig()
	end

	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:Notify( Positive, Player, Message, Format, ... )
	Shine:NotifyDualColour( Player, Positive and 0 or 255, Positive and 255 or 0, 0,
		"[TournamentMode]", 255, 255, 255, Message, Format, ... )
end

-- Never allow the map to auto-cycle.
function Plugin:ShouldCycleMap()
	return false
end

function Plugin:EndGame( Gamerules, WinningTeam )
	TableEmpty( self.TeamMembers )

	-- Record the winner, and network it.
	if WinningTeam == Gamerules.team1 or WinningTeam == 1 then
		self.TeamScores[ 1 ] = self.TeamScores[ 1 ] + 1

		self.dt.MarineScore = self.TeamScores[ 1 ]
	elseif WinningTeam == Gamerules.team2 or WinningTeam == 2 then
		self.TeamScores[ 2 ] = self.TeamScores[ 2 ] + 1

		self.dt.AlienScore = self.TeamScores[ 2 ]
	end

	self.GameStarted = false
end

local NextStartNag = 0

function Plugin:CheckGameStart( Gamerules )
	local State = Gamerules:GetGameState()

	if State <= kGameState.PreGame then
		self.GameStarted = false

		self:CheckCommanders( Gamerules )

		local Time = Shared.GetTime()

		-- Have you started yet? No? Start pls.
		if NextStartNag < Time then
			NextStartNag = Time + 30

			local TeamWaitingFor = self:GetTeamNotReady()
			if not TeamWaitingFor then return false end

			self:SendNetworkMessage( nil, "StartNag", { WaitingTeam = TeamWaitingFor }, true )
		end

		return false
	end
end

function Plugin:GetTeamNotReady()
	local MarinesReady = self.ReadyStates[ 1 ]
	local AliensReady = self.ReadyStates[ 2 ]
	if MarinesReady and AliensReady then return nil end

	if MarinesReady and not AliensReady then
		return 2
	elseif AliensReady and not MarinesReady then
		return 1
	else
		return 0
	end
end

function Plugin:CheckCommanders( Gamerules )
	if self.Config.EveryoneReady then return end

	local Team1 = Gamerules.team1
	local Team2 = Gamerules.team2

	local Team1Com = Team1:GetCommander()
	local Team2Com = Team2:GetCommander()

	local MarinesReady = self.ReadyStates[ 1 ]
	local AliensReady = self.ReadyStates[ 2 ]

	if MarinesReady and not Team1Com then
		self.ReadyStates[ 1 ] = false
		self:SendNetworkMessage( nil, "TeamReadyChange", {
			Team = 1,
			IsReady = false
		}, true )
		self:CheckStart()
	end

	if AliensReady and not Team2Com then
		self.ReadyStates[ 2 ] = false
		self:SendNetworkMessage( nil, "TeamReadyChange", {
			Team = 2,
			IsReady = false
		}, true )
		self:CheckStart()
	end
end

function Plugin:StartGame( Gamerules )
	Gamerules:ResetGame()
	Gamerules:SetGameState( kGameState.Countdown )
	Gamerules.countdownTime = kCountDownLength
	Gamerules.lastCountdownPlayed = nil

	local Players, Count = Shine.GetAllPlayers()

	for i = 1, Count do
		local Player = Players[ i ]

		if Player.ResetScores then
			Player:ResetScores()
		end
	end

	TableEmpty( self.ReadyStates )

	if self.ReadiedPlayers then
		TableEmpty( self.ReadiedPlayers )
	end

	self.GameStarted = true
end

--[[
	Rejoin a reconnected client to their old team.
]]
function Plugin:ClientConfirmConnect( Client )
	self:SetupServerConfig()

	if Client:GetIsVirtual() then return end

	local ID = Client:GetUserId()

	if self.Config.ForceTeams then
		if self.TeamMembers[ ID ] then
			Gamerules:JoinTeam( Client:GetControllingPlayer(), self.TeamMembers[ ID ],
				nil, true )
		end
	end
end

--[[
	Remove readied clients on disconnect.
]]
function Plugin:ClientDisconnect( Client )
	if not self.ReadiedPlayers then return end

	self.ReadiedPlayers[ Client ] = nil
end

--[[
	Performs a full check on all team members for readyness.
]]
function Plugin:CheckTeams()
	local Marines = Shine.GetTeamClients( 1 )
	local Aliens = Shine.GetTeamClients( 2 )

	local MarineReady = true
	local AlienReady = true

	for i = 1, #Marines do
		if not self.ReadiedPlayers[ Marines[ i ] ] then
			MarineReady = false
			break
		end
	end

	for i = 1, #Aliens do
		if not self.ReadiedPlayers[ Aliens[ i ] ] then
			AlienReady = false
			break
		end
	end

	self.ReadyStates[ 1 ] = MarineReady
	self.ReadyStates[ 2 ] = AlienReady

	self:CheckStart()
end

--[[
	Record the team that players join.
]]
function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force )
	if NewTeam == 0 or NewTeam == 3 then return end

	local Client = Server.GetOwner( Player )

	if not Client then return end

	local ID = Client:GetUserId()

	self.TeamMembers[ ID ] = NewTeam

	if self.ReadiedPlayers then
		self.ReadiedPlayers[ Client ] = false
	end
end

function Plugin:CheckStart()
	-- Both teams are ready, start the countdown.
	if self.ReadyStates[ 1 ] and self.ReadyStates[ 2 ] then
		local CountdownTime = self.Config.CountdownTime
		self:SendNetworkMessage( nil, "GameStartCountdown", {
			IsFinalCountdown = false,
			CountdownTime = CountdownTime
		}, true )

		-- Game starts in 5 seconds!
		self:CreateTimer( self.FiveSecondTimer, CountdownTime - 5, 1, function()
			self:SendNetworkMessage( nil, "GameStartCountdown", {
				IsFinalCountdown = true,
				CountdownTime = 5
			}, true )
		end )

		-- If we get this far, then we can start.
		self:CreateTimer( self.CountdownTimer, self.Config.CountdownTime, 1, function()
			self:StartGame( GetGamerules() )
		end )

		return
	end

	-- One or both teams are not ready, halt the countdown.
	if self:TimerExists( self.CountdownTimer ) then
		self:DestroyTimer( self.FiveSecondTimer )
		self:DestroyTimer( self.CountdownTimer )

		self:SendNetworkMessage( nil, "GameStartAborted", {}, true )
	end
end

function Plugin:GetReadyState( Team )
	return self.ReadyStates[ Team ]
end

function Plugin:GetOppositeTeam( Team )
	return Team == 1 and 2 or 1
end

function Plugin:ReadyTeam( Team )
	self.ReadyStates[ Team ] = true

	local OtherTeam = self:GetOppositeTeam( Team )
	local OtherReady = self:GetReadyState( OtherTeam )

	if OtherReady then
		self:SendNetworkMessage( nil, "TeamReadyChange", {
			Team = Team,
			IsReady = true
		}, true )
	else
		self:SendNetworkMessage( nil, "TeamReadyWaiting", {
			ReadyTeam = Team,
			WaitingTeam = OtherTeam
		}, true )
	end

	self:CheckStart()
end

function Plugin:UnReadyTeam( Team, Notify )
	if self.ReadyStates[ Team ] then
		self.ReadyStates[ Team ] = false
	end

	if Notify then
		self:SendNetworkMessage( nil, "TeamReadyChange", {
			Team = Team,
			IsReady = false
		}, true )
	end

	self:CheckStart()
end

function Plugin:CreateCommands()
	local function IsPlayingClient( Client )
		local Player = Client:GetControllingPlayer()
		if not Player then return false end

		local Team = Player:GetTeamNumber()
		if Team ~= 1 and Team ~= 2 then return false end

		return true, Player, Team
	end

	local function Unready( Client )
		if self.GameStarted then return end
		local Valid, Player, Team = IsPlayingClient( Client )
		if not Valid then return end

		if not Player:isa( "Commander" ) and not self.Config.EveryoneReady then
			self:NotifyTranslatedCommandError( Client, "ERROR_ONLY_COMMANDER_UNREADY" )

			return
		end

		local Time = Shared.GetTime()

		if self.Config.EveryoneReady then
			if not self.ReadiedPlayers[ Client ] then
				self:NotifyTranslatedCommandError( Client, "ERROR_NOT_READY" )

				return
			end

			local NextReady = self.NextReady[ Client ] or 0
			if NextReady > Time then return end

			self.NextReady[ Client ] = Time + 5
			self.ReadiedPlayers[ Client ] = false

			local TeamWasReady = self.ReadyStates[ Team ]
			if TeamWasReady then
				self:SendNetworkMessage( nil, "TeamPlayerNotReady", {
					Team = Team,
					PlayerName = Player:GetName()
				}, true )
			else
				self:SendNetworkMessage( nil, "PlayerReadyChange", {
					PlayerName = Player:GetName(),
					IsReady = false
				}, true )
			end

			self:UnReadyTeam( Team )

			return
		end

		local NextReady = self.NextReady[ Team ] or 0

		if self.ReadyStates[ Team ] then
			if NextReady > Time then return end

			-- Add a delay to prevent ready->unready spam.
			self.NextReady[ Team ] = Time + 5
			self:UnReadyTeam( Team, true )
		else
			self:NotifyTranslatedCommandError( Client, "ERROR_NOT_TEAM_READY" )
		end
	end
	local UnReadyCommand = self:BindCommand( "sh_unready", { "unrdy", "unready" }, Unready, true )
	UnReadyCommand:Help( "Makes your team not ready to start the game." )
	UnReadyCommand:SetAlwaysMatchChat( true )

	local function ReadyUp( Client )
		if self.GameStarted then return end
		local Valid, Player, Team = IsPlayingClient( Client )
		if not Valid then return end

		if not Player:isa( "Commander" ) and not self.Config.EveryoneReady then
			self:NotifyTranslatedCommandError( Client, "ERROR_ONLY_COMMANDER_READY" )

			return
		end

		local Time = Shared.GetTime()

		if self.Config.EveryoneReady then
			if self.ReadiedPlayers[ Client ] then
				Unready( Client )

				return
			end

			local NextReady = self.NextReady[ Client ] or 0
			if NextReady > Time then return end

			self.NextReady[ Client ] = Time + 5
			self.ReadiedPlayers[ Client ] = true

			self:SendNetworkMessage( nil, "PlayerReadyChange", {
				PlayerName = Player:GetName(),
				IsReady = true
			}, true )

			local Clients = Shine.GetTeamClients( Team )
			local Ready = true

			for i = 1, #Clients do
				if not self.ReadiedPlayers[ Clients[ i ] ] then
					Ready = false
					break
				end
			end

			if not Ready then return end

			self:ReadyTeam( Team )

			return
		end

		local NextReady = self.NextReady[ Team ] or 0

		if not self.ReadyStates[ Team ] then
			if NextReady > Time then return end

			-- Add a delay to prevent ready->unready spam.
			self.NextReady[ Team ] = Time + 5
			self:ReadyTeam( Team )
		else
			Unready( Client )
		end
	end
	local ReadyCommand = self:BindCommand( "sh_ready", { "rdy", "ready" }, ReadyUp, true )
	ReadyCommand:Help( "Makes your team ready to start the game." )
	ReadyCommand:SetAlwaysMatchChat( true )

	local function SetTeamNames( Client, Marine, Alien )
		self.TeamNames[ 1 ] = Marine
		self.TeamNames[ 2 ] = Alien

		self.dt.MarineName = Marine
		self.dt.AlienName = Alien
	end
	local SetTeamNamesCommand = self:BindCommand( "sh_setteamnames",
		{ "teamnames" }, SetTeamNames )
	SetTeamNamesCommand:AddParam{ Type = "string", Optional = true, Default = "", Help = "Marine Name" }
	SetTeamNamesCommand:AddParam{ Type = "string", Optional = true, Default = "", Help = "Alien Name" }
	SetTeamNamesCommand:Help( "Sets the names of the marine and alien teams." )

	local function SetTeamScores( Client, Marine, Alien )
		self.TeamScores[ 1 ] = Marine
		self.TeamScores[ 2 ] = Alien

		self.dt.MarineScore = Marine
		self.dt.AlienScore = Alien
	end
	local SetTeamScoresCommand = self:BindCommand( "sh_setteamscores",
		{ "scores" }, SetTeamScores )
	SetTeamScoresCommand:AddParam{ Type = "number", Min = 0, Max = 255, Round = true, Optional = true, Default = 0,
		Help = "Marine Score" }
	SetTeamScoresCommand:AddParam{ Type = "number", Min = 0, Max = 255, Round = true, Optional = true, Default = 0,
		Help = "Alien Score" }
	SetTeamScoresCommand:Help( "Sets the score for the marine and alien teams." )
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )

	self.TeamMembers = nil
	self.ReadyStates = nil
	self.TeamNames = nil

	self:RestoreConfigSettings()
end

-- Restore config settings on map change, in case this plugin is disabled on the next map.
function Plugin:MapChange()
	self:RestoreConfigSettings()
end
