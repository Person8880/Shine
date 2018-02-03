--[[
	Voting logic.
]]

local Shine = Shine

local Ceil = math.ceil
local Floor = math.floor
local GetMaxPlayers = Server.GetMaxPlayers
local GetNumPlayers = Shine.GetHumanPlayerCount
local Max = math.max
local Min = math.min
local next = next
local pairs = pairs
local SharedTime = Shared.GetTime
local StringFormat = string.format
local StringUpper = string.upper
local TableAsSet = table.AsSet
local TableConcat = table.concat

local Plugin = Plugin
local IsType = Shine.IsType

Shine.LoadPluginModule( "vote.lua" )

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

function Plugin:ClientConnect( Client )
	self:UpdateVoteCounters( self.StartingVote )
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
	self:UpdateVoteCounters( self.StartingVote )
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
	if ID == "random" then
		local VoteRandom = Shine.Plugins.voterandom

		if self:IsEndVote() or self.CyclingMap then
			return false, "You cannot start a vote at the end of the map.",
				VoteRandom:GetStartFailureMessage()
		end

		return
	end

	if self.CyclingMap then
		return false, "The map is now changing, unable to start a vote.",
			"VOTE_FAIL_MAP_CHANGE", {}
	end
end

-- Block these votes when the end of map vote is running.
Plugin.BlockedEndOfMapVotes = {
	VoteResetGame = true,
	VoteRandomizeRR = true,
	VotingForceEvenTeams = true,
	VoteChangeMap = true,
	VoteAddCommanderBots = true
}

function Plugin:NS2StartVote( VoteName, Client, Data )
	if not self:IsEndVote() and not self.CyclingMap then return end

	if self.BlockedEndOfMapVotes[ VoteName ] then
		return false, kVoteCannotStartReason.Waiting
	end
end

function Plugin:GetVoteConstraint( Category, Type, PercentageTotal )
	local Constraint = self.Config.Constraints[ Category ][ Type ]
	if StringUpper( Constraint.Type ) == self.ConstraintType.PERCENT then
		return Ceil( Constraint.Value * PercentageTotal )
	end
	return Constraint.Value
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
	return self:GetVoteConstraint( "StartVote", "MinVotesRequired", self:GetPlayerCountForVote() )
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
	local PlayerCount = self:GetPlayerCountForVote()

	if PlayerCount < self:GetVoteConstraint( "StartVote", "MinPlayers", GetMaxPlayers() ) then
		return false, "There are not enough players to start a vote.", "VOTE_FAIL_INSUFFICIENT_PLAYERS", {}
	end

	if self.Vote.NextVote >= SharedTime() then
		return false, "You cannot start a map vote at this time.", "VOTE_FAIL_TIME", {}
	end

	return true
end

function Plugin:GetVoteEnd( Category )
	local PlayerCount = self:GetPlayerCountForVote()
	return self:GetVoteConstraint( Category, "MinVotesToFinish", PlayerCount )
end

--[[
	Adds a vote to begin a map vote.
]]
function Plugin:AddStartVote( Client )
	if not Client then Client = "Console" end

	local Allow, Error, Key, Data = Shine.Hook.Call( "OnVoteStart", "rtv" )
	if Allow == false then
		return false, Error, Key, Data
	end

	if self:VoteStarted() then return false, "A vote is already in progress.", "VOTE_FAIL_IN_PROGRESS", {} end
	local Success = self.StartingVote:AddVote( Client )

	if not Success then return false, "You have already voted to begin a map vote.", "VOTE_FAIL_ALREADY_VOTED", {} end

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
	Sends a client's vote choice so their menu knows which map they have selected.
]]
function Plugin:SendVoteChoice( Client, Map )
	self:SendNetworkMessage( Client, "ChosenMap", { MapName = Map }, true )
end

