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
		LuaPrint( "Destroying GUIView for", Entry.URL, Entry.GUIView )
		Client.DestroyGUIView( Entry.GUIView )
		Entry.GUIView = nil
	end

	if Entry.URL then
		CacheByURL[ Entry.URL ] = nil
		Entry.URL = nil
	end

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
			LuaPrint( "Image loader has been idle for", IDLE_WEBVIEW_TIMEOUT, "seconds, destroying web view." )
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

	local TextureName, PoolEntry = GetTextureName()
	if Entry.IsCaching then
		PoolEntry.URL = Entry.URL
	end

	Entry.TextureName = TextureName
	Entry.PoolEntry = PoolEntry

	if Entry.Width ~= self.Width or Entry.Height ~= self.Height and self.WebView then
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

		LuaPrint( Clock(), "Completed loading", Entry.URL, ", now setting up confirmation..." )

		if Entry.SetupJS then
			-- Execute any setup script required before confirming the image is loaded (e.g. for local data injection).
			self.WebView:ExecuteJS( Entry.SetupJS )
		end

		-- Now the page has finished loading, we need to confirm the image has definitely loaded successfully.
		self.OnAlert = function( Alert )
			self.OnAlert = nil

			if Alert == "WRONG_URL" then
				LuaPrint( Clock(), "WebView hasn't actually changed URL yet, go back to waiting for it to load..." )
				Entry.State = STATE_LOADING_URL
				return
			end

			LuaPrint( Clock(), "JS confirms image has loaded, setting up GUIView", Alert )

			Entry.State = STATE_SETUP_GUI_VIEW
			-- Give the WebView time to refresh its texture (seems to update at a different rate to the game)
			Entry.RenderTime = Clock() + 0.2
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

		LuaPrint( Clock(), "Image loaded, now copying", Entry.URL, "into GUIView..." )

		local View = Client.CreateGUIView( Entry.Width, Entry.Height )
		View:Load( "lua/shine/lib/gui/views/copy.lua" )
		View:SetGlobal( "SourceTexture", self.TextureName )
		View:SetGlobal( "Width", Entry.Width )
		View:SetGlobal( "Height", Entry.Height )
		View:SetRenderCondition( GUIView.RenderOnce )
		View:SetTargetTexture( Entry.TextureName )

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

		LuaPrint( "GUIView has completed copying", Entry.URL, "calling callbacks and advancing to next image..." )

		-- GUIView has finished rendering, can now pass along the texture and render
		-- the next image.
		-- Need to keep the GUIView alive, otherwise its target texture is deleted.
		Entry.PoolEntry.GUIView = View

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

-- Multiple loaders allows concurrent loading of data, at the cost of more resource usage
-- while doing so. Ideally image loading should not be done during gameplay.
local ImageLoaders = {}
for i = 1, 1 do
	ImageLoaders[ i ] = WebViewImageLoader( i )
end
local LastImageLoaderIndex = 0

