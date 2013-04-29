--[[
	Shine vote random plugin.
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
		VoteTimeout = 60, --Time after the last vote before the vote resets.
	}

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

	local Changed

	if self.Config.InstantForce == nil then
		self.Config.InstantForce = true

		Changed = true
	end

	if self.Config.VoteTimeout == nil then
		self.Config.VoteTimeout = 60
		Changed = true
	end

	if Changed then self:SaveConfig() end
end

--[[
	Shuffles everyone on the server into random teams.
]]
function Plugin:ShuffleTeams()
	local Players = Shine.GetRandomPlayerList()

	local Gamerules = GetGamerules()

	if not Gamerules then return end

	local Targets = {}

	for i = 1, #Players do
		local Player = Players[ i ]

		if Player then
			if Player.ResetScores then
				Player:ResetScores()
			end
			
			local Client = Player:GetClient()

			if Client then
				if not Shine:HasAccess( Client, "sh_randomimmune" ) then
					Targets[ #Targets + 1 ] = Player
				end
			end
		end
	end

	local NumPlayers = #Targets

	local TeamSequence = math.GenerateSequence( NumPlayers, { 1, 2 } )

	for i = 1, NumPlayers do
		local Player = Targets[ i ]
		if Player then
			Gamerules:JoinTeam( Player, TeamSequence[ i ], nil, true )
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
		else
			self.ForceRandom = false
			Shine.Timer.Simple( 10, function()
				Shine:Notify( nil, "Random", Shine.Config.ChatName, "Shuffling teams due to random vote." )

				self:ShuffleTeams()

				if Shine.Timer.Exists( self.RandomEndTimer ) then
					self.ForceRandom = true
				end
			end )
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

	local Client = Player:GetClient()
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

	self.LastVoted = Shared.GetTime()

	if self.Votes >= self:GetVotesNeeded() then
		self:ApplyRandomSettings()
	end

	return true
end

--[[
	Timeout the vote. 1 minute and no votes should reset it.
]]
function Plugin:Think()
	if self.LastVoted and ( ( Shared.GetTime() - self.LastVoted ) > self.Config.VoteTimeout ) then
		if self.Votes > 0 then
			self.Voted = {}
			self.Votes = 0
		end		
	end 
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

	self.RandomApplied = true
	Shine.Timer.Simple( 0, function()
		self.RandomApplied = false
	end )

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

		self:ShuffleTeams()

		GetGamerules():ResetGame()
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

			--Somehow it didn't apply random settings??
			if VotesNeeded == 0 and not self.RandomApplied then
				self:ApplyRandomSettings()
			end

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