--[[
	Adds a vote for a given map in the map vote.
]]
function Plugin:AddVote( Client, Map, Revote )
	if not Client then Client = "Console" end

	if not self:VoteStarted() then return false, "no vote in progress" end
	if self.Vote.Voted[ Client ] and not Revote then return false, "already voted" end

	local Choice = self:GetVoteChoice( Map )
	if not Choice then
		return false, StringFormat( "%s is not a valid map choice.", Map ), "VOTE_FAIL_INVALID_MAP", { MapName = Map }
	end

	if Revote then
		local OldVote = self.Vote.Voted[ Client ]
		if OldVote == Choice then
			return false, StringFormat( "You have already voted for %s.", Choice ), "VOTE_FAIL_VOTED_MAP", { MapName = Choice }
		end

		if OldVote then
			self.Vote.VoteList[ OldVote ] = self.Vote.VoteList[ OldVote ] - 1
		end

		-- Update all client's vote counters.
		self:SendMapVoteCount( nil, OldVote, self.Vote.VoteList[ OldVote ] )
	end

	local CurVotes = self.Vote.VoteList[ Choice ]
	self.Vote.VoteList[ Choice ] = CurVotes + 1

	-- Update all client's vote counters.
	self:SendMapVoteCount( nil, Choice, self.Vote.VoteList[ Choice ] )
	if Client ~= "Console" then
		self:SendVoteChoice( Client, Choice )
	end

	if not Revote then
		self.Vote.TotalVotes = self.Vote.TotalVotes + 1
	end

	self.Vote.Voted[ Client ] = Choice

	if self.Vote.TotalVotes >= self:GetVoteEnd( self:GetVoteCategory( self:IsNextMapVote() ) ) then
		self:SimpleTimer( 0, function()
			self:ProcessResults()
		end )

		self:DestroyTimer( self.VoteTimer )
	end

	return true, Choice
end

function Plugin:GetVoteCategory( NextMap )
	return NextMap and "NextMapVote" or "MapVote"
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
		self:NotifyTranslated( nil, "EXTENDING_ROUND" )
	else
		self:SendTranslatedNotify( nil, "EXTENDING_TIME", {
			Duration = ExtendTime
		} )
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

	self:SendTranslatedNotify( nil, "MAP_CHANGING", {
		Duration = self.Config.ChangeDelay
	} )

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
		local Key
		if not self.VoteOnEnd then
			Key = MentionMap and "WINNER_NEXT_MAP" or "WINNER_NEXT_MAP2"
		else
			Key = MentionMap and "WINNER_CYCLING" or "WINNER_CYCLING2"

			self.CyclingMap = true
			self:SimpleTimer( 5, function()
				MapCycle_ChangeMap( Choice )
			end )
		end

		if MentionMap then
			self:SendTranslatedNotify( nil, Key, {
				MapName = Choice
			} )
		else
			self:NotifyTranslated( nil, Key )
		end
	end

	self.NextMap.Voting = false
end

function Plugin:OnNextMapVoteFail()
	self.NextMap.Voting = false

	if self.VoteOnEnd then
		local Map = self:GetNextMap()

		self:SendTranslatedNotify( nil, "MAP_CYCLING", {
			MapName = Map
		} )
		self.CyclingMap = true

		self:SimpleTimer( 5, function()
			MapCycle_ChangeMap( Map )
		end )
	end
end

local TableRandom = table.ChooseRandom

