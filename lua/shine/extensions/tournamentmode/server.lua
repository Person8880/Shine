--[[
	Shine tournament mode

	TODO:
	- Best of X mode?
]]

local Shine = Shine
local Timer = Shine.Timer

local StringFormat = string.format
local TableEmpty = table.Empty

local Plugin = Plugin
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "TournamentMode.json"
Plugin.DefaultConfig = {
	CountdownTime = 15, --How long should the game wait after team are ready to start?
	ForceTeams = false --Force teams to stay the same.
}

Plugin.CheckConfig = true

--Don't allow the afkkick, pregame, mapvote or readyroom plugins to load with us.
Plugin.Conflicts = {
	DisableThem = {
		"pregame",
		"mapvote",
		"readyroom",
		"afkkick"
	}
}

Plugin.CountdownTimer = "TournamentCountdown"
Plugin.FiveSecondTimer = "Tournament5SecondCount"

--List of mods not compatible with tournament mode
local BlacklistMods = {
	[ "5f35045" ] = "Combat",
	[ "7e64c1a" ] = "Xenoswarm",
	[ "7957667" ] = "Marine vs Marine",
	[ "6ed01f8" ] = "The Faded"
}

function Plugin:Initialise()
	local GetMod = Server.GetActiveModId

	for i = 1, Server.GetNumActiveMods() do
		local Mod = GetMod( i ):lower()

		local OnBlacklist = BlacklistMods[ Mod ]

		if OnBlacklist then
			return false, StringFormat( "The tournamentmode plugin does not work with %s.", OnBlacklist )
		end
	end

	self.TeamMembers = {}
	self.ReadyStates = { false, false }
	self.TeamNames = {}
	self.NextReady = { 0, 0 }
	self.TeamScores = { 0, 0 }

	self.dt.MarineScore = 0
	self.dt.AlienScore = 0

	self.dt.AlienName = ""
	self.dt.MarineName = ""

	--We've been reactivated, we can disable autobalance here and now.
	if self.Enabled ~= nil then
		Server.SetConfigSetting( "auto_team_balance", false )
		Server.SetConfigSetting( "end_round_on_team_unbalance", false )
		Server.SetConfigSetting( "force_even_teams_on_join", false )
	end

	self:CreateCommands()
	
	self.Enabled = true

	return true
end

function Plugin:Notify( Positive, Player, Message, Format, ... )
	Shine:NotifyDualColour( Player, Positive and 0 or 255, Positive and 255 or 0, 0, 
		"[TournamentMode]", 255, 255, 255, Message, Format, ... )
end

function Plugin:EndGame( Gamerules, WinningTeam )
	TableEmpty( self.TeamMembers )

	--Record the winner, and network it.
	if WinningTeam == Gamerules.team1 then
		self.TeamScores[ 1 ] = self.TeamScores[ 1 ] + 1
	
		self.dt.MarineScore = self.TeamScores[ 1 ]
	else
		self.TeamScores[ 2 ] = self.TeamScores[ 2 ] + 1

		self.dt.AlienScore = self.TeamScores[ 2 ]
	end

	self.GameStarted = false
end

local NextStartNag = 0

function Plugin:CheckGameStart( Gamerules )
	local State = Gamerules:GetGameState()
	
	if State == kGameState.PreGame or State == kGameState.NotStarted then
		self:CheckCommanders( Gamerules )

		local Time = Shared.GetTime()

		--Have you started yet? No? Start pls.
		if NextStartNag < Time then
			NextStartNag = Time + 30

			local Nag = self:GetStartNag()

			if not Nag then return end

			self:SendNetworkMessage( nil, "StartNag", { Message = Nag }, true )
		end

		return false
	end
end

function Plugin:GetStartNag()
	local MarinesReady = self.ReadyStates[ 1 ]
	local AliensReady = self.ReadyStates[ 2 ]

	if MarinesReady and AliensReady then return nil end
	
	if MarinesReady and not AliensReady then
		return StringFormat( "Waiting on %s to start", self:GetTeamName( 2 ) )
	elseif AliensReady and not MarinesReady then
		return StringFormat( "Waiting on %s to start", self:GetTeamName( 1 ) )
	else
		return StringFormat( "Waiting on both teams to start" )
	end
