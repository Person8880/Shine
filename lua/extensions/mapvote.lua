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
local Max = math.max
local Random = math.random
local InRange = math.InRange

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "MapVote.json"

Plugin.Commands = {}

Plugin.VoteTimer = "MapVote"
Plugin.NextMapTimer = "MapVoteNext"

local function istable( Table )
	return type( Table ) == "table"
end

function Plugin:Initialise()
	self.Vote = self.Vote or {}
	self.Vote.Nominated = {} --Table of nominated maps.

	self.Vote.VotedToStart = {} --Table of players that have voted to start a vote.
	self.Vote.StartVotes = 0 --Number of votes made to start a map vote.

	self.Vote.Votes = 0 --Number of map votes that have taken place.
	self.Vote.Voted = {} --Table of players that have voted for a map.
	self.Vote.TotalVotes = 0 --Number of votes in the current map vote. 

	self.NextMap = {}
	self.NextMap.Extends = 0

	local Cycle = MapCycle_GetMapCycle and MapCycle_GetMapCycle()

	if not Cycle then
		local CycleFile = io.open( "config://MapCycle.json", "r" )

		if CycleFile then
			Cycle = Decode( CycleFile:read( "*all" ) )

			CycleFile:close()
		end
	end

	if self.Config.GetMapsFromMapCycle then
		local Maps = Cycle and Cycle.maps

		if Maps then
			self.Config.Maps = {}
			local ConfigMaps = self.Config.Maps

			for i = 1, #Maps do
				local Map = Maps[ i ]
				if istable( Map ) then
					ConfigMaps[ Map.map ] = true
				else
					ConfigMaps[ Map ] = true
				end
			end
		end
	end

	self:CreateCommands()

	if self.Config.EnableNextMapVote then
		local Time = Shared.GetTime()
		local CycleTime = Cycle and ( Cycle.time * 60 ) or ( kCombatTimeLimit * 60 ) or 1800

		Shine.Timer.Create( self.NextMapTimer, ( CycleTime * self.Config.NextMapVote ) - Time, 1, function()
			local Players = Shine.GetAllPlayers()
			if #Players > 0 then
				self:StartVote( true )
			end
		end )
	end

	self.MapCycle = Cycle

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		GetMapsFromMapCycle = true, --Get the valid votemaps directly from the mapcycle file.
		Maps = { --Valid votemaps if you do not wish to get them from the map cycle.
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
		ChangeDelay = 10, --Time in seconds to wait before changing map after a vote (gives time for veto)
		VoteDelay = 10, --Time to wait in minutes after map change/vote fail before voting can occur.

		ShowVoteChoices = true, --Show who votes for what map.
		MaxOptions = 4, --Max number of options to provide.
		
		AllowExtend = true, --Allow going to the same map to be an option.
		ExtendTime = 15, --Time in minutes to extend the map.
		MaxExtends = 1, --Maximum number of map extensions.

		TieFails = false, --A tie means the vote fails.
		ChooseRandomOnTie = true, --Choose randomly between the tied maps. If not, a revote is called.
		MaxRevotes = 1, --Maximum number of revotes.

		EnableNextMapVote = true, --Enables the vote to choose the next map.
		NextMapVote = 0.5, --How far into a game to begin a vote for the next map.
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
	Prevents the map from cycling if we've extended the current one.
]]
function Plugin:ShouldCycleMap()
	if self:VoteStarted() then return false end --Do not allow map change whilst a vote is running.

	local Winner = self.NextMap.Winner
	if not Winner then return end

	local Time = Shared.GetTime()

	--if self.Vote.GraceTime and self.Vote.GraceTime > Time then return false end
	
	if Winner == Shared.GetMapName() then
		if Shared.GetTime() < self.NextMap.ExtendTime then 
			return false 
		end
	end
end

--[[
	Prevents the map from changing if we've extended the current one.
	If we've chosen a map from the next map vote, then we override the cycle and switch to it instead.
]]
function Plugin:OnCycleMap()
	if self:VoteStarted() then return false end --Do not allow map change whilst a vote is running.

	local Time = Shared.GetTime()

	local Winner = self.NextMap.Winner

	if not Winner then return end

	--if self.Vote.GraceTime and self.Vote.GraceTime > Time then return false end

	local CurMap = Shared.GetMapName()

	if Winner == CurMap and Time < self.NextMap.ExtendTime then return false end

	if Winner ~= CurMap then
		MapCycle_ChangeMap( Winner )

		return false
	end
