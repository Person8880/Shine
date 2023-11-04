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
local Random = math.random
local SharedTime = Shared.GetTime
local StringFormat = string.format
local StringStartsWith = string.StartsWith
local StringUpper = string.upper
local TableAsSet = table.AsSet
local TableConcat = table.concat
local TableQuickCopy = table.QuickCopy
local TableRemove = table.remove
local tonumber = tonumber

local Plugin = ...
local IsType = Shine.IsType

Shine.LoadPluginModule( "vote.lua", Plugin )

function Plugin:SendVoteOptions( Client, Options, Duration, NextMap, TimeLeft, ShowTime, CurrentMap )
	local MessageTable = {
		Options = Options,
		CurrentMap = CurrentMap,
		Duration = Duration,
		NextMap = NextMap,
		TimeLeft = TimeLeft,
		ShowTime = ShowTime,
		ForceMenuOpen = self.Config.ForceMenuOpenOnMapVote
	}

	if Client then
		self:SendNetworkMessage( Client, "VoteOptions", MessageTable, true )
	else
		self:SendNetworkMessage( nil, "VoteOptions", MessageTable, true )
	end
end

do
	local StringHexToNumber = string.HexToNumber

	local function ModIDToHex( ModID )
		return IsType( ModID, "number" ) and StringFormat( "%x", ModID ) or ModID
	end

	local function FindBestMatchingModID( self, ModList )
		local MapMods = Shine.Stream.Of( ModList ):Map( ModIDToHex ):Filter( function( ModID )
			return self.KnownMapMods[ ModID ]
		end ):AsTable()

		-- If we know which mod is the map, use it.
		local ModID = MapMods[ 1 ]
		if not ModID then
			-- Otherwise assume it's the first mod with an unknown type.
			MapMods = Shine.Stream.Of( ModList ):Map( ModIDToHex ):Filter( function( ModID )
				return self.KnownMapMods[ ModID ] ~= false
			end ):AsTable()

			ModID = MapMods[ 1 ]
		end

		return ModID
	end

	local function HasMod( ModList, ModID )
		local ModIDBase10 = StringHexToNumber( ModID )
		if not ModIDBase10 then return false end

		for i = 1, #ModList do
			local MapMod = ModList[ i ]
			if
				MapMod == ModIDBase10 or
				( IsType( MapMod, "string" ) and StringHexToNumber( MapMod ) == ModIDBase10 )
			then
				return true
			end
		end

		return false
	end

	local function IsModMap( MapName, Index, self )
		local Options = self.MapOptions[ MapName ]
		return Options and IsType( Options.mods, "table" ) and not self.KnownVanillaMaps[ MapName ]
	end

	local function GetModInfo( MapName, Index, self )
		local Options = self.MapOptions[ MapName ]
		local ModID = self.MapNameToModID[ MapName ]

		if not ModID or not HasMod( Options.mods, ModID ) then
			ModID = FindBestMatchingModID( self, Options.mods ) or ModID
		end

		if not IsType( ModID, "string" ) or not StringHexToNumber( ModID ) then
			ModID = nil
		end

		return {
			MapName = MapName,
			ModID = ModID
		}
	end

	local function HasModID( Value ) return Value.ModID ~= nil end

	function Plugin:GetMapModsForMapList( MapList )
		return Shine.Stream( MapList )
			:Filter( IsModMap, self )
			:Map( GetModInfo, self )
			:Filter( HasModID )
	end

	function Plugin:SendMapMods( Client, MapList )
		MapList = MapList or self.Vote.MapList
		if not MapList then return end

		self:GetMapModsForMapList( MapList ):ForEach( function( MapInfo )
			local MapName = MapInfo.MapName
			local ModID = MapInfo.ModID

			self.Logger:Debug( "Map %s has mod ID: %s", MapName, ModID )
			self:SendNetworkMessage( Client, "MapMod", {
				MapName = MapName,
				ModID = ModID
			}, true )
		end )
	end
end

function Plugin:SendMapPrefixes( Client )
	local Prefixes = self:GetMapModPrefixes()
	for Prefix in pairs( Prefixes ) do
		self:SendNetworkMessage( Client, "MapModPrefix", {
			Prefix = Prefix
		}, true )
	end
end

function Plugin:ClientConnect( Client )
	self:UpdateVoteCounters( self.StartingVote )
end

