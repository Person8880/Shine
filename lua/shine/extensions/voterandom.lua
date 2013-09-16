--[[
	Shine vote random plugin.
]]

local Shine = Shine

local Notify = Shared.Message

local Abs = math.abs
local assert = assert
local Ceil = math.ceil
local Clamp = math.Clamp
local Decode = json.decode
local Floor = math.floor
local Max = math.max
local Min = math.min
local next = next
local pairs = pairs
local Random = math.random
local StringFormat = string.format
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableSort = table.sort
local tostring = tostring

local Plugin = {}
Plugin.Version = "1.5"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteRandom.json"

Plugin.Commands = {}

Plugin.RandomEndTimer = "VoteRandomTimer"

Plugin.MODE_RANDOM = 1
Plugin.MODE_SCORE = 2
Plugin.MODE_ELO = 3
Plugin.MODE_KDR = 4
Plugin.MODE_SPONITOR = 5 --Lets use the best stats source in the game.

local ModeStrings = {
	Mode = {
		"Random",
		"Score based",
		"ELO based",
		"KDR based",
		"Skill based"
	},
	ModeLower = {
		"random",
		"score based",
		"ELO based",
		"KDR based",
		"skill based"
	},
	Action = {
		"randomly",
		"based on score",
		"based on ELO",
		"based on KDR",
		"based on skill"
	}
}
Plugin.ModeStrings = ModeStrings

local DefaultConfig = {
	MinPlayers = 10, --Minimum number of players on the server to enable random voting.
	PercentNeeded = 0.75, --Percentage of the server population needing to vote for it to succeed.
	Duration = 15, --Time to force people onto random teams for after a random vote. Also time between successful votes.
	RandomOnNextRound = true, --If false, then random teams are forced for a duration instead.
	InstantForce = true, --Forces a shuffle of everyone instantly when the vote succeeds (for time based).
	VoteTimeout = 60, --Time after the last vote before the vote resets.
	BalanceMode = Plugin.MODE_RANDOM, --How should teams be balanced?
	FallbackMode = Plugin.MODE_KDR, --Which method should be used if ELO fails?
	BlockTeams = true, --Should team changing/joining be blocked after an instant force or in a round?
	IgnoreCommanders = false, --Should the plugin ignore commanders when switching?
	IgnoreSpectators = false, --Should the plugin ignore spectators when switching?
	AlwaysEnabled = false, --Should the plugin be always forcing each round?
	MaxStoredRounds = 3 --How many rounds of score data should we buffer?
}

function Plugin:Initialise()
	self:CreateCommands()

	self.NextVote = 0

	self.Vote = Shine:CreateVote( function() return self:GetVotesNeeded() end, function() self:ApplyRandomSettings() end, 
	function( Vote )
		if Vote.LastVoted and Shared.GetTime() - Vote.LastVoted > self.Config.VoteTimeout then
			Vote:Reset()
		end
	end	)

	self.ForceRandomEnd = 0 --Time based.
	self.RandomOnNextRound = false --Round based.

	self.ForceRandom = self.Config.AlwaysEnabled

	self.ScoreData = self:LoadScoreData()

	--We need this value to keep track of where we store the next round data.
	if not self.ScoreData.Round then
		self.ScoreData.Round = 1
	end

	if not self.ScoreData.Rounds then
		self.ScoreData.Rounds = {}
	end

	self.Enabled = true

	return true
end