end

--[[
	Send the map vote text and map options when a new player connects and a map vote is in progress.
]]
function Plugin:ClientConnect( Client )
	if not self:VoteStarted() then return end

	local Duration = Floor( self.Vote.EndTime - Shared.GetTime() )
	if Duration <= 5 then return end
	
	local Player = Client:GetControllingPlayer()

	if not Player then
		if Duration < 10 then return end

		--Delay so the client can be assigned a player.
		Shine.Timer.Simple( 5, function()
			Duration = Duration - 5
			local Player = Client and Client:GetControllingPlayer()

			if not Player then return end
			
			local OptionsText = self.Vote.OptionsText

			Shine:SendVoteOptions( Player, OptionsText, Duration, self.NextMap.Voting )
		end )

		return
	end

	local OptionsText = self.Vote.OptionsText

	Shine:SendVoteOptions( Player, OptionsText, Duration, self.NextMap.Voting )
end

local function GetMapName( Map )
    if type( Map ) == "table" and Map.map then
        return Map.map
    end

    return Map
end

--[[
	Returns the next map in the map cycle or the map that's been voted for next.
]]
function Plugin:GetNextMap()
	local CurMap = Shared.GetMapName()

	local Winner = self.NextMap.Winner

	if Winner and Winner ~= CurMap then return Winner end --Winner decided.
	
	local Cycle = self.MapCycle

	if not Cycle then return "unknown" end --No map cycle?

	local Maps = Cycle.maps
	local NumMaps = #Maps
	local Index = 0

	for i = #Maps, 1, -1 do
		if GetMapName( Maps[ i ] ) == CurMap then
			Index = i + 1
			break
		end
	end
	
	if Index > NumMaps then
		Index = 1
	end
	
	return Maps[ Index ]
end

--[[
	On end of the round, notify players of the remaining time.
]]
function Plugin:EndGame()
	Shine.Timer.Simple( 10, function()
		local Time = Shared.GetTime()

		local Cycle = self.MapCycle
		local CycleTime = Cycle and ( Cycle.time * 60 ) or ( kCombatTimeLimit and kCombatTimeLimit * 60 )

		if not CycleTime then return end

		local ExtendTime = self.NextMap.ExtendTime

		local TimeLeft = CycleTime - Time

		if ExtendTime then
			TimeLeft = ExtendTime - Time
		end
		
		local Message = "There is %s remaining on this map."

		if TimeLeft <= 0 then
			if not self:VoteStarted() then
				Shine:Notify( nil, "", "", "The server will now cycle to %s.", true, self:GetNextMap() )

				return
			else
				Message = "Waiting on map vote to change map."
			end
		end

		Shine:Notify( nil, "", "", Message, true, string.TimeToString( TimeLeft ) )
	end )
end

function Plugin:IsNextMapVote()
	return self.NextMap.Voting or false
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
	Gets the corresponding map in the current vote matching a string.
	Allows players to do !vote summit or !vote docking etc.
]]
function Plugin:GetVoteChoice( Map )
	local Choices = self.Vote.VoteList

	if Choices[ Map ] then return Map end

	Map = Map:lower()

	if Map == "ns2_" or Map == "ns2" then return nil end --Not specific enough.

	for Name, Votes in pairs( Choices ) do
		if Name:lower():find( Map ) then
			return Name
		end
	end

	return nil
end

--[[
	Adds a vote for a given map in the map vote.
]]
function Plugin:AddVote( Client, Map, Revote )
	if not Client then Client = "Console" end
	
	if not self:VoteStarted() then return false, "no vote in progress" end
	if self.Vote.Voted[ Client ] and not Revote then return false, "already voted" end

	local Choice = self:GetVoteChoice( Map )
	if not Choice then return false, "map is not a valid choice" end
	
	if Revote then
		local OldVote = self.Vote.Voted[ Client ]
		if OldVote then
			self.Vote.VoteList[ OldVote ] = self.Vote.VoteList[ OldVote ] - 1
		end
	end

	local CurVotes = self.Vote.VoteList[ Choice ]
	self.Vote.VoteList[ Choice ] = CurVotes + 1

	if not Revote then
		self.Vote.TotalVotes = self.Vote.TotalVotes + 1
	end

	self.Vote.Voted[ Client ] = Choice

	return true, Choice
