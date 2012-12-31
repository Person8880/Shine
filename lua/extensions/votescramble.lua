--[[
	Shine scramble teams vote plugin.
]]

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format

local Ceil = math.ceil
local Floor = math.floor
local Random = math.random

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
		ScrambleType = self.SCRAMBLE_RANDOM --1 means random, 2 means by score.
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

function Plugin:GetVotesNeeded()
	return Ceil( #EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) ) * self.Config.PercentNeeded )
end

function Plugin:CanStartVote()
	return #EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) ) >= self.Config.MinPlayers and self.NextVote < Shared.GetTime()
end

function Plugin:AddVote( Client )
	if not Client then Client = "Console" end
	
	if not self:CanStartVote() then return false, "can't start" end
	if self.Voted[ Client ] then return false, "already voted" end

	self.Voted[ Client ] = true
	self.Votes = self.Votes + 1

	if self.Votes >= self:GetVotesNeeded() then
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

	if IgnoreComm then
		for i = 1, #Players do
			local Player = Players[ i ]
			if not Player or not Player.isa or Player:isa( "Commander" ) then
				TableRemove( Players, i )
			end
		end
	end

	if IgnoreSpectators then
		for i = 1, #Players do
			local Player = Players[ i ]
			if not Player or not Player.GetTeamNumber or Player:GetTeamNumber() == kTeamReadyRoom then
				TableRemove( Players, i )
			end
		end
	end

	local ScrambleType = self.Config.ScrambleType

	if ScrambleType == self.SCRAMBLE_RANDOM then
		TableShuffle( Players )

		for i = 1, #Players do
			Gamerules:JoinTeam( Players[ i ], ( i % 2 ) + 1 )
		end

		Shine.Timer.Simple( 0.1, function()
			Shine:Notify( nil, "Teams have been scrambled randomly." )
		end )

		self.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
		self.Voted = {}
		self.Votes = 0

		return
	end

	if ScrambleType == self.SCRAMBLE_SCORE then
		TableSort( Players, function( A, B ) return ( A.score or 0 ) > ( B.score or 0 ) end )

		for i = 1, #Players do
			Gamerules:JoinTeam( Players[ i ], ( i % 2 ) + 1 )
		end

		Shine.Timer.Simple( 0.1, function()
			Shine:Notify( nil, "Teams have been scrambled based on score." )
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
			local VotesNeeded = self:GetVotesNeeded()

			Shine:Notify( nil, "%s voted to scramble the teams (%s more votes needed).", true, PlayerName, VotesNeeded - Votes - 1 )

			return
		end

		if Err == "can't start" then
			if Player then
				Shine:Notify( Player, "You cannot start a scramble teams vote at this time." )
			else
				Notify( "You cannot start a scramble teams vote at this time." )
			end
		else
			if Player then
				Shine:Notify( Player, "You have already voted." )
			else
				Notify( "You have already voted." )
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