function Plugin:NetworkVoteData( Client, Duration )
	-- Send any mods for maps in the current vote (so the map vote menu shows the right preview image).
	self:SendMapMods( Client )
	-- Send all known map prefixes (so the map vote menu can derive the actual map names to load a preview for).
	self:SendMapPrefixes( Client )

	-- Send them the current vote progress and options (after the above so the menu has everything it needs).
	self:SendVoteOptions(
		Client,
		self.Vote.OptionsText,
		Duration,
		self.NextMap.Voting,
		self:GetTimeRemaining(),
		not self.VoteOnEnd,
		self:GetCurrentMap()
	)

	-- Send the current vote counters so they're reflected in the UI.
	for Map, Votes in pairs( self.Vote.VoteList ) do
		self:SendMapVoteCount( Client, Map, Votes )
	end

	self.Vote.NotifiedClients[ Client ] = true
end

--[[
	Send the map vote text and map options when a new player connects and a map vote is in progress.
]]
function Plugin:ClientConfirmConnect( Client )
	if not self:VoteStarted() or ( self.Vote.NotifiedClients and self.Vote.NotifiedClients[ Client ] ) then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug(
				"%s does not need to be notified of an ongoing map vote.",
				Shine.GetClientInfo( Client )
			)
		end
		return
	end

	local Time = SharedTime()
	local Duration = Floor( self.Vote.EndTime - Time )
	if Duration < 5 then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug(
				"Skipping sending map vote to %s as the vote will end soon.",
				Shine.GetClientInfo( Client )
			)
		end
		return
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Sending map vote to %s who has just connected.", Shine.GetClientInfo( Client ) )
	end

	self:NetworkVoteData( Client, Duration )
end

function Plugin:ClientDisconnect( Client )
	self.StartingVote:ClientDisconnect( Client )
	self:UpdateVoteCounters( self.StartingVote )

	if self.Vote.NotifiedClients then
		self.Vote.NotifiedClients[ Client ] = nil
	end
end

function Plugin:SetGameState( Gamerules, State, OldState )
	if State == kGameState.Started and self.Config.BlockAfterRoundTimeInMinutes > 0 then
		self.VoteDisableTime = SharedTime() + self.Config.BlockAfterRoundTimeInMinutes * 60
	else
		self.VoteDisableTime = math.huge
	end
end

function Plugin:CheckGameStartOutsideVote()
	-- Do nothing normally to avoid constant overhead.
end

Plugin.CheckGameStart = Plugin.CheckGameStartOutsideVote
Plugin.UpdatePregame = Plugin.CheckGameStartOutsideVote

function Plugin:ShouldBlockGameStart()
	-- Stop the game from starting during a player-initiated vote or after a vote has triggered a map change.
	return self.CyclingMap or ( self:VoteStarted() and not self:IsNextMapVote() )
end

function Plugin:UpdatePregameDuringVote( Gamerules )
	if self:ShouldBlockGameStart() then
		if Gamerules:GetGameState() == kGameState.PreGame then
			return false
		end
	else
		self.UpdatePregame = self.CheckGameStartOutsideVote
	end
end

function Plugin:CheckGameStartDuringVote( Gamerules )
	if self:ShouldBlockGameStart() then
		return false
	else
		self.CheckGameStart = self.CheckGameStartOutsideVote
	end
end

--[[
	Client's requesting the vote data.
]]
function Plugin:SendVoteData( Client )
	if not self:VoteStarted() then return end

	local Time = SharedTime()
	local Duration = Floor( self.Vote.EndTime - Time )

	self:NetworkVoteData( Client, Duration )
end

function Plugin:ReceiveRequestVoteOptions( Client, Message )
	self:SendVoteData( Client )
end

function Plugin:OnVoteStart( ID, SourcePlugin )
	if ID == "random" then
		local VoteRandom = Shine.IsPlugin( SourcePlugin ) and SourcePlugin or Shine.Plugins.voterandom
		if
			VoteRandom and VoteRandom.GetStartFailureMessage and VoteRandom.Enabled and
			( self:IsEndVote() or self.CyclingMap )
		then
			return false, "You cannot start a vote at the end of the map.", VoteRandom:GetStartFailureMessage()
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

function Plugin:GetVoteDelay()
	return self.Config.VoteDelayInMinutes * 60
end

