--[[
	Shine map voting plugin.
]]

local Shine = Shine

local Ceil = math.ceil
local Clamp = math.Clamp
local Floor = math.floor
local GetNumPlayers = Shine.GetHumanPlayerCount
local GetOwner = Server.GetOwner
local InRange = math.InRange
local Max = math.max
local Notify = Shared.Message
local next = next
local pairs = pairs
local Random = math.random
local SharedTime = Shared.GetTime
local StringFormat = string.format
local TableConcat = table.concat
local TableContains = table.contains
local TableCopy = table.Copy
local TableCount = table.Count
local TableRemove = table.remove

local Plugin = Plugin
Plugin.Version = "1.6"

Plugin.HasConfig = true
Plugin.ConfigName = "MapVote.json"

Plugin.DefaultConfig = {
	GetMapsFromMapCycle = true, --Get the valid votemaps directly from the mapcycle file.
	Maps = { --Valid votemaps if you do not wish to get them from the map cycle.
		ns2_veil = true,
		ns2_summit = true,
		ns2_docking = true,
		ns2_mineshaft = true,
		ns2_refinery = true,
		ns2_tram = true,
		ns2_descent = true,
		ns2_biodome = true,
		ns2_eclipse = true,
		ns2_kodiak = true
	},
	ForcedMaps = {}, --Maps that must always be in the vote list.
	DontExtend = {}, --Maps that should never have an extension option.
	IgnoreAutoCycle = {}, --Maps that should not be cycled to unless voted for.
	MinPlayers = 10, --Minimum number of players needed to begin a map vote.
	PercentToStart = 0.6, --Percentage of people needing to vote to change to start a vote.
	PercentToFinish = 0.8, --Percentage of people needing to vote in order to skip the rest of an RTV vote's time.

	VoteLength = 2, --Time in minutes a vote should last before failing.
	ChangeDelay = 10, --Time in seconds to wait before changing map after a vote (gives time for veto)
	VoteDelay = 10, --Time to wait in minutes after map change/vote fail before voting can occur.

	ShowVoteChoices = true, --Show who votes for what map.
	MaxOptions = 4, --Max number of options to provide.

	AllowExtend = true, --Allow going to the same map to be an option.
	ExtendTime = 15, --Time in minutes to extend the map.
	MaxExtends = 1, --Maximum number of map extensions.
	AlwaysExtend = true, --Always show an option to extend the map if not past the max extends.

	TieFails = false, --A tie means the vote fails.
	ChooseRandomOnTie = true, --Choose randomly between the tied maps. If not, a revote is called.
	MaxRevotes = 1, --Maximum number of revotes.

	EnableRTV = true, --Enables RTV voting.

	EnableNextMapVote = true, --Enables the vote to choose the next map.
	NextMapVote = 1, --How far into a game to begin a vote for the next map. Setting to 1 queues for the end of the map.
	RoundLimit = 0, --How many rounds should the map last for? This overrides time based cycling.

	ForceChange = 60, --How long left on the current map when a round ends that should force a change to the next map.
	CycleOnEmpty = false, --Should the map cycle when the server's empty and it's past the map's time limit?
	EmptyPlayerCount = 0, --How many players defines 'empty'?

	ExcludeLastMaps = 0 --How many previous maps should be excluded from votes?
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.VoteTimer = "MapVote"
Plugin.NextMapTimer = "MapVoteNext"

local IsType = Shine.IsType

local function IsTableArray( Table )
	local Count = #Table
	return Count > 0 and Count or nil
end

local function ConvertArrayToLookup( Table )
	local Count = IsTableArray( Table )
	if not Count then return end

	for i = 1, Count do
		Table[ Table[ i ] ] = true
		Table[ i ] = nil
	end
end

local function GetMapName( Map )
	if IsType( Map, "table" ) and Map.map then
		return Map.map
	end

	return Map
end

function Plugin:Initialise()
	self.Config.ForceChange = Max( self.Config.ForceChange, 0 )
	self.Config.RoundLimit = Max( self.Config.RoundLimit, 0 )
	self.Config.NextMapVote = Clamp( self.Config.NextMapVote, 0, 1 )
	self.Config.PercentToFinish = Clamp( self.Config.PercentToFinish, 0, 1 )
	self.Config.PercentToStart = Clamp( self.Config.PercentToStart, 0, 1 )
	self.Config.VoteLength = Max( self.Config.VoteLength, 0.25 )

	self.Round = 0

	self.Vote = self.Vote or {}
	self.Vote.NextVote = self.Vote.NextVote or ( SharedTime() + ( self.Config.VoteDelay * 60 ) )
	self.Vote.Nominated = {} --Table of nominated maps.
	self.Vote.Votes = 0 --Number of map votes that have taken place.
	self.Vote.Voted = {} --Table of players that have voted for a map.
	self.Vote.TotalVotes = 0 --Number of votes in the current map vote.

	self.StartingVote = Shine:CreateVote( function() return self:GetVotesNeededToStart() end,
		function() self:StartVote() end )

	self.NextMap = {}
	self.NextMap.Extends = 0

	local Cycle = MapCycle_GetMapCycle and MapCycle_GetMapCycle()
	if not Cycle then
		Cycle = Shine.LoadJSONFile( "config://MapCycle.json" )
	end

	self.MapProbabilities = {}
	self.MapChoices = {}

	if self.Config.GetMapsFromMapCycle then
		local Maps = Cycle and Cycle.maps

		if Maps then
			self.Config.Maps = {}
			local ConfigMaps = self.Config.Maps

			for i = 1, #Maps do
				local Map = Maps[ i ]

				if IsType( Map, "table" ) and IsType( Map.map, "string" ) then
					ConfigMaps[ Map.map ] = true
					self.MapChoices[ #self.MapChoices + 1 ] = Map
					self.MapProbabilities[ Map.map ] = Clamp( tonumber( Map.chance or Map.Chance ) or 1, 0, 1 )
				elseif IsType( Map, "string" ) then
					ConfigMaps[ Map ] = true
					self.MapProbabilities[ Map ] = 1
					self.MapChoices[ #self.MapChoices + 1 ] = Map
				end
			end
		end
	else
		local Done = {}

		for Map, Data in pairs( self.Config.Maps ) do
			Done[ Map ] = true
			if IsType( Data, "table" ) then
				Data.map = Map
				self.MapChoices[ #self.MapChoices + 1 ] = Data
				self.MapProbabilities[ Map ] = Clamp( tonumber( Data.chance or Data.Chance ) or 1, 0, 1 )
			elseif Data then
				self.MapChoices[ #self.MapChoices + 1 ] = Map
			end
		end

		if Cycle.maps then
			for i = 1, #Cycle.maps do
				local Map = Cycle.maps[ i ]

				if not Done[ GetMapName( Map ) ] then
					self.MapChoices[ #self.MapChoices + 1 ] = Map
				end
			end
		end
	end

	local MapCount = #self.MapChoices
	if MapCount == 0 then
		return false, "No maps configured in either the map cycle or the allowed config list"
	end

	local AllowVotes = MapCount > 1

	if not AllowVotes then
		self.Config.EnableRTV = false
	end

	self.MapCycle = Cycle or {}
	self.MapCycle.time = tonumber( self.MapCycle.time ) or 30

	if self.Config.EnableNextMapVote and AllowVotes then
		if self.Config.NextMapVote == 1 or self.Config.RoundLimit > 0 then
			self.VoteOnEnd = true
		else
			local Time = SharedTime()
			local CycleTime = Cycle and ( Cycle.time * 60 ) or 1800

			self:CreateTimer( self.NextMapTimer,
				( CycleTime * self.Config.NextMapVote ) - Time, 1, function()
				local Players = Shine.GetAllPlayers()
				if #Players > 0 then
					self:StartVote( true )
				end
			end )
		end
	end

	do
		local ForcedMaps = self.Config.ForcedMaps
		local Count = IsTableArray( ForcedMaps )
		local MaxOptions = self.Config.MaxOptions

		if Count then
			self.ForcedMapCount = Clamp( Count, 0, MaxOptions )

			for i = 1, Count do
				local Map = ForcedMaps[ i ]

				if IsType( Map, "string" ) then
					ForcedMaps[ Map ] = true
				end

				ForcedMaps[ i ] = nil
			end
		else
			self.ForcedMapCount = Clamp( TableCount( ForcedMaps ), 0, MaxOptions )
		end

		self.MaxNominations = Max( MaxOptions - self.ForcedMapCount - 1, 0 )
	end

	ConvertArrayToLookup( self.Config.DontExtend )
	ConvertArrayToLookup( self.Config.IgnoreAutoCycle )

	self.Config.ExcludeLastMaps = Max( self.Config.ExcludeLastMaps, 0 )

	if self.Config.ExcludeLastMaps > 0 then
		self:LoadLastMaps()
	end

	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:OnFirstThink()
	local CurMap = Shared.GetMapName()

	local Choices = self.MapChoices
	for i = 1, #Choices do
		local Data = Choices[ i ]

		if IsType( Data, "table" ) and Data.map == CurMap then
			if tonumber( Data.time or Data.Time ) then
				self.MapCycle.time = tonumber( Data.time or Data.Time )
			end

			if tonumber( Data.rounds or Data.Rounds ) then
				self.Config.RoundLimit = Max( tonumber( Data.rounds or Data.Rounds ), 0 )
			end

			break
		end
	end
end

function Plugin:Notify( Player, Message, Format, ... )
	Shine:NotifyDualColour( Player, 255, 255, 0, "[Map Vote]", 255, 255, 255, Message, Format, ... )
end

--[[
	Prevents the map from auto cycling if we've extended the current one.
]]
function Plugin:ShouldCycleMap()
	if self:VoteStarted() then return false end --Do not allow map change whilst a vote is running.
	if self.VoteOnEnd then return false end --Never let the gamerules auto-cycle if we're end of map voting.

	local Winner = self.NextMap.Winner
	if not Winner then return end

	local Time = SharedTime()

	if self.NextMap.ExtendTime and Time < self.NextMap.ExtendTime then
		return false
	end

	if self.Config.RoundLimit > 0 and self.Round < self.Config.RoundLimit then return false end
end

function Plugin:OnCycleMap()
	MapCycle_ChangeMap( self:GetNextMap() )

	return false
end

--[[
	Returns the remaining time on the map (for networking).
]]
function Plugin:GetTimeRemaining()
	local Time = SharedTime()

	local TimeLeft = self.MapCycle.time * 60 - Time

	if self.NextMap.ExtendTime then
		TimeLeft = self.NextMap.ExtendTime - Time
	end

	return Floor( Max( TimeLeft, 0 ) )
end

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
	Save the current map to the last maps list when we change map.
]]
function Plugin:MapChange()
	if self.Config.ExcludeLastMaps > 0 and not self.StoredCurrentMap then
		self:SaveLastMaps()

		self.StoredCurrentMap = true
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

--[[
	Returns the next map in the map cycle or the map that's been voted for next.
]]
function Plugin:GetNextMap()
	local CurMap = Shared.GetMapName()

	local Winner = self.NextMap.Winner
	if Winner and Winner ~= CurMap then return Winner end --Winner decided.

	local Cycle = self.MapCycle
	if not Cycle then return "unknown" end --No map cycle?

	local Maps = self.MapChoices
	local NumMaps = #Maps
	local Index = 0

	for i = #Maps, 1, -1 do
		if GetMapName( Maps[ i ] ) == CurMap then
			Index = i
			break
		end
	end

	Index = Index + 1

	if Index > NumMaps then
		Index = 1
	end

	local Map = Maps[ Index ]

	local IgnoreList = TableCopy( self.Config.IgnoreAutoCycle )
	local PlayerCount = GetNumPlayers()

	--Handle min/max player limits for maps.
	for i = 1, #Maps do
		local Map = Maps[ i ]

		if IsType( Map, "table" ) then
			local Min = Map.min
			local Max = Map.max

			local MapName = Map.map

			if ( Min and PlayerCount < Min ) or ( Max and PlayerCount > Max ) then
				IgnoreList[ MapName ] = true
			end
		end
	end

	if IsType( Map, "table" ) then
		Map = Map.map
	end

	local Iterations = 0

	while IgnoreList[ Map ] and Iterations < NumMaps do
		Index = Index + 1

		if Index > NumMaps then
			Index = 1
		end

		Map = Maps[ Index ]

		if IsType( Map, "table" ) then
			Map = Map.map
		end

		Iterations = Iterations + 1
	end

	return Map
end

function Plugin:Think()
	if not self.Config.CycleOnEmpty then return end
	if SharedTime() <= ( self.MapCycle.time * 60 ) then return end
	if Shine.GameIDs:GetCount() > self.Config.EmptyPlayerCount then return end

	if not self.Cycled then
		self.Cycled = true

		Shine:LogString( "Server is at or below empty player count and map has exceeded its timelimit. Cycling to next map..." )

		MapCycle_ChangeMap( self:GetNextMap() )
	end
end

local LastMapsFile = "config://shine/temp/lastmaps.json"

function Plugin:LoadLastMaps()
	local File, Err = Shine.LoadJSONFile( LastMapsFile )

	if File then
		self.LastMapData = File
	end
end

function Plugin:SaveLastMaps()
	local Max = self.Config.ExcludeLastMaps
	local Data = self.LastMapData

	if not Data then
		self.LastMapData = {}
		Data = self.LastMapData
	end

	Data[ #Data + 1 ] = Shared.GetMapName()

	while #Data > Max do
		TableRemove( Data, 1 )
	end

	local Success, Err = Shine.SaveJSONFile( Data, LastMapsFile )

	if not Success then
		Notify( "Error saving mapvote previous maps file: "..Err )
	end
end

function Plugin:GetLastMaps()
	return self.LastMapData
end

function Plugin:ForcePlayersIntoReadyRoom()
	local Gamerules = GetGamerules()
	local Players = Shine.GetAllPlayers()

	for i = 1, #Players do
		local Ply = Players[ i ]

		if Ply then
			Gamerules:JoinTeam( Ply, 0, nil, true )
		end
	end
end

--[[
	On end of the round, notify players of the remaining time.
]]
function Plugin:EndGame()
	self:SimpleTimer( 10, function()
		local Time = SharedTime()

		local Cycle = self.MapCycle
		local CycleTime = Cycle and ( Cycle.time * 60 ) or 1800

		if not CycleTime then return end

		local ExtendTime = self.NextMap.ExtendTime
		local TimeLeft = CycleTime - Time

		if ExtendTime then
			TimeLeft = ExtendTime - Time
		end

		local Message = "There is %s remaining on this map."
		local Gamerules = GetGamerules()

		if self.Config.RoundLimit > 0 then
			self.Round = self.Round + 1

			--Prevent time based cycling from passing.
			if Gamerules then
				Gamerules.timeToCycleMap = nil
			end

			if self.Round >= self.Config.RoundLimit then
				TimeLeft = 0
			else
				local RoundsLeft = self.Config.RoundLimit - self.Round
				TimeLeft = self.Config.ForceChange + 1

				local RoundMessage = RoundsLeft ~= 1 and StringFormat( "are %i rounds", RoundsLeft )
					or "is 1 round"

				Message = StringFormat( "There %s remaining on this map.", RoundMessage )
			end
		end

		if TimeLeft <= self.Config.ForceChange then
			if not self:VoteStarted() and not self.VoteOnEnd then
				Shine:NotifyColour( nil, 255, 160, 0, "The server will now cycle to %s.", true,
					self:GetNextMap() )

				self:ForcePlayersIntoReadyRoom()
				self.CyclingMap = true

				Gamerules.timeToCycleMap = Time + 30

				return
			end

			if self.VoteOnEnd then
				self:StartVote( true )
				self:ForcePlayersIntoReadyRoom()
			end

			return
		end

		--Round the time down to the nearest 30 seconds.
		if TimeLeft > 30 then
			TimeLeft = TimeLeft - ( TimeLeft % 30 )
		end

		Shine:NotifyColour( nil, 255, 160, 0, Message, true, string.TimeToString( TimeLeft ) )
	end )
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

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	local IsEndVote = self:IsEndVote()

	if not ( self.CyclingMap or IsEndVote ) then return end
	if not Player then return end
	if ShineForce then return end
	if NewTeam == 0 then return end

	local Message = IsEndVote and "You cannot join a team whilst the map vote is in progress." or
		"The map is now changing, you cannot join a team."

	if Shine:CanNotify( GetOwner( Player ) ) then
		Shine:NotifyColour( Player, 255, 160, 0, Message )
	end

	return false
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
	if Client then
		self:SendNetworkMessage( Client, "VoteProgress", { Map = Map, Votes = Count }, true )
	else
		self:SendNetworkMessage( nil, "VoteProgress", { Map = Map, Votes = Count }, true )
	end
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

local BlankTable = {}

--[[
	Tells the given player or everyone that the vote is over.
]]
function Plugin:EndVote( Player )
	if Player then
		self:SendNetworkMessage( Player, "EndVote", BlankTable, true )
	else
		self:SendNetworkMessage( nil, "EndVote", BlankTable, true )
	end
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
	Shine:RemoveText( nil, { ID = 1 } )
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

function Plugin:CanExtend()
	local CurMap = Shared.GetMapName()

	return self.Config.AllowExtend and self.NextMap.Extends < self.Config.MaxExtends
		and not self.Config.DontExtend[ CurMap ]
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

	local AllMaps = table.duplicate( self.Config.Maps )
	local MapList = {}

	local PlayerCount = GetNumPlayers()

	local Cycle = self.MapCycle
	local CycleMaps = self.MapChoices

	local DeniedMaps = {}

	--Handle min/max player count maps.
	if CycleMaps then
		for i = 1, #CycleMaps do
			local Map = CycleMaps[ i ]

			if IsType( Map, "table" ) then
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
		end
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

function Plugin:CreateCommands()
	local function NotifyError( Player, Message, Format, ... )
		if Player then
			Shine:NotifyError( Player, Message, Format, ... )
		else
			Notify( Format and StringFormat( Message, ... ) or Message )
		end
	end

	local function GetPlayerData( Client )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"

		return Player, PlayerName
	end

	local function Nominate( Client, Map )
		local Player, PlayerName = GetPlayerData( Client )

		if not self.Config.Maps[ Map ] then
			NotifyError( Player, "%s is not on the map list.", true, Map )

			return
		end

		if not self:CanExtend() and Shared.GetMapName() == Map then
			NotifyError( Player, "You cannot nominate the current map." )

			return
		end

		local Nominated = self.Vote.Nominated

		if self.Config.ForcedMaps[ Map ] or TableContains( Nominated, Map ) then
			NotifyError( Player, "%s has already been nominated.", true, Map )

			return
		end

		local LastMaps = self:GetLastMaps()
		if LastMaps and TableContains( LastMaps, Map ) then
			NotifyError( Player, "%s was recently played and cannot be voted for yet.", true, Map )

			return
		end

		local Count = #Nominated

		if Count >= self.MaxNominations then
			NotifyError( Player, "Nominations are full." )

			return
		end

		if self:VoteStarted() then
			NotifyError( Player, "A vote is already in progress." )

			return
		end

		Nominated[ Count + 1 ] = Map

		self:Notify( nil, "%s nominated %s for a map vote.", true, PlayerName, Map )
	end
	local NominateCommand = self:BindCommand( "sh_nominate", "nominate", Nominate, true )
	NominateCommand:AddParam{ Type = "string", Error = "Please specify a map name to nominate." }
	NominateCommand:Help( "<mapname> Nominates a map for the next map vote." )

	local function VoteToChange( Client )
		local Player, PlayerName = GetPlayerData( Client )

		if not self.Config.EnableRTV then
			NotifyError( Player, "RTV has been disabled." )

			return
		end

		local Success, Err = self:CanStartVote()

		if not Success then
			NotifyError( Player, Err )

			return
		end

		Success, Err = self:AddStartVote( Client )
		if Success then
			if self:TimerExists( self.VoteTimer ) then return end

			local VotesNeeded = self.StartingVote:GetVotesNeeded()

			self:Notify( nil, "%s voted to change the map (%s more votes needed).", true,
				PlayerName, VotesNeeded )

			return
		end

		NotifyError( Player, Err )
	end
	local StartVoteCommand = self:BindCommand( "sh_votemap", { "rtv", "votemap", "mapvote" },
		VoteToChange, true )
	StartVoteCommand:Help( "Begin a vote to change the map." )

	local function ShowVoteChoice( PlayerName, Map, Revote )
		local NumForThis = self.Vote.VoteList[ Map ]
		local NumTotal = self.Vote.TotalVotes

		self:Notify( nil, "%s %s for %s (%s for this, %i total)", true,
			PlayerName, Revote and "revoted" or "voted", Map,
			NumForThis > 1 and NumForThis.." votes" or "1 vote",
			NumTotal )
	end

	local function Vote( Client, Map )
		local Player, PlayerName = GetPlayerData( Client )

		if not self:VoteStarted() then
			NotifyError( Player, "There is no map vote in progress." )

			return
		end

		local Success, Err = self:AddVote( Client, Map )

		if Success then
			if self.Config.ShowVoteChoices then
				ShowVoteChoice( PlayerName, Err )
			end

			return
		end

		if Err == "already voted" then
			local Success, Err = self:AddVote( Client, Map, true )

			if Success then
				if self.Config.ShowVoteChoices then
					ShowVoteChoice( PlayerName, Err, true )
				end

				return
			end
		end

		NotifyError( Player, "%s is not a valid map choice.", true, Map )
	end
	local VoteCommand = self:BindCommand( "sh_vote", "vote", Vote, true )
	VoteCommand:AddParam{ Type = "string", Error = "Please specify a map to vote for." }
	VoteCommand:Help( "<mapname> Vote for a particular map in the active map vote." )

	local function Veto( Client )
		local Player, PlayerName = GetPlayerData( Client )

		if not self.Vote.CanVeto then
			NotifyError( Player, "There is no map change in progress." )

			return
		end

		self.Vote.Veto = true
		self:Notify( nil, "%s cancelled the map change.", true, PlayerName )
	end
	local VetoCommand = self:BindCommand( "sh_veto", "veto", Veto )
	VetoCommand:Help( "Cancels a map change from a successful map vote." )

	local function ForceVote( Client )
		local Player, PlayerName = GetPlayerData( Client )

		if not self:VoteStarted() then
			self:StartVote( nil, true )

			Shine:Print( "%s[%s] forced a map vote.", true, PlayerName,
				Client and Client:GetUserId() or "N/A" )

			Shine:CommandNotify( Client, "forced a map vote." )
		else
			NotifyError( Client, "Unable to start a new vote, a vote is already in progress." )
		end
	end
	local ForceVoteCommand = self:BindCommand( "sh_forcemapvote", "forcemapvote", ForceVote )
	ForceVoteCommand:Help( "Forces a map vote to start, if possible." )

	local function NotifyPlayer( Player, Message, Format, ... )
		if Player then
			Shine:NotifyColour( Player, 255, 255, 255, Message, Format, ... )
		else
			Notify( Format and StringFormat( Message, ... ) or Message )
		end
	end

	local function TimeLeft( Client )
		local Cycle = self.MapCycle
		local Player = Client and Client:GetControllingPlayer()

		if self.Config.RoundLimit > 0 then
			local RoundsLeft = self.Config.RoundLimit - self.Round

			if RoundsLeft > 1 then
				local RoundMessage = StringFormat( "are %i rounds", RoundsLeft )

				NotifyPlayer( Player, "There %s remaining.", true, RoundMessage )
			else
				NotifyPlayer( Player, "The map will cycle on round end." )
			end

			return
		end

		local CycleTime = Cycle and ( Cycle.time * 60 ) or 1800

		if not CycleTime then
			NotifyPlayer( Player, "The server does not have a map cycle. No timelimit given." )

			return
		end

		local ExtendTime = self.NextMap.ExtendTime

		local TimeLeft = ExtendTime and ( ExtendTime - SharedTime() ) or ( CycleTime - SharedTime() )
		local Message = "%s remaining on this map."

		if TimeLeft <= 0 then
			Message = "Map will change on round end."
		end

		NotifyPlayer( Player, Message, true, string.TimeToString( TimeLeft ) )
	end
	local TimeLeftCommand = self:BindCommand( "sh_timeleft", "timeleft", TimeLeft, true )
	TimeLeftCommand:Help( "Displays the remaining time for the current map." )

	local function NextMap( Client )
		local Map = self:GetNextMap() or "unknown"

		NotifyPlayer( Client, "The next map is currently set to %s.", true, Map )
	end
	local NextMapCommand = self:BindCommand( "sh_nextmap", "nextmap", NextMap, true )
	NextMapCommand:Help( "Displays the next map in the cycle or the next map voted for." )

	local function AddTime( Client, Time )
		if Time == 0 then return end

		self.MapCycle.time = self.MapCycle.time + Time

		Time = Time * 60

		if Time > 0 then
			Shine:CommandNotify( Client, "extended the map by %s.", true,
				string.TimeToString( Time ) )
		else
			Shine:CommandNotify( Client, "shortened the map by %s.", true,
				string.TimeToString( -Time ) )
		end
	end
	local AddTimeCommand = self:BindCommand( "sh_addtimelimit", "addtimelimit", AddTime )
	AddTimeCommand:AddParam{ Type = "number", Error = "Please specify a time to add." }
	AddTimeCommand:Help( "<time in minutes> Adds the given time to the current map's time limit." )

	local function SetTime( Client, Time )
		self.MapCycle.time = Time

		Time = Time * 60

		Shine:CommandNotify( Client, "set the map time to %s.", true, string.TimeToString( Time ) )
	end
	local SetTimeCommand = self:BindCommand( "sh_settimelimit", "settimelimit", SetTime )
	SetTimeCommand:AddParam{ Type = "number", Min = 0, Error = "Please specify the map time." }
	SetTimeCommand:Help( "<time in minutes> Sets the current map's time limit." )

	local function AddRounds( Client, Rounds )
		if Rounds == 0 then return end

		self.Config.RoundLimit = self.Config.RoundLimit + Rounds

		if Rounds > 0 then
			local RoundString = Rounds == 1 and "1 round" or Rounds.." rounds"

			Shine:CommandNotify( Client, "extended the map by %s.", true, RoundString )
		else
			local RoundString = Rounds == -1 and "1 round" or -Rounds.." rounds"

			Shine:CommandNotify( Client, "shortened the map by %s.", true, RoundString )
		end
	end
	local AddRoundsCommand = self:BindCommand( "sh_addroundlimit", "addroundlimit", AddRounds )
	AddRoundsCommand:AddParam{ Type = "number", Round = true,
		Error = "Please specify the amount of rounds to add." }
	AddRoundsCommand:Help( "<rounds> Adds the given number of rounds to the round limit." )

	local function SetRounds( Client, Rounds )
		self.Config.RoundLimit = Rounds

		local RoundString = Rounds == 1 and "1 round" or Rounds.." rounds"

		Shine:CommandNotify( Client, "set the round limit to %s.", true, RoundString )
	end
	local SetRoundsCommand = self:BindCommand( "sh_setroundlimit", "setroundlimit", SetRounds )
	SetRoundsCommand:AddParam{ Type = "number", Round = true, Min = 0,
		Error = "Please specify a round limit." }
	SetRoundsCommand:Help( "<rounds> Sets the round limit." )
end

function Plugin:Cleanup()
	if self:VoteStarted() then
		self:Notify( nil, "Map vote plugin disabled. Current vote cancelled." )

		--Remember to clean up client side vote text/menu entries...
		Shine:RemoveText( nil, { ID = 1 } )
		self:EndVote()
	end

	self.BaseClass.Cleanup( self )

	self.Enabled = false
end
