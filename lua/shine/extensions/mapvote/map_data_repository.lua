--[[
	Manages acquisition and storage of map data to assist map votes.

	Map data includes:
	* A preview image
		* For stock maps, this is taken from screens/<map>.
		* For mods, this is downloaded from Steam via the workshop API and then cached locally.
	* A minimap image
		* For stock/mounted maps, this is taken from maps/overviews/<map>.tga.
		* For mods that are not mounted, this is downloaded from a provided API and then cached locally.
	* Last updated time
		* For mods, this is tracked to ensure that previews/minimaps are refreshed if the mod updates.

	If coroutines didn't cause crashes this would be a lot cleaner...
]]

local Clock = os.time
local IsType = Shine.IsType
local JSONDecode = json.decode
local StringFormat = string.format
local TableBuild = table.Build

local Shine = Shine

local TextureLoader = require "shine/lib/gui/texture_loader"

local METADATA_FILE = "config://shine/cache/maps/index.json"
local OVERVIEW_API_URL = "http://127.0.0.1:7994/ns2/api/overview/%s/%s"
local UPDATE_CHECK_INTERVAL = 60 * 60 * 24

local MapOverviews = {}
local MapPreviews = {}
local ModMaps

do
	local StringMatch = string.match

	Shared.GetMatchingFileNames( "maps/overviews/*.tga", false, MapOverviews )
	for i = 1, #MapOverviews do
		local Path = MapOverviews[ i ]
		local Map = StringMatch( Path, "^maps/overviews/(.+)%.tga$" )
		MapOverviews[ i ] = nil
		MapOverviews[ Map ] = Path
	end

	Shared.GetMatchingFileNames( "screens/*.jpg", true, MapPreviews )
	for i = 1, #MapPreviews do
		local Path = MapPreviews[ i ]
		local Map = StringMatch( Path, "^screens/([^/]+)/1%.jpg$" )
		if Map then
			MapPreviews[ Map ] = Path
		end
		MapPreviews[ i ] = nil
	end

	-- Load previously stored metadata.
	ModMaps = Shine.LoadJSONFile( METADATA_FILE ) or {}

	-- Make sure the metadata is in sync with the current files.
	local CachedImages = {}
	Shared.GetMatchingFileNames( "config://shine/cache/maps/*.png", true, CachedImages )

	local FoundMods = {}
	for i = 1, #CachedImages do
		local Path = CachedImages[ i ]
		local ModID, FileName = StringMatch( Path, "^shine/cache/maps/(%d+)/(.+)%.png$" )
		if ModID then
			FoundMods[ ModID ] = true

			local ModData = TableBuild( ModMaps, ModID )

			local MapName, Type = StringMatch( FileName, "^(.+)_([^_]+)%.png" )
			if Type == "overview" then
				local MapMetadata = TableBuild( ModData, "Maps", MapName )
				MapMetadata.OverviewImage = StringFormat( "config://%s", Path )
			elseif FileName == "preview.png" then
				ModData.PreviewImage = StringFormat( "config://%s", Path )
			end

			ModData.LastUpdatedTime = ModData.LastUpdatedTime or 0
			ModData.NextUpdateCheckTime = ModData.NextUpdateCheckTime or 0
		end
	end

	local function IsMapDataValid( MapData )
		if not IsType( MapData, "table" ) then return false end

		for MapName, Data in pairs( MapData ) do
			if not IsType( Data, "table" ) then
				return false
			end
		end

		return true
	end

	-- Clear out any mods that are no longer in the cache folder, or have missing images.
	for ModID, Data in pairs( ModMaps ) do
		if not FoundMods[ ModID ] or not IsMapDataValid( Data.Maps ) then
			ModMaps[ ModID ] = nil
		end
	end
end

local function SaveCache()
	Shine.SaveJSONFile( ModMaps, METADATA_FILE, { indent = false } )
end

local FileNameFormats = {
	-- Currently all maps have the same preview image (derived from the workshop mod).
	PreviewImage = "config://shine/cache/maps/%s/preview.png",
	-- Overviews however are unique to each map.
	OverviewImage = "config://shine/cache/maps/%s/%s_overview.png"
}
local function SaveImageToCache( ModID, MapName, CacheKey, ImageData, LastUpdatedTime )
	local FileName = StringFormat( FileNameFormats[ CacheKey ], ModID, MapName )
	if not Shine.WriteFile( FileName, ImageData ) then return end

	if MapName then
		local MapEntry = TableBuild( ModMaps, ModID, "Maps", MapName )
		MapEntry[ CacheKey ] = FileName
		MapEntry.NextUpdateCheckTime = Clock() + UPDATE_CHECK_INTERVAL
	else
		local ModEntry = TableBuild( ModMaps, ModID )
		ModEntry[ CacheKey ] = FileName
		ModEntry.NextUpdateCheckTime = Clock() + UPDATE_CHECK_INTERVAL
	end

	if LastUpdatedTime then
		ModMaps[ ModID ].LastUpdatedTime = LastUpdatedTime
	end

	SaveCache()