function Plugin:ProcessResults( NextMap )
	self:EndVote()

	local Cycle = self.MapCycle

	local TotalVotes = self.Vote.TotalVotes
	local MaxVotes = 0
	local Voted = self.Vote.VoteList

	local Time = SharedTime()
	local Category = self:GetVoteCategory( NextMap )
	local EligblePlayerCount = self:GetPlayerCountForVote()

	-- Not enough players voted :|
	if TotalVotes < Max( self:GetVoteConstraint( Category, "MinVotesRequired", EligblePlayerCount ), 1 ) then
		self:NotifyTranslated( nil, "NOT_ENOUGH_VOTES" )

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
			self:SendTranslatedNotify( nil, "WINNER_VOTES", {
				MapName = Results[ 1 ],
				Votes = MaxVotes,
				TotalVotes = TotalVotes
			} )

			self:ApplyRTVWinner( Time, Results[ 1 ] )

			return
		end

		self:ApplyNextMapWinner( Time, Results[ 1 ], true )

		return
	end

	--Now we're in the case where there's more than one map that won.
	--If we're set to fail on a tie, then fail.
	if self.Config.TieFails then
		self:NotifyTranslated( nil, "VOTES_TIED_FAILURE" )
		self.Vote.NextVote = Time + ( self.Config.VoteDelay * 60 )

		if NextMap then
			self:OnNextMapVoteFail()
		end

		return
	end

	--We're set to choose randomly between them on tie.
	if self.Config.ChooseRandomOnTie then
		local Choice = TableRandom( Results )
		local Tied = TableConcat( Results, ", " )

		self.Vote.CanVeto = true --Allow vetos.

		self:SendTranslatedNotify( nil, "VOTES_TIED", {
			MapNames = Tied
		} )
		self:SendTranslatedNotify( nil, "CHOOSING_RANDOM_MAP", {
			MapName = Choice
		} )

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
		self:NotifyTranslated( nil, "VOTES_TIED_REVOTE" )

		self.Vote.Votes = self.Vote.Votes + 1

		self:SimpleTimer( 0, function()
			self:StartVote( NextMap )
		end )
	else
		self:NotifyTranslated( nil, "VOTES_TIED_LIMIT" )

		if NextMap then
			self:OnNextMapVoteFail()
		else
			self.Vote.NextVote = Time + ( self.Config.VoteDelay * 60 )
		end
	end
end

local Stream = Shine.Stream

do
	local BaseEntryCount = 10

	--[[
		Chooses random maps from the remaining maps pool, weighting each map according
		to their chance setting.
	]]
	function Plugin:ChooseRandomMaps( PotentialMaps, FinalChoices, MaxOptions )
		local MapBucket = {}
		local MapBucketStream = Stream( MapBucket )
		local Count = 0

		for Map in PotentialMaps:Iterate() do
			local Chance = self.MapProbabilities[ Map ] or 1
			local NumEntries = Ceil( Chance * BaseEntryCount )

			-- The higher the chance, the more times the map appears in the bucket.
			for i = 1, NumEntries do
				Count = Count + 1
				MapBucket[ Count ] = Map
			end
		end

		while FinalChoices:GetCount() < MaxOptions and #MapBucket > 0 do
			local Choice = TableRandom( MapBucket )
			FinalChoices:Add( Choice )

			MapBucketStream:Filter( function( Value )
				return Value ~= Choice
			end )
		end
	end
end

