--[[
	Shadow rendering utilities.
]]

local RenderPipeline = require "shine/lib/gui/util/pipeline"

local BitBAnd = bit.band
local BitBOr = bit.bor
local BitLShift = bit.lshift
local Max = math.max
local StringFormat = string.format

local ShadowManager = {}
local ShadowTextureCache = {}

local function ColourToInt( Colour )
	return BitBOr(
		BitBAnd( Colour.r * 255, 0xFF ),
		BitLShift( BitBAnd( Colour.g * 255, 0xFF ), 8 ),
		BitLShift( BitBAnd( Colour.b * 255, 0xFF ), 16 ),
		BitLShift( BitBAnd( Colour.a * 255, 0xFF ), 24 )
	)
end

local function BuildCacheKey( Type, Width, Height, BlurRadius, Colour )
	return StringFormat( "%s:%s:%s:%s:%s", Type, Width, Height, BlurRadius, ColourToInt( Colour ) )
end

local ShadowCacheEntry = Shine.TypeDef()
function ShadowCacheEntry:Init( Key, Context )
	self.Key = Key
	self.Context = Context
	self.RefCount = 0
	return self
end

function ShadowCacheEntry.OnExpired( Timer )
	local Entry = Timer.Data
	Entry.Texture:Free()
	ShadowTextureCache[ Entry.Key ] = nil
end

function ShadowCacheEntry:GetTextureName()
	return self.Texture:GetName()
end

function ShadowCacheEntry:Borrow()
	self.RefCount = self.RefCount + 1

	if self.ExpiryTimer then
		self.ExpiryTimer:Destroy()
		self.ExpiryTimer = nil
	end

	return self
end

function ShadowCacheEntry:Free()
	self.RefCount = Max( self.RefCount - 1, 0 )

	if self.RefCount == 0 and not self.ExpiryTimer then
		-- Retain the cache entry for 30 seconds after the last usage in case another request for the same shadow is
		-- made (e.g. if a window is re-opened).
		Shine.Logger:Debug(
			"Shadow texture '%s' is no longer referenced, will expire in 30 seconds...",
			self:GetTextureName()
		)
		self.ExpiryTimer = Shine.Timer.Simple( 30, self.OnExpired, self )
	end
end

--[[
	Renders a box shadow with the given parameters and calls the given callback once the texture is ready for use.

	This internally caches shadows with the same parameters to avoid repeated rendering work and to minimise the number
	of active GUIView instances. Callers should call :Free() on the returned object when they are finished with the
	texture.
]]
function ShadowManager.GetBoxShadow( Params, OnRendered )
	local CacheKey = BuildCacheKey( "Box", Params.Width, Params.Height, Params.BlurRadius, Params.Colour )
	local CacheEntry = ShadowTextureCache[ CacheKey ]
	if CacheEntry then
		if CacheEntry.Context then
			Shine.Logger:Debug(
				"Found cache entry for shadow '%s' that has not yet finished rendering, attaching callback...",
				CacheKey
			)
			-- Rendering is in-progress for this shadow, wait for it to be completed.
			CacheEntry.Context:AddCallback( function( Texture )
				return OnRendered( CacheEntry:Borrow() )
			end )
			return
		end

		Shine.Logger:Debug( "Found cache entry for shadow '%s' that has been previously rendered.", CacheKey )

		-- Shadow was previously rendered, borrow it and return it immediately.
		return OnRendered( CacheEntry:Borrow() )
	end

	Shine.Logger:Debug( "No cache entry exists for shadow '%s', executing render pipeline...", CacheKey )

	-- Shadow not yet rendered, build and start the pipeline.
	local Pipeline, TextureWidth, TextureHeight = RenderPipeline.BuildBoxShadowPipeline( Params )

	local CacheEntry
	local Context = RenderPipeline.Execute( Pipeline, TextureWidth, TextureHeight, function( Texture )
		CacheEntry.Texture = Texture
		CacheEntry.Context = nil
		return OnRendered( CacheEntry:Borrow() )
	end )
	CacheEntry = ShadowCacheEntry( CacheKey, Context )

	ShadowTextureCache[ CacheKey ] = CacheEntry
end

return ShadowManager