end

--[[
	Sets up and begins a map vote.
]]
function Plugin:StartVote( NextMap )
	if self:VoteStarted() then return end
	if not NextMap and not self:CanStartVote() then return end

	if not NextMap then
		self.Vote.StartVotes = 0 --Reset votes to start.
		self.Vote.VotedToStart = {} --Reset those who voted to start.
	end

	self.Vote.TotalVotes = 0 --Reset votes.
	self.Vote.Voted = {} --Reset who has voted from last time.	
	
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

	local CurMap = Shared.GetMapName()
	local AllowCurMap = self.Config.AllowExtend and self.NextMap.Extends < self.Config.MaxExtends

	--If we have map extension enabled, ensure it's in the vote list.
	if AllowCurMap then
		if AllMaps[ CurMap ] then
			MapList[ #MapList + 1 ] = CurMap
			AllMaps[ CurMap ] = nil
		end
	end

	local RemainingSpaces = MaxOptions - #MapList

	--If we didn't have enough nominations to fill the vote list, add maps from the allowed list that weren't nominated.
	if RemainingSpaces > 0 then
		if next( AllMaps ) then
			for Name, _ in RandomPairs( AllMaps ) do
				if Name ~= CurMap then
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
	local VoteLength = self.Config.VoteLength * 60

	--This is when the map vote should end and collect its results.
	local EndTime = Shared.GetTime() + VoteLength

	--Store these values for new clients.
	self.Vote.EndTime = EndTime
	self.Vote.OptionsText = OptionsText

	if NextMap then
		self.NextMap.Voting = true
	end

	Shine.Timer.Simple( 0.1, function()
		local ChatName = Shine.Config.ChatName
		--Notify players the map vote has started.
		if not NextMap then
			Shine:Notify( nil, "Vote", ChatName, "Map vote started." )
		else
			Shine:Notify( nil, "Vote", ChatName, "Voting for the next map has started." )
		end
	end )
	
	Shine:SendVoteOptions( nil, OptionsText, VoteLength, NextMap )

	--This timer runs when the vote ends, and sorts out the results.
	Shine.Timer.Create( self.VoteTimer, VoteLength, 1, function()
		local TotalVotes = self.Vote.TotalVotes
		local MaxVotes = 0
		local Voted = self.Vote.VoteList

		local Time = Shared.GetTime()

		local ChatName = Shine.Config.ChatName

		--No one voted :|
		if TotalVotes == 0 then
			Shine:Notify( nil, "Vote", ChatName, "No votes made. Map vote failed." )
			self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
			
			if NextMap then
				self.NextMap.Voting = false
			end

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

		--Only one map won.
		if Count == 1 then
			if not NextMap then
				Shine:Notify( nil, "Vote", ChatName, "%s won the vote with %s/%s votes.", true, Results[ 1 ], MaxVotes, TotalVotes )

				local Choice = Results[ 1 ]
				if Choice == Shared.GetMapName() then
					local ExtendTime = self.Config.ExtendTime * 60
					
					Shine:Notify( nil, "Vote", ChatName, "Extending the current map for another %s.", true, string.TimeToString( ExtendTime ) )
					
					self.NextMap.Winner = Choice
					self.NextMap.ExtendTime = Time + ExtendTime
					self.NextMap.Extends = self.NextMap.Extends + 1

					Shine.Timer.Destroy( self.NextMapTimer )
					Shine.Timer.Create( self.NextMapTimer, ExtendTime * 0.5, 1, function()
						self:StartVote( true )
					end )

					return
				end

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

			self.NextMap.Winner = Results[ 1 ]

			if Results[ 1 ] == Shared.GetMapName() then
				local ExtendTime = self.Config.ExtendTime * 60

				self.NextMap.ExtendTime = Time + ExtendTime
				self.NextMap.Extends = self.NextMap.Extends + 1

				Shine:Notify( nil, "Vote", ChatName, "Extending the current map for another %s.", true, string.TimeToString( ExtendTime ) )

				Shine.Timer.Simple( ExtendTime * self.Config.NextMapVote, function()
					local Players = Shine.GetAllPlayers()
					if #Players > 0 then
						self:StartVote( true )
					end
				end )
			else
				Shine:Notify( nil, "Vote", ChatName, "%s won the vote. Setting next map to %s.", true, Results[ 1 ], Results[ 1 ] )
			end

			self.NextMap.Voting = false

			self.Vote.GraceTime = Time + self.Config.ChangeDelay * 2

			return
		end

		--Now we're in the case where there's more than one map that won.
		--If we're set to fail on a tie, then fail.
		if self.Config.TieFails then
			Shine:Notify( nil, "Vote", ChatName, "Votes were tied. Map vote failed." )
			self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )

			if NextMap then
				self.NextMap.Voting = false
			end

			return
		end

		--We're set to choose randomly between them on tie.
		if self.Config.ChooseRandomOnTie then
			local NewCount = Count * 100 --If there were 3 tied choices, we're looking at numbers between 1 and 300.
			local RandNum = Random( 1, Count )
			local Choice = ""

			for i = 1, Count do
				if InRange( ( i - 1 ) * 100, i * 100, ( i + 1 ) * 100 ) then --Is this map the winner?
					Choice = Results[ i ]
					break
				end 
			end

			local Tied = TableConcat( Results, ", " )

			self.Vote.CanVeto = true --Allow vetos.

			Shine:Notify( nil, "Vote", ChatName, "Votes were tied between %s.", true, Tied )
			Shine:Notify( nil, "Vote", ChatName, "Choosing random map..." )
			Shine:Notify( nil, "Vote", ChatName, "Chosen map: %s.", true, Choice )

			if not NextMap then
				if Choice == Shared.GetMapName() then
					local ExtendTime = self.Config.ExtendTime * 60
					
					Shine:Notify( nil, "Vote", ChatName, "Extending the current map for another %s.", true, string.TimeToString( ExtendTime ) )
					
					self.NextMap.Winner = Choice
					self.NextMap.ExtendTime = Shared.GetTime() + ExtendTime
					self.NextMap.Extends = self.NextMap.Extends + 1

					Shine.Timer.Destroy( self.NextMapTimer )
					Shine.Timer.Create( self.NextMapTimer, ExtendTime * 0.5, 1, function()
						self:StartVote( true )
					end )

					return
				end

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

			self.NextMap.Winner = Choice

			if Choice == Shared.GetMapName() then
				local ExtendTime = self.Config.ExtendTime * 60
				
				self.NextMap.ExtendTime = Time + ExtendTime
				self.NextMap.Extends = self.NextMap.Extends + 1

				Shine:Notify( nil, "Vote", ChatName, "Extending the current map for another %s.", true, string.TimeToString( ExtendTime ) )

				Shine.Timer.Simple( ExtendTime * self.Config.NextMapVote, function()
					local Players = Shine.GetAllPlayers()
					if #Players > 0 then
						self:StartVote( true )
					end
				end )

				self.Vote.GraceTime = Time + self.Config.ChangeDelay * 2
			else
				Shine:Notify( nil, "Vote", ChatName, "%s won the vote. Setting next map to %s.", true, Choice, Choice )
			end

			self.NextMap.Voting = false

			return
		end

		Shine.Timer.Destroy( self.VoteTimer ) --Now we're dealing with the case where we want to revote on fail, so we need to get rid of the timer.

		if self.Vote.Votes < self.Config.MaxRevotes then --We can revote, so do so.
			Shine:Notify( nil, "Vote", ChatName, "Votes were tied, map vote failed. Beginning revote." )

			self.Vote.Votes = self.Vote.Votes + 1

			Shine.Timer.Simple( 0, function()
				self:StartVote( NextMap )
			end )
		else
			Shine:Notify( nil, "Vote", ChatName, "Votes were tied, map vote failed. Revote limit reached." )

			if not NextMap then
				self.Vote.NextVote = Shared.GetTime() + ( self.Config.VoteDelay * 60 )
			end

			self.Vote.GraceTime = Time + self.Config.ChangeDelay * 2

			if NextMap then
				self.NextMap.Voting = false
			end
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

		if Count >= ( self.Config.MaxOptions - 1 ) then
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
			local VotesNeeded = Max( self:GetVotesNeededToStart() - TotalVotes - 1, 0 )

			Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s voted to change the map (%s more votes needed).", true, PlayerName, VotesNeeded )

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

		local Success, Err = self:AddVote( Client, Map )

		if Success then
			if self.Config.ShowVoteChoices then
				local NumForThis = self.Vote.VoteList[ Err ]
				local NumTotal = self.Vote.TotalVotes

				Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s voted for %s (%s for this, %s)", true, 
					PlayerName, Err, 
					NumForThis > 1 and NumForThis.." votes" or "1 vote", 
					NumTotal > 1 and NumTotal.." total votes" or "1 total vote" 
				)
			end

			return
		end

		if Err == "already voted" then
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "You have already voted. Type !revote <map> to change your vote." )
			else
				Notify( "You have already voted. Type !revote <map> to change your vote." )
			end
		else
			if Player then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "%s is not a valid map choice.", true, Map )
			else
				Notify( StringFormat( "%s is not a valid map choice.", Map ) )
			end
		end
	end
	Commands.VoteCommand = Shine:RegisterCommand( "sh_vote", "vote", Vote, true )
	Commands.VoteCommand:AddParam{ Type = "string", Error = "Please specify a map to vote for." }
	Commands.VoteCommand:Help( "<mapname> Vote for a particular map in the active map vote." )

	local function ReVote( Client, Map )
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

		local Success, Err = self:AddVote( Client, Map, true )

		if Success then
			if self.Config.ShowVoteChoices then
				local NumForThis = self.Vote.VoteList[ Err ]
				local NumTotal = self.Vote.TotalVotes

				Shine:Notify( nil, "Vote", Shine.Config.ChatName, "%s revoted for %s (%s for this, %s)", true, 
					PlayerName, Err, 
					NumForThis > 1 and NumForThis.." votes" or "1 vote", 
					NumTotal > 1 and NumTotal.." total votes" or "1 total vote" 
				)
			end

			return
		end

		if Player then
			Shine:Notify( Player, "Error", Shine.Config.ChatName, "%s is not a valid map choice.", true, Map )
		else
			Notify( StringFormat( "%s is not a valid map choice.", Map ) )
		end
	end
	Commands.ReVoteCommand = Shine:RegisterCommand( "sh_revote", "revote", ReVote, true )
	Commands.ReVoteCommand:AddParam{ Type = "string", Error = "Please specify your new map choice." }
	Commands.ReVoteCommand:Help( "<mapname> Change your vote to another map in the vote." )

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

	local function TimeLeft( Client )
		local Cycle = self.MapCycle
		local Player = Client and Client:GetControllingPlayer()

		local CycleTime = Cycle and ( Cycle.time * 60 ) or ( kCombatTimeLimit and kCombatTimeLimit * 60 )

		if not CycleTime then
			if Player then
				Shine:Notify( Player, "", "", "The server does not have a map cycle. No timelimit given." )
			else
				Notify( "The server does not have a map cycle. No timelimit given." )
			end

			return
		end

		local ExtendTime = self.NextMap.ExtendTime

		local TimeLeft = ExtendTime and ( ExtendTime - Shared.GetTime() ) or ( CycleTime - Shared.GetTime() )
		local Message = "%s remaining on this map."

		if TimeLeft <= 0 then
			Message = "Map will change on round end."
		end

		if Player then
			Shine:Notify( Player, "", "", Message, true, string.TimeToString( TimeLeft ) )
		else
			Notify( StringFormat( Message, string.TimeToString( TimeLeft ) ) )
		end
	end
	Commands.TimeLeftCommand = Shine:RegisterCommand( "sh_timeleft", "timeleft", TimeLeft, true )
	Commands.TimeLeftCommand:Help( "Displays the remaining time for the current map." )
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