function Plugin:GetVoteConstraint( Category, Type, NumTotal )
	local Constraint = self.Config.Constraints[ Category ][ Type ]
	if StringUpper( Constraint.Type ) == self.ConstraintType.FRACTION_OF_PLAYERS then
		return Ceil( Constraint.Value * NumTotal )
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
	local Time = SharedTime()
	if self.Vote.NextVote > Time then
		local TimeTillNextVote = Ceil( self.Vote.NextVote - Time )
		return false,
			StringFormat( "You must wait for %s before starting a map vote.", string.TimeToString( TimeTillNextVote ) ),
			"VOTE_FAIL_MUST_WAIT",
			{
				SecondsToWait = TimeTillNextVote
			}
	end

	if Time > self.VoteDisableTime then
		return false, "It is too far into the current round to begin a map vote.", "VOTE_FAIL_TOO_LATE", {}
	end

	local PlayerCount = self:GetPlayerCountForVote()

	if PlayerCount < self:GetVoteConstraint( "StartVote", "MinPlayers", GetMaxPlayers() ) then
		return false, "There are not enough players to start a vote.", "VOTE_FAIL_INSUFFICIENT_PLAYERS", {}
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
	if not Client then return false, "Console cannot vote." end

	local Success, Err, Args = self:CanClientVote( Client )
	if not Success then
		return false, "Client is not eligible to vote.", Err, Args
	end

	local Allow, Error, Key, Data = Shine.Hook.Call( "OnVoteStart", "rtv", self )
	if Allow == false then
		return false, Error, Key, Data
	end

	if self:VoteStarted() then
		return false, "A vote is already in progress.", "VOTE_FAIL_IN_PROGRESS", {}
	end

	local Success = self.StartingVote:AddVote( Client )
	if not Success then
		return false, "You have already voted to begin a map vote.", "VOTE_FAIL_ALREADY_VOTED", {}
	end

	return true
end

function Plugin:GetVoteChoices()
	return Shine.Set( self.Vote.VoteList ):AsList()
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
function Plugin:SendVoteChoice( Client, Map, IsSelected )
	self:SendNetworkMessage( Client, "ChosenMap", { MapName = Map, IsSelected = IsSelected }, true )
end

local function SetVoteCount( self, MapName, Count )
	self.Vote.VoteList[ MapName ] = Count
	-- Update all client's vote counters.
	self:SendMapVoteCount( nil, MapName, Count )
end

function Plugin:RemoveVote( Client, Map )
	if not Client then return false, "Console cannot vote." end

	local Choice = self:GetVoteChoice( Map )
	if not Choice then
		return false, StringFormat( "%s is not a valid map choice.", Map ), "VOTE_FAIL_INVALID_MAP", { MapName = Map }
	end

	if self.Vote.Voted:HasKeyValue( Client, Choice ) then
		self.Vote.Voted:RemoveKeyValue( Client, Choice )
		self.Vote.TotalVotes = self.Vote.TotalVotes - 1

		SetVoteCount( self, Choice, self.Vote.VoteList[ Choice ] - 1 )

		self:SendVoteChoice( Client, Choice, false )

		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug(
				"Client %s revoked their vote for %s (now at %s/%s votes).",
				Shine.GetClientInfo( Client ),
				Choice,
				self.Vote.VoteList[ Choice ],
				self.Vote.TotalVotes
			)
		end

		return true, Choice
	end

	return false
end

