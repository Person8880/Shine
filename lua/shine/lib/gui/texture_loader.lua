--[[
	Provides a way to load image data and turn it into textures.

	Each request for a texture uses a WebView to either load a remote image file
	from a given URL, or otherwise to inject image data from memory into a basic
	web page.

	Once the web view has rendered the image, a GUIView is created to copy the data
	to a texture managed by the GUIView (as the target texture of a WebView cannot be
	changed and will be destroyed when it is). This avoids having to keep around many
	WebView instances, GUIViews are much cheaper.

	This texture is then passed back to the caller in the callback. Once the caller has
	finished using the texture, it should use Free() to ensure the GUIView and texture
	data are cleaned up.
]]

local Hook = Shine.Hook

local Clamp = math.Clamp
local Clock = Shared.GetSystemTimeReal
local Max = math.max
local StringFormat = string.format
local xpcall = xpcall

local OnCallbackError = Shine.BuildErrorHandler( "Texture loader callback error" )

local MIN_IMAGE_SIZE = 16
local MAX_IMAGE_SIZE = 4096

local MIN_TIMEOUT_SECONDS = 0.1

-- How long after an image loader becomes idle before its WebView should be destroyed.
-- This avoids WebView instances being left running, but also prevents them being constantly
-- created and destroyed in close proximity.
local IDLE_WEBVIEW_TIMEOUT = 30
-- Use a single texture for the web view, this will be copied to GUIViews to retain.
-- A GUIView should be much cheaper to keep hanging around than a WebView is.
local WEB_VIEW_TEXTURE = "*shine_texture_loader_webview"

local DefaultWidth = 1024
local DefaultHeight = 1024
local DefaultTimeout = 5

local ErrorCodes = {
	-- Loading the image took too long.
	TIMEOUT_ERROR = "TIMEOUT_ERROR",
	-- Image data provided is corrupted.
	IMAGE_DATA_ERROR = "IMAGE_DATA_ERROR",
	-- Couldn't open the given image file.
	FILE_OPEN_ERROR = "FILE_OPEN_ERROR"
}

-- Cache and texture pool are shared by all loader queues.
local CacheByURL = {}
local TexturePool = {}

local function GetTextureName()
	local Index = #TexturePool + 1

	for i = 1, #TexturePool do
		local Entry = TexturePool[ i ]
		if Entry.Free then
			Entry.Free = false
			return Entry.TextureName, Entry
		end
	end

	local TextureName = "*shine_texture_loader_"..Index
	TexturePool[ Index ] = {
		Free = false,
		TextureName = TextureName
	}
	TexturePool[ TextureName ] = TexturePool[ Index ]

	return TextureName, TexturePool[ Index ]
end

local function FreeTexture( TextureName )
	local Entry = TexturePool[ TextureName ]
	if not Entry or Entry.Free then return end

	if Entry.GUIView then
		Shine.Logger:Debug( "Destroying GUIView for %s: %s", Entry.URL, Entry.GUIView )
		Client.DestroyGUIView( Entry.GUIView )
		Entry.GUIView = nil
	end

	if Entry.IsCaching and Entry.URL then
		CacheByURL[ Entry.URL ] = nil
	end

	Entry.URL = nil
	Entry.IsCaching = nil
	Entry.SetupJS = nil
	Entry.Width = nil
	Entry.Height = nil
	Entry.Free = true
end

local WebViewImageLoader = Shine.TypeDef()

function WebViewImageLoader:Init( Index )
	self.RequestQueue = Shine.Queue()
	self.TextureName = WEB_VIEW_TEXTURE..Index
	self.JSAlertHook = function( WebView, Alert )
		if self.OnAlert then
			self.OnAlert( Alert )
		end
	end

	self.ThinkCallback = function()
		self:WaitForURLToLoad()
	end

	return self
end

function WebViewImageLoader:IsIdle()
	return self.RequestQueue:GetCount() == 0
end

function WebViewImageLoader:AddEntry( Entry )
	self.RequestQueue:Add( Entry )

	if self.RequestQueue:GetCount() > 1 then
		return
	end

	self:ProcessNextEntry()
end

