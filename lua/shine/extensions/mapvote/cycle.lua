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
local StringFind = string.find
local StringFormat = string.format
local StringHexToNumber = string.HexToNumber
local TableAdd = table.Add
local TableConcat = table.concat
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

local function IsValidMapName( Name ) return IsType( Name, "string" ) end
local function ValidateGroups( self, Groups )
	local ValidatedGroups = {}

	for i = 1, #Groups do
		local Group = Groups[ i ]
		if IsType( Group, "table" ) and IsType( Group.maps, "table" ) and IsType( Group.name, "string" ) then
			local ValidMaps = Shine.Stream.Of( Group.maps ):Filter( IsValidMapName ):AsTable()
			if #ValidMaps > 0 then
				ValidatedGroups[ #ValidatedGroups + 1 ] = {
					maps = ValidMaps,
					name = Group.name,
					select = Group.select
				}
			else
				self.Logger:Warn( "Found no valid maps in map group %d ('%s').", i, Group.name )
			end
		else
			self.Logger:Warn(
				"Map group at index %d is invalid. Ensure it is a JSON object with a \"maps\" array and \"name\" value.",
				i
			)
		end
	end

	return ValidatedGroups
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
				self.MapGroups = ValidateGroups( self, Cycle.groups )
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
	local MapModsCacheFile = "config://shine/temp/mapmods.json"

	function Plugin:LoadMapModsCache()
		return Shine.LoadJSONFile( MapModsCacheFile )
	end

	function Plugin:SaveMapModsCache( MapMods )
		Shine.SaveJSONFile( MapMods, MapModsCacheFile )
	end
end

