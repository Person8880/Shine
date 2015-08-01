--[[
	Voting logic.
]]

local Shine = Shine

local Ceil = math.ceil
local Floor = math.floor
local GetNumPlayers = Shine.GetHumanPlayerCount
local InRange = math.InRange
local next = next
local pairs = pairs
local Random = math.random
local SharedTime = Shared.GetTime
local StringFormat = string.format
local TableAsSet = table.AsSet
local TableConcat = table.concat
local TableCopy = table.Copy
local TableRemove = table.remove

local Plugin = Plugin
local IsType = Shine.IsType

function Plugin:SendVoteOptions( Client, Options, Duration, NextMap, TimeLeft, ShowTime )
	local MessageTable = {
		Options = Options,
		Duration = Duration,
		NextMap = NextMap,
		TimeLeft = TimeLeft,
		ShowTime = ShowTime
	}

	if Client then
		self:SendNetworkMessage( Client, "VoteOptions", MessageTable, true )
	else
		self:SendNetworkMessage( nil, "VoteOptions", MessageTable, true )
	end
end

--[[
	Send the map vote text and map options when a new player connects and a map vote is in progress.
]]
function Plugin:ClientConfirmConnect( Client )
	if not self:VoteStarted() then return end

	local Time = SharedTime()
	local Duration = Floor( self.Vote.EndTime - Time )
	if Duration < 5 then return end

	local OptionsText = self.Vote.OptionsText

	--Send them the current vote progress and options.
	self:SendVoteOptions( Client, OptionsText, Duration, self.NextMap.Voting,
		self:GetTimeRemaining(), not self.VoteOnEnd )

	--Update their radial menu vote counters.
	for Map, Votes in pairs( self.Vote.VoteList ) do
		self:SendMapVoteCount( Client, Map, Votes )
	end
end

function Plugin:ClientDisconnect( Client )
	self.StartingVote:ClientDisconnect( Client )
end

--[[
	Client's requesting the vote data.
]]
function Plugin:SendVoteData( Client )
	if not self:VoteStarted() then return end

	local Time = SharedTime()

	local Duration = Floor( self.Vote.EndTime - Time )

	local OptionsText = self.Vote.OptionsText

	self:SendVoteOptions( Client, OptionsText, Duration, self.NextMap.Voting,
		self:GetTimeRemaining(), not self.VoteOnEnd )
end

function Plugin:OnVoteStart( ID )
	if self.CyclingMap then
		return false, "The map is now changing, unable to start a vote."
	end

	if ID == "random" and self:IsEndVote() then
		local VoteRandom = Shine.Plugins.voterandom

		return false, StringFormat( "You cannot start %s teams vote while the map vote is running.",
			VoteRandom:GetVoteName() )
	end
end

function Plugin:IsEndVote()
	return self.VoteOnEnd and self:VoteStarted() and self:IsNextMapVote()
end

function Plugin:IsNextMapVote()
	return self.NextMap.Voting or false
end

--[[
	Returns the number of votes needed to begin a map vote.
]]
function Plugin:GetVotesNeededToStart()
	return Ceil( GetNumPlayers() * self.Config.PercentToStart )
end

--[[
	Returns whether a map vote is in progress.
]]
function Plugin:VoteStarted()
	return self:TimerExists( self.VoteTimer )
end

--[[
	Returns whether a map vote can start.
]]
function Plugin:CanStartVote()
	local PlayerCount = GetNumPlayers()

	if PlayerCount < self.Config.MinPlayers then
		return false, "There are not enough players to start a vote."
	end

	if self.Vote.NextVote >= SharedTime() then
		return false, "You cannot start a map vote at this time."
	end

	return true
end

function Plugin:GetVoteEnd()
	local PlayerCount = GetNumPlayers()

	return Ceil( PlayerCount * self.Config.PercentToFinish )
end

--[[
	Adds a vote to begin a map vote.
]]
function Plugin:AddStartVote( Client )
	if not Client then Client = "Console" end

	local Allow, Error = Shine.Hook.Call( "OnVoteStart", "rtv" )
	if Allow == false then
		return false, Error
	end

	if self:VoteStarted() then return false, "A vote is already in progress." end
	local Success = self.StartingVote:AddVote( Client )

	if not Success then return false, "You have already voted to begin a map vote." end

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

	if #Map < 4 then return nil end --Not specific enough.

	for Name, Votes in pairs( Choices ) do
		if Name:lower():find( Map, 1, true ) then
			return Name
		end
	end

	return nil
end