function WebViewImageLoader:ProcessNextEntry()
	local Entry = self.RequestQueue:Peek()
	if not Entry then
		Hook.Remove( "Think", self )

		self.WebViewDestructionTimer = Shine.Timer.Simple( IDLE_WEBVIEW_TIMEOUT, function()
			Shine.Logger:Debug(
				"Image loader has been idle for %s seconds, destroying web view.",
				IDLE_WEBVIEW_TIMEOUT
			)
			if self.WebView then
				Client.DestroyWebView( self.WebView )
				self.WebView = nil
			end
		end )

		return
	end

	if self.WebViewDestructionTimer then
		self.WebViewDestructionTimer:Destroy()
		self.WebViewDestructionTimer = nil
	end

	local TextureName, PoolEntry
	if Entry.TextureName then
		TextureName, PoolEntry = Entry.TextureName, Entry.PoolEntry
	else
		TextureName, PoolEntry = GetTextureName()
	end

	PoolEntry.URL = Entry.URL
	PoolEntry.IsCaching = Entry.IsCaching

	Entry.TextureName = TextureName
	Entry.PoolEntry = PoolEntry

	if ( Entry.Width ~= self.Width or Entry.Height ~= self.Height ) and self.WebView then
		-- Need to re-initialise the web view with the new texture size, as it's determined when constructed.
		Client.DestroyWebView( self.WebView )
		self.WebView = nil
	end

	self.Width = Entry.Width
	self.Height = Entry.Height

	if not self.WebView then
		self.WebView = Client.CreateWebView( self.Width, self.Height )
		-- Alerts are the only way to send any data back to Lua from the WebView...
		self.WebView:HookJSAlert( self.JSAlertHook )
		self.WebView:SetTargetTexture( self.TextureName )
	end

	self.WebView:LoadUrl( Entry.URL )
	self.TimeoutTime = Clock() + Entry.TimeoutInSeconds

	Hook.Add( "Think", self, self.ThinkCallback )
end

local STATE_LOADING_URL = 1
local STATE_WAITING_FOR_CONFIRMATION = 2
local STATE_SETUP_GUI_VIEW = 3
local STATE_COPYING_TEXTURE = 4

local IMAGE_CONFIRM_JS = [[var Image = document.querySelector( "img" );
var Interval;
function IsImageReady() {
	// Make sure the image has actually loaded correctly before continuing.
	// If the image failed to load for some reason, the timeout will be hit.
	if ( Image && Image.complete && Image.naturalWidth !== 0 ) {
		if ( Interval ) {
			clearInterval( Interval );
		}
		alert( "OK" );
		return true;
	}
}

if ( window.location.href.indexOf( %q ) < 0 ) {
	// Sanity check, should never happen.
	alert( "WRONG_URL" );
} else {
	// Make sure the background is transparent to allow alpha in images to show.
	document.querySelector( "body" ).style[ 'background-color' ] = 'rgba( 0, 0, 0, 0 )';

	if ( !IsImageReady() ) {
		Interval = setInterval( IsImageReady, 10 );
	}
}
]]

local function CheckTimeout( self, Entry )
	if Clock() > self.TimeoutTime then
		-- Waited too long for the image to load, run all the callbacks with a timeout error
		-- and proceed to the next image.
		self.OnAlert = nil

		for i = 1, #Entry.Callbacks do
			xpcall(
				Entry.Callbacks[ i ],
				OnCallbackError,
				nil,
				StringFormat( "%s: Request timed out.", ErrorCodes.TIMEOUT_ERROR )
			)
		end

		CacheByURL[ Entry.URL ] = nil
		FreeTexture( Entry.TextureName )

		self.RequestQueue:Pop()
		self:ProcessNextEntry()
	end
end

