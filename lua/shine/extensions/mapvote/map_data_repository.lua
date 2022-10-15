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
local StringExplode = string.Explode
local StringFind = string.find
local StringFormat = string.format
local StringSub = string.sub
local TableBuild = table.Build

local Shine = Shine

local TextureLoader = require "shine/lib/gui/texture_loader"

local MapDataRepository = {
	Logger = Shine.Objects.Logger( Shine.Objects.Logger.LogLevel.INFO, Shared.Message )
}

local METADATA_FILE = "config://shine/cache/maps/index.json"
local OVERVIEW_API_URL = "http://51.68.206.223:7990/ns2/api/overview/%s/%s"
local UPDATE_CHECK_INTERVAL = 60 * 60 * 24
local DEFAULT_OVERVIEW_API_CALL_TIMEOUT = 20

local MapOverviews = {}
local MapPreviews = {}
local MapPreviewOverlays = {}
local ModMaps

local function SaveCache()
	Shine.SaveJSONFile( ModMaps, METADATA_FILE, { indent = false } )
end

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

	local SupportedOverlayExtensions = {
		png = true,
		tga = true,
		dds = true
	}
	Shared.GetMatchingFileNames( "ui/shine/map_overlays/*", false, MapPreviewOverlays )
	for i = 1, #MapPreviewOverlays do
		local Path = MapPreviewOverlays[ i ]
		local Prefix, Extension = StringMatch( Path, "^ui/shine/map_overlays/(.+)%.([^%.]+)$" )
		if Prefix and SupportedOverlayExtensions[ Extension ] then
			MapPreviewOverlays[ Prefix ] = Path
		end
		MapPreviewOverlays[ i ] = nil
	end
	MapPreviewOverlays.infect = MapPreviewOverlays.infest

	-- Load previously stored metadata.
	ModMaps = Shine.LoadJSONFile( METADATA_FILE ) or {}

	-- Make sure the metadata is in sync with the current files.
	local CachedImages = {}
	Shared.GetMatchingFileNames( "config://shine/cache/maps/*", true, CachedImages )

	local FoundMods = {}
	for i = 1, #CachedImages do
		local Path = CachedImages[ i ]
		local FullPath = StringFormat( "config://%s", Path )

		CachedImages[ FullPath ] = true

		local ModID, FileName = StringMatch( Path, "^shine/cache/maps/(%d+)/(.+)%.%a+$" )
		if ModID then
			FoundMods[ ModID ] = true

			local ModData = TableBuild( ModMaps, ModID )

			local MapName, Type = StringMatch( FileName, "^(.+)_([^_]+)$" )
			if Type == "overview" then
				local MapMetadata = TableBuild( ModData, "Maps", MapName )
				MapMetadata.OverviewImage = FullPath
			elseif FileName == "preview" then
				ModData.PreviewImage = FullPath
			end

			ModData.LastUpdatedTime = ModData.LastUpdatedTime or 0
			ModData.NextUpdateCheckTime = ModData.NextUpdateCheckTime or 0
		end
	end

	local function IsMapDataValid( MapData )
		if MapData == nil then
			-- No overview has been loaded yet.
			return true
		end

		if not IsType( MapData, "table" ) then return false end

		for MapName, Data in pairs( MapData ) do
			if not IsType( Data, "table" ) then
				return false
			end

			if not CachedImages[ Data.OverviewImage ] then
				-- If the overview image was deleted, forget this map.
				MapData[ MapName ] = nil
			end
		end

		return true
	end

	-- Clear out any mods that are no longer in the cache folder, or have missing images.
	for ModID, Data in pairs( ModMaps ) do
		if not CachedImages[ Data.PreviewImage ] then
			Data.PreviewImage = nil
		end

		if not FoundMods[ ModID ] or not IsMapDataValid( Data.Maps ) then
			ModMaps[ ModID ] = nil
		end
	end

	SaveCache()
end

local function GetMapPrefix( MapName )
	local Start = StringFind( MapName, "_", 1, true )
	if not Start then return MapName end

	return StringSub( MapName, 1, Start - 1 )
end

