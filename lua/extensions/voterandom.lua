--[[
	Shine vote random plugin.
]]

local Shine = Shine

local Notify = Shared.Message

local Ceil = math.ceil
local Clamp = math.Clamp
local Floor = math.floor
local Max = math.max
local next = next
local pairs = pairs
local Random = math.random
local StringFormat = string.format
local TableSort = table.sort

local Plugin = {}
Plugin.Version = "1.5"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteRandom.json"

Plugin.Commands = {}

Plugin.RandomEndTimer = "VoteRandomTimer"

Plugin.MODE_RANDOM = 1
Plugin.MODE_SCORE = 2
Plugin.MODE_ELO = 3

local ModeStrings = {
	Mode = {
		"Random",
		"Score based",
		"ELO based"
	},
	ModeLower = {
		"random",
		"score based",
		"ELO based"
	},
	Action = {
		"randomly",
		"based on score",
		"based on ELO"
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
	BlockTeams = true, --Should team changing/joining be blocked after an instant force or in a round?
	IgnoreCommanders = false, --Should the plugin ignore commanders when switching?
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

	self.ForceRandom = false

	self.ScoreData = {}

	self.Enabled = true

	return true
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

	self.Config.BalanceMode = Clamp( Floor( self.Config.BalanceMode or 1 ), 1, 3 )
end

Plugin.ShufflingModes = {
	function( self, Gamerules, Targets ) --Random only.
		local NumPlayers = #Targets

		local TeamSequence = math.GenerateSequence( NumPlayers, { 1, 2 } )

		for i = 1, NumPlayers do
			local Player = Targets[ i ]
			if Player then
				Gamerules:JoinTeam( Player, TeamSequence[ i ], nil, true )
			end
		end
	end,

	function( self, Gamerules, Targets ) --Score based if available, random if not.
		local ScoreData = self.ScoreData

		local ScoreTable = {}
		local RandomTable = {}

		for i = 1, #Targets do
			local Player = Targets[ i ]

			if Player then
				local Client = Player:GetClient()

				if Client then
					local ID = Client:GetUserId()

					local Data = ScoreData[ ID ]

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

			for i = 1, ScoreSortCount do
				Gamerules:JoinTeam( ScoreTable[ i ].Player, ( i % 2 ) + 1, nil, true )
			end
		end

		local RandomTableCount = #RandomTable

		if RandomTableCount > 0 then
			local TeamSequence = math.GenerateSequence( RandomTableCount, { 1, 2 } )

			for i = 1, RandomTableCount do
				Gamerules:JoinTeam( RandomTable[ i ], TeamSequence[ i ], nil, true )
			end
		end
	end,

	function( self, Gamerules, Targets ) --NS2Stats ELO based.
		if not RBPS then return self.ShufflingModes[ 1 ]( self, Gamerules, Targets ) end

		RBPS:autoArrangeSetELOs()

		if not next( RBPSwebPlayers ) then
			Shine:Print( "[ELO Vote] NS2Stats does not have any web data for players. Using random based sorting instead." )

			return self.ShufflingModes[ 1 ]( self, Gamerules, Targets )
		end
		
		local Players = RBPS.Players

		local ELOSort = {}
		local Count = 0

		local Sorted = {}

		for Index, Player in pairs( Players ) do
			local MELO = Player.marine_ELO
			local AELO = Player.alien_ELO

			local ID = Player.steamId

			local Client = Shine.GetClientByNS2ID( tonumber( ID ) )
			local Ply = Client:GetControllingPlayer()

			if Ply then
				Count = Count + 1
				ELOSort[ Count ] = { Player = Ply, ELO = ( MELO + AELO ) * 0.5 } --Average ELO, otherwise this gets way too messy.
				Sorted[ Ply ] = true
			end
		end

		TableSort( ELOSort, function( A, B ) return A.ELO > B.ELO end )

		for i = 1, Count do
			if ELOSort[ i ] then
				Gamerules:JoinTeam( ELOSort[ i ].Player, ( i % 2 ) + 1, nil, true )
			end
		end

		local Players = Shine.GetAllPlayers()
		local Count = #Players - Count

		local TeamSequence = math.GenerateSequence( Count, { 1, 2 } )
		local SequenceNum = 0

		for i = 1, #Players do
			local Player = Players[ i ]

			if Player and not Sorted[ Player ] then
				SequenceNum = SequenceNum + 1
				Gamerules:JoinTeam( Player, TeamSequence[ SequenceNum ], nil, true )
			end
		end
	end
}

--[[
	Shuffles everyone on the server into random teams.
]]
function Plugin:ShuffleTeams( ResetScores )
	local Players = Shine.GetRandomPlayerList()

	local Gamerules = GetGamerules()

	if not Gamerules then return end

	local Targets = {}

	for i = 1, #Players do
		local Player = Players[ i ]

		if Player then
			if Player.ResetScores and ResetScores then
				Player:ResetScores()
			end

			local Commander = Player:isa( "Commander" ) and self.Config.IgnoreCommanders
			
			local Client = Player:GetClient()

			if Client then
				if not Shine:HasAccess( Client, "sh_randomimmune" ) and not Commander then
					Targets[ #Targets + 1 ] = Player
				end
			end
		end
	end

	self.ShufflingModes[ self.Config.BalanceMode ]( self, Gamerules, Targets )
end

--[[
	Stores a player's score.
]]
function Plugin:StoreScoreData( Player )
	local Client = Player:GetClient()

	if not Client then return end
	
	local ID = Client:GetUserId()

	--Don't want to store data about 0 score players, we'll just randomise them.
	if Player.score and Player.score > 0 then
		self.ScoreData[ ID ] = Player.score
	end
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

function Plugin:EndGame( Gamerules, WinningTeam )
	if self.RandomOnNextRound then
		self.RandomOnNextRound = false
		
		Shine.Timer.Simple( 10, function()
			Shine:Notify( nil, "Random", Shine.Config.ChatName, "Shuffling teams %s due to random vote.", true, ModeStrings.Action[ self.Config.BalanceMode ] )

			self:ShuffleTeams()
			
			self.ForceRandom = true
		end )
	else
		if not Shine.Timer.Exists( self.RandomEndTimer ) then
			self.ForceRandom = false
		else
			self.ForceRandom = false
			Shine.Timer.Simple( 10, function()
				Shine:Notify( nil, "Random", Shine.Config.ChatName, "Shuffling teams %s due to random vote.", true, ModeStrings.Action[ self.Config.BalanceMode ] )

				self:ShuffleTeams()

				if Shine.Timer.Exists( self.RandomEndTimer ) then
					self.ForceRandom = true
				end
			end )
		end
	end
	local Players = Shine.GetAllPlayers()
	local IsScoreBased = self.Config.BalanceMode == self.MODE_SCORE

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
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce then return end
	if not self.ForceRandom then return end
	
	local ChatName = Shine.Config.ChatName

	local Team = Player:GetTeamNumber()

	local Client = Player:GetClient()
	if not Client then return false end

	local Time = Shared.GetTime()

	local Immune = Shine:HasAccess( Client, "sh_randomimmune" )

	if not Player.ShineRandomised then
		--Do not allow cheating the system.
		if Team == 1 or Team == 2 and not ( Immune or not self.Config.BlockTeams ) then 
			if not Player.NextShineNotify or Player.NextShineNotify < Time then --Spamming F4 shouldn't spam messages...
				Shine:Notify( Player, "Random", ChatName, "You cannot switch teams. %s teams are enabled.", true, ModeStrings.Mode[ self.Config.BalanceMode ] )

				Player.NextShineNotify = Time + 5
			end

			return false
		end 

		if Team == 0 or Team == 3 then --They're going from the ready room/spectate to a team.
			Player.ShineRandomised = true --Prevent an infinite loop!
			
			if not Immune then
				Shine:Notify( Player, "Random", ChatName, "You have been placed on a random team." )

				self:JoinRandomTeam( Player )

				return false
			end
		end
	else
		--Do not allow cheating the system.
		if Team == 1 or Team == 2 and not ( Immune or not self.Config.BlockTeams ) then 
			if not Player.NextShineNotify or Player.NextShineNotify < Time then
				Shine:Notify( Player, "Random", ChatName, "You cannot switch teams. %s teams are enabled.", true, ModeStrings.Mode[ self.Config.BalanceMode ] )

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
	if not Client then Client = "Console" end
	
	local Result = Shine.Hook.Call( "OnVoteStart", "random" )
	if Result then 
		if not Result[ 1 ] then return false, Result[ 2 ] end
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
			Shine:Notify( nil, "Random", ChatName, "Shuffling teams %s for the next round...", 
				true, ModeStrings.Action[ self.Config.BalanceMode ] )

			self:ShuffleTeams()

			self.ForceRandom = true

			return
		end

		Shine:Notify( nil, "Random", ChatName, "Teams will be forced to %s in the next round.", 
			true, ModeStrings.ModeLower[ self.Config.BalanceMode ] )

		self.RandomOnNextRound = true

		return
	end

	--Set up random teams now and make them last for the given time in the config.
	local Duration = self.Config.Duration * 60

	self.ForceRandom = true
	self.NextVote = Shared.GetTime() + Duration

	Shine:Notify( nil, "Random", ChatName, "%s teams have been enabled for the next %s.", 
		true, ModeStrings.Mode[ self.Config.BalanceMode ], string.TimeToString( Duration ) )

	if self.Config.InstantForce then
		local Gamerules = GetGamerules()

		local Started = Gamerules:GetGameStarted()

		if Started then
			Shine:Notify( nil, "Random", ChatName, "Shuffling teams %s and restarting round...", 
				true, ModeStrings.Action[ self.Config.BalanceMode ] )

			self:ShuffleTeams( true )
		else
			Shine:Notify( nil, "Random", ChatName, "Shuffling teams %s...", 
				true, ModeStrings.Action[ self.Config.BalanceMode ] )

			self:ShuffleTeams()
		end

		if Started then
			Gamerules:ResetGame()
		end
	end

	Shine.Timer.Create( self.RandomEndTimer, Duration, 1, function()
		Shine:Notify( nil, "Random", ChatName, "%s teams disabled, time limit reached.", true, ModeStrings.Mode[ self.Config.BalanceMode ] )
		self.ForceRandom = false
	end )
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function VoteRandom( Client )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		local Votes = self.Vote:GetVotes()

		local Success, Err = self:AddVote( Client )	

		if Success then
			local VotesNeeded = Max( self:GetVotesNeeded() - Votes - 1, 0 )

			Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s voted to force %s teams (%s more votes needed).", 
				true, PlayerName, ModeStrings.ModeLower[ self.Config.BalanceMode ], VotesNeeded )

			--Somehow it didn't apply random settings??
			if VotesNeeded == 0 and not self.RandomApplied then
				self:ApplyRandomSettings()
			end

			return
		end

		if Player then
			Shine:Notify( Player, "Error", Shine.Config.ChatName, Err )
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

			Shine:Notify( nil, "Random", Shine.Config.ChatName, "%s teams were disabled.", true, ModeStrings.Mode[ self.Config.BalanceMode ] )
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
