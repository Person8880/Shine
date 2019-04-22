--[[
	Gamemode stuff.
]]

do
	local Gamemode

	--[[
		Gets the name of the currently running gamemode.
	]]
	function Shine.GetGamemode()
		if Gamemode then return Gamemode end

		local GameSetup = io.open( "game_setup.xml", "r" )
		if not GameSetup then
			Gamemode = "ns2"
			return Gamemode
		end

		local Data = GameSetup:read( "*all" )
		GameSetup:close()

		local Match = Data:match( "<name>(.+)</name>" )
		Gamemode = Match or "ns2"
		return Gamemode
	end
end

do
	local IsType = Shine.IsType
	local StringFind = string.find
	local StringMatch = string.match

	local KnownMaps
	local function FindMaps()
		local Maps = {}

		-- Check the map cycle first as it will include maps that are mounted from mods.
		local MapCycle = MapCycle_GetMapCycle and MapCycle_GetMapCycle()
		if IsType( MapCycle, "table" ) and IsType( MapCycle.maps, "table" ) then
			for i = 1, #MapCycle.maps do
				local Entry = MapCycle.maps[ i ]
				local MapName = IsType( Entry, "table" ) and Entry.map or Entry
				if IsType( MapName, "string" ) then
					Maps[ MapName ] = true
					Maps[ #Maps + 1 ] = MapName
				end
			end
		end

		-- Then check all mounted level files.
		local LevelFiles = {}
		Shared.GetMatchingFileNames( "maps/*.level", false, LevelFiles )
		for i = 1, #LevelFiles do
			local Map = LevelFiles[ i ]
			local MapName = StringMatch( Map, "([^/]+)%.level$" )
			-- Only check maps starting with ns2_ to avoid the menu level.
			if StringMatch( MapName, "^ns2_" ) and not Maps[ MapName ] then
				Maps[ MapName ] = true
				Maps[ #Maps + 1 ] = MapName
			end
		end

		return Maps
	end

	local function GetKnownMaps()
		if not KnownMaps then
			KnownMaps = FindMaps()
		end
		return KnownMaps
	end
	Shine.GetKnownMapNames = GetKnownMaps

	function Shine.FindMapNamesMatching( MapName )
		local KnownMaps = GetKnownMaps()

		-- Provided an exact map name, use it.
		if KnownMaps[ MapName ] then
			return { MapName }
		end

		-- Don't know what map it is, try adding ns2_ at the start.
		local MapWithNS2 = "ns2_"..MapName
		if KnownMaps[ MapWithNS2 ] then
			return { MapWithNS2 }
		end

		-- Doesn't match a known map even with ns2_, so try to find maps that contain the given name.
		local FoundMaps = {}
		for i = 1, #KnownMaps do
			local KnownMap = KnownMaps[ i ]
			if StringFind( KnownMap, MapName, 1, true ) then
				FoundMaps[ #FoundMaps + 1 ] = KnownMap
			end
		end

		return FoundMaps
	end

	function Shine.IsValidMapName( MapName )
		return GetKnownMaps()[ MapName ] or false
	end
end
