--[[
	Shine map voting plugin.
]]

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format

local TableConcat = table.concat
local TableContains = table.contains

local Ceil = math.ceil
local Floor = math.floor
local Random = math.random
local InRange = math.InRange

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "MapVote.json"

Plugin.Commands = {}

Plugin.VoteTimer = "MapVote"
Plugin.NotifyTimer = "MapVoteNotify"

function Plugin:Initialise()
	self.Vote = self.Vote or {}
	self.Vote.Nominated = {} --Table of nominated maps.

	self.Vote.VotedToStart = {} --Table of players that have voted to start a vote.
	self.Vote.StartVotes = 0 --Number of votes made to start a map vote.

	self.Vote.Votes = 0 --Number of map votes that have taken place.
	self.Vote.Voted = {} --Table of players that have voted for a map.
	self.Vote.TotalVotes = 0 --Number of votes in the current map vote. 

	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		Maps = { --Valid votemaps.
			ns2_veil = true,
			ns2_summit = true,
			ns2_docking = true,
			ns2_mineshaft = true,
			ns2_refinery = true,
			ns2_tram = true,
		},
		MinPlayers = 10, --Minimum number of players needed to begin a map vote.
		PercentToStart = 0.6, --Percentage of people needing to vote to change to start a vote.

		VoteLength = 2, --Time in minutes a vote should last before failing.
		NotifyInterval = 30, --Time in seconds to notify players of the ongoing map vote.
		ChangeDelay = 10, --Time in seconds to wait before changing map after a vote (gives time for veto)
		VoteDelay = 10, --Time to wait in minutes after map change/vote fail before voting can occur.

		ShowVoteChoices = true, --Show who votes for what map.
		MaxOptions = 4, --Max number of options to provide.
		
		AllowExtend = true, --Allow going to the same map to be an option.

		TieFails = false, --A tie means the vote fails.
		ChooseRandomOnTie = true, --Choose randomly between the tied maps. If not, a revote is called.
		MaxRevotes = 1 --Maximum number of revotes.
	}

	self.Vote = {}

	if self.Enabled == nil then
		self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
	end

	if Save then
		local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

		if not PluginConfig then
			Notify( "Error writing mapvote config file: "..Err )	

			return	
		end

		PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

		Notify( "Shine mapvote config file created." )

		PluginConfig:close()
	end
end

function Plugin:SaveConfig()
	local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

	if not PluginConfig then
		Notify( "Error writing mapvote config file: "..Err )	

		return	
	end

	PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

	Shine:Print( "Shine mapvote config file saved." )

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

	self.Vote = {}

	if self.Enabled == nil then
		self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
	end
end