--[[
	Reads the given map list, and for any that are tables with a "mods" entry,
	retrieves the mod's details from Steam and attempts to determine if it is a map.

	Those that are maps are then used when a vote contains a map with the mod to know
	where the overview/map preview image should come from.
]]
function Plugin:InferMapMods( Maps )
	self.KnownMapMods = self:LoadMapModsCache() or {}
	self.KnownVanillaMaps = {}
	self.MapNameToModID = {}

	-- Check all locally installed maps to find any that are known to be from mods.
	local Changed = false
	for i = 1, Server.GetNumMaps() do
		local ModID = Server.GetMapModId( i )
		local MapName = Server.GetMapName( i )
		if ModID and ModID ~= "0" and StringFind( MapName, "^ns[12]?_" ) then
			if not self.KnownMapMods[ ModID ] then
				Changed = true
				self.KnownMapMods[ ModID ] = true
			end

			self.MapNameToModID[ MapName ] = ModID
			self.Logger:Debug( "Map %s is installed locally under mod %s.", MapName, ModID )
		elseif not ModID or ModID == "0" then
			self.KnownVanillaMaps[ MapName ] = true
			self.Logger:Debug( "Map %s has no mod associated with it.", MapName )
		end
	end

	if Changed then
		self:SaveMapModsCache( self.KnownMapMods )
	end

	local Mods = {}
	local Base10ToModID = {}
	local ModToMapName = {}
	local function AddMod( ModID, MapName )
		local HexModID = ModID
		if IsType( HexModID, "number" ) then
			-- New map cycle format, convert back to hex.
			HexModID = StringFormat( "%x", HexModID )
		end

		if self.KnownMapMods[ HexModID ] ~= nil then return end

		local ModIDBase10 = IsType( ModID, "number" ) and ModID or StringHexToNumber( ModID )
		if not ModIDBase10 or Base10ToModID[ ModIDBase10 ] then return end

		ModToMapName[ HexModID ] = MapName
		Base10ToModID[ ModIDBase10 ] = HexModID
		Mods[ #Mods + 1 ] = ModIDBase10
	end

	for i = 1, #Maps do
		local Map = Maps[ i ]
		if IsType( Map, "table" ) and IsType( Map.map, "string" ) and IsType( Map.mods, "table" ) then
			Shine.Stream( Map.mods ):ForEach( function( ModID )
				AddMod( ModID, Map.map )
			end )
		end
	end

	if #Mods == 0 then
		self.Logger:Debug( "No new mods found in map list, skipping lookup." )
		return
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Looking up map mods: %s", TableConcat( Mods, ", " ) )
	end

	local Params = {
		publishedfileids = Mods
	}
	Shine.ExternalAPIHandler:PerformRequest( "SteamPublic", "GetPublishedFileDetails", Params, {
		OnSuccess = function( PublishedFileDetails, RequestError )
			if RequestError then
				self.Logger:Error( "Failed to retrieve mod information from Steam: %s", RequestError )
				return
			end

			if not PublishedFileDetails then
				self.Logger:Warn(
					"Steam failed to respond with mod information, map mods may not be detected correctly."
				)
				return
			end

			local function IsMapTag( Tag ) return Tag.tag == "Map" end

			Shine.Stream( PublishedFileDetails ):ForEach( function( File )
				local FileID = tonumber( File.publishedfileid )
				local ModIDHex = Base10ToModID[ FileID ]
				if not ModIDHex then return end

				if IsType( File.tags, "table" ) and Shine.Stream( File.tags ):AnyMatch( IsMapTag ) then
					self.Logger:Debug( "Mod %s is tagged as a map and thus is assumed to be a map mod.", ModIDHex )
					self.KnownMapMods[ ModIDHex ] = true
					return
				end

				local MapName = ModToMapName[ ModIDHex ]
				if IsType( File.title, "string" ) and StringFind( File.title, MapName, 1, true ) then
					self.Logger:Debug( "Mod %s's title ('%s') contains %s and thus is assumed to be a map mod.",
						ModIDHex, File.title, MapName )
					self.KnownMapMods[ ModIDHex ] = true
					return
				end

				self.Logger:Debug( "Mod %s does not appear to be a map mod.", ModIDHex )
				self.KnownMapMods[ ModIDHex ] = false
			end )

			self:SaveMapModsCache( self.KnownMapMods )
		end,
		OnFailure = function()
			self.Logger:Warn(
				"Failed to retrieve mod details for mods specified in the map cycle. "..
				"Map vote previews may fail to render. "..
				"To mitigate, ensure the first mod in each map's list is the map itself."
			)
		end
	} )
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
		if not self.MapGroups or self.Config.GroupCycleMode ~= self.GroupCycleMode.SEQUENTIAL then return end

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

do
	local StringExplode = string.Explode

	local InfestedModID = "2e813610"
	local FallbackModPrefixes = {
		infest = InfestedModID,
		infect = InfestedModID
	}

	local function GetMapNameWithoutPrefix( MapName )
		local Segments = StringExplode( MapName, "_" )
		return TableConcat( Segments, "_", 2 ), Segments[ 1 ]
	end

	local function GetInstalledMods()
		local ModsByID = {}
		for i = 1, Server.GetNumActiveMods() do
			ModsByID[ Server.GetActiveModId( i ) ] = true
		end
		return ModsByID
	end

	local function ResolvePrefixedMapEntry( MapChoices, Prefixes, CurrentMapWithoutPrefix )
		local Mods = GetInstalledMods()

		for i = 1, #MapChoices do
			local Choice = MapChoices[ i ]
			local MapName = GetMapName( Choice )
			local NameWithoutPrefix, Prefix = GetMapNameWithoutPrefix( MapName )
			local PrefixMod = Prefixes[ Prefix ]

			if PrefixMod and NameWithoutPrefix == CurrentMapWithoutPrefix and Mods[ PrefixMod ] then
				-- Prefix mod is currently loaded and the map names match up, assume that the current map was loaded
				-- using this prefix.
				return MapName
			end
		end

		return nil
	end

	function Plugin:GetMapModPrefixes()
		return self.GetSpecialMapPrefixes and self.GetSpecialMapPrefixes() or FallbackModPrefixes
	end

	function Plugin:GetCurrentMap()
		if self.KnownCurrentMap then
			return self.KnownCurrentMap
		end

		local Prefixes = self:GetMapModPrefixes()
		local CurrentMap = Shared.GetMapName()

		local CurrentMapWithoutPrefix, CurrentPrefix = GetMapNameWithoutPrefix( CurrentMap )
		if CurrentPrefix == "ns2" then
			-- If the current map uses the standard ns2 prefix, check for the game's special prefixes to determine
			-- the current map, as the actual map name will always be the ns2_ prefixed name.
			CurrentMap = ResolvePrefixedMapEntry( self.MapChoices, Prefixes, CurrentMapWithoutPrefix ) or CurrentMap
		end

		self.Logger:Debug( "Detected current map as: %s", CurrentMap )

		self.KnownCurrentMap = CurrentMap

		return CurrentMap
	end
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

local function LogMissingNextMapError( self )
	self.Logger:Error(
		"Unable to find a valid map to advance to! Verify the map cycle and IgnoreAutoCycle "..
		"configuration do not exclude every possible map!"
	)
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
				LogMissingNextMapError( self )
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

	if self.RoundLimit > 0 and self.Round < self.RoundLimit then return false end
end

function Plugin:OnCycleMap()
	local NextMap = self:GetNextMap()
	if not NextMap then
		LogMissingNextMapError( self )
		return
	end

	MapCycle_ChangeMap( NextMap )

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