end

function Plugin:CheckCommanders( Gamerules )
	local Team1 = Gamerules.team1
	local Team2 = Gamerules.team2

	local Team1Com = Team1:GetCommander()
	local Team2Com = Team2:GetCommander()

	local MarinesReady = self.ReadyStates[ 1 ]
	local AliensReady = self.ReadyStates[ 2 ]

	if MarinesReady and not Team1Com then
		self.ReadyStates[ 1 ] = false

		self:Notify( false, nil, "%s is no longer ready.", true, self:GetTeamName( 1 ) )

		self:CheckStart()
	end

	if AliensReady and not Team2Com then
		self.ReadyStates[ 2 ] = false

		self:Notify( false, nil, "%s is no longer ready.", true, self:GetTeamName( 2 ) )

		self:CheckStart()
	end
end

function Plugin:StartGame( Gamerules )
	Gamerules:ResetGame()
	Gamerules:SetGameState( kGameState.Countdown )
	Gamerules.countdownTime = kCountDownLength
	Gamerules.lastCountdownPlayed = nil

	for _, Player in ientitylist( Shared.GetEntitiesWithClassname( "Player" ) ) do
		if Player.ResetScores then
			Player:ResetScores()
		end
	end

	TableEmpty( self.ReadyStates )

	self.GameStarted = true
end

--[[
	Rejoin a reconnected client to their old team.
]]
function Plugin:ClientConfirmConnect( Client )
	if not self.DisabledAutobalance then
		Server.SetConfigSetting( "auto_team_balance", false )
		Server.SetConfigSetting( "end_round_on_team_unbalance", false )
		Server.SetConfigSetting( "force_even_teams_on_join", false )

		self.DisabledAutobalance = true
	end
	
	if Client:GetIsVirtual() then return end

	local ID = Client:GetUserId()

	if self.Config.ForceTeams then
		if self.TeamMembers[ ID ] then
			Gamerules:JoinTeam( Client:GetControllingPlayer(), self.TeamMembers[ ID ], nil, true )     
		end
	end
end

--[[
	Record the team that players join.
]]
function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force )
	if NewTeam == 0 or NewTeam == 3 then return end
	
	local Client = Player:GetClient()

	if not Client then return end

	local ID = Client:GetUserId()

	self.TeamMembers[ ID ] = NewTeam
end

function Plugin:GetTeamName( Team )
	if self.TeamNames[ Team ] then
		return self.TeamNames[ Team ]
	end

	return Shine:GetTeamName( Team, true )
end

function Plugin:CheckStart()
	--Both teams are ready, start the countdown.
	if self.ReadyStates[ 1 ] and self.ReadyStates[ 2 ] then
		local CountdownTime = self.Config.CountdownTime

		local GameStartTime = string.TimeToString( CountdownTime )

		Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in "..GameStartTime, 5, 255, 255, 255, 1, 3, 1 ) )

		--Game starts in 5 seconds!
		Timer.Create( self.FiveSecondTimer, CountdownTime - 5, 1, function()
			Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", 5, 255, 0, 0, 1, 3, 0 ) )
		end )

		--If we get this far, then we can start.
		Timer.Create( self.CountdownTimer, self.Config.CountdownTime, 1, function()
			self:StartGame( GetGamerules() )
		end )

		return
	end

	--One or both teams are not ready, halt the countdown.
	if Timer.Exists( self.CountdownTimer ) then
		Timer.Destroy( self.FiveSecondTimer )
		Timer.Destroy( self.CountdownTimer )

		--Remove the countdown text.
		Shine:RemoveText( nil, { ID = 2 } )

		self:Notify( false, nil, "Game start aborted." )
	end
end

function Plugin:GetReadyState( Team )
	return self.ReadyStates[ Team ]
end

function Plugin:GetOppositeTeam( Team )
	return Team == 1 and 2 or 1
end

