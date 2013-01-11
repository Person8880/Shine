--[[
	Shine vote random plugin.
]]

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
Plugin.ConfigName = "VoteRandom.json"

Plugin.Commands = {}

Plugin.RandomEndTimer = "VoteRandomTimer"

function Plugin:Initialise()
	self:CreateCommands()

	self.NextVote = 0
	self.Voted = {}
	self.Votes = 0

	self.ForceRandomEnd = 0 --Time based.
	self.RandomOnNextRound = false --Round based.

	self.ForceRandom = false

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		MinPlayers = 10, --Minimum number of players on the server to enable random voting.
		PercentNeeded = 0.75, --Percentage of the server population needing to vote for it to succeed.
		Duration = 15, --Time to force people onto random teams for after a random vote. Also time between successful votes.
		RandomOnNextRound = true, --If false, then random teams are forced for a duration instead.
		InstantForce = true, --Forces a shuffle of everyone instantly when the vote succeeds (for time based).
	}

	if Save then
		local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

		if not PluginConfig then
			Notify( "Error writing voterandom config file: "..Err )	

			return	
		end

		PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

		Notify( "Shine voterandom config file created." )

		PluginConfig:close()
	end
end

function Plugin:SaveConfig()
	local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

	if not PluginConfig then
		Notify( "Error writing voterandom config file: "..Err )	

		return	
	end

	PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

	Notify( "Shine voterandom config file saved." )

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

	if self.Config.InstantForce == nil then
		self.Config.InstantForce = true
		self:SaveConfig()
	end
end

--[[
	Shuffles everyone on the server into random teams.
]]
function Plugin:ShuffleTeams()
	local Players = Shine.GetRandomPlayerList()

	local Gamerules = GetGamerules()

	if not Gamerules then return end

	for i = 1, #Players do
		local Player = Players[ i ]
		if Player then
			local Client = Server.GetOwner( Player )

			if Client then
				if not Shine:HasAccess( Client, "sh_randomimmune" ) then
					Gamerules:JoinTeam( Player, ( i % 2 ) + 1, nil, true )
				end
			end
		end
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
			Shine:Notify( nil, "Random", Shine.Config.ChatName, "Shuffling teams due to random vote." )

			self:ShuffleTeams()
			
			self.ForceRandom = true
		end )
	else
		if not Shine.Timer.Exists( self.RandomEndTimer ) then
			self.ForceRandom = false
		end
	end
	local Players = Shine.GetAllPlayers()

	--Reset the randomised state of all players.
	for i = 1, #Players do
		local Player = Players[ i ]
		
		if Player then
			Player.ShineRandomised = nil
		end
	end
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce then return end
	if not self.ForceRandom then return end
	
	local ChatName = Shine.Config.ChatName

	local Team = Player:GetTeamNumber()

	local Client = Server.GetOwner( Player )
	if not Client then return false end

	local Time = Shared.GetTime()

	local Immune = Shine:HasAccess( Client, "sh_randomimmune" )

	if not Player.ShineRandomised then
		--Do not allow cheating the system.
		if Team == 1 or Team == 2 and not Immune then 
			if not Player.NextShineNotify or Player.NextShineNotify < Shared.GetTime() then --Spamming F4 shouldn't spam messages...
				Shine:Notify( Player, "Random", ChatName, "You cannot switch teams. Random teams are enabled." )

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
		if Team == 1 or Team == 2 and not Immune then 
			if not Player.NextShineNotify or Player.NextShineNotify < Shared.GetTime() then
				Shine:Notify( Player, "Random", ChatName, "You cannot switch teams. Random teams are enabled." )

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

function Plugin:GetVotesNeeded()
	return Ceil( #EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) ) * self.Config.PercentNeeded )
end

function Plugin:CanStartVote()
	return #EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) ) >= self.Config.MinPlayers and self.NextVote < Shared.GetTime() and not self.RandomOnNextRound
end

--[[
	Adds a player's vote to the counter.
]]
function Plugin:AddVote( Client )
	if not Client then Client = "Console" end
	
	if not self:CanStartVote() then return false, "can't start" end
	if self.Voted[ Client ] then return false, "already voted" end

	self.Voted[ Client ] = true
	self.Votes = self.Votes + 1

	if self.Votes >= self:GetVotesNeeded() then
		self:ApplyRandomSettings()
	end

	return true
end

--[[
	Applies the configured randomise settings.
	If set to random teams on next round, it queues a force of random teams for the next round.
	If set to a time duration, it enables random teams and queues the disabling of them.
]]
function Plugin:ApplyRandomSettings()
	self.Voted = {}
	self.Votes = 0
	local ChatName = Shine.Config.ChatName

	--Set up random teams for the next round.
	if self.Config.RandomOnNextRound then
		Shine:Notify( nil, "Random", ChatName, "Teams will be forced to random in the next round." )

		self.RandomOnNextRound = true

		return
	end

	--Set up random teams now and make them last for the given time in the config.
	local Duration = self.Config.Duration * 60

	self.ForceRandom = true
	self.NextVote = Shared.GetTime() + Duration

	Shine:Notify( nil, "Random", ChatName, "Random teams have been enabled for the next %s.", true, string.TimeToString( Duration ) )

	if self.Config.InstantForce then
		Shine:Notify( nil, "Random", ChatName, "Shuffling teams and restarting round..." )

		GetGamerules():ResetGame()

		self:ShuffleTeams()
	end

	Shine.Timer.Create( self.RandomEndTimer, Duration, 1, function()
		Shine:Notify( nil, "Random", ChatName, "Random teams disabled, time limit reached." )
		self.ForceRandom = false
	end )
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function VoteRandom( Client )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		local Success, Err = self:AddVote( Client )

		local Votes = self.Votes

		if Success then
			local VotesNeeded = Max( self:GetVotesNeeded() - Votes - 1, 0 )

			Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s voted to force random teams (%s more votes needed).", true, PlayerName, VotesNeeded )

			return
		end

		if Err == "can't start" then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "You cannot start a random teams vote at this time." )
			else
				Notify( "You cannot start a random teams vote at this time." )
			end
		else
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "You have already voted for random teams." )
			else
				Notify( "You have already voted for random teams." )
			end
		end
	end
	Commands.VoteRandomCommand = Shine:RegisterCommand( "sh_voterandom", { "random", "voterandom", "randomvote" }, VoteRandom, true )
	Commands.VoteRandomCommand:Help( "Votes to force random teams." )

	local function ForceRandomTeams( Client, Enable )
		if Enable then
			self:ApplyRandomSettings()
		else
			self.Votes = 0
			self.Voted = {}

			Shine.Timer.Destroy( self.RandomEndTimer )

			self.RandomOnNextRound = false
			self.ForceRandom = false

			Shine:Notify( nil, "Random", Shine.Config.ChatName, "Random teams were disabled." )
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