--[[
	Adds a vote for a given map in the map vote.
]]
function Plugin:AddVote( Client, Map )
	if not Client then return false, "Console cannot vote." end

	local Success, Err, Args = self:CanClientVote( Client )
	if not Success then
		return false, "Client is not eligible to vote.", Err, Args
	end

	if not self:VoteStarted() then return false, "no vote in progress" end

	local Choice = self:GetVoteChoice( Map )
	if not Choice then
		return false, StringFormat( "%s is not a valid map choice.", Map ), "VOTE_FAIL_INVALID_MAP", { MapName = Map }
	end

	local OldVote
	local IsSingleChoice = self.Config.VotingMode == Plugin.VotingMode.SINGLE_CHOICE
	if IsSingleChoice then
		local OldVotes = self.Vote.Voted:Get( Client )
		OldVote = OldVotes and OldVotes[ 1 ]

		if OldVote == Choice then
			return false, StringFormat( "You have already voted for %s.", Choice ),
				"VOTE_FAIL_VOTED_MAP", { MapName = Choice }
		end

		if OldVote then
			self.Vote.Voted:RemoveKeyValue( Client, OldVote )
			SetVoteCount( self, OldVote, self.Vote.VoteList[ OldVote ] - 1 )

			if self.Logger:IsDebugEnabled() then
				self.Logger:Debug(
					"Client %s revoked their vote for %s (now at %s/%s votes).",
					Shine.GetClientInfo( Client ),
					OldVote,
					self.Vote.VoteList[ OldVote ],
					self.Vote.TotalVotes
				)
			end
		end
	else
		if self.Vote.Voted:HasKeyValue( Client, Choice ) then
			return false, StringFormat( "You have already voted for %s.", Choice ),
				"VOTE_FAIL_VOTED_MAP", { MapName = Choice }
		end

		local Choices = self.Vote.Voted:Get( Client )
		local MaxMapChoices = self.Config.MaxVoteChoicesPerPlayer
		if Choices and #Choices >= MaxMapChoices then
			return false, StringFormat( "You cannot vote for more than %d maps.", MaxMapChoices ),
				"VOTE_FAIL_CHOICE_LIMIT_REACHED", { MaxMapChoices = MaxMapChoices }
		end
	end

	SetVoteCount( self, Choice, self.Vote.VoteList[ Choice ] + 1 )

	if Client ~= "Console" then
		self:SendVoteChoice( Client, Choice, true )
	end

	if not OldVote then
		self.Vote.TotalVotes = self.Vote.TotalVotes + 1
	end

	self.Vote.Voted:Add( Client, Choice )

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug(
			"Client %s voted for %s (now at %s/%s votes).",
			Shine.GetClientInfo( Client ),
			Choice,
			self.Vote.VoteList[ Choice ],
			self.Vote.TotalVotes
		)
	end

	local TotalVotes
	if IsSingleChoice then
		TotalVotes = self.Vote.TotalVotes
	else
		-- It doesn't make sense to use the total number of votes when multiple choices are allowed as it will be
		-- a multiple of the player count. Instead, end early if any map receives the fraction to finish amount.
		TotalVotes = self.Vote.VoteList[ Choice ]
	end

	local VotesToEnd = self:GetVoteEnd( self:GetVoteCategory( self:IsNextMapVote() ) )
	if TotalVotes >= VotesToEnd then
		self.Logger:Debug( "Ending vote early due to %s/%s votes being cast.", TotalVotes, VotesToEnd )

		self:SimpleTimer( 0, function()
			self:ProcessResults()
		end )

		self:DestroyTimer( self.VoteTimer )
	end

	return true, Choice, OldVote
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

	local ExtendTime = self.Config.ExtendTimeInMinutes * 60

	local CycleTime = Cycle and ( Cycle.time * 60 ) or 0
	local BaseTime = CycleTime > Time and CycleTime or Time

	if self.RoundLimit > 0 then
		self.Round = self.Round - 1
		self:NotifyTranslated( nil, "EXTENDING_ROUND" )
	else
		self:SendTranslatedNotify( nil, "EXTENDING_TIME", {
			Duration = ExtendTime
		} )
	end

	self.NextMap.ExtendTime = BaseTime + ExtendTime
	self.NextMap.Extends = self.NextMap.Extends + 1

	if self.VoteOnEnd then return end

	if NextMap then
		self.NextMapVoteTime = Time + ExtendTime * self.Config.NextMapVoteMapTimeFraction
	else
		if not self.Config.EnableNextMapVote then return end

		-- Start the next timer taking the extended time as the new cycle time.
		local NextVoteTime = ( BaseTime + ExtendTime ) * self.Config.NextMapVoteMapTimeFraction - Time

		-- Timer would start immediately for the next map vote...
		if NextVoteTime <= Time then
			NextVoteTime = ExtendTime * self.Config.NextMapVoteMapTimeFraction
		end

		self.NextMapVoteTime = Time + NextVoteTime
	end
end

function Plugin:ApplyRTVWinner( Time, Choice )
	if Choice == self:GetCurrentMap() then
		self.NextMap.Winner = Choice
		self:ExtendMap( Time, false )
		self.Vote.NextVote = Time + self:GetVoteDelay()

		return
	end

	self:SendTranslatedNotify( nil, "MAP_CHANGING", {
		Duration = self.Config.ChangeDelayInSeconds
	} )

	self.Vote.CanVeto = true --Allow admins to cancel the change.
	self.CyclingMap = true

	--Queue the change.
	self:SimpleTimer( self.Config.ChangeDelayInSeconds, function()
		if not self.Vote.Veto then --No one cancelled it, change map.
			MapCycle_ChangeMap( Choice )
		else --Someone cancelled it, set the next vote time.
			self.Vote.NextVote = Time + self:GetVoteDelay()
			self.Vote.Veto = false
			self.Vote.CanVeto = false --Veto has no meaning anymore.

			self.CyclingMap = false
		end
	end )