local StateUpdaters = {
	-- Start by waiting for the WebView to indicate it's finished loading, then inject some simple JS to verify the
	-- image loaded successfully.
	[ STATE_LOADING_URL ] = function( self, Entry )
		if not self.WebView:GetUrlLoaded() then
			CheckTimeout( self, Entry )
			return
		end

		Shine.Logger:Debug( "%s - Completed loading %s, now setting up confirmation...", Clock(), Entry.URL )

		if Entry.SetupJS then
			-- Execute any setup script required before confirming the image is loaded (e.g. for local data injection).
			self.WebView:ExecuteJS( Entry.SetupJS )
		end

		-- Now the page has finished loading, we need to confirm the image has definitely loaded successfully.
		self.OnAlert = function( Alert )
			self.OnAlert = nil

			if Alert == "WRONG_URL" then
				Shine.Logger:Debug(
					"%s - WebView hasn't actually changed URL yet, go back to waiting for it to load...",
					Clock()
				)
				Entry.State = STATE_LOADING_URL
				return
			end

			Shine.Logger:Debug( "%s - JS confirms image has loaded, setting up GUIView: %s", Clock(), Alert )

			Entry.State = STATE_SETUP_GUI_VIEW

			-- Force the WebView to refresh its texture now that it's finished loading (otherwise it may not refresh in
			-- time to be copied).
			self.WebView:RefreshTexture()
			-- Give the WebView time to refresh its texture (it doesn't occur straight away).
			Entry.RenderTime = Clock() + 0.1
		end
		self.WebView:ExecuteJS( StringFormat( IMAGE_CONFIRM_JS, Entry.URL ) )

		Entry.State = STATE_WAITING_FOR_CONFIRMATION
	end,

	-- Wait for either confirmation or timeout once the WebView claims the page has loaded.
	[ STATE_WAITING_FOR_CONFIRMATION ] = CheckTimeout,

	-- WebView has confirmed the image has loaded successfully, now setup a GUIView to copy the texture data.
	[ STATE_SETUP_GUI_VIEW ] = function( self, Entry )
		if Entry.RenderTime > Clock() then
			return
		end

		Shine.Logger:Debug( "%s - Image loaded, now copying %s into GUIView...", Clock(), Entry.URL )

		local View = Entry.GUIView
		if not View then
			View = Client.CreateGUIView( Entry.Width, Entry.Height )
			View:Load( "lua/shine/lib/gui/views/copy.lua" )
			View:SetGlobal( "SourceTexture", self.TextureName )
			View:SetGlobal( "Width", Entry.Width )
			View:SetGlobal( "Height", Entry.Height )
			View:SetTargetTexture( Entry.TextureName )
		end

		View:SetRenderCondition( GUIView.RenderOnce )

		Entry.GUIView = View
		Entry.State = STATE_COPYING_TEXTURE
	end,

	-- Wait for the GUIView to finish copying the data, and then pass the target texture to all callbacks
	-- and advance to the next entry in the queue.
	[ STATE_COPYING_TEXTURE ] = function( self, Entry )
		local View = Entry.GUIView

		-- The render condition switches itself to RenderNever when the GUIView has rendered once.
		if View:GetRenderCondition() ~= GUIView.RenderNever then
			return
		end

		Shine.Logger:Debug(
			"GUIView has completed copying %s, calling callbacks and advancing to next image...", Entry.URL
		)

		-- Need to keep the GUIView alive, otherwise its target texture is deleted.
		local PoolEntry = Entry.PoolEntry
		PoolEntry.GUIView = View
		-- Remember the parameters to ensure the texture can be loaded again if the render device resets.
		PoolEntry.SetupJS = Entry.SetupJS
		PoolEntry.Width = Entry.Width
		PoolEntry.Height = Entry.Height

		local CacheEntry = CacheByURL[ Entry.URL ]
		if CacheEntry then
			CacheEntry.Complete = true
			CacheEntry.Callbacks = nil
		end

		for i = 1, #Entry.Callbacks do
			xpcall( Entry.Callbacks[ i ], OnCallbackError, Entry.TextureName )
		end

		self.RequestQueue:Pop()
		self:ProcessNextEntry()
	end
}

function WebViewImageLoader:WaitForURLToLoad()
	local Entry = self.RequestQueue:Peek()
	StateUpdaters[ Entry.State ]( self, Entry )
end

-- Ideally using multiple WebViews would help here. However they seem to randomly share the same texture data
-- and thus only 1 works at the moment.
local ImageLoaders = {}
for i = 1, 1 do
	ImageLoaders[ i ] = WebViewImageLoader( i )
