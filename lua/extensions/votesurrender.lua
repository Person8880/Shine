--[[
	Shine surrender vote plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format

local Ceil = math.ceil
local Floor = math.floor
local Max = math.max
local Random = math.random

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteSurrender.json"

Plugin.Commands = {}

function Plugin:Initialise()
	self.Votes = {}
	self.Votes[ 1 ] = 0 --Marines
	self.Votes[ 2 ] = 0 --Aliens

	self.Voted = {}
	self.Voted[ 1 ] = {}
	self.Voted[ 2 ] = {}

	self.LastVoted = {}

	self.NextVote = 0

	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		PercentNeeded = 0.75, --Percentage of the team needing to vote in order to surrender.
		VoteDelay = 10, --Time after round start before surrender vote is available
		MinPlayers = 6, --Min players needed for voting to be enabled.
		VoteTimeout = 120, --How long after no votes before the vote should reset?
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing votesurrender config file: "..Err )	

			return	
		end

		Notify( "Shine votesurrender config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing votesurrender config file: "..Err )	

		return	
	end

	Notify( "Shine votesurrender config file updated." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig

	local Changed

	if self.Config.VoteTimeout == nil then
		self.Config.VoteTimeout = 120
		Changed = true
	end

	if Changed then self:SaveConfig() end
end

--[[
	Runs when the game state is set.
	If a round has started, we set the next vote time to current time + delay.
]]
function Plugin:SetGameState( Gamerules, State, OldState )
	if State == kGameState.Started then
		self.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
	end
end

function Plugin:GetVotesNeeded( Team )
	return Max( 1, Ceil( #GetEntitiesForTeam( "Player", Team ) * self.Config.PercentNeeded ) )
end

--[[
	Make sure we only vote when a round has started.
]]
function Plugin:CanStartVote( Team )
	local Gamerules = GetGamerules()

	if not Gamerules then return false end

	local State = Gamerules:GetGameState()

	return State == kGameState.Started and #GetEntitiesForTeam( "Player", Team ) >= self.Config.MinPlayers and self.NextVote < Shared.GetTime()
end

function Plugin:AddVote( Client, Team )
	if not Client then return end

	if Team ~= 1 and Team ~= 2 then return false, "spectators can't surrender!" end --Would be a fun bug...
	
	if not self:CanStartVote( Team ) then return false, "can't start" end
	if self.Voted[ Team ][ Client ] then return false, "already voted" end

	self.Voted[ Team ][ Client ] = true
	self.Votes[ Team ] = self.Votes[ Team ] + 1

	self.LastVoted[ Team ] = Shared.GetTime()

	if self.Votes[ Team ] >= self:GetVotesNeeded( Team ) then
		self:Surrender( Team )
	end

	return true
end

--[[
	Timeout the vote. 1 minute and no votes should reset it.
]]
function Plugin:Think()
	for i = 1, 2 do
		if self.LastVoted[ i ] and ( ( Shared.GetTime() - self.LastVoted[ i ] ) > self.Config.VoteTimeout ) then
			if self.Votes[ i ] > 0 then
				self.Voted[ i ] = {}
				self.Votes[ i ] = 0
			end		
		end 
	end
end

--[[
	Makes the given team surrender (moves them to the ready room).
]]
function Plugin:Surrender( Team )
	local Players = GetEntitiesForTeam( "Player", Team )

	local Gamerules = GetGamerules()

	if not Gamerules then return end

	Gamerules:EndGame( Team == 1 and Gamerules.team2 or Gamerules.team1 )

	Shine.Timer.Simple( 0.1, function()
		Shine:Notify( nil, "Vote", Shine.Config.ChatName, "The %s team has voted to surrender.", true, Team == 1 and "marine" or "alien" )
	end )

	self.Votes[ Team ] = 0
	self.Voted[ Team ] = {}
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function VoteSurrender( Client )
		if not Client then return end

		local Player = Client:GetControllingPlayer()
		if not Player then return end

		local Team = Player:GetTeamNumber()

		local Votes = self.Votes[ Team ]
		
		local Success, Err = self:AddVote( Client, Team )

		if Success then
			local Players = GetEntitiesForTeam( "Player", Team )
			local VotesNeeded = Max( self:GetVotesNeeded( Team ) - Votes - 1, 0 )

			Shine:Notify( Players, "Vote", Shine.Config.ChatName, "%s voted to surrender (%s more votes needed).", true, Player:GetName(), VotesNeeded )

			return
		end

		if Err == "already voted" then
			Shine:Notify( Player, "Error", Shine.Config.ChatName, "You have already voted to surrender." )
		else
			Shine:Notify( Player, "Error", Shine.Config.ChatName, "You cannot start a surrender vote at this time." )
		end
	end
	Commands.VoteSurrenderCommand = Shine:RegisterCommand( "sh_votesurrender", { "surrender", "votesurrender", "surrendervote" }, VoteSurrender, true )
	Commands.VoteSurrenderCommand:Help( "Votes to surrender the round." )
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "votesurrender", Plugin )