end

function Plugin:ApplyNextMapWinner( Time, Choice, MentionMap )
	self.NextMap.Winner = Choice

	if Choice == self:GetCurrentMap() then
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

function Plugin:OnNextMapVoteFail( Time )
	self.NextMap.Voting = false

	if self.VoteOnEnd then
		local Map = self:GetNextMap()
		if not Map then
			self.Logger:Warn( "Unable to find valid next map to advance to! Current map will be extended." )
			self:ExtendMap( Time, true )
			return
		end

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
	self.Vote.NotifiedClients = nil

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
			self:OnNextMapVoteFail( Time )

			return
		end

		self.Vote.NextVote = Time + self:GetVoteDelay()

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
		self.Vote.NextVote = Time + self:GetVoteDelay()

		if NextMap then
			self:OnNextMapVoteFail( Time )
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
			self:OnNextMapVoteFail( Time )
		else
			self.Vote.NextVote = Time + self:GetVoteDelay()
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

local function AreMapsSimilar( MapA, MapB )
	return StringStartsWith( MapA, MapB ) or StringStartsWith( MapB, MapA )
end

function Plugin:RemoveLastMaps( PotentialMaps, FinalChoices )
	local MapsToRemove = self:GetBlacklistedLastMaps( PotentialMaps:GetCount(), FinalChoices:GetCount() )
	local MaxOptions = self.Config.MaxOptions

	if self.Config.ExcludeLastMaps.UseStrictMatching then
		-- Remove precisely the previous maps, ignoring any that are similar.
		for i = 1, #MapsToRemove do
			PotentialMaps:Remove( MapsToRemove[ i ] )
			if FinalChoices:GetCount() > MaxOptions then
				FinalChoices:Remove( MapsToRemove[ i ] )
			end
		end
	else
		PotentialMaps:Filter( function( Map )
			for i = 1, #MapsToRemove do
				-- If the map is similarly named to a previous map, exclude it.
				-- For example: ns2_veil vs. ns2_veil_five.
				if AreMapsSimilar( Map, MapsToRemove[ i ] ) then
					if FinalChoices:GetCount() > MaxOptions then
						FinalChoices:Remove( Map )
					end
					return false
				end
			end

			return true
		end )
	end
end