local function GetImageLoader()
	-- First try to find an idle loader.
	for i = 1, #ImageLoaders do
		if ImageLoaders[ i ]:IsIdle() then
			LuaPrint( "Assigning idle image loader:", i )
			LastImageLoaderIndex = i
			return ImageLoaders[ i ]
		end
	end

	-- Round-robin assign if all are busy.
	LastImageLoaderIndex = ( LastImageLoaderIndex % #ImageLoaders ) + 1

	LuaPrint( "Round-robin assigning image loader", LastImageLoaderIndex )

	return ImageLoaders[ LastImageLoaderIndex ]
end

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
	local BAnd = bit.band
	local BOr = bit.bor
	local LShift = bit.lshift
	local RShift = bit.rshift
	local StringByte = string.byte
	local StringSub = string.sub
	local StringToBase64 = string.ToBase64
	local TableShallowMerge = table.ShallowMerge

	local function UInt16BE( Byte1, Byte2 )
		return BOr( LShift( Byte1, 8 ), Byte2 )
	end

	local function UInt16LE( Byte1, Byte2 )
		return BOr( LShift( Byte2, 8 ), Byte1 )
	end

	local function UInt24LE( Byte1, Byte2, Byte3 )
		return BOr( LShift( Byte3, 16 ), LShift( Byte2, 8 ), Byte1 )
	end

	local function UInt32BE( Byte1, Byte2, Byte3, Byte4 )
		return BOr( LShift( Byte1, 24 ), LShift( Byte2, 16 ), LShift( Byte3, 8 ), Byte4 )
	end

	local function UInt32LE( Byte1, Byte2, Byte3, Byte4 )
		return BOr( LShift( Byte4, 24 ), LShift( Byte3, 16 ), LShift( Byte2, 8 ), Byte1 )
	end

	local SupportedMediaTypes = {
		[ "image/png" ] = function( Data )
			-- Validate the header is as expected.
			local ExpectedBytes = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }
			for i = 1, #ExpectedBytes do
				local Byte = StringByte( Data, i )
				if Byte ~= ExpectedBytes[ i ] then
					return nil
				end
			end

			-- Expect an image header.
			if StringSub( Data, 13, 16 ) ~= "IHDR" then
				return nil
			end

			local SizeData = StringSub( Data, 17, 24 )
			if #SizeData ~= 8 then return nil end

			local Width = UInt32BE( StringByte( SizeData, 1, 4 ) )
			local Height = UInt32BE( StringByte( SizeData, 5, 8 ) )

			return Width, Height
		end,
		[ "image/jpeg" ] = function( Data )
			-- Look for the expected magic bytes (FF D8) then the start of a marker (FF).
			local Byte1, Byte2, Byte3, Byte4 = StringByte( Data, 1, 4 )
			if Byte1 ~= 0xFF or Byte2 ~= 0xD8 or Byte3 ~= 0xFF then
				return nil
			end

			-- Must be a supported type of JPG (raw, JFIF or EXIF).
			if Byte4 ~= 0xDB and Byte4 ~= 0xE0 and Byte4 ~= 0xE1 then
				return nil
			end

			-- Should always end in FF D9, otherwise it's corrupt.
			local LastByte1, LastByte2 = StringByte( Data, #Data - 1, #Data )
			if LastByte1 ~= 0xFF or LastByte2 ~= 0xD9 then
				return nil
			end

			local Index = 3
			local Width, Height
			while true do
				-- Segment marker (FF ??)
				local Marker, Code = StringByte( Data, Index, Index + 1 )
				if Marker ~= 0xFF then
					return nil
				end

				-- Size of segment as a 16 bit integer.
				local SizeByte1, SizeByte2 = StringByte( Data, Index + 2, Index + 3 )
				if not SizeByte1 or not SizeByte2 then
					return nil
				end

				Index = Index + 4

				if Code >= 0xC0 and Code <= 0xC3 then
					-- Is a Start Of Frame segment, extract the width/height from it.
					local SizeData = StringSub( Data, Index, Index + 4 )
					if #SizeData ~= 5 then
						return nil
					end

					local Height1, Height2, Width1, Width2 = StringByte( SizeData, 2, 5 )
					Width = UInt16BE( Width1, Width2 )
					Height = UInt16BE( Height1, Height2 )

					break
				end

				local Length = UInt16BE( SizeByte1, SizeByte2 )
				-- Length includes its own 2 bytes.
				Index = Index + Length - 2
			end

			return Width, Height
		end,
		[ "image/gif" ] = function( Data )
			local Header = StringSub( Data, 1, 6 )
			if Header ~= "GIF87a" and Header ~= "GIF89a" then
				return nil
			end

			local Width = UInt16LE( StringByte( Data, 7, 8 ) )
			local Height = UInt16LE( StringByte( Data, 9, 10 ) )

			return Width, Height
		end,
		[ "image/webp" ] = function( Data )
			local Header = StringSub( Data, 1, 4 )
			if Header ~= "RIFF" then
				return nil
			end

			local Index = 5
			local FileSize = UInt32LE( StringByte( Data, Index, Index + 3 ) ) - 4
			Index = Index + 4

			local Identifier = StringSub( Data, Index, Index + 3 )
			if Identifier ~= "WEBP" then
				return nil
			end

			Index = Index + 4

			while Index <= FileSize do
				-- Chunks always start with 4 bytes of text indicating the type.
				local ChunkType = StringSub( Data, Index, Index + 3 )
				Index = Index + 4

				-- Then the length of the chunk.
				local ChunkLength = UInt32LE( StringByte( Data, Index, Index + 3 ) )
				Index = Index + 4

				if ChunkType == "VP8 " then
					-- VP8 encoded frame, make sure the expected magic bytes are present.
					if StringByte( Data, Index + 3 ) ~= 0x9D
					or StringByte( Data, Index + 4 ) ~= 0x01
					or StringByte( Data, Index + 5 ) ~= 0x2A then
						return nil
					end

					local Width = UInt16LE( StringByte( Data, Index + 6, Index + 7 ) )
					local Height = UInt16LE( StringByte( Data, Index + 8, Index + 9 ) )

					return Width, Height
				elseif ChunkType == "VP8L" then
					-- VP8 lossless frame, look for magic byte.
					if StringByte( Data, Index ) ~= 0x2F then
						return nil
					end

					local Byte1, Byte2, Byte3, Byte4 = StringByte( Data, Index + 1, Index + 4 )
					-- Width and height are encoded in 14 bits for each dimension, but as 1 less than their value.
					local WidthMinusOne = BOr( LShift( BAnd( Byte2, 0x3F ), 8 ), Byte1 )
					local HeightMinusOne = BOr( LShift( BAnd( Byte4, 0xF ), 10 ), LShift( Byte3, 2 ),
						RShift( Byte2, 6 ) )

					return WidthMinusOne + 1, HeightMinusOne + 1
				elseif ChunkType == "VP8X" then
					-- VP8 lossy frame, no magic bytes so just grab the 24 bit width/height values.
					local WidthMinusOne = UInt24LE( StringByte( Data, Index + 4, Index + 6 ) )
					local HeightMinusOne = UInt24LE( StringByte( Data, Index + 7, Index + 9 ) )

					return WidthMinusOne + 1, HeightMinusOne + 1
				else
					-- Chunks are always padded to have even size.
					Index = Index + ChunkLength + ChunkLength % 2
				end
			end

			return nil
		end
	}

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

do
	local StringMatch = string.match

	local ExtensionToMediaType = {
		png = "image/png",
		jpg = "image/jpeg",
		jpeg = "image/jpeg",
		webp = "image/webp",
		gif = "image/gif"
	}

	--[[
		Loads an image into a texture from the given file.

		Essentially reads the file contents, infers the media type from the file extension, then
		calls LoadFromMemory().

		Inputs:
			1. The file path to load.
			2. Callback to run when the image has completed loading, or failed.
			3. Options to configure the width/height and timeout duration.
	]]
	function TextureLoader.LoadFromFile( FilePath, Callback, Options )
		Shine.TypeCheck( FilePath, "string", 1, "LoadFromFile" )

		local Extension = StringMatch( FilePath, ".+%.(%a+)$" )
		local MediaType = ExtensionToMediaType[ Extension ]
		if not Extension or not MediaType then
			error( StringFormat( "Unknown file type for file: %s", FilePath ), 2 )
		end

		local Contents, Err = Shine.ReadFile( FilePath )
		if not Contents then
			return Callback( nil, StringFormat( "%s: Unable to open file %s: %s",
				ErrorCodes.FILE_OPEN_ERROR, FilePath, Err ) )
		end

		return TextureLoader.LoadFromMemory( MediaType, Contents, Callback, Options )
	end
end

--[[
	Marks a texture as no longer in use, allowing it to be re-used by another request.

	This also clears the cache for the URL the texture was loaded for.
]]
TextureLoader.Free = FreeTexture

return TextureLoader