end

local function LoadFromURL( ModID, MapName, CacheKey, URL, Callback, LastUpdatedTime )
	Shine.TimedHTTPRequest( URL, "GET", function( ImageData )
		if not ImageData then
			Callback( nil, StringFormat( "Unable to acquire image from URL: %s", URL ) )
			return
		end

		local MediaType = TextureLoader.InferMediaType( ImageData )
		if not MediaType then
			Callback( nil, StringFormat( "Unknown image format returned from %s", URL ) )
			return
		end

		TextureLoader.LoadFromMemory( MediaType, ImageData, function( TextureName, Err )
			if not Err then
				-- Image loaded successfully, so cache it.
				SaveImageToCache( ModID, MapName, CacheKey, ImageData, LastUpdatedTime )
			end

			Callback( MapName, TextureName, Err )
		end )
	end, function()
		Callback( MapName, nil, StringFormat( "Timed out attempting to acquire image from URL: %s", URL ) )
	end )
end

local ImageLoaders = {
	PreviewImage = function( ModID, MapName, Callback, ImageURL, LastUpdatedTime )
		if not ImageURL then
			-- Get the file details from Steam and then use the preview image URL.
			local Params = {
				publishedfileids = { ModID }
			}
			LuaPrint( "Requesting preview image for", ModID )
			Shine.ExternalAPIHandler:PerformRequest( "SteamPublic", "GetPublishedFileDetails", Params, {
				OnSuccess = function( PublishedFileDetails )
					local FileDetails = PublishedFileDetails[ 1 ]
					if not IsType( FileDetails, "table" ) then
						Callback( MapName, nil, StringFormat( "Steam did not return details for mod %s", ModID ) )
						return
					end

					if not IsType( FileDetails.preview_url, "string" ) then
						Callback( MapName, nil, StringFormat( "Steam did not return preview_url for mod %s", ModID ) )
						return
					end

					LoadFromURL( ModID, MapName, "PreviewImage", FileDetails.preview_url, Callback, FileDetails.time_updated )
				end,
				OnFailure = function()
					Callback( MapName, nil, StringFormat( "Unable to acquire details for mod %s from Steam.", ModID ) )
				end
			} )
		else
			-- Already know the image URL, just request it.
			LoadFromURL( ModID, MapName, "PreviewImage", ImageURL, Callback, LastUpdatedTime )
		end
	end,
	OverviewImage = function( ModID, MapName, Callback )
		Shine.TimedHTTPRequest( StringFormat( OVERVIEW_API_URL, ModID, MapName ), "GET", function( Response )
			local Data = JSONDecode( Response )
			if not Data or not IsType( Data.OverviewURL, "string" ) then
				Callback( MapName, nil, StringFormat( "No overview available for %s/%s", ModID, MapName ) )
				return
			end

			LoadFromURL( ModID, MapName, "OverviewImage", Data.OverviewURL, Callback )
		end, function()
			Callback( MapName, nil, "Timed out attempting to acquire overview." )
		end, 10 )
	end
}

local function LoadImageFromCache( ModID, MapName, CacheKey, Callback )
	local CacheEntry = ModMaps[ ModID ]
	if MapName then
		CacheEntry = CacheEntry and CacheEntry.Maps[ MapName ]
	end

	local Now = Clock()
	if CacheEntry and IsType( CacheEntry[ CacheKey ], "string" ) and ( CacheEntry.NextUpdateCheckTime or 0 ) > Now then
		-- Cache entry exists, and has not yet expired, so load it from the file.
		TextureLoader.LoadFromFile( CacheEntry[ CacheKey ], function( TextureName, Err )
			if Err then
				-- Failed to load from local file, may be missing or corrupt. Try to get the latest version.
				ImageLoaders[ CacheKey ]( ModID, MapName, Callback )
				return
			end

			Callback( MapName, TextureName, Err )
		end )

		return true
	end

	-- Either the image is not cached, or the cache has expired.
	return false
end