local function LogMapGroupChoices( Logger, GroupName, Maps )
	Logger:Debug( "Selected %d map(s) from group '%s': %s", #Maps, GroupName, TableConcat( Maps, ", " ) )
end

function Plugin:BuildPotentialMapChoices()
	local PotentialMaps = Shine.Set( self.Config.Maps )
	local PlayerCount = GetNumPlayers()

	if self.Config.GroupCycleMode == self.GroupCycleMode.WEIGHTED_CHOICE and self.MapGroups then
		local GroupChoices = Shine.Set()
		for i = 1, #self.MapGroups do
			local Group = self.MapGroups[ i ]
			-- If no weighting is specified, assume the group should be fully represented in every vote.
			local Weighting = tonumber( Group.select ) or #Group.maps

			-- Remove maps randomly from the group until the weighting is satisfied.
			local Maps = TableQuickCopy( Group.maps )
			while #Maps > Weighting do
				local Index = Random( 1, #Maps )
				TableRemove( Maps, Index )
			end

			self.Logger:IfDebugEnabled( LogMapGroupChoices, Group.name, Maps )

			GroupChoices:AddAll( Maps )
		end

		if GroupChoices:GetCount() > 0 then
			-- Cut down the maps to those selected from the groups.
			PotentialMaps:Intersection( GroupChoices )
		end
	else
		local MapGroup = self:GetMapGroup()

		-- If we have a map group, then get rid of any maps that aren't in the group.
		if MapGroup then
			local GroupMaps = TableAsSet( MapGroup.maps )
			PotentialMaps:Intersection( GroupMaps )

			self.LastMapGroup = MapGroup
		end
	end

	-- We then look in the nominations, and enter those into the list.
	local Nominations = self.Vote.Nominated
	local MaxPermittedNominations = self:GetMaxNominations()
	local NumNominationsAdded = 0
	for i = 1, #Nominations do
		local Nominee = Nominations[ i ]

		if self:IsValidMapChoice( self.MapOptions[ Nominee ] or Nominee, PlayerCount ) then
			PotentialMaps:Add( Nominee )
			NumNominationsAdded = NumNominationsAdded + 1

			if NumNominationsAdded >= MaxPermittedNominations then
				-- Stop if we hit the limit of nominations allowed.
				break
			end
		end
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

function Plugin:AddNomination( Nominee, FinalChoices, MaxOptionsExceededAction, NominationsSet )
	if FinalChoices:GetCount() < self.Config.MaxOptions then
		-- Always add when there's still options remaining.
		FinalChoices:Add( Nominee )
		return true
	end

	if MaxOptionsExceededAction == self.MaxOptionsExceededAction.ADD_MAP then
		-- Allow the number of options to exceed the maximum.
		FinalChoices:Add( Nominee )
		return true
	end

	if MaxOptionsExceededAction == self.MaxOptionsExceededAction.REPLACE_MAP then
		-- Try to replace a map in the choices that was not nominated.
		FinalChoices:ReplaceMatchingValue( Nominee, function( Map )
			return not NominationsSet:Contains( Map )
		end )
		return FinalChoices:Contains( Nominee )
	end

	-- Skip nominations when full.
	return false
end

function Plugin:AddNominations( PotentialMaps, FinalChoices, Nominations )
	local MaxPermittedNominations = self:GetMaxNominations()
	local MaxOptionsExceededAction = self.Config.Nominations.MaxOptionsExceededAction
	local NominationsSet = Shine.Set()

	for i = 1, #Nominations do
		local Nominee = Nominations[ i ]

		if PotentialMaps:Contains( Nominee ) and not FinalChoices:Contains( Nominee )
		and self:AddNomination( Nominee, FinalChoices, MaxOptionsExceededAction, NominationsSet ) then
			NominationsSet:Add( Nominee )
			PotentialMaps:Remove( Nominee )

			if NominationsSet:GetCount() >= MaxPermittedNominations then
				break
			end
		end
	end
end

function Plugin:AddCurrentMap( PotentialMaps, FinalChoices )
	local AllowCurMap = self:CanExtend()
	local CurMap = self:GetCurrentMap()
	if AllowCurMap then
		if PotentialMaps:Contains( CurMap ) and self.Config.AlwaysExtend then
			FinalChoices:Add( CurMap )
			PotentialMaps:Remove( CurMap )
		end
	else
		-- Otherwise remove it!
		PotentialMaps:Remove( CurMap )

		if self.Config.ConsiderSimilarMapsAsExtension then
			-- Remove any maps that are similar to the current map from the pool too.
			PotentialMaps:Filter( function( Map )
				return not AreMapsSimilar( Map, CurMap )
			end )
		end
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
	self.Vote.Voted = Shine.UnorderedMultimap()
	self.Vote.NominationTracker = {}
	self.Vote.NotifiedClients = {}

	local MapList = self:BuildMapChoices()
	self.Vote.MapList = MapList

	self.Vote.Nominated = {}
	self.Vote.VoteList = {}
	for i = 1, #MapList do
		self.Vote.VoteList[ MapList[ i ] ] = 0
	end

	local OptionsText = TableConcat( MapList, ", " )
	local VoteLength = self.Config.VoteLengthInMinutes * 60
	local EndTime = SharedTime() + VoteLength

	-- Store these values for new clients.
	self.Vote.EndTime = EndTime
	self.Vote.OptionsText = OptionsText
	self.NextMap.Voting = NextMap

	self:SimpleTimer( 0.1, function()
		if not NextMap then
			self:NotifyTranslated( nil, "RTV_STARTED" )
		else
			self:NotifyTranslated( nil, "NEXT_MAP_STARTED" )
		end
	end )

	-- For every map in the vote list that requires a mod, tell every client the mod ID
	-- so they can load a preview for it if they hover the button.
	self:SendMapMods( nil )
	self:SendMapPrefixes( nil )

	self:SendVoteOptions(
		nil,
		OptionsText,
		VoteLength,
		NextMap,
		self:GetTimeRemaining(),
		not self.VoteOnEnd,
		self:GetCurrentMap()
	)

	self:CreateTimer( self.VoteTimer, VoteLength, 1, function()
		self:ProcessResults( NextMap )
	end )

	for Client in Shine.IterateClients() do
		self.Vote.NotifiedClients[ Client ] = true
	end

	-- Stop the game from starting if the current vote is player-initiated.
	self.CheckGameStart = self.CheckGameStartDuringVote
	self.UpdatePregame = self.UpdatePregameDuringVote

	-- Notify other plugins that a map vote has started to allow them to stop any game start
	-- they may be controlling.
	Shine.Hook.Broadcast( "OnMapVoteStarted", self, NextMap, EndTime )
end