--[[
	Returns the number of votes needed to begin a map vote.
]]
function Plugin:GetVotesNeededToStart()
	return Ceil( #EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) ) * self.Config.PercentToStart )
end

--[[
	Returns whether a map vote is in progress.
]]
function Plugin:VoteStarted()
	return Shine.Timer.Exists( self.VoteTimer )
end

--[[
	Returns whether a map vote can start.
]]
function Plugin:CanStartVote()
	return #EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) ) >= self.Config.MinPlayers and self.Vote.NextVote < Shared.GetTime()
end

--[[
	Adds a vote to begin a map vote.
]]
function Plugin:AddStartVote( Client )
	if not Client then Client = "Console" end
	
	if self:VoteStarted() then return false, "vote in progress" end
	if self.Vote.VotedToStart[ Client ] then return false, "already voted" end
	
	self.Vote.StartVotes = self.Vote.StartVotes + 1

	self.Vote.VotedToStart[ Client ] = true

	local VotesNeeded = self:GetVotesNeededToStart() 

	if self.Vote.StartVotes >= VotesNeeded then
		self:StartVote()
	end

	return true
end

--[[
	Adds a vote for a given map in the map vote.
]]
function Plugin:AddVote( Client, Map )
	if not Client then Client = "Console" end
	
	if not self:VoteStarted() then return false, "no vote in progress" end
	if self.Vote.Voted[ Client ] then return false, "already voted" end
	if not self.Vote.VoteList[ Map ] then return false, "map is not a valid choice" end
	
	local CurVotes = self.Vote.VoteList[ Map ]
	self.Vote.VoteList[ Map ] = CurVotes + 1
	self.Vote.TotalVotes = self.Vote.TotalVotes + 1

	self.Vote.Voted[ Client ] = true

	return true
end

--[[
	Sets up and begins a map vote.
]]
function Plugin:StartVote()
	if not self:CanStartVote() then return end

	self.Vote.StartVotes = 0 --Reset votes to start.
	self.Vote.TotalVotes = 0 --Reset votes.
	self.Vote.Voted = {} --Reset who has voted from last time.
	self.Vote.VotedToStart = {} --Reset those who voted to start.
	
	--First we compile the list of maps that are going to be available to vote for.
	local MaxOptions = self.Config.MaxOptions
	local Nominations = self.Vote.Nominated

	local AllMaps = table.duplicate( self.Config.Maps )
	local MapList = {}

	--We first look in the nominations, and enter those into the list.
	for i = 1, #Nominations do
		local Nominee = Nominations[ i ]
		MapList[ i ] = Nominee
		AllMaps[ Nominee ] = nil --Remove this from the list of all maps as it's now in our vote list.
	end

	local RemainingSpaces = MaxOptions - #MapList

	--If we didn't have enough nominations to fill the vote list, add maps from the allowed list that weren't nominated.
	if RemainingSpaces > 0 then
		if next( AllMaps ) then
			for Name, _ in RandomPairs( AllMaps ) do
				if self.Config.AllowExtend or Name ~= Shared.GetMapName() then
					MapList[ #MapList + 1 ] = Name
				end

				if #MapList == MaxOptions then
					break
				end
			end
		end
	end

	self.Vote.VoteList = {} --Our table of maps that are being voted for.
	for i = 1, #MapList do
		self.Vote.VoteList[ MapList[ i ] ] = 0 --Set each one to start with 0 votes.
	end

	--Get the list of maps as a comma separated string to print.
	local OptionsText = TableConcat( MapList, ", " )

	--Get our notification interval, length of the vote in seconds and the number of times to repeat our notification.
	local Interval = self.Config.NotifyInterval
	local VoteLength = self.Config.VoteLength * 60
	local Reps = Floor( VoteLength / Interval ) - 1

	--This is when the map vote should end and collect its results.
	local EndTime = Shared.GetTime() + VoteLength

	Shine.Timer.Simple( 0.1, function()
		local ChatName = Shine.Config.ChatName

		--Notify players the map vote has started.
		Shine:Notify( nil, "Vote", ChatName, "Map vote started. Available maps: " )
		Shine:Notify( nil, "Vote", ChatName, OptionsText )
		Shine:Notify( nil, "Vote", ChatName, "Type !vote <mapname> to vote for a map." )
	end )

	--Create our notification timer, it will inform the players of how long is left and remind them the vote is still going.
	Shine.Timer.Create( self.NotifyTimer, Interval, Reps, function()
		local TimeLeft = Ceil( EndTime - Shared.GetTime() )
		if TimeLeft <= 0 then return end

		local ChatName = Shine.Config.ChatName

		local TimeLeftString = string.TimeToString( TimeLeft )

		Shine:Notify( nil, "Vote", ChatName, "Map vote in progress. Available maps:" )
		Shine:Notify( nil, "Vote", ChatName, OptionsText )
		Shine:Notify( nil, "Vote", ChatName, "Type !vote <mapname> to vote for a map." )
		Shine:Notify( nil, "Vote", ChatName, "Time left to vote: %s.", true, TimeLeftString )
	end )

	--This timer runs when the vote ends, and sorts out the results.
	Shine.Timer.Create( self.VoteTimer, VoteLength, 1, function()
		local TotalVotes = self.Vote.TotalVotes
		local MaxVotes = 0
		local Voted = self.Vote.VoteList

		local ChatName = Shine.Config.ChatName

		--No one voted :|
		if TotalVotes == 0 then
			Shine:Notify( nil, "Vote", ChatName, "No votes made. Map vote failed." )
			self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )

			return
		end

		local Results = {}

		--Compile the list of maps with the most votes, if two have the same amount they'll both be in the list.
		for Map, Votes in pairs( Voted ) do
			if Votes >= MaxVotes then
				MaxVotes = Votes
			end
		end

		for Map, Votes in pairs( Voted ) do
			if Votes == MaxVotes then
				Results[ #Results + 1 ] = Map
			end
		end

		local Count = #Results

		--Only one map won, let's change to it!
		if Count == 1 then
			Shine:Notify( nil, "Vote", ChatName, "%s won the vote with %s/%s votes.", true, Results[ 1 ], MaxVotes, TotalVotes )
			Shine:Notify( nil, "Vote", ChatName, "Map changing in %s.", true, string.TimeToString( self.Config.ChangeDelay ) )

			self.Vote.CanVeto = true --Allow admins to cancel the change.

			--Queue the change.
			Shine.Timer.Simple( self.Config.ChangeDelay, function()
				if not self.Vote.Veto then --No one cancelled it, change map.
					MapCycle_ChangeMap( Results[ 1 ] )
				else --Someone cancelled it, set the next vote time.
					self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
					self.Vote.Veto = false
					self.Vote.CanVeto = false --Veto has no meaning anymore.
				end
			end )

			return
		end

		--Now we're in the case where there's more than one map that won.
		--If we're set to fail on a tie, then fail.
		if self.Config.TieFails then
			Shine:Notify( nil, "Vote", ChatName, "Votes were tied. Map vote failed." )
			self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )

			return
		end

		--We're set to choose randomly between them on tie.
		if self.Config.ChooseRandomOnTie then
			local NewCount = Count * 100 --If there were 3 tied choices, we're looking at numbers between 1 and 300.
			local RandNum = Random( 1, Count )
			local Choice = ""

			for i = 1, Count do
				if InRange( ( i - 1 ) * 100, i * 100, ( i + 1 ) * 100 ) then --Is this map the winner?
					Choice = MapList[ i ]
					break
				end 
			end

			local Tied = TableConcat( Results, ", " )

			self.Vote.CanVeto = true --Allow vetos.

			Shine:Notify( nil, "Vote", ChatName, "Votes were tied between %s.", true, Tied )
			Shine:Notify( nil, "Vote", ChatName, "Choosing random map..." )
			Shine:Notify( nil, "Vote", ChatName, "Chosen map: %s.", true, Choice )
			Shine:Notify( nil, "Vote", ChatName, "Map changing in %s.", true, string.TimeToString( self.Config.ChangeDelay ) )

			--Queue the change.
			Shine.Timer.Simple( self.Config.ChangeDelay, function()
				if not self.Vote.Veto then
					MapCycle_ChangeMap( Choice )
				else
					self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
					self.Vote.Veto = false
					self.Vote.CanVeto = false
				end
			end )

			return
		end

		Shine.Timer.Destroy( self.VoteTimer ) --Now we're dealing with the case where we want to revote on fail, so we need to get rid of the timer.

		if self.Vote.Votes < self.Config.MaxRevotes then --We can revote, so do so.
			Shine:Notify( nil, "Vote", ChatName, "Map vote failed. Beginning revote." )

			self.Vote.Votes = self.Vote.Votes + 1

			self:StartVote()
		else
			Shine:Notify( nil, "Vote", ChatName, "Map vote failed." )
			self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
		end
	end )
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function Nominate( Client, Map )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		if not self.Config.Maps[ Map ] then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "%s is not on the map list.", true, Map )
			else
				Notify( StringFormat( "%s is not on the map list.", Map ) )
			end

			return
		end

		if not self.Config.AllowExtend and Shared.GetMapName() == Map then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "You cannot nominate the current map." )
			else
				Notify( "You cannot nominate the current map." )
			end

			return
		end
		
		local Nominated = self.Vote.Nominated

		if TableContains( Nominated, Map ) then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "%s has already been nominated.", true, Map )
			else
				Notify( StringFormat( "%s has already been nominated.", Map ) )
			end

			return
		end

		local Count = #Nominated 

		if Count >= self.Config.MaxOptions then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "Nominations are full." )
			else
				Notify( "Nominations are full." )
			end

			return
		end

		if self:VoteStarted() then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "A vote is already in progress." )
			else
				Notify( "A vote is already in progress." )
			end

			return
		end

		Nominated[ Count + 1 ] = Map

		Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s nominated %s for a map vote.", true, PlayerName, Map )
	end
	Commands.NominateCommand = Shine:RegisterCommand( "sh_nominate", "nominate", Nominate, true )
	Commands.NominateCommand:AddParam{ Type = "string", Error = "Please specify a map name to nominate." }
	Commands.NominateCommand:Help( "<mapname> Nominates a map for the next map vote." )

	local function VoteToChange( Client )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		if not self:CanStartVote() then
			if Client then
				Shine:Notify( Client:GetControllingPlayer(), "Error", Shine.Config.ChatName, "You cannot start a map vote at this time." )
			else
				Notify( "You cannot start a map vote at this time." )
			end

			return
		end

		local TotalVotes = self.Vote.StartVotes

		local Success, Err = self:AddStartVote( Client )
		if Success then
			local VotesNeeded = self:GetVotesNeededToStart()

			Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s voted to change the map (%s more votes needed).", true, PlayerName, VotesNeeded - TotalVotes - 1 )

			return
		end
		
		if Err == "already voted" then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "You have already voted to begin a map vote." )
			else
				Notify( "You have already voted to begin a map vote." )
			end
		else
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "A map vote is already in progress." )
			else
				Notify( "A map vote is already in progress." )
			end
		end
	end
	Commands.StartVoteCommand = Shine:RegisterCommand( "sh_votemap", { "rtv", "votemap", "mapvote" }, VoteToChange, true )
	Commands.StartVoteCommand:Help( "Begin a vote to change the map." )

	local function Vote( Client, Map )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		if not self:VoteStarted() then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "There is no map vote in progress." )
			else
				Notify( "There is no map vote in progress." )
			end

			return
		end

		if not self.Vote.VoteList[ Map ] then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "%s is not a choice in the vote.", true, Map )
			else
				Notify( StringFormat( "%s is not a choice in the vote.", Map ) )
			end

			return
		end

		local Success, Err = self:AddVote( Client, Map )

		if Success then
			if self.Config.ShowVoteChoices then
				Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s voted for %s (%s/%s votes).", true, PlayerName, Map, self.Vote.VoteList[ Map ], self.Vote.TotalVotes )
			end

			return
		end

		if Player then
			Shine:Notify( Player, "Error", Shine.Config.ChatName, "You have already voted." )
		else
			Notify( "You have already voted." )
		end
	end
	Commands.VoteCommand = Shine:RegisterCommand( "sh_vote", "vote", Vote, true )
	Commands.VoteCommand:AddParam{ Type = "string", Error = "Please specify a map to vote for." }
	Commands.VoteCommand:Help( "<mapname> Vote for a particular map in the active map vote." )

	local function Veto( Client )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		if not self.Vote.CanVeto then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "There is no map change in progress." )
			else
				Notify( "There is no map change in progress." )
			end

			return
		end

		self.Vote.Veto = true

		Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s cancelled the map change.", true, PlayerName )
	end
	Commands.VetoCommand = Shine:RegisterCommand( "sh_veto", "veto", Veto )
	Commands.VetoCommand:Help( "Cancels a map change from a successful map vote." )
end

function Plugin:Cleanup()
	if self:VoteStarted() then
		Shine:Notify( nil, "Vote", Shine.Config.ChatName, "Map vote plugin disabled. Current vote cancelled." )
	end

	Shine.Timer.Destroy( self.VoteTimer )
	Shine.Timer.Destroy( self.NotifyTimer )

	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "mapvote", Plugin )