--[[
	Sends the number of votes the given map has to the given player or everyone.
]]
function Plugin:SendMapVoteCount( Client, Map, Count )
	self:SendNetworkMessage( Client, "VoteProgress", { Map = Map, Votes = Count }, true )
end

--[[
	Adds a vote for a given map in the map vote.
]]
function Plugin:AddVote( Client, Map, Revote )
	if not Client then Client = "Console" end

	if not self:VoteStarted() then return false, "no vote in progress" end
	if self.Vote.Voted[ Client ] and not Revote then return false, "already voted" end

	local Choice = self:GetVoteChoice( Map )
	if not Choice then return false, StringFormat( "%s is not a valid map choice.", Map ) end

	if Revote then
		local OldVote = self.Vote.Voted[ Client ]
		if OldVote == Choice then
			return false, StringFormat( "You have already voted for %s.", Choice )
		end

		if OldVote then
			self.Vote.VoteList[ OldVote ] = self.Vote.VoteList[ OldVote ] - 1
		end

		--Update all client's vote counters.
		self:SendMapVoteCount( nil, OldVote, self.Vote.VoteList[ OldVote ] )
	end

	local CurVotes = self.Vote.VoteList[ Choice ]
	self.Vote.VoteList[ Choice ] = CurVotes + 1

	--Update all client's vote counters.
	self:SendMapVoteCount( nil, Choice, self.Vote.VoteList[ Choice ] )

	if not Revote then
		self.Vote.TotalVotes = self.Vote.TotalVotes + 1
	end

	self.Vote.Voted[ Client ] = Choice

	if not self:IsNextMapVote() and self.Vote.TotalVotes >= self:GetVoteEnd() then
		self:SimpleTimer( 0, function()
			self:ProcessResults()
		end )

		self:DestroyTimer( self.VoteTimer )
	end

	return true, Choice
end

--[[
	Tells the given player or everyone that the vote is over.
]]
function Plugin:EndVote( Player )
	self:SendNetworkMessage( Player, "EndVote", {}, true )
end

function Plugin:ExtendMap( Time, NextMap )
	local Cycle = self.MapCycle

	local ExtendTime = self.Config.ExtendTime * 60

	local CycleTime = Cycle and ( Cycle.time * 60 ) or 0
	local BaseTime = CycleTime > Time and CycleTime or Time

	if self.Config.RoundLimit > 0 then
		self.Round = self.Round - 1

		self:Notify( nil, "Extending the current map for another round." )
	else
		self:Notify( nil, "Extending the current map for another %s.", true,
			string.TimeToString( ExtendTime ) )
	end

	self.NextMap.ExtendTime = BaseTime + ExtendTime
	self.NextMap.Extends = self.NextMap.Extends + 1

	if NextMap then
		if not self.VoteOnEnd then
			self:SimpleTimer( ExtendTime * self.Config.NextMapVote, function()
				local Players = Shine.GetAllPlayers()
				if #Players > 0 then
					self:StartVote( true )
				end
			end )
		end
	else
		if not self.Config.EnableNextMapVote then return end

		--Start the next timer taking the extended time as the new cycle time.
		local NextVoteTime = ( BaseTime + ExtendTime ) * self.Config.NextMapVote - Time

		--Timer would start immediately for the next map vote...
		if NextVoteTime <= Time then
			NextVoteTime = ExtendTime * self.Config.NextMapVote
		end

		if not self.VoteOnEnd then
			self:DestroyTimer( self.NextMapTimer )
			self:CreateTimer( self.NextMapTimer, NextVoteTime, 1, function()
				self:StartVote( true )
			end )
		end
	end
end

function Plugin:ApplyRTVWinner( Time, Choice )
	if Choice == Shared.GetMapName() then
		self.NextMap.Winner = Choice
		self:ExtendMap( Time, false )
		self.Vote.NextVote = Time + ( self.Config.VoteDelay * 60 )

		return
	end

	self:Notify( nil, "Map changing in %s.", true,
		string.TimeToString( self.Config.ChangeDelay ) )

	self.Vote.CanVeto = true --Allow admins to cancel the change.
	self.CyclingMap = true

	--Queue the change.
	self:SimpleTimer( self.Config.ChangeDelay, function()
		if not self.Vote.Veto then --No one cancelled it, change map.
			MapCycle_ChangeMap( Choice )
		else --Someone cancelled it, set the next vote time.
			self.Vote.NextVote = Time + ( self.Config.VoteDelay * 60 )
			self.Vote.Veto = false
			self.Vote.CanVeto = false --Veto has no meaning anymore.

			self.CyclingMap = false
		end
	end )
end