do
	local SGUI = Shine.GUI

	local function PreviewExists( MapName )
		-- Look for either a preview image, or an overlay (maps shouldn't have both).
		return MapPreviews[ MapName ] ~= nil or MapPreviewOverlays[ GetMapPrefix( MapName ) ] ~= nil
	end

	local function GetPreviewImage( MapName )
		return MapPreviews[ MapName ] or MapPreviewOverlays[ GetMapPrefix( MapName ) ]
	end

	--[[
		Precaches the map preview textures to avoid awkward pop-in.
		Shared.PrecacheTexture doesn't seem to work on the screen textures, hence this horrible hack.
	]]
	function MapDataRepository.PrecacheMapPreviews( MapNames )
		local PreviewsToPrecache = Shine.Stream.Of( MapNames ):Filter( PreviewExists ):Map( GetPreviewImage ):AsTable()
		if #PreviewsToPrecache == 0 then return end

		local Index = 0
		local Image

		-- Textures seem to be cached only if visible for at least one frame (where visible means visible as far as the
		-- GUI system can tell).
		Shine.Hook.Add( "Think", PreviewsToPrecache, function()
			if not Image then
				Image = SGUI:Create( "Image" )
				Image:SetSize( Vector2( 1, 1 ) )
				-- This hides the image element from view, but still loads the texture.
				Image:SetShader( SGUI.Shaders.Invisible )
			end

			Index = Index + 1
			if Index > #PreviewsToPrecache then
				Shine.Hook.Remove( "Think", PreviewsToPrecache )
				if SGUI.IsValid( Image ) then
					Image:Destroy()
					Image = nil
				end
				return
			end

			local TextureName = PreviewsToPrecache[ Index ]
			MapDataRepository.Logger:Debug( "Precaching map preview: %s", TextureName )
			Image:SetTexture( TextureName )
		end )
	end
end

local FileNameFormats = {
	-- Currently all maps have the same preview image (derived from the workshop mod).
	PreviewImage = "config://shine/cache/maps/%s/preview.dat",
	-- Overviews however are unique to each map.
	OverviewImage = "config://shine/cache/maps/%s/%s_overview.dat"
}
local function SaveImageToCache( ModID, MapName, CacheKey, ImageData, LastUpdatedTime )
	local FileName
	if CacheKey == "PreviewImage" then
		FileName = StringFormat( FileNameFormats[ CacheKey ], ModID )
	else
		FileName = StringFormat( FileNameFormats[ CacheKey ], ModID, MapName )
	end

	do
		local Success, Err = Shine.WriteFile( FileName, ImageData )
		if not Success then
			MapDataRepository.Logger:Debug(
				"Failed to save %s to %s for %s/%s: %s", CacheKey, FileName, ModID, MapName, Err
			)
			return
		end
	end

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

	MapDataRepository.Logger:Debug( "Updated cache with %s for %s/%s saved as: %s", CacheKey, ModID, MapName, FileName )
end

local function LoadFromURL( ModID, MapName, CacheKey, URL, Callback, LastUpdatedTime )
	MapDataRepository.Logger:Debug( "Loading image for %s/%s from URL: %s", ModID, MapName, URL )

	Shine.TimedHTTPRequest( URL, "GET", function( ImageData, RequestError )
		if not ImageData or RequestError then
			Callback(
				MapName,
				nil,
				StringFormat(
					"Unable to acquire image from URL '%s': %s", URL, RequestError or "no response received."
				)
			)
			return
		end

		local MediaType = TextureLoader.InferMediaType( ImageData )
		if not MediaType then
			Callback( MapName, nil, StringFormat( "Unknown image format returned from %s", URL ) )
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

			MapDataRepository.Logger:Debug( "Requesting preview image for %s", ModID )

			Shine.ExternalAPIHandler:PerformRequest( "SteamPublic", "GetPublishedFileDetails", Params, {
				OnSuccess = function( PublishedFileDetails, RequestError )
					if RequestError then
						Callback(
							MapName,
							nil,
							StringFormat( "Failed to retrieve details for mod %s: %s", ModID, RequestError )
						)
						return
					end

					local FileDetails = PublishedFileDetails and PublishedFileDetails[ 1 ]
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
	OverviewImage = function( ModID, MapName, Callback, TimeoutInSeconds )
		local URL = StringFormat( OVERVIEW_API_URL, ModID, MapName )
		Shine.TimedHTTPRequest( URL, "GET", function( Response, RequestError )
			if not Response or RequestError then
				Callback(
					MapName,
					nil,
					StringFormat(
						"Failed to retrieve overview for %s/%s: %s",
						ModID,
						MapName,
						RequestError or "no response received."
					)
				)
				return
			end

			local Data = JSONDecode( Response )
			if not Data or not IsType( Data.OverviewURL, "string" ) then
				Callback( MapName, nil, StringFormat( "No overview available for %s/%s", ModID, MapName ) )
				return
			end

			LoadFromURL( ModID, MapName, "OverviewImage", Data.OverviewURL, Callback )
		end, function()
			Callback( MapName, nil, "Timed out attempting to acquire overview." )
		end, TimeoutInSeconds or DEFAULT_OVERVIEW_API_CALL_TIMEOUT )
	end
}

local function GetCacheEntry( ModID, MapName )
	local CacheEntry = ModMaps[ ModID ]
	if MapName then
		CacheEntry = CacheEntry and CacheEntry.Maps and CacheEntry.Maps[ MapName ]
	end
	return CacheEntry
end

local function LoadImageFromCache( ModID, MapName, CacheKey, Callback )
	local CacheEntry = GetCacheEntry( ModID, MapName )
	local Now = Clock()

	if CacheEntry and IsType( CacheEntry[ CacheKey ], "string" ) and ( CacheEntry.NextUpdateCheckTime or 0 ) > Now then
		local FileName = CacheEntry[ CacheKey ]

		MapDataRepository.Logger:Debug( "%s/%s has cached %s: %s", ModID, MapName, CacheKey, FileName )

		-- Cache entry exists, and has not yet expired, so load it from the file.
		TextureLoader.LoadFromFile( FileName, function( TextureName, Err )
			if Err then
				MapDataRepository.Logger:Debug(
					"Failed to load %s for %s/%s from cache: %s", CacheKey, ModID, MapName, Err
				)

				-- Failed to load from local file, may be missing or corrupt. Try to get the latest version.
				ImageLoaders[ CacheKey ]( ModID, MapName, Callback )

				return
			end

			MapDataRepository.Logger:Debug(
				"Successfully loaded %s for %s/%s from file: %s", CacheKey, ModID, MapName, FileName
			)

			Callback( MapName, TextureName, Err )
		end )

		return true
	end

	if MapDataRepository.Logger:IsDebugEnabled() then
		MapDataRepository.Logger:Debug(
			"%s/%s has expired or missing %s cache entry: %s",
			ModID, MapName, CacheKey, CacheEntry and table.ToString( CacheEntry )
		)
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
		local CacheEntry = GetCacheEntry( ModID, IsForMap and MapName )
		if CacheEntry and IsType( CacheEntry[ CacheKey ], "string" ) then
			MapDataRepository.Logger:Debug(
				"Loading %s for %s/%s from remote source failed, using stale cached image. Error: %s",
				CacheKey, ModID, MapName, Err
			)

			-- Have a stale cached image, wait a while for the API to be available again before trying to update it,
			-- but not as long as if the image were loaded successfully.
			CacheEntry.NextUpdateCheckTime = Clock() + 60 * 60
			SaveCache()

			TextureLoader.LoadFromFile( CacheEntry[ CacheKey ], function( TextureName, FileLoadError )
				if FileLoadError then
					-- Couldn't load from file, and the API is unavailable, so give up.
					return Callback( MapName, nil, FileLoadError )
				end

				Callback( MapName, TextureName, FileLoadError )
			end )

			return
		end

		MapDataRepository.Logger:Debug(
			"Loading %s for %s/%s from remote source failed, no cached image available. Error: %s",
			CacheKey, ModID, MapName, Err
		)

		-- No cache entry and couldn't load from API, give up.
		return Callback( MapName, nil, Err )
	end
end

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
		local PreviewName = Entry.PreviewName or MapName

		if MapPreviews[ PreviewName ] then
			MapDataRepository.Logger:Debug( "%s is a known map, returning its mounted preview image...", MapName )
			Callback( MapName, MapPreviews[ PreviewName ] )
		elseif Entry.ModID then
			MapModIDs:Add( Entry.ModID, MapName )
		else
			MapDataRepository.Logger:Debug( "%s has no mod ID or mounted preview!", MapName )
			Callback( MapName, nil, "Map is not mounted and has no mod ID" )
		end
	end

	for ModID, MapNames in MapModIDs:Iterate() do
		if not LoadImageFromCache( ModID, nil, "PreviewImage", WrapCallback( Callback, MapNames ) ) then
			ModsRequiringLookup[ #ModsRequiringLookup + 1 ] = ModID
			MapDataRepository.Logger:Debug( "Couldn't satisfy mod %s from cache, will be retrieved from Steam.", ModID )
		else
			MapDataRepository.Logger:Debug( "%s is already cached, skipping Steam check.", ModID )
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
			if PublishedFileDetails then
				for i = 1, #PublishedFileDetails do
					local File = PublishedFileDetails[ i ]
					local ModID = tostring( File.publishedfileid )
					local MapNames = MapModIDs:Get( ModID )
					if MapNames and IsType( File.preview_url, "string" ) then
						MapModIDs:Remove( ModID )

						local LoaderCallback = CallbackWithFallbackToCache(
							ModID, false, "PreviewImage", WrapCallback( Callback, MapNames )
						)
						ImageLoaders.PreviewImage( ModID, nil, LoaderCallback, File.preview_url, File.time_updated )
					end
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

	local TimeoutInSeconds = DEFAULT_OVERVIEW_API_CALL_TIMEOUT
	local CacheEntry = GetCacheEntry( ModID, MapName )
	if CacheEntry and IsType( CacheEntry.OverviewImage, "string" ) then
		-- Wait less time to get an updated image if it's already cached as a timeout will fallback to the cache.
		TimeoutInSeconds = 5
	end

	return ImageLoaders.OverviewImage(
		ModID,
		MapName,
		CallbackWithFallbackToCache( ModID, true, "OverviewImage", Callback ),
		TimeoutInSeconds
	)
end

function MapDataRepository.GetPreviewOverlay( MapName )
	local Prefix = GetMapPrefix( MapName )
	return MapPreviewOverlays[ Prefix ]
end

return MapDataRepository
