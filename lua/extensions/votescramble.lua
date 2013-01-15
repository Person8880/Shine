--[[
	Shine scramble teams vote plugin.
]]

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format

local Ceil = math.ceil
local Floor = math.floor
local Max = math.max
local Random = math.random

local TableRandom = table.ChooseRandom
local TableRemove = table.remove
local TableShuffle = table.Shuffle
local TableSort = table.sort

local Plugin = {}

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteScramble.json"

Plugin.Commands = {}

Plugin.SCRAMBLE_RANDOM = 1
Plugin.SCRAMBLE_SCORE = 2

function Plugin:Initialise()
	self:CreateCommands()
	self.NextVote = 0
	self.Voted = {}
	self.Votes = 0

	local Gamerules = GetGamerules()

	if Gamerules and Gamerules:GetGameState() == kGameState.Started then
		self.RoundStarted = true
	else
		self.RoundStarted = false
	end

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		IgnoreCommanders = true, --Don't switch commander's team.
		IgnoreSpectators = true, --Don't affect spectators.
		PercentNeeded = 0.75, --Percentage of the population needing to vote in order to scramble.
		VoteDelay = 5, --Time between successful votes
		MinPlayers = 10, --Min players needed for voting to be enabled.
		ScrambleType = self.SCRAMBLE_SCORE --1 means random, 2 means by score.
	}

	if Save then
		local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

		if not PluginConfig then
			Notify( "Error writing votescramble config file: "..Err )	

			return	
		end

		PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

		Notify( "Shine votescramble config file created." )

		PluginConfig:close()
	end
end

function Plugin:SaveConfig()
	local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

	if not PluginConfig then
		Notify( "Error writing votescramble config file: "..Err )	

		return	
	end

	PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

	Shine:Print( "Shine votescramble config file saved." )

	PluginConfig:close()
end

function Plugin:LoadConfig()
	local PluginConfig = io.open( Shine.Config.ExtensionDir..self.ConfigName, "r" )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = Decode( PluginConfig:read( "*all" ) )

	PluginConfig:close()
end

--[[
	Reset and disallow scrambling on game end.
]]
function Plugin:EndGame( Gamerules, WinningTeam )
	self.Votes = 0
	self.Voted = {}

	self.RoundStarted = false
end

--[[
	Re-enable scramble voting once the next round starts.
]]
function Plugin:SetGameState( Gamerules, State, OldState )
	if State == kGameState.Started then
		self.RoundStarted = true
	end
end