end
local LastImageLoaderIndex = 0

local function GetImageLoader()
	-- First try to find an idle loader.
	for i = 1, #ImageLoaders do
		if ImageLoaders[ i ]:IsIdle() then
			Shine.Logger:Debug( "Assigning idle image loader: %s", i )
			LastImageLoaderIndex = i
			return ImageLoaders[ i ]
		end
	end

	-- Round-robin assign if all are busy.
	LastImageLoaderIndex = ( LastImageLoaderIndex % #ImageLoaders ) + 1

	Shine.Logger:Debug( "Round-robin assigning image loader: %s", LastImageLoaderIndex )

	return ImageLoaders[ LastImageLoaderIndex ]
end

Hook.Add( "OnRenderDeviceReset", "TextureLoader", function()
	-- For every texture allocated, trigger a re-render when the render device resets as the engine
	-- helpfully wipes all texture data.
	for i = 1, #TexturePool do
		local Entry = TexturePool[ i ]
		if not Entry.Free then
			Shine.Logger:Debug( "Render device reset forcing re-render of texture: %s", Entry.TextureName )

			local ImageLoader = GetImageLoader()
			ImageLoader:AddEntry( {
				URL = Entry.URL,
				SetupJS = Entry.SetupJS,
				Width = Entry.Width,
				Height = Entry.Height,
				TimeoutInSeconds = DefaultTimeout,
				State = STATE_LOADING_URL,
				Callbacks = {},
				IsCaching = Entry.IsCaching,

				-- Provide the existing name and pool entry to avoid allocating a new one.
				TextureName = Entry.TextureName,
				PoolEntry = Entry,
				GUIView = Entry.GUIView
			} )
		end
	end
end )

local TextureLoader = {
	ErrorCodes = ErrorCodes
}

--[[
	Queue a request for the given URL, with the given width and height values.

	Note that multiple requests to the same URL with differing width/height values
	will result in the same texture with the width/height from the first request.

	To reload an image, the texture must first be freed using the Free() function.

	Inputs:
		1. URL to load the image data from.
		2. Callback to run when the image has completed loading, or failed.
		3. Options to configure the width/height and timeout duration.
]]
function TextureLoader.LoadFromURL( URL, Callback, Options )
	Shine.TypeCheck( URL, "string", 1, "LoadFromURL" )
	Shine.AssertAtLevel( Shine.IsCallable( Callback ), "Provided callback must be callable!", 3 )
	Shine.TypeCheck( Options, { "table", "nil" }, 3, "LoadFromURL" )

	if Options then
		Shine.TypeCheckField( Options, "SetupJS", { "string", "nil" }, "Options" )
		Shine.TypeCheckField( Options, "Width", { "number", "nil" }, "Options" )
		Shine.TypeCheckField( Options, "Height", { "number", "nil" }, "Options" )
		Shine.TypeCheckField( Options, "TimeoutInSeconds", { "number", "nil" }, "Options" )
	end

	local CacheEntry = CacheByURL[ URL ]
	local Callbacks
	local IsCaching = false

	if ( not Options or Options.UseCache ~= false ) then
		IsCaching = true

		if CacheEntry then
			if CacheEntry.Complete then
				return Callback( CacheEntry.TextureName )
			end

			-- Callbacks points to the same table on the queue entry, so can add directly here.
			CacheEntry.Callbacks[ #CacheEntry.Callbacks + 1 ] = Callback

			return
		end

		Callbacks = { Callback }

		CacheByURL[ URL ] = {
			Complete = false,
			Callbacks = Callbacks
		}
	else
		Callbacks = { Callback }
	end

	local ImageLoader = GetImageLoader()
	ImageLoader:AddEntry( {
		URL = URL,
		SetupJS = Options and Options.SetupJS,
		Width = Clamp( Options and Options.Width or DefaultWidth, MIN_IMAGE_SIZE, MAX_IMAGE_SIZE ),
		Height = Clamp( Options and Options.Height or DefaultHeight, MIN_IMAGE_SIZE, MAX_IMAGE_SIZE ),
		TimeoutInSeconds = Max( Options and Options.TimeoutInSeconds or DefaultTimeout, MIN_TIMEOUT_SECONDS ),
		State = STATE_LOADING_URL,
		Callbacks = Callbacks,
		IsCaching = IsCaching
	} )
end

do
	local StringToBase64 = string.ToBase64
	local TableShallowMerge = table.ShallowMerge

	local SupportedMediaTypes = require "shine/lib/gui/util/image_formats"

	--[[
		Infers the image type from the given image data.
		This uses known file formats, though does not guarantee the image is free from corruption.
	]]
	function TextureLoader.InferMediaType( ImageData )
		for MimeType, Validator in pairs( SupportedMediaTypes ) do
			if Validator( ImageData ) then
				return MimeType
			end
		end
		return nil
	end

	local LocalImageHTML = [[<body style="background-color: rgba(0,0,0,0);margin: 0;padding: 0;">
		<img style="width: auto; height: auto;margin: 0;padding: 0;"></img>
	</body>]]
	local DataURL = StringFormat( "data:text/html;base64,%s", StringToBase64( LocalImageHTML ) )
	local MemorySetupJS = "document.querySelector( 'img' ).src = 'data:%s;base64,%s';"

	--[[
		Loads an image into a texture from a given binary string containing the image.

		This auto-detects the image size, and will set the loaded texture to use it unless
		Options.Width/Options.Height are provided. It also provides a rudimentary check to
		ensure the given image conforms to the provided type.

		Inputs:
			1. The image type (e.g. image/png, image/jpeg or image/gif).
			2. The image data as a string.
			3. Callback to run when the image has completed loading, or failed.
			4. Options to configure the width/height and timeout duration.
	]]
	function TextureLoader.LoadFromMemory( MediaType, ImageData, Callback, Options )
		local Validator = SupportedMediaTypes[ MediaType ]
		Shine.AssertAtLevel( Validator, "%s is not a supported media type!", 3, MediaType )
		Shine.TypeCheck( ImageData, "string", 2, "LoadFromMemory" )

		local Width, Height = Validator( ImageData )
		if not Width then
			return Callback(
				nil,
				StringFormat(
					"%s: Image data is corrupt or encoded in an unsupported format.",
					ErrorCodes.IMAGE_DATA_ERROR
				)
			)
		end

		return TextureLoader.LoadFromURL( DataURL, Callback, TableShallowMerge( Options or {}, {
			-- When the page loads, set the image data as a data URL.
			SetupJS = StringFormat( MemorySetupJS, MediaType, StringToBase64( ImageData ) ),
			-- Always the same URL, so no point in caching.
			UseCache = false,
			-- Pass through the known size values, unless they're overridden.
			Width = Options and Options.Width or Width,
			Height = Options and Options.Height or Height
		} ) )
	end
end

--[[
	Loads an image into a texture from the given file.

	Essentially reads the file contents, infers the media type from the file contents, then
	calls LoadFromMemory().

	Inputs:
		1. The file path to load.
		2. Callback to run when the image has completed loading, or failed.
		3. Options to configure the width/height and timeout duration.
]]
function TextureLoader.LoadFromFile( FilePath, Callback, Options )
	Shine.TypeCheck( FilePath, "string", 1, "LoadFromFile" )

	local Contents, Err = Shine.ReadFile( FilePath )
	if not Contents then
		return Callback( nil, StringFormat( "%s: Unable to open file %s: %s",
			ErrorCodes.FILE_OPEN_ERROR, FilePath, Err ) )
	end

	local MediaType = TextureLoader.InferMediaType( Contents )
	if not MediaType then
		return Callback(
			nil, StringFormat( "%s: Unknown media type for file: %s", ErrorCodes.IMAGE_DATA_ERROR, FilePath )
		)
	end

	return TextureLoader.LoadFromMemory( MediaType, Contents, Callback, Options )
end

--[[
	Marks a texture as no longer in use, allowing it to be re-used by another request.

	This also clears the cache for the URL the texture was loaded for.
]]
TextureLoader.Free = FreeTexture

return TextureLoader
