--[[
	Map cycling logic.
]]

local Shine = Shine

local Clamp = math.Clamp
local Floor = math.floor
local GetNumPlayers = Shine.GetHumanPlayerCount
local Max = math.max
local Notify = Shared.Message
local pairs = pairs
local SharedTime = Shared.GetTime
local TableAdd = table.Add
local TableCopy = table.Copy
local TableFindByField = table.FindByField
local TableRemove = table.remove
local TableSlice = table.Slice

local Plugin = ...

local IsType = Shine.IsType

local function GetMapName( Map )
	if IsType( Map, "table" ) and Map.map then
		return Map.map
	end

	return Map
end

local function SetupFromTable( self, Map )
	self.MapProbabilities[ Map.map ] = Clamp( tonumber( Map.chance or Map.Chance ) or 1, 0, 1 )

	if IsType( Map.percent or Map.Percent, "number" ) then
		self.TrackMapStats = true
	end

	self.MapOptions[ Map.map ] = Map
end

function Plugin:AddMapFromCycle( ConfigMaps, Map )
	if IsType( Map, "table" ) and IsType( Map.map, "string" ) then
		ConfigMaps[ Map.map ] = true
		SetupFromTable( self, Map )
	elseif IsType( Map, "string" ) then
		ConfigMaps[ Map ] = true
		self.MapProbabilities[ Map ] = 1
	else
		-- Skip invalid map entries.
		return false
	end

	self.MapChoices[ #self.MapChoices + 1 ] = Map

	return true
end

function Plugin:SetupMaps( Cycle )
	self.MapProbabilities = {}
	self.MapChoices = {}
	self.MapOptions = {}

	if self.Config.GetMapsFromMapCycle then
		local Maps = Cycle and Cycle.maps

		if IsType( Maps, "table" ) then
			self.Config.Maps = {}

			local ConfigMaps = self.Config.Maps
			if IsType( Cycle.groups, "table" ) then
				self.MapGroups = Cycle.groups
			end

			for i = 1, #Maps do
				local Map = Maps[ i ]
				if not self:AddMapFromCycle( ConfigMaps, Map ) then
					self.Logger:Warn(
						"Entry %d in the map cycle \"maps\" list does not specify a map name and will be ignored.",
						i
					)
				end
			end
		else
			self.Logger:Error(
				"The map cycle \"maps\" list is invalid (expected table, got %s). Check the MapCycle.json file.",
				type( Maps )
			)
		end
	else
		for Map, Data in pairs( self.Config.Maps ) do
			if IsType( Map, "string" ) then
				if not Data then
					-- No need to exist at all...
					self.Config.Maps[ Map ] = nil
				elseif IsType( Data, "table" ) then
					Data.map = Map
					SetupFromTable( self, Data )
				else
					self.MapProbabilities[ Map ] = 1
				end
			end
		end

		if Cycle and IsType( Cycle.maps, "table" ) then
			for i = 1, #Cycle.maps do
				local Map = Cycle.maps[ i ]

				local IsValidMap = false
				if IsType( Map, "table" ) and IsType( Map.map, "string" ) then
					IsValidMap = true
					SetupFromTable( self, Map )
				elseif IsType( Map, "string" ) then
					IsValidMap = true
					self.MapProbabilities[ Map ] = 1
				else
					self.Logger:Warn(
						"Entry %d in the map cycle \"maps\" list does not specify a map name and will be ignored.",
						i
					)
				end

				if IsValidMap then
					self.MapChoices[ #self.MapChoices + 1 ] = Map
				end
			end
		else
			self.Logger:Error(
				"The map cycle \"maps\" list is invalid (expected table, got %s). Check the MapCycle.json file.",
				type( Maps )
			)
		end
	end

	if self.TrackMapStats then
		self:LoadMapStats()
	end
end

do
	local MapGroupFile = "config://shine/temp/mapgroup.json"
	function Plugin:GetMapGroup()
		if not self.MapGroups then return nil end
		if self.LastMapGroup then return self.LastMapGroup end

		local NextMapGroup = Shine.ReadFile( MapGroupFile )
		if not NextMapGroup then
			return self.MapGroups[ 1 ]
		end

		return TableFindByField( self.MapGroups, "name", NextMapGroup ) or self.MapGroups[ 1 ]
	end

	function Plugin:AdvanceMapGroup( LastMapGroup )
		if not self.MapGroups then return end

		local Group, Index = TableFindByField( self.MapGroups, "name", LastMapGroup )
		local NextIndex = Index == #self.MapGroups and 1 or ( Index + 1 )

		local NextGroup = self.MapGroups[ NextIndex ]
		Shine.WriteFile( MapGroupFile, NextGroup.name )
	end
end

function Plugin:IsConditionalMap( Map )
	if not IsType( Map, "table" ) or not IsType( Map.map, "string" ) then
		return false
	end

	return IsType( Map.min, "number" ) or IsType( Map.max, "number" )
		or ( self.TrackMapStats and IsType( Map.percent or Map.Percent, "number" ) )
end

--[[
	Checks various restrictions to see if the map should be available.
]]
function Plugin:IsValidMapChoice( Map, PlayerCount )
	if not IsType( Map, "table" ) or not IsType( Map.map, "string" ) then
		return true
	end

	local Min = Map.min
	local Max = Map.max

	local MapName = Map.map

	if IsType( Min, "number" ) and PlayerCount < Min then
		return false
	end

	if IsType( Max, "number" ) and PlayerCount > Max then
		return false
	end

	-- Track percentage of total maps played.
	local Percent = Map.percent or Map.Percent
	if self.TrackMapStats and IsType( Percent, "number" ) then
		local Stats = self.MapStats
		local CurrentPercent = ( Stats[ MapName ] or 0 ) / self.TotalPlayedMaps * 100

		if CurrentPercent >= Percent then
			return false
		end
	end

	return true
end

function Plugin:GetCurrentMap()
	return Shared.GetMapName()
end

--[[
	Returns the next map in the map cycle or the map that's been voted for next.
]]
function Plugin:GetNextMap()
	local CurMap = self:GetCurrentMap()
	local Winner = self.NextMap.Winner

	if Winner and Winner ~= CurMap then
		-- Vote has decided the next map.
		return Winner
	end

	local Maps = self.MapChoices
	local NumMaps = #Maps
	local Index = 0

	for i = #Maps, 1, -1 do
		if GetMapName( Maps[ i ] ) == CurMap then
			Index = i
			break
		end
	end

	local CycleExcludingCurrentMap = Shine.Stream(
		TableAdd(
			TableSlice( Maps, Index + 1 ),
			TableSlice( Maps, 1, Index - 1 )
		)
	):Filter( function( Map ) return not self.Config.IgnoreAutoCycle[ GetMapName( Map ) ] end )

	-- Start with the next map that's not ignored when cycling, in case every map is marked as invalid
	-- for the current player count.
	local NextMap = CycleExcludingCurrentMap:AsTable()[ 1 ]

	local PlayerCount = GetNumPlayers()
	local ValidMaps = CycleExcludingCurrentMap:Filter( function( Map )
		return self:IsValidMapChoice( Map, PlayerCount )
	end ):AsTable()

	if #ValidMaps > 0 then
		NextMap = ValidMaps[ 1 ]
	end

	if IsType( NextMap, "table" ) then
		NextMap = NextMap.map
	end

	return NextMap
end

function Plugin:SetupEmptyCheckTimer()
	if not self.Config.CycleOnEmpty then return end

	self:CreateTimer( "EmptyCheck", 1, -1, function()
		if SharedTime() <= ( self.MapCycle.time * 60 ) then return end
		if Shine.GameIDs:GetCount() > self.Config.EmptyPlayerCount then return end

		if not self.Cycled then
			self.Cycled = true

			self.Logger:Info(
				"Server is at or below empty player count and map has exceeded its timelimit. Cycling to next map..."
			)

			local NextMap = self:GetNextMap()
			if not NextMap then
				self.Logger:Error(
					"Unable to find a valid map to advance to! Verify the map cycle and IgnoreAutoCycle "..
					"configuration do not exclude every possible map!"
				)
			else
				MapCycle_ChangeMap( NextMap )
			end
		end
	end )
end

local LastMapsFile = "config://shine/temp/lastmaps.json"
local MapStatsFile = "config://shine/temp/mapstats.json"

function Plugin:LoadLastMaps()
	local File, Err = Shine.LoadJSONFile( LastMapsFile )

	if File then
		self.LastMapData = File
	end
end

function Plugin:SaveLastMaps()
	local Data = self.LastMapData

	if not Data then
		self.LastMapData = {}
		Data = self.LastMapData
	end

	-- Store the last played maps in an ever repeating cycle.
	local CurrentMap = self:GetCurrentMap()
	for i = #Data, 1, -1 do
		if Data[ i ] == CurrentMap then
			TableRemove( Data, i )
		end
	end
	Data[ #Data + 1 ] = CurrentMap

	local Success, Err = Shine.SaveJSONFile( Data, LastMapsFile )

	if not Success then
		Notify( "Error saving mapvote previous maps file: "..Err )
	end
end

function Plugin:LoadMapStats()
	self.MapStats = Shine.LoadJSONFile( MapStatsFile ) or {}

	local TotalPlayed = 0
	for Map, Count in pairs( self.MapStats ) do
		TotalPlayed = TotalPlayed + Count
	end

	if TotalPlayed <= 0 then
		TotalPlayed = 1
	end

	self.TotalPlayedMaps = TotalPlayed
end

function Plugin:SaveMapStats()
	local Map = self:GetCurrentMap()

	self.MapStats[ Map ] = ( self.MapStats[ Map ] or 0 ) + 1

	local Success, Err = Shine.SaveJSONFile( self.MapStats, MapStatsFile )
	if not Success then
		Notify( "Error saving mapvote stats file: "..Err )
	end
end

function Plugin:GetLastMaps()
	return self.LastMapData
end

--[[
	Save the current map to the last maps list when we change map.
	Also, advance the current map group if we have one.
]]
function Plugin:MapChange()
	if not self.StoredCurrentMap then
		self.StoredCurrentMap = true
		self:SaveLastMaps()
	end

	if self.TrackMapStats and not self.StoredMapStats then
		self.StoredMapStats = true
		self:SaveMapStats()
	end

	if self.LastMapGroup then
		self:AdvanceMapGroup( self.LastMapGroup.name )
	end
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