function Plugin:ApplyNextMapWinner( Time, Choice, MentionMap )
	self.NextMap.Winner = Choice

	if Choice == Shared.GetMapName() then
		self:ExtendMap( Time, true )
	else
		if not self.VoteOnEnd then
			self:Notify( nil, MentionMap and "%s won the vote. Setting as next map..."
				or "Setting as next map in the cycle...", MentionMap, Choice )
		else
			self:Notify( nil, MentionMap and "%s won the vote. Cycling map..."
				or "Cycling map...", MentionMap, Choice )

			self.CyclingMap = true
			self:SimpleTimer( 5, function()
				MapCycle_ChangeMap( Choice )
			end )
		end
	end

	self.NextMap.Voting = false
end

function Plugin:OnNextMapVoteFail()
	self.NextMap.Voting = false

	if self.VoteOnEnd then
		local Map = self:GetNextMap()

		self:Notify( nil, "The map will now cycle to %s.", true, Map )
		self.CyclingMap = true

		self:SimpleTimer( 5, function()
			MapCycle_ChangeMap( Map )
		end )
	end
end

function Plugin:ProcessResults( NextMap )
	self:EndVote()

	local Cycle = self.MapCycle

	local TotalVotes = self.Vote.TotalVotes
	local MaxVotes = 0
	local Voted = self.Vote.VoteList

	local Time = SharedTime()

	--No one voted :|
	if TotalVotes == 0 then
		self:Notify( nil, "No votes made. Map vote failed." )

		if self.VoteOnEnd and NextMap then
			self:OnNextMapVoteFail()

			return
		end

		self.Vote.NextVote = Time + ( self.Config.VoteDelay * 60 )

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
			self:Notify( nil, "%s won the vote with %s/%s votes.", true,
				Results[ 1 ], MaxVotes, TotalVotes )

			self:ApplyRTVWinner( Time, Results[ 1 ] )

			return
		end

		self:ApplyNextMapWinner( Time, Results[ 1 ], true )

		return
	end

	--Now we're in the case where there's more than one map that won.
	--If we're set to fail on a tie, then fail.
	if self.Config.TieFails then
		self:Notify( nil, "Votes were tied. Map vote failed." )
		self.Vote.NextVote = Time + ( self.Config.VoteDelay * 60 )

		if NextMap then
			self:OnNextMapVoteFail()
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

		self:Notify( nil, "Votes were tied between %s.", true, Tied )
		self:Notify( nil, "Choosing random map. Map chosen: %s.", true, Choice )

		if not NextMap then
			self:ApplyRTVWinner( Time, Choice )
			return
		end

		self:ApplyNextMapWinner( Time, Choice )

		return
	end

	--Now we're dealing with the case where we want to revote on fail, so we need to get rid of the timer.
	self:DestroyTimer( self.VoteTimer )

	if self.Vote.Votes < self.Config.MaxRevotes then --We can revote, so do so.
		self:Notify( nil, "Votes were tied, map vote failed. Beginning revote." )

		self.Vote.Votes = self.Vote.Votes + 1

		self:SimpleTimer( 0, function()
			self:StartVote( NextMap )
		end )
	else
		self:Notify( nil, "Votes were tied, map vote failed. Revote limit reached." )

		if NextMap then
			self:OnNextMapVoteFail()
		else
			self.Vote.NextVote = Time + ( self.Config.VoteDelay * 60 )
		end
	end
end

