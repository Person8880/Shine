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
Plugin.Version = "1.2"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteSurrender.json"

Plugin.Commands = {}

function Plugin:Initialise()
	self.Votes = {
		Shine:CreateVote( function() return self:GetVotesNeeded( 1 ) end, function() self:Surrender( 1 ) end,
		function( Vote )
			if Vote.LastVoted and Shared.GetTime() - Vote.LastVoted > self.Config.VoteTimeout then
				Vote:Reset()
			end
		end ),

		Shine:CreateVote( function() return self:GetVotesNeeded( 2 ) end, function() self:Surrender( 2 ) end,
		function( Vote )
			if Vote.LastVoted and Shared.GetTime() - Vote.LastVoted > self.Config.VoteTimeout then
				Vote:Reset()
			end
		end )
	}

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
	local Success, Err = self.Votes[ Team ]:AddVote( Client )

	if not Success then return false, Err end

	return true
end

--[[
	Timeout the vote. 1 minute and no votes should reset it.
]]
function Plugin:Think()
	for i = 1, 2 do
		self.Votes[ i ]:Think()
	end
end

--[[
	Remove a client's vote if they disconnect!
]]
function Plugin:ClientDisconnect( Client )
	for i = 1, 2 do
		self.Votes[ i ]:ClientDisconnect( Client )
	end
end

--[[
	Remove a client's vote if they leave the team!
]]
function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if not Player then return end
	local Client = Player:GetClient()

	if not Client then return end

	local Vote = self.Votes[ OldTeam ]

	if Vote then
		Vote:RemoveVote( Client )
	end
end

--[[
	Makes the given team surrender (moves them to the ready room).
]]
function Plugin:Surrender( Team )
	local Players = GetEntitiesForTeam( "Player", Team )

	local Gamerules = GetGamerules()

	if not Gamerules then return end

	Server.SendNetworkMessage( "TeamConceded", { teamNumber = Team } )

	Gamerules:EndGame( Team == 1 and Gamerules.team2 or Gamerules.team1 )
end

--[[
	Overrides the concede vote button in the NS2 request menu.
]]
function Plugin:CastVoteByPlayer( Gamerules, ID, Player )
	if not Player then return end
	if ID ~= kTechId.VoteConcedeRound then return end
	
	local Client = Player:GetClient()

	if not Client then return true end

	local Team = Player:GetTeam():GetTeamNumber()

	local Votes = self.Votes[ Team ]:GetVotes()
	
	local Success, Err = self:AddVote( Client, Team )

	if not Success then return true end --We failed to add the vote, but we should still stop it going through NS2's system...

	local VotesNeeded = Max( self:GetVotesNeeded( Team ) - Votes - 1, 0 )
	
	self:AnnounceVote( Player, Team, VotesNeeded )

	return true
end

function Plugin:AnnounceVote( Player, Team, VotesNeeded )
	local Players = GetEntitiesForTeam( "Player", Team )

	local NWMessage = {
		voterName = Player:GetName(),
		votesMoreNeeded = VotesNeeded
	}

	for i = 1, #Players do
		local Ply = Players[ i ]

		if Ply then
			Server.SendNetworkMessage( Ply, "VoteConcedeCast", NWMessage, true ) --Use NS2's built in concede, it's localised.
		end
	end
end
			
function Plugin:CreateCommands()
	local Commands = self.Commands

	local function VoteSurrender( Client )
		if not Client then return end

		local Player = Client:GetControllingPlayer()
		if not Player then return end

		local Team = Player:GetTeamNumber()

		if not self.Votes[ Team ] then
			Shine:Notify( Player, "Error", Shine.Config.ChatName, "You cannot start a surrender vote at this time." )

			return
		end

		local Votes = self.Votes[ Team ]:GetVotes()
		
		local Success, Err = self:AddVote( Client, Team )

		if Success then
			local VotesNeeded = Max( self:GetVotesNeeded( Team ) - Votes - 1, 0 )

			return self:AnnounceVote( Player, Team, VotesNeeded )
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