function Plugin:CreateCommands()
	local function ReadyUp( Client )
		if self.GameStarted then
			return
		end

		local Player = Client:GetControllingPlayer()

		if not Player then return end
		
		local Team = Player:GetTeamNumber()

		if Team ~= 1 and Team ~= 2 then
			return
		end

		if not Player:isa( "Commander" ) then
			Shine:NotifyError( Client, "Only the commander can ready up the team." )

			return
		end

		local Time = Shared.GetTime()
		local NextReady = self.NextReady[ Team ] or 0

		if not self.ReadyStates[ Team ] then
			if NextReady > Time then
				return
			end

			self.ReadyStates[ Team ] = true

			local TeamName = self:GetTeamName( Team )

			local OtherTeam = self:GetOppositeTeam( Team )
			local OtherReady = self:GetReadyState( OtherTeam )

			if OtherReady then
				self:Notify( true, nil, "%s is now ready.", true, TeamName )
			else
				self:Notify( true, nil, "%s is now ready. Waiting on %s to start.", true, TeamName, self:GetTeamName( OtherTeam ) )
			end
			
			--Add a delay to prevent ready->unready spam.
			self.NextReady[ Team ] = Time + 5

			self:CheckStart()
		else
			Shine:NotifyError( Client, "Your team is already ready! Use !unready to unready your team." )
		end
	end
	local ReadyCommand = self:BindCommand( "sh_ready", { "rdy", "ready" }, ReadyUp, true )
	ReadyCommand:Help( "Makes your team ready to start the game." )
	
	local function Unready( Client )
		if self.GameStarted then
			return
		end

		local Player = Client:GetControllingPlayer()

		if not Player then return end
		
		local Team = Player:GetTeamNumber()

		if Team ~= 1 and Team ~= 2 then
			return
		end

		if not Player:isa( "Commander" ) then
			Shine:NotifyError( Client, "Only the commander can ready up the team." )

			return
		end

		local Time = Shared.GetTime()
		local NextReady = self.NextReady[ Team ] or 0

		if self.ReadyStates[ Team ] then
			if NextReady > Time then
				return
			end

			self.ReadyStates[ Team ] = false

			local TeamName = self:GetTeamName( Team )

			self:Notify( false, nil, "%s is no longer ready.", true, TeamName )

			--Add a delay to prevent ready->unready spam.
			self.NextReady[ Team ] = Time + 5

			self:CheckStart()
		else
			Shine:NotifyError( Client, "Your team has not readied yet! Use !ready to ready your team." )
		end
	end
	local UnReadyCommand = self:BindCommand( "sh_unready", { "unrdy", "unready" }, Unready, true )
	UnReadyCommand:Help( "Makes your team not ready to start the game." )

	local function SetTeamNames( Client, Marine, Alien )
		self.TeamNames[ 1 ] = Marine
		self.TeamNames[ 2 ] = Alien

		self.dt.MarineName = Marine
		self.dt.AlienName = Alien
	end
	local SetTeamNamesCommand = self:BindCommand( "sh_setteamnames", { "teamnames" }, SetTeamNames )
	SetTeamNamesCommand:AddParam{ Type = "string", Optional = true, Default = "" }
	SetTeamNamesCommand:AddParam{ Type = "string", Optional = true, Default = "" }
	SetTeamNamesCommand:Help( "<Marine Name> <Alien Name> Sets the names of the marine and alien teams." )

	local function SetTeamScores( Client, Marine, Alien )
		self.TeamScores[ 1 ] = Marine
		self.TeamScores[ 2 ] = Alien

		self.dt.MarineScore = Marine
		self.dt.AlienScore = Alien
	end
	local SetTeamScoresCommand = self:BindCommand( "sh_setteamscores", { "scores" }, SetTeamScores )
	SetTeamScoresCommand:AddParam{ Type = "number", Min = 0, Max = 255, Round = true, Optional = true, Default = 0 }
	SetTeamScoresCommand:AddParam{ Type = "number", Min = 0, Max = 255, Round = true, Optional = true, Default = 0 }
	SetTeamScoresCommand:Help( "<Marine Score> <Alien Score> Sets the score for the marine and alien teams." )
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )

	self.TeamMembers = nil
	self.ReadyStates = nil
	self.TeamNames = nil

	Server.SetConfigSetting( "auto_team_balance", true )
	Server.SetConfigSetting( "end_round_on_team_unbalance", true )
	Server.SetConfigSetting( "force_even_teams_on_join", true )

	self.Enabled = false
end