do
	local TableRandom = table.ChooseRandom

	local BaseEntryCount = 10

	local function RemoveAllMatches( Table, Value )
		local Offset = 0

		for i = 1, #Table do
			local Key = i - Offset

			if Table[ Key ] == Value then
				TableRemove( Table, Key )
				Offset = Offset + 1
			end
		end
	end

	--[[
		Chooses random maps from the remaining maps pool, weighting each map according
		to their chance setting.
	]]
	function Plugin:ChooseRandomMaps( AllMaps, MapList, MaxOptions )
		local MapBucket = {}
		local Count = 0

		for Map in pairs( AllMaps ) do
			local Chance = self.MapProbabilities[ Map ] or 1
			local NumEntries = Ceil( Chance * BaseEntryCount )

			--The higher the chance, the more times the map appears in the bucket.
			for i = 1, NumEntries do
				Count = Count + 1
				MapBucket[ Count ] = Map
			end
		end

		while #MapList < MaxOptions and #MapBucket > 0 do
			local Choice = TableRandom( MapBucket )

			MapList[ #MapList + 1 ] = Choice

			RemoveAllMatches( MapBucket, Choice )
		end
	end
end

--[[
	Sets up and begins a map vote.
]]
function Plugin:StartVote( NextMap, Force )
	if self:VoteStarted() then return end
	if not Force and not NextMap and not self:CanStartVote() then return end
	if not Force and not NextMap and not self.Config.EnableRTV then return end

	self.StartingVote:Reset()

	self.Vote.TotalVotes = 0
	self.Vote.Voted = {}

	--First we compile the list of maps that are going to be available to vote for.
	local MaxOptions = self.Config.MaxOptions
	local Nominations = self.Vote.Nominated
	local ForcedMaps = self.Config.ForcedMaps

	local AllMaps = TableCopy( self.Config.Maps )
	local MapGroup = self:GetMapGroup()

	--If we have a map group, then get rid of any maps that aren't in the group.
	if MapGroup then
		local GroupMaps = TableAsSet( MapGroup.maps )

		for Map in pairs( AllMaps ) do
			if not GroupMaps[ Map ] then
				AllMaps[ Map ] = nil
			end
		end

		self.LastMapGroup = MapGroup
	end

	local MapList = {}

	local PlayerCount = GetNumPlayers()

	local Cycle = self.MapCycle
	local CycleMaps = self.MapChoices

	local DeniedMaps = {}

	local function SortOutMinMax( Map )
		if not IsType( Map, "table" ) or not IsType( Map.map, "string" ) then
			return
		end

		local Min = Map.min
		local Max = Map.max

		local MapName = Map.map

		if Min and PlayerCount < Min then
			AllMaps[ MapName ] = nil
			DeniedMaps[ MapName ] = true
		elseif Max and PlayerCount > Max then
			AllMaps[ MapName ] = nil
			DeniedMaps[ MapName ] = true
		end
	end

	--Handle min/max player count maps.
	if CycleMaps then
		for i = 1, #CycleMaps do
			local Map = CycleMaps[ i ]

			SortOutMinMax( Map )
		end
	end

	for Map, Data in pairs( self.Config.Maps ) do
		SortOutMinMax( Data )
	end

	--Remove the last maps played.
	local LastMaps = self:GetLastMaps()

	if LastMaps then
		for i = 1, #LastMaps do
			local Map = LastMaps[ i ]

			AllMaps[ Map ] = nil
			DeniedMaps[ Map ] = true
		end
	end

	local CurMap = Shared.GetMapName()
	local AllowCurMap = self:CanExtend()

	local ForcedMapCount = self.ForcedMapCount

	if ForcedMapCount > 0 then
		--Check the forced maps that should always be an option.
		local Count = 1

		for Map in pairs( ForcedMaps ) do
			if Map ~= CurMap or AllowCurMap then
				MapList[ Count ] = Map

				Count = Count + 1

				AllMaps[ Map ] = nil
			end
		end
	end

	--We then look in the nominations, and enter those into the list.
	for i = 1, #Nominations do
		local Nominee = Nominations[ i ]

		if not DeniedMaps[ Nominee ] then
			MapList[ #MapList + 1 ] = Nominee
			AllMaps[ Nominee ] = nil
		end

		Nominations[ i ] = nil
	end

	--If we have map extension enabled, ensure it's in the vote list.
	if AllowCurMap then
		if AllMaps[ CurMap ] and self.Config.AlwaysExtend then
			MapList[ #MapList + 1 ] = CurMap
			AllMaps[ CurMap ] = nil
		end
	else
		--Otherwise remove it!
		AllMaps[ CurMap ] = nil
	end

	local RemainingSpaces = MaxOptions - #MapList

	--If we have more room, add maps from the allowed list that weren't nominated.
	if RemainingSpaces > 0 then
		if next( AllMaps ) then
			self:ChooseRandomMaps( AllMaps, MapList, MaxOptions )
		end
	end

	self.Vote.VoteList = {}
	for i = 1, #MapList do
		self.Vote.VoteList[ MapList[ i ] ] = 0
	end

	local OptionsText = TableConcat( MapList, ", " )
	local VoteLength = self.Config.VoteLength * 60

	local Time = SharedTime()
	local EndTime = Time + VoteLength

	--Store these values for new clients.
	self.Vote.EndTime = EndTime
	self.Vote.OptionsText = OptionsText

	if NextMap then
		self.NextMap.Voting = true
	end

	self:SimpleTimer( 0.1, function()
		if not NextMap then
			self:Notify( nil, "Map vote started." )
		else
			self:Notify( nil, "Voting for the next map has started." )
		end
	end )

	self:SendVoteOptions( nil, OptionsText, VoteLength, NextMap, self:GetTimeRemaining(),
		not self.VoteOnEnd )

	self:CreateTimer( self.VoteTimer, VoteLength, 1, function()
		self:ProcessResults( NextMap )
	end )
end