local function CallbackWithFallbackToCache( ModID, IsForMap, CacheKey, Callback )
	return function( MapName, TextureName, Err )
		if TextureName then
			return Callback( MapName, TextureName, Err )
		end

		-- Couldn't load image from the remote source, so check to see if we have a stale cached image.
		local CacheEntry = ModMaps[ ModID ]
		if IsForMap then
			CacheEntry = CacheEntry and CacheEntry.Maps[ MapName ]
		end

		if CacheEntry and CacheEntry[ CacheKey ] then
			LuaPrint( "Loading ", CacheKey, " for ", ModID, MapName, " from remote source failed, using stale cached image." )
			-- Have a stale cached image, wait a while for the API to be available again before trying to update it,
			-- but not as long as if the image were loaded successfully.
			CacheEntry.NextUpdateCheckTime = Clock() + 60 * 60
			SaveCache()

			TextureLoader.LoadFromFile( CacheEntry[ CacheKey ], function( TextureName, Err )
				if Err then
					-- Couldn't load from file, and the API is unavailable, so give up.
					return Callback( MapName, nil, Err )
				end

				Callback( MapName, TextureName, Err )
			end )

			return
		end

		LuaPrint( "Loading", CacheKey, " for ", ModID, MapName, " from remote source failed, no cached image available." )

		-- No cache entry and couldn't load from API, give up.
		return Callback( MapName, nil, Err )
	end
end

local MapDataRepository = {}

-- Previews are currently stored per mod ID, and not specific to a map.
-- Hence the callback is really for all maps with the mod ID at once.
local function WrapCallback( Callback, MapNames )
	return function( _, TextureName, Error )
		for i = 1, #MapNames do
			Callback( MapNames[ i ], TextureName, Error )
		end
	end
end

--[[
	Calls the given callback once for every map in the given map list, providing either a texture
	name that can be used to render a preview image for the map, or nil and an error explaining why
	the preview image could not be loaded.

	ModIDs passed into this method are expected to be strings.

	This is expected to be called once when the map vote UI is initially opened to populate all
	map tiles in one request (as they'll all be visible at once).
]]
function MapDataRepository.GetPreviewImages( Maps, Callback )
	local ModsRequiringLookup = {}
	local MapModIDs = Shine.Multimap()

	for i = 1, #Maps do
		local Entry = Maps[ i ]
		local MapName = Entry.MapName

		if MapPreviews[ MapName ] then
			LuaPrint( MapName, "is a known map, returning its mounted preview image..." )
			Callback( MapName, MapPreviews[ MapName ] )
		elseif Entry.ModID then
			MapModIDs:Add( Entry.ModID, MapName )
		else
			LuaPrint( MapName, "has no mod ID or mounted preview!" )
			Callback( MapName, nil, "Map is not mounted and has no mod ID" )
		end
	end

	for ModID, MapNames in MapModIDs:Iterate() do
		if not LoadImageFromCache( ModID, nil, "PreviewImage", WrapCallback( Callback, MapNames ) ) then
			ModsRequiringLookup[ #ModsRequiringLookup + 1 ] = ModID
			LuaPrint( "Couldn't satisfy mod", ModID, "from cache, will be retrieved from Steam." )
		else
			LuaPrint( ModID, "is already cached, skipping Steam check." )
			MapModIDs:Remove( ModID )
		end
	end

	if #ModsRequiringLookup == 0 then return end

	local Params = {
		publishedfileids = ModsRequiringLookup
	}

	local function OnFailure()
		for ModID, MapNames in MapModIDs:Iterate() do
			for i = 1, #MapNames do
				Callback( MapNames[ i ], nil, StringFormat( "Unable to acquire details for mod %s from Steam.", ModID ) )
			end
		end
	end

	Shine.ExternalAPIHandler:PerformRequest( "SteamPublic", "GetPublishedFileDetails", Params, {
		OnSuccess = function( PublishedFileDetails )
			for i = 1, #PublishedFileDetails do
				local File = PublishedFileDetails[ i ]
				local ModID = tostring( File.publishedfileid )
				local MapNames = MapModIDs:Get( ModID )
				if MapNames then
					MapModIDs:Remove( ModID )

					local LoaderCallback = CallbackWithFallbackToCache( ModID, false, "PreviewImage", Callback )
					ImageLoaders.PreviewImage( ModID, nil, WrapCallback( LoaderCallback, MapNames ),
						File.preview_url, File.time_updated )
				end
			end

			-- Any mods not returned in the response have failed.
			OnFailure()
		end,
		OnFailure = OnFailure
	} )
end

--[[
	Gets a single overview image for the given mod ID (string) and map name.

	This is expected to be called lazily when hovering over a map tile in the map vote UI to
	avoid large volumes of requests to the overview API.
]]
function MapDataRepository.GetOverviewImage( ModID, MapName, Callback )
	if not ModID then
		-- No ModID means we expect the map to be mounted already (e.g. a vanilla map).
		local Overview = MapOverviews[ MapName ]
		if Overview then
			return Callback( MapName, Overview )
		end
		return Callback( MapName, nil, "Map is not mounted and has no mod ID" )
	end

	if LoadImageFromCache( ModID, MapName, "OverviewImage", Callback ) then
		return
	end

	return ImageLoaders.OverviewImage( ModID, MapName,
		CallbackWithFallbackToCache( ModID, true, "OverviewImage", Callback ) )
end

return MapDataRepository
