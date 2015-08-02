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
local TableCopy = table.Copy
local TableFindByField = table.FindByField
local TableRemove = table.remove

local Plugin = Plugin

local IsType = Shine.IsType

local function GetMapName( Map )
	if IsType( Map, "table" ) and Map.map then
		return Map.map
	end

	return Map
end

function Plugin:AddMapFromCycle( ConfigMaps, Map )
	if IsType( Map, "table" ) and IsType( Map.map, "string" ) then
		ConfigMaps[ Map.map ] = true
		self.MapProbabilities[ Map.map ] = Clamp( tonumber( Map.chance or Map.Chance ) or 1, 0, 1 )
	elseif IsType( Map, "string" ) then
		ConfigMaps[ Map ] = true
		self.MapProbabilities[ Map ] = 1
	end

	self.MapChoices[ #self.MapChoices + 1 ] = Map
end

function Plugin:SetupMaps( Cycle )
	self.MapProbabilities = {}
	self.MapChoices = {}

	if self.Config.GetMapsFromMapCycle then
		local Maps = Cycle and Cycle.maps

		if Maps then
			self.Config.Maps = {}
			local ConfigMaps = self.Config.Maps

			if Cycle.groups then
				self.MapGroups = Cycle.groups
			end

			for i = 1, #Maps do
				local Map = Maps[ i ]

				self:AddMapFromCycle( ConfigMaps, Map )
			end
		end
	else
		for Map, Data in pairs( self.Config.Maps ) do
			if not Data then
				--No need to exist at all...
				self.Config.Maps[ Map ] = nil
			elseif IsType( Data, "table" ) then
				Data.map = Map
				self.MapProbabilities[ Map ] = Clamp( tonumber( Data.chance or Data.Chance ) or 1, 0, 1 )
			end
		end

		if Cycle.maps then
			for i = 1, #Cycle.maps do
				local Map = Cycle.maps[ i ]
				if IsType( Map, "table" ) and IsType( Map.map, "string" ) then
					self.MapProbabilities[ Map.map ] = Clamp( tonumber( Map.chance or Map.Chance ) or 1, 0, 1 )
				end
				self.MapChoices[ #self.MapChoices + 1 ] = Map
			end
		end
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

--[[
	Save the current map to the last maps list when we change map.
	Also, advance the current map group if we have one.
]]
function Plugin:MapChange()
	if self.Config.ExcludeLastMaps > 0 and not self.StoredCurrentMap then
		self:SaveLastMaps()

		self.StoredCurrentMap = true
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