function Plugin:GetVotesNeeded()
	return Ceil( #EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) ) * self.Config.PercentNeeded )
end

function Plugin:CanStartVote()
	return self.RoundStarted and #EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) ) >= self.Config.MinPlayers and self.NextVote < Shared.GetTime()
end

function Plugin:AddVote( Client )
	if not Client then Client = "Console" end
	
	if not self:CanStartVote() then return false, "can't start" end
	if self.Voted[ Client ] then return false, "already voted" end

	self.Voted[ Client ] = true
	self.Votes = self.Votes + 1

	if self.Votes == self:GetVotesNeeded() then
		self:ScrambleTeams()
	end

	return true
end

function Plugin:ScrambleTeams()
	local Gamerules = GetGamerules()

	if not Gamerules then return end

	local Players = EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) )
	local IgnoreComm = self.Config.IgnoreCommanders
	local IgnoreSpectators = self.Config.IgnoreSpectators

	local Targets = {}
	local Clients = {}

	--Lua loops can be a pain sometimes...
	for i = 1, #Players do
		local Player = Players[ i ]

		if Player then
			--Either we're not ignoring commanders, or they're not a commander.
			if not IgnoreComm or not ( Player.isa and Player:isa( "Commander" ) ) then 
				local Team = Player.GetTeamNumber and Player:GetTeamNumber() or 0
				
				--Either we're not ignoring spectators, or they're not a spectator.
				if not IgnoreSpectators or not ( Team == 0 or Team == 3 ) then
					local Client = Player:GetClient()

					--They have a valid client object.
					if Client then
						--They're not immune, so finally add them.
						if not Shine:HasAccess( Client, "sh_scrambleimmune" ) then
							Targets[ #Targets + 1 ] = Player
							Clients[ #Clients + 1 ] = Client
						end
					end
				end
			end
		end
	end

	local ScrambleType = self.Config.ScrambleType

	if ScrambleType == self.SCRAMBLE_RANDOM then
		TableShuffle( Targets )

		local NumTargets = #Targets

		local TeamSequence = math.GenerateSequence( NumTargets, { 1, 2 } )

		for i = 1, NumTargets do
			Gamerules:JoinTeam( Targets[ i ], TeamSequence[ i ], nil, true )
		end

		--Account for imbalance caused by immune players.
		Shine.Timer.Simple( 1, function()
			local Aliens = Gamerules:GetTeam( 2 ):GetNumPlayers()
			local Marines = Gamerules:GetTeam( 1 ):GetNumPlayers()

			local Imbalance = 0
			local Team = 1

			if Aliens > Marines then
				Imbalance = Floor( ( Aliens - Marines ) * 0.5 )
			else
				Imbalance = Floor( ( Marines - Aliens ) * 0.5 )
				Team = 2
			end

			if Imbalance >= 1 then
				for i = 1, Imbalance do
					local TargetClient, Index = TableRandom( Clients )

					if TargetClient then
						local Target = TargetClient:GetControllingPlayer()
						Gamerules:JoinTeam( Target, Team, nil, true )
						TableRemove( Clients, Index )
					end
				end
			end
		end )

		Shine.Timer.Simple( 0.1, function()
			Shine:Notify( nil, "Scramble", Shine.Config.ChatName, "Teams have been scrambled randomly." )
		end )

		self.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
		self.Voted = {}
		self.Votes = 0

		return
	end

	if ScrambleType == self.SCRAMBLE_SCORE then
		TableSort( Targets, function( A, B ) return ( A.score or 0 ) > ( B.score or 0 ) end )

		local NumTargets = #Targets

		for i = 1, NumTargets do
			Gamerules:JoinTeam( Targets[ i ], ( i % 2 ) + 1, nil, true )
		end

		Shine.Timer.Simple( 1, function()
			local Aliens = Gamerules:GetTeam( 2 ):GetNumPlayers()
			local Marines = Gamerules:GetTeam( 1 ):GetNumPlayers()

			local Imbalance = 0
			local Team = 1

			if Aliens > Marines then
				Imbalance = Floor( ( Aliens - Marines ) * 0.5 )
			else
				Imbalance = Floor( ( Marines - Aliens ) * 0.5 )
				Team = 2
			end

			if Imbalance >= 1 then
				for i = 1, Imbalance do
					local TargetClient = Clients[ NumTargets - ( i - 1 ) ]

					if TargetClient then
						local Target = TargetClient:GetControllingPlayer()
						Gamerules:JoinTeam( Target, Team, nil, true )
					end
				end
			end
		end )

		Shine.Timer.Simple( 0.1, function()
			Shine:Notify( nil, "Scramble", Shine.Config.ChatName, "Teams have been scrambled based on score." )
		end )

		self.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
		self.Voted = {}
		self.Votes = 0

		return
	end
end

function Plugin:CreateCommands()
	local Commands = self.Commands
	
	local function VoteScramble( Client )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		local Success, Err = self:AddVote( Client )

		local Votes = self.Votes

		if Success then
			local VotesNeeded = Max( self:GetVotesNeeded() - Votes - 1, 0 )

			Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s voted to scramble the teams (%s more votes needed).", true, PlayerName, VotesNeeded )

			return
		end

		if Err == "can't start" then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "You cannot start a scramble teams vote at this time." )
			else
				Notify( "You cannot start a scramble teams vote at this time." )
			end
		else
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "You have already voted for a team scramble." )
			else
				Notify( "You have already voted for a team scramble." )
			end
		end
	end
	Commands.VoteScrambleCommand = Shine:RegisterCommand( "sh_votescramble", { "votescramble", "scramble", "scrambleteams", "scramblevote" }, VoteScramble, true )
	Commands.VoteScrambleCommand:Help( "Votes to scramble the teams." )
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "votescramble", Plugin )