function Plugin:Notify( Player, Message, Format, ... )
	Shine:NotifyDualColour( Player, 100, 255, 100, "[Random]", 255, 255, 255, Message, Format, ... )
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = DefaultConfig

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing voterandom config file: "..Err )	

			return	
		end

		Notify( "Shine voterandom config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing voterandom config file: "..Err )	

		return	
	end

	Notify( "Shine voterandom config file updated." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig

	if Shine.CheckConfig( self.Config, DefaultConfig ) then self:SaveConfig() end

	self.Config.BalanceMode = Clamp( Floor( self.Config.BalanceMode or 1 ), 1, 5 )
	self.Config.FallbackMode = Clamp( Floor( self.Config.FallbackMode or 1 ), 1, 5 )

	self.Config.MaxStoredRounds = Max( Floor( self.Config.MaxStoredRounds ), 1 )

	if self.Config.FallbackMode == self.MODE_ELO then
		self.Config.FallbackMode = self.MODE_KDR

		Notify( "Error in voterandom config, cannot set FallbackMode to ELO sorting mode. Setting FallbackMode to KDR mode." )
	
		self:SaveConfig()
	end
end

--[[
	Too many failed NS2Stats connections should revert the sorting mode for the rest of the map.
]]
function Plugin:AddELOFail()
	if not self.ELOFailed then
		self.ELOFailed = true

		self.ELOFailCount = 1

		return
	end

	self.ELOFailCount = self.ELOFailCount + 1

	if self.ELOFailCount >= 2 then
		self.Config.BalanceMode = self.Config.FallbackMode

		Shine:Print( "[ELO Vote] Connection to NS2Stats failed 2 times in a row, reverting to %s sorting for the rest of the map.", 
			true, ModeStrings.ModeLower[ self.Config.FallbackMode ] )
	end
end

local Requests = {}
local ReqCount = 1

function Plugin:RequestNS2Stats( Gamerules, Callback )
	local Players = Shared.GetEntitiesWithClassname( "Player" )
	local Concat = {}

	local Count = 0

	local GetOwner = Server.GetOwner
	for _, Player in ientitylist( Players ) do
		local Client = GetOwner( Player )

		if Client and not Client:GetIsVirtual() then
			Count = Count + 1

			Concat[ Count ] = Client:GetUserId()
		end
	end

	local URL
	local NS2Stats = Shine.Plugins.ns2stats

	if NS2Stats then
		URL = NS2Stats.Config.WebsiteUrl.."/api/players"
	elseif RBPS then
		URL = RBPS.websiteUrl.."/api/players"
	end
	
	local Params = {
		players = TableConcat( Concat, "," )
	}

	local CurRequest = ReqCount
	local CurTime = Shared.GetTime()

	Requests[ CurRequest ] = CurTime + 5 --No response after 5 seconds is a fail.

	ReqCount = ReqCount + 1

	Shine.Timer.Simple( 5, function()
		if Requests[ CurRequest ] then
			Shine:Print( "[ELO Vote] Connection to NS2Stats timed out." )

			self:AddELOFail()

			Callback()
		end
	end )

	Shared.SendHTTPRequest( URL, "POST", Params, function( Response, Status )
		local Time = Shared.GetTime()

		if Requests[ CurRequest ] < Time then
			Shine:Print( "[ELO Vote] NS2Stats responded too late after %.2f seconds!", true, Time - CurTime )

			Requests[ CurRequest ] = nil

			return
		end

		Requests[ CurRequest ] = nil

		local ChatName = Shine.Config.ChatName

		if not Response then
			local FallbackMode = ModeStrings.ModeLower[ self.Config.FallbackMode ]

			Shine:Print( "[ELO Vote] Could not connect to NS2Stats. Falling back to %s sorting...", true, FallbackMode )

			self:Notify( nil, "NS2Stats failed to respond, falling back to %s sorting.", true, FallbackMode )

			self:ShuffleTeams( false, self.Config.FallbackMode )

			self:AddELOFail()

			return
		end

		local Data = Decode( Response )

		if not Data then
			local FallbackMode = ModeStrings.ModeLower[ self.Config.FallbackMode ]

			Shine:Print( "[ELO Vote] NS2Stats returned corrupt or empty data. Falling back to %s sorting...", true, FallbackMode )

			self:Notify( nil, "NS2Stats failed to respond, falling back to %s sorting.", true, FallbackMode )

			self:ShuffleTeams( false, self.Config.FallbackMode )

			self:AddELOFail()

			return
		end

		self.StatsData = self.StatsData or {}
		local StatsData = self.StatsData

		for i = 1, #Data do
			local Player = Data[ i ]

			if Player.id then
				local ID = tostring( Player.id )

				local Stored = StatsData[ ID ]

				if Stored then
					if Player.alien_ELO then
						Stored.AELO = Player.alien_ELO
					end
					if Player.marine_ELO then
						Stored.MELO = Player.marine_ELO
					end
				else
					StatsData[ ID ] = {
						AELO = Player.alien_ELO or 1500,
						MELO = Player.marine_ELO or 1500
					}
				end
			end
		end

		self.ELOFailed = nil

		Callback()
	end )
end

local EvenlySpreadTeams = Shine.EvenlySpreadTeams
local MaxELOSort = 8

local function RandomiseSimilarSkill( Data, Count, Difference )
	local LastSkill

	--Swap those with a similar skill value randomly to make things different.
	for i = 1, Count do
		local Obj = Data[ i ]

		if i == 1 then
			LastSkill = Obj.Skill
		else
			local CurSkill = Obj.Skill

			if LastSkill - CurSkill < Difference then
				if Random() >= 0.5 then
					local LastObj = Data[ i - 1 ]

					Data[ i ] = LastObj
					Data[ i - 1 ] = Obj

					LastSkill = LastObj.Skill
				else
					LastSkill = CurSkill
				end
			else
				LastSkill = CurSkill
			end
		end
	end
end

--Gets the average skill ranking of a table of players.
local function GetAverageSkill( Players )
	local PlayerCount = #Players

	if PlayerCount == 0 then return 0 end

	local PlayerSkillSum = 0

	for i = 1, PlayerCount do
		local Ply = Players[ i ]

		if Ply and Ply.GetPlayerSkill then
			PlayerSkillSum = PlayerSkillSum + Ply:GetPlayerSkill()
		end
	end

	return PlayerSkillSum / PlayerCount
end

Plugin.ShufflingModes = {
	function( self, Gamerules, Targets, TeamMembers ) --Random only.
		local NumPlayers = #Targets

		local TeamSequence = math.GenerateSequence( NumPlayers, { 1, 2 } )

		for i = 1, NumPlayers do
			local Player = Targets[ i ]
			if Player then
				local TeamTable = TeamMembers[ TeamSequence[ i ] ]

				TeamTable[ #TeamTable + 1 ] = Player
			end
		end

		EvenlySpreadTeams( Gamerules, TeamMembers )

		Shine:LogString( "[Random] Teams were sorted randomly." )

		return
	end,

	function( self, Gamerules, Targets, TeamMembers, Silent ) --Score based if available, random if not.
		local ScoreData = self.ScoreData

		local ScoreTable = {}
		local RandomTable = {}

		for i = 1, #Targets do
			local Player = Targets[ i ]

			if Player then
				local Client = Player:GetClient()

				if Client then
					local ID = Client:GetUserId()

					local Data = self:GetAverageScoreData( ID )

					if Data then
						ScoreTable[ #ScoreTable + 1 ] = { Player = Player, Score = Data }
					else
						RandomTable[ #RandomTable + 1 ] = Player
					end
				end
			end
		end

		local ScoreSortCount = #ScoreTable

		if ScoreSortCount > 0 then
			TableSort( ScoreTable, function( A, B ) return A.Score > B.Score end )

			local Add = Random() >= 0.5 and 1 or 0

			for i = 1, ScoreSortCount do
				local TeamTable = TeamMembers[ ( ( i + Add ) % 2 ) + 1 ]

				TeamTable[ #TeamTable + 1 ] = ScoreTable[ i ].Player
			end
		end

		local RandomTableCount = #RandomTable

		if RandomTableCount > 0 then
			local TeamSequence = math.GenerateSequence( RandomTableCount, { 1, 2 } )

			for i = 1, RandomTableCount do
				local TeamTable = TeamMembers[ TeamSequence[ i ] ]

				TeamTable[ #TeamTable + 1 ] = RandomTable[ i ]
			end
		end

		EvenlySpreadTeams( Gamerules, TeamMembers )

		if not Silent then
			Shine:LogString( "[Random] Teams were sorted based on score." )
		end

		return
	end,

	function( self, Gamerules, Targets, TeamMembers ) --NS2Stats ELO based.
		local ChatName = Shine.Config.ChatName
		if not RBPS and not Shine.Plugins.ns2stats then 
			local FallbackMode = ModeStrings.ModeLower[ self.Config.FallbackMode ]

			self:Notify( nil, "Shuffling based on ELO failed, falling back to %s sorting.", true, FallbackMode )

			self.ShufflingModes[ self.Config.FallbackMode ]( self, Gamerules, Targets, TeamMembers ) 

			self.LastShuffleMode = self.Config.FallbackMode

			Shine:Print( "[ELO Vote] NS2Stats is not installed correctly, defaulting to %s sorting.", true, FallbackMode )

			self:AddELOFail()

			return
		end

		self:RequestNS2Stats( Gamerules, function()
			local StatsData = self.StatsData

			if not StatsData or not next( StatsData ) then
				local FallbackMode = ModeStrings.ModeLower[ self.Config.FallbackMode ]

				Shine:Print( "[ELO Vote] NS2Stats does not have any web data for players. Using %s sorting instead.", true, FallbackMode )

				self:Notify( nil, "NS2Stats failed to respond, falling back to %s sorting.", true, FallbackMode )

				self:ShuffleTeams( false, self.Config.FallbackMode )

				return
			end

			local Targets, TeamMembers = self:GetTargetsForSorting()
			
			local Players = Shine.GetAllPlayers()

			local ELOSort = {}
			local Count = 0

			local Sorted = {}

			local GetOwner = Server.GetOwner

			for i = 1, #Targets do
				local Player = Targets[ i ]
				local Client = Player and GetOwner( Player )

				if Client then
					local ID = tostring( Client:GetUserId() )
					local Data = StatsData[ ID ]

					if Data then
						Count = Count + 1
						ELOSort[ Count ] = { Player = Player, Skill = ( Data.AELO + Data.MELO ) * 0.5 }
					end
				end
			end

			TableSort( ELOSort, function( A, B ) return A.Skill > B.Skill end )

			RandomiseSimilarSkill( ELOSort, Count, 20 )

			--Should we start from Aliens or Marines?
			local Add = Random() >= 0.5 and 1 or 0

			local ELOSorted = Min( MaxELOSort, Count )

			for i = 1, ELOSorted do
				if ELOSort[ i ] then
					local Player = ELOSort[ i ].Player

					local TeamTable = TeamMembers[ ( ( i + Add ) % 2 ) + 1 ]

					TeamTable[ #TeamTable + 1 ] = Player
					Sorted[ Player ] = true
				end
			end

			local Count = #Players - ELOSorted

			--Sort the remaining players with the fallback method.
			if Count > 0 then
				local FallbackTargets = {}

				for i = 1, #Players do
					local Player = Players[ i ]

					if Player and not Sorted[ Player ] then
						FallbackTargets[ #FallbackTargets + 1 ] = Player
					end
				end

				self.ShufflingModes[ self.Config.FallbackMode ]( self, Gamerules, FallbackTargets, TeamMembers, true )

				Shine:LogString( "[ELO Vote] Teams were sorted based on NS2Stats ELO ranking." )

				--We return as the fallback has already evenly spread the teams.
				return
			end

			EvenlySpreadTeams( Gamerules, TeamMembers )

			Shine:LogString( "[ELO Vote] Teams were sorted based on NS2Stats ELO ranking." )
		end )
	end,

	--KDR based works identically to score, the score data is what is different.
	function( self, Gamerules, Targets, TeamMembers )
		Shine:LogString( "[Random] Teams were sorted based on KDR." )
		
		return self.ShufflingModes[ self.MODE_SCORE ]( self, Gamerules, Targets, TeamMembers, true )
	end,

	--Sponitor data based. Relies on UWE's ranking data to be correct for it to work.
	function( self, Gamerules, Targets, TeamMembers )
		local SortTable = {}
		local Count = 0

		for i = 1, #Targets do
			local Ply = Targets[ i ]

			if Ply and Ply.GetPlayerSkill then
				local SkillData = Ply:GetPlayerSkill()

				Count = Count + 1
				SortTable[ Count ] = { Player = Ply, Skill = SkillData }
			end
		end

		TableSort( SortTable, function( A, B )
			return A.Skill > B.Skill
		end )

		RandomiseSimilarSkill( SortTable, Count, 10 )

		local Add = Random() >= 0.5 and 1 or 0

		for i = 1, Count do
			if SortTable[ i ] then
				local Player = SortTable[ i ].Player

				local TeamTable = TeamMembers[ ( ( i + Add ) % 2 ) + 1 ]

				TeamTable[ #TeamTable + 1 ] = Player
			end
		end

		EvenlySpreadTeams( Gamerules, TeamMembers )

		Shine:LogString( "[Skill Vote] Teams were sorted based on Sponitor skill ranking." )

		local Marines = GetEntitiesForTeam( "Player", 1 )
		local Aliens = GetEntitiesForTeam( "Player", 2 )

		local MarineSkill = GetAverageSkill( Marines )
		local AlienSkill = GetAverageSkill( Aliens )

		self:Notify( nil, "Average skill rankings - Marines: %.1f. Aliens: %.1f.", true, MarineSkill, AlienSkill )
	end
}

--[[
	Gets all valid targets for sorting.
]]
function Plugin:GetTargetsForSorting( ResetScores )
	local Players = Shine.GetAllPlayers()

	local Gamerules = GetGamerules()

	if not Gamerules then return end

	local Targets = {}
	local TeamMembers = {
		{},
		{}
	}

	local AFKKick = Shine.Plugins.afkkick
	local AFKEnabled = AFKKick and AFKKick.Enabled

	local Time = Shared.GetTime()

	local function SortPlayer( Player, Client, Commander )
		local Team = Player:GetTeamNumber()

		if Team == 3 and self.Config.IgnoreSpectators then
			return
		end

		if not Shine:HasAccess( Client, "sh_randomimmune" ) and not Commander then
			Targets[ #Targets + 1 ] = Player
		else
			local TeamTable = TeamMembers[ Team ]

			if TeamTable then
				TeamTable[ #TeamTable + 1 ] = Player
			end
		end
	end

	for i = 1, #Players do
		local Player = Players[ i ]

		if Player then
			if Player.ResetScores and ResetScores then
				Player:ResetScores()
			end

			local Commander = Player:isa( "Commander" ) and self.Config.IgnoreCommanders
			
			local Client = Player:GetClient()

			if Client then
				if AFKEnabled then --Ignore AFK players in sorting.
					local LastMove = AFKKick:GetLastMoveTime( Client )

					if not ( LastMove and Time - LastMove > 60 ) then
						SortPlayer( Player, Client, Commander )
					else --Chuck AFK players into the ready room.
						local Team = Player:GetTeamNumber()

						--Only move players on playing teams...
						if Team == 1 or Team == 2 then
							Gamerules:JoinTeam( Player, 0, nil, true )
						end
					end
				else
					SortPlayer( Player, Client, Commander )
				end
			end
		end
	end

	return Targets, TeamMembers
end

--[[
	Shuffles everyone on the server into random teams.
]]
function Plugin:ShuffleTeams( ResetScores, ForceMode )
	local Gamerules = GetGamerules()

	if not Gamerules then return end

	local Targets, TeamMembers = self:GetTargetsForSorting( ResetScores )

	self.LastShuffleMode = ForceMode or self.Config.BalanceMode

	return self.ShufflingModes[ ForceMode or self.Config.BalanceMode ]( self, Gamerules, Targets, TeamMembers )
end

--[[
	Stores a player's score.
]]
function Plugin:StoreScoreData( Player )
	local Client = Server.GetOwner( Player )

	if not Client then return end

	if Client.GetIsVirtual and Client:GetIsVirtual() then return end
	if not Client.GetUserId then return end

	local Round = self.Round

	assert( Round, "Attempted to store score data before round data was created!" )
	
	local ID = tostring( Client:GetUserId() )

	local Mode = self.Config.BalanceMode

	if Mode == self.MODE_ELO then
		Mode = self.Config.FallbackMode
	end

	local DataTable = self.ScoreData.Rounds[ Round ]

	if Mode == self.MODE_SCORE then
		--Don't want to store data about 0 score players, we'll just randomise them.
		if Player.score and Player.score > 0 then
			DataTable[ ID ] = Player.score
		end
	elseif Mode == self.MODE_KDR then
		local Kills = Player.GetKills and Player:GetKills() or 0
		local Deaths = Player.GetDeaths and Player:GetDeaths() or 0

		--0 KDR is useless, let's just randomise them.
		if Kills == 0 then return end 
		--Don't want a NaN ratio!
		if Deaths == 0 then Deaths = 1 end

		DataTable[ ID ] = Kills / Deaths
	end
end

--[[
	Gets the average of all stored round scores for the given Steam ID.
]]
function Plugin:GetAverageScoreData( ID )
	ID = tostring( ID )
	
	local ScoreData = self.ScoreData
	local RoundData = ScoreData.Rounds
	local StoredRounds = #RoundData

	local Score = 0
	local StoredForPlayer = 0

	for i = 1, StoredRounds do
		local CurScore = RoundData[ i ][ ID ]

		if CurScore then
			Score = Score + CurScore
			StoredForPlayer = StoredForPlayer + 1
		end
	end

	if StoredForPlayer == 0 then return 0 end

	return Score / StoredForPlayer
end

--[[
	Saves the score data for previous rounds.
]]
function Plugin:SaveScoreData()
	local Success, Err = Shine.SaveJSONFile( self.ScoreData, "config://shine\\temp\\voterandom_scores.json" )

	if not Success then
		Notify( "Error writing voterandom scoredata file: "..Err )	

		return
	end
end

--[[
	Loads the stored data from the file, will load on plugin load only.
]]
function Plugin:LoadScoreData()
	local Data = Shine.LoadJSONFile( "config://shine\\temp\\voterandom_scores.json" )

	return Data or { Round = 1, Rounds = {} }
end

--[[
	Moves a single player onto a random team.
]]
function Plugin:JoinRandomTeam( Player )
	local Gamerules = GetGamerules()
	if not Gamerules then return end

	local Team1 = Gamerules:GetTeam( kTeam1Index ):GetNumPlayers()
	local Team2 = Gamerules:GetTeam( kTeam2Index ):GetNumPlayers()
	
	if Team1 < Team2 then
		Gamerules:JoinTeam( Player, 1, nil, true )
	elseif Team2 < Team1 then
		Gamerules:JoinTeam( Player, 2, nil, true )
	else
		if Random() < 0.5 then
			Gamerules:JoinTeam( Player, 1, nil, true )
		else
			Gamerules:JoinTeam( Player, 2, nil, true )
		end
	end
end

function Plugin:SetGameState( Gamerules, NewState, OldState )
	if not self.Config.AlwaysEnabled then return end
	if NewState ~= kGameState.Countdown then return end
	if Shared.GetEntitiesWithClassname( "Player" ):GetSize() < self.Config.MinPlayers then
		return
	end

	if self.DoneStartShuffle then return end

	self.DoneStartShuffle = true

	local OldValue = self.Config.IgnoreCommanders

	--Force ignoring commanders.
	self.Config.IgnoreCommanders = true

	self:Notify( nil, "Shuffling teams %s due to server settings.", true, ModeStrings.Action[ self.Config.BalanceMode ] )

	self:ShuffleTeams()

	self.Config.IgnoreCommanders = OldValue
end

function Plugin:EndGame( Gamerules, WinningTeam )
	self.DoneStartShuffle = false

	local Players = Shine.GetAllPlayers()
	local BalanceMode = self.Config.BalanceMode
	local IsScoreBased = BalanceMode == self.MODE_SCORE or BalanceMode == self.MODE_KDR

	if BalanceMode == self.MODE_ELO then
		local Fallback = self.Config.FallbackMode
		IsScoreBased = Fallback == self.MODE_SCORE or Fallback == self.MODE_KDR
	end

	if IsScoreBased then
		local ScoreData = self.ScoreData
		local Round = ScoreData.Round
		local RoundData = ScoreData.Rounds

		RoundData[ Round ] = RoundData[ Round ] or {}

		TableEmpty( RoundData[ Round ] )

		self.Round = Round

		ScoreData.Round = ( Round % self.Config.MaxStoredRounds ) + 1
	end

	--Reset the randomised state of all players and store score data.
	for i = 1, #Players do
		local Player = Players[ i ]
		
		if Player then
			Player.ShineRandomised = nil
			
			if IsScoreBased then
				self:StoreScoreData( Player )
			end
		end
	end

	self:SaveScoreData()

	--If we're always enabled, we'll shuffle on round start.
	if self.Config.AlwaysEnabled then
		return
	end

	if self.RandomOnNextRound then
		self.RandomOnNextRound = false
		
		Shine.Timer.Simple( 15, function()
			local MapVote = Shine.Plugins.mapvote

			if MapVote and MapVote.Enabled and MapVote:IsEndVote() then
				self.ForceRandom = true

				return
			end

			self:Notify( nil, "Shuffling teams %s due to random vote.", true, ModeStrings.Action[ self.Config.BalanceMode ] )

			self:ShuffleTeams()
			
			self.ForceRandom = true
		end )
	else
		if not Shine.Timer.Exists( self.RandomEndTimer ) then
			self.ForceRandom = false
		else
			self.ForceRandom = false
			Shine.Timer.Simple( 15, function()
				local MapVote = Shine.Plugins.mapvote

				if not ( MapVote and MapVote.Enabled and MapVote:IsEndVote() ) then
					self:Notify( nil, "Shuffling teams %s due to random vote.", true, ModeStrings.Action[ self.Config.BalanceMode ] )
					
					self:ShuffleTeams()
				end

				if Shine.Timer.Exists( self.RandomEndTimer ) then
					self.ForceRandom = true
				end
			end )
		end
	end
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce then return end
	if not self.ForceRandom then return end

	local Gamestate = Gamerules:GetGameState()

	--We'll do a mass balance, don't worry about them yet.
	if self.Config.AlwaysEnabled and Gamestate == kGameState.NotStarted then return end

	--Don't block them from going back to the ready room at the end of the round.
	if Gamestate == kGameState.Team1Won or Gamestate == kGameState.Team2Won or GameState == kGameState.Draw then return end

	local MapVote = Shine.Plugins.mapvote

	if MapVote and MapVote.Enabled then
		if MapVote:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce ) == false then
			return false
		end
	end
	
	local ChatName = Shine.Config.ChatName

	local Team = Player:GetTeamNumber()

	local Client = Player:GetClient()
	if not Client then return false end

	local Time = Shared.GetTime()

	local Immune = Shine:HasAccess( Client, "sh_randomimmune" )
	local OnPlayingTeam = Team == 1 or Team == 2

	if not Player.ShineRandomised then
		--Do not allow cheating the system.
		if OnPlayingTeam and not ( Immune or not self.Config.BlockTeams ) then 
			if not Player.NextShineNotify or Player.NextShineNotify < Time then --Spamming F4 shouldn't spam messages...
				self:Notify( Player, "You cannot switch teams. %s teams are enabled.", true, ModeStrings.Mode[ self.Config.BalanceMode ] )

				Player.NextShineNotify = Time + 5
			end

			return false
		end 

		if Team == 0 or Team == 3 then --They're going from the ready room/spectate to a team.
			Player.ShineRandomised = true --Prevent an infinite loop!
			
			if not Immune then
				self:Notify( Player, "You have been placed on a random team." )

				self:JoinRandomTeam( Player )

				return false
			end
		end
	else
		--Do not allow cheating the system.
		if OnPlayingTeam and not ( Immune or not self.Config.BlockTeams ) then 
			if not Player.NextShineNotify or Player.NextShineNotify < Time then
				self:Notify( Player, "You cannot switch teams. %s teams are enabled.", true, ModeStrings.Mode[ self.Config.BalanceMode ] )

				Player.NextShineNotify = Time + 5
			end

			return false
		end

		if Team == 0 or Team == 3 then --They came from ready room or spectate, i.e, we just randomised them.
			Player.ShineRandomised = nil

			return 
		end
	end
end

function Plugin:ClientDisconnect( Client )
	self.Vote:ClientDisconnect( Client )
end

function Plugin:GetVotesNeeded()
	return Ceil( Shared.GetEntitiesWithClassname( "Player" ):GetSize() * self.Config.PercentNeeded )
end

function Plugin:CanStartVote()
	return Shared.GetEntitiesWithClassname( "Player" ):GetSize() >= self.Config.MinPlayers and self.NextVote < Shared.GetTime() and not self.RandomOnNextRound
end

--[[
	Adds a player's vote to the counter.
]]
function Plugin:AddVote( Client )
	if self.Config.AlwaysEnabled then
		return false, StringFormat( "%s teams are forced to enabled by the server.", ModeStrings.Mode[ self.Config.BalanceMode ] )
	end

	if not Client then Client = "Console" end
	
	local Allow, Error = Shine.Hook.Call( "OnVoteStart", "random" )
	if Allow == false then
		return false, Error
	end

	if not self:CanStartVote() then
		local String = ModeStrings.ModeLower[ self.Config.BalanceMode ]

		String = String:sub( 1, 1 ) == "E" and "an "..String or "a "..String

		return false, StringFormat( "You cannot start %s teams vote at this time.", String ) 
	end
	
	local Success = self.Vote:AddVote( Client )
	if not Success then 
		return false, StringFormat( "You have already voted for %s teams.", ModeStrings.ModeLower[ self.Config.BalanceMode ] ) 
	end

	return true
end

--[[
	Timeout the vote.
]]
function Plugin:Think()
	self.Vote:Think()
end

--[[
	Applies the configured randomise settings.
	If set to random teams on next round, it queues a force of random teams for the next round.
	If set to a time duration, it enables random teams and queues the disabling of them.
]]
function Plugin:ApplyRandomSettings()
	local ChatName = Shine.Config.ChatName

	self.RandomApplied = true
	Shine.Timer.Simple( 0, function()
		self.RandomApplied = false
	end )

	--Set up random teams for the next round.
	if self.Config.RandomOnNextRound then
		local Gamerules = GetGamerules()

		--Game hasn't started, apply the random settings now, as the next round is the one that's going to start...
		if not Gamerules:GetGameStarted() then
			self:Notify( nil, "Shuffling teams %s for the next round...", 
				true, ModeStrings.Action[ self.Config.BalanceMode ] )

			self:ShuffleTeams()

			self.ForceRandom = true

			return
		end

		self:Notify( nil, "Teams will be forced to %s in the next round.", 
			true, ModeStrings.ModeLower[ self.Config.BalanceMode ] )

		self.RandomOnNextRound = true

		return
	end

	--Set up random teams now and make them last for the given time in the config.
	local Duration = self.Config.Duration * 60

	self.ForceRandom = true
	self.NextVote = Shared.GetTime() + Duration

	self:Notify( nil, "%s teams have been enabled for the next %s.", 
		true, ModeStrings.Mode[ self.Config.BalanceMode ], string.TimeToString( Duration ) )

	if self.Config.InstantForce then
		local Gamerules = GetGamerules()

		local Started = Gamerules:GetGameStarted()

		if Started then
			self:Notify( nil, "Shuffling teams %s and restarting round...", 
				true, ModeStrings.Action[ self.Config.BalanceMode ] )

			self:ShuffleTeams( true )
		else
			self:Notify( nil, "Shuffling teams %s...", 
				true, ModeStrings.Action[ self.Config.BalanceMode ] )

			self:ShuffleTeams()
		end

		if Started then
			Gamerules:ResetGame()
		end
	end

	Shine.Timer.Create( self.RandomEndTimer, Duration, 1, function()
		self:Notify( nil, "%s team enforcing disabled, time limit reached.", true, ModeStrings.Mode[ self.LastShuffleMode or self.Config.BalanceMode ] )
		self.ForceRandom = false
	end )
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function VoteRandom( Client )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		local Success, Err = self:AddVote( Client )	

		if Success then
			local VotesNeeded = self.Vote:GetVotesNeeded()

			if not self.RandomApplied then
				self:Notify( nil, "%s voted to force %s teams (%s more votes needed).", 
					true, PlayerName, ModeStrings.ModeLower[ self.Config.BalanceMode ], VotesNeeded )
			end

			--Somehow it didn't apply random settings??
			if VotesNeeded == 0 and not self.RandomApplied then
				self:ApplyRandomSettings()
			end

			return
		end

		if Player then
			Shine:NotifyError( Player, Err )
		else
			Notify( Err )
		end
	end
	Commands.VoteRandomCommand = Shine:RegisterCommand( "sh_voterandom", { "random", "voterandom", "randomvote" }, VoteRandom, true )
	Commands.VoteRandomCommand:Help( "Votes to force random teams." )

	local function ForceRandomTeams( Client, Enable )
		if Enable then
			self.Vote:Reset()
			self:ApplyRandomSettings()
		else
			Shine.Timer.Destroy( self.RandomEndTimer )
			self.Vote:Reset()

			self.RandomOnNextRound = false
			self.ForceRandom = false

			self.Config.AlwaysEnabled = false

			self:Notify( nil, "%s teams were disabled.", true, ModeStrings.Mode[ self.Config.BalanceMode ] )
		end
	end
	Commands.ForceRandomCommand = Shine:RegisterCommand( "sh_enablerandom", "enablerandom", ForceRandomTeams )
	Commands.ForceRandomCommand:AddParam{ Type = "boolean", Optional = true, Default = function() return not self.ForceRandom end }
	Commands.ForceRandomCommand:Help( "<true/false> Enables or disables forcing random teams." )
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "voterandom", Plugin )