function Plugin:GetBlacklistedLastMaps( NumAvailable, NumSelected )
	local LastMaps = self:GetLastMaps()
	if not LastMaps then return {} end

	local ExclusionOptions = self.Config.ExcludeLastMaps

	-- Start with the amount of extra options remaining vs the max.
	local AmountToRemove = NumAvailable - ( self.Config.MaxOptions - NumSelected )
	-- Must remove at least the minimum, regardless of whether it drops the option count.
	AmountToRemove = Max( AmountToRemove, ExclusionOptions.Min )

	-- If there's a maximum set, then do not remove more than that.
	local MaxRemovable = tonumber( ExclusionOptions.Max ) or 0
	if ExclusionOptions.Max and MaxRemovable >= 0 then
		AmountToRemove = Min( AmountToRemove, MaxRemovable )
	end

	local Maps = {}
	for i = #LastMaps, Max( #LastMaps - AmountToRemove + 1, 1 ), -1 do
		Maps[ #Maps + 1 ] = LastMaps[ i ]
	end

	return Maps
end

function Plugin:RemoveLastMaps( PotentialMaps, FinalChoices )
	local MapsToRemove = self:GetBlacklistedLastMaps( PotentialMaps:GetCount(), FinalChoices:GetCount() )
	for i = 1, #MapsToRemove do
		PotentialMaps:Remove( MapsToRemove[ i ] )
	end
end

function Plugin:BuildPotentialMapChoices()
	local PotentialMaps = Shine.Set( self.Config.Maps )
	local MapGroup = self:GetMapGroup()
	local PlayerCount = GetNumPlayers()

	-- If we have a map group, then get rid of any maps that aren't in the group.
	if MapGroup then
		local GroupMaps = TableAsSet( MapGroup.maps )
		PotentialMaps:Intersection( GroupMaps )

		self.LastMapGroup = MapGroup
	end

	-- We then look in the nominations, and enter those into the list.
	local Nominations = self.Vote.Nominated
	for i = 1, #Nominations do
		local Nominee = Nominations[ i ]
		PotentialMaps:Add( Nominee )
	end

	-- Now filter out any maps that are invalid.
	PotentialMaps:Filter( function( Map ) return self:IsValidMapChoice( self.MapOptions[ Map ] or Map, PlayerCount ) end )

	return PotentialMaps
end

function Plugin:AddForcedMaps( PotentialMaps, FinalChoices )
	if self.ForcedMapCount <= 0 then return end

	for Map in pairs( self.Config.ForcedMaps ) do
		if Map ~= CurMap or AllowCurMap then
			FinalChoices:Add( Map )
			PotentialMaps:Remove( Map )
		end
	end
end

function Plugin:AddNominations( PotentialMaps, FinalChoices, Nominations )
	for i = 1, #Nominations do
		local Nominee = Nominations[ i ]
		if PotentialMaps:Contains( Nominee ) then
			FinalChoices:Add( Nominee )
			PotentialMaps:Remove( Nominee )
		end
	end
end

function Plugin:AddCurrentMap( PotentialMaps, FinalChoices )
	local AllowCurMap = self:CanExtend()
	local CurMap = Shared.GetMapName()
	if AllowCurMap then
		if PotentialMaps:Contains( CurMap ) and self.Config.AlwaysExtend then
			FinalChoices:Add( CurMap )
			PotentialMaps:Remove( CurMap )
		end
	else
		-- Otherwise remove it!
		PotentialMaps:Remove( CurMap )
	end
end

function Plugin:BuildMapChoices()
	-- First we compile the list of maps that are going to be available to vote for.
	local PotentialMaps = self:BuildPotentialMapChoices()

	-- Now we build our actual map choices.
	local FinalChoices = Shine.Set()

	-- Add forced maps, these skip validity checks.
	self:AddForcedMaps( PotentialMaps, FinalChoices )

	-- Add all nominations that are allowed to the vote list.
	self:AddNominations( PotentialMaps, FinalChoices, self.Vote.Nominated )

	-- If we have map extension enabled and forced, ensure it's in the vote list.
	self:AddCurrentMap( PotentialMaps, FinalChoices )

	-- Get rid of any maps we've previously played based on the exclusion config.
	self:RemoveLastMaps( PotentialMaps, FinalChoices )

	local MaxOptions = self.Config.MaxOptions
	local RemainingSpaces = MaxOptions - FinalChoices:GetCount()

	-- Finally, if we have more room, add maps from the allowed list that weren't nominated.
	if RemainingSpaces > 0 then
		self:ChooseRandomMaps( PotentialMaps, FinalChoices, MaxOptions )
	end

	return FinalChoices:AsList()
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
	self.Vote.NominationTracker = {}

	local MapList = self:BuildMapChoices()

	self.Vote.Nominated = {}
	self.Vote.VoteList = {}
	for i = 1, #MapList do
		self.Vote.VoteList[ MapList[ i ] ] = 0
	end

	local OptionsText = TableConcat( MapList, ", " )
	local VoteLength = self.Config.VoteLength * 60
	local EndTime = SharedTime() + VoteLength

	-- Store these values for new clients.
	self.Vote.EndTime = EndTime
	self.Vote.OptionsText = OptionsText

	if NextMap then
		self.NextMap.Voting = true
	end

	self:SimpleTimer( 0.1, function()
		if not NextMap then
			self:NotifyTranslated( nil, "RTV_STARTED" )
		else
			self:NotifyTranslated( nil, "NEXT_MAP_STARTED" )
		end
	end )

	self:SendVoteOptions( nil, OptionsText, VoteLength, NextMap, self:GetTimeRemaining(),
		not self.VoteOnEnd )

	self:CreateTimer( self.VoteTimer, VoteLength, 1, function()
		self:ProcessResults( NextMap )
	end )
end
