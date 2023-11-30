--[[
	Misc tweaks.
]]

local RenderPipeline = require "shine/lib/gui/util/pipeline"

local SGUI = Shine.GUI

local Ceil = math.ceil
local Floor = math.floor
local Huge = math.huge
local Max = math.max
local Min = math.min
local StringFormat = string.format
local TableEmpty = table.Empty

local Plugin = Shine.Plugin( ... )

Plugin.HasConfig = true
Plugin.ConfigName = "Tweaks.json"

Plugin.DefaultConfig = {
	AlienHighlightColour = { 255, 202, 58 },
	HostileHighlightColour = { 255, 0, 0 },
	MarineHighlightColour = { 77, 219, 255 }
}

Plugin.CheckConfig = true
Plugin.SilentConfigSave = true
Plugin.Version = "1.0"

Shine.Hook.CallAfterFileLoad( "lua/GUIMinimap.lua", function()
	Shine.Hook.SetupClassHook( "GUIMinimap", "Uninitialize", "OnGUIMinimapDestroy", "PassivePost" )
	Shine.Hook.SetupClassHook( "GUIMinimap", "UpdatePlayerIcon", "OnGUIMinimapUpdatePlayerIcon", "PassivePost" )
	Shine.Hook.SetupClassHook( "GUIMinimap", "ShowMap", "OnGUIMinimapShowMap", "PassivePost" )
end )

local BLUR_RADIUS = 8
local DOUBLE_BLUR_RADIUS = BLUR_RADIUS * 2

local MARINE_HIGHLIGHT_INDEX = 1
local ALIEN_HIGHLIGHT_INDEX = 2
local HOSTILE_HIGHLIGHT_INDEX = 3

local HighlightingState = {
	PENDING = 1,
	HIDDEN = 2,
	VISIBLE = 3
}

local function GetStencilBox( Minimap, Index )
	local Box = Minimap.HighlightStencilBoxes[ Index ]
	if not Box then
		Box = GUIManager:CreateGraphicItem()
		Box:SetInheritsParentAlpha( false )
		Box:SetInheritsParentStencilSettings( false )
		Box:SetIsStencil( true )
		-- Need to clear on the first box, otherwise stencil bits can be left behind from previous frames.
		Box:SetClearsStencilBuffer( Index == 1 )
		Box:SetAnchor( GUIItem.Middle, GUIItem.Center )
		-- Put the stencil box behind the minimap so it renders first (and thus writes to the stencil buffer before
		-- the minimap is drawn).
		Box:SetLayer( -100 )
		Minimap.background:AddChild( Box )
		Minimap.HighlightStencilBoxes[ Index ] = Box
		Plugin.Logger:Trace( "Created new stencil box at index: %d", Index )
	end
	return Box
end

local function GetLocationForHighlightOnMinimap( Minimap )
	if Minimap.comMode ~= GUIMinimapFrame.kModeBig or PlayerUI_IsOverhead() then
		return nil
	end

	local LocationName = PlayerUI_GetLocationName()
	if not LocationName or LocationName == "" then
		return nil
	end

	return LocationName
end

local function Input( Key, Value )
	return { Key = Key, Value = Value }
end

local LocationAtlasState = {
	EMPTY = 1,
	RENDERING = 2,
	RENDERED = 3
}

local LocationAtlas = Shine.TypeDef()
function LocationAtlas:Init( Params )
	self.LocationName = Params.LocationName
	self.Minimap = Params.Minimap
	self.MinimapSize = Params.MinimapSize
	self:InitialiseTextureParameters( Params )
	self.State = LocationAtlasState.EMPTY
	return self
end

function LocationAtlas:InitialiseTextureParameters( Params )
	local Locations = Params.LocationTriggerEntities
	local Minimap = self.Minimap
	local MinimapSize = self.MinimapSize
	local NumLocations = #Locations

	local StencilBoxParams = {}

	local ScreenMinsX, ScreenMinsY = Huge, Huge
	local ScreenMaxsX, ScreenMaxsY = -Huge, -Huge

	local MinimapNodeInput = {}
	local BlendNodeInput = {}

	MinimapNodeInput[ 1 ] = Input( "MinimapTexture", Minimap.minimap:GetTexture() )
	BlendNodeInput[ 1 ] = MinimapNodeInput[ 1 ]
	MinimapNodeInput[ 2 ] = Input( "NumBoxes", NumLocations )
	BlendNodeInput[ 2 ] = MinimapNodeInput[ 2 ]
	MinimapNodeInput[ 3 ] = Input( "MinimapWidth", MinimapSize.x )
	BlendNodeInput[ 3 ] = MinimapNodeInput[ 3 ]
	MinimapNodeInput[ 4 ] = Input( "MinimapHeight", MinimapSize.y )
	BlendNodeInput[ 4 ] = MinimapNodeInput[ 4 ]

	local Count = 4

	for i = 1, NumLocations do
		local Location = Locations[ i ]

		local Extents = Location.scale * 0.2395
		local Coords = Location:GetCoords()
		local Mins = Coords:TransformPoint( -Extents )
		local Maxs = Coords:TransformPoint( Extents )

		local TopLeftX, TopLeftY = Minimap:PlotToMap( Max( Maxs.x, Mins.x ), Min( Maxs.z, Mins.z ) )
		local BottomRightX, BottomRightY = Minimap:PlotToMap( Min( Maxs.x, Mins.x ), Max( Maxs.z, Mins.z ) )

		local Width = BottomRightX - TopLeftX
		local Height = BottomRightY - TopLeftY

		-- Use integer co-ordinates to avoid sub-pixel rendering.
		-- These are shared between the main screen's stencil boxes, and the GUIView stencil boxes to ensure both are
		-- rendering to the exact same pixels.
		local X = Floor( TopLeftX )
		local Y = Floor( TopLeftY )
		local W = Ceil( Width )
		local H = Ceil( Height )

		-- Both GUIViews need the location boxes to restrict rendering.
		Count = Count + 1
		MinimapNodeInput[ Count ] = Input( "X"..i, X )
		BlendNodeInput[ Count ] = MinimapNodeInput[ Count ]
		Count = Count + 1
		MinimapNodeInput[ Count ] = Input( "Y"..i, Y )
		BlendNodeInput[ Count ] = MinimapNodeInput[ Count ]
		Count = Count + 1
		MinimapNodeInput[ Count ] = Input( "W"..i, W )
		BlendNodeInput[ Count ] = MinimapNodeInput[ Count ]
		Count = Count + 1
		MinimapNodeInput[ Count ] = Input( "H"..i, H )
		BlendNodeInput[ Count ] = MinimapNodeInput[ Count ]

		StencilBoxParams[ i ] = {
			X,
			Y,
			W,
			H
		}

		ScreenMinsX = Min( ScreenMinsX, X )
		ScreenMinsY = Min( ScreenMinsY, Y )

		ScreenMaxsX = Max( ScreenMaxsX, X + W )
		ScreenMaxsY = Max( ScreenMaxsY, Y + H )
	end

	local BoxWidth = ScreenMaxsX - ScreenMinsX
	local BoxHeight = ScreenMaxsY - ScreenMinsY

	-- Position of the minimap texture such that it aligns with the top-left corner of this location's bounding box.
	-- The co-ordinates on the map are relative to the centre of the minimap texture, while the minimap is positioned
	-- relative to the top-left of the tile in the GUIViews.
	local OffsetX = -( MinimapSize.x * 0.5 + ScreenMinsX )
	local OffsetY = -( MinimapSize.y * 0.5 + ScreenMinsY )

	Plugin.Logger:Debug(
		"Computed bounding box for location '%s' as (%s, %s) -> (%s, %s) with minimap offset by (%s, %s).",
		self.LocationName,
		ScreenMinsX,
		ScreenMinsY,
		ScreenMaxsX,
		ScreenMaxsY,
		OffsetX,
		OffsetY
	)

	Count = Count + 1
	MinimapNodeInput[ Count ] = Input( "MinimapX", OffsetX )
	BlendNodeInput[ Count ] = MinimapNodeInput[ Count ]

	Count = Count + 1
	MinimapNodeInput[ Count ] = Input( "MinimapY", OffsetY )
	BlendNodeInput[ Count ] = MinimapNodeInput[ Count ]

	Count = Count + 1
	MinimapNodeInput[ Count ] = Input( "BoxWidth", BoxWidth )
	BlendNodeInput[ Count ] = MinimapNodeInput[ Count ]

	Count = Count + 1
	MinimapNodeInput[ Count ] = Input( "BoxHeight", OffsetY )
	BlendNodeInput[ Count ] = MinimapNodeInput[ Count ]

	Count = Count + 1
	MinimapNodeInput[ Count ] = Input( "BlurRadius", BLUR_RADIUS )
	BlendNodeInput[ Count ] = MinimapNodeInput[ Count ]

	BlendNodeInput[ Count + 1 ] = Input( "BackgroundTexture", RenderPipeline.TextureInput )

	self.ColourInputIndex = Count

	-- Final inputs are the colours to allow for easily updating them later.
	for i = 1, 3 do
		Count = Count + 1
		MinimapNodeInput[ Count ] = Input( "HighlightColour"..i, Params.Colours[ i ] )
	end
	self.MinimapNodeInput = MinimapNodeInput

	-- Pixel co-ordinates in the texture atlas for each variant.
	-- Each box is offset by 3 * BLUR_RADIUS to given enough room to avoid any overlapping pixels.
	self.PixelTextureCoordinates = {
		{ 0, 0, BoxWidth + DOUBLE_BLUR_RADIUS, BoxHeight + DOUBLE_BLUR_RADIUS },
		{ BoxWidth + BLUR_RADIUS * 3, 0, BoxWidth * 2 + BLUR_RADIUS * 5, BoxHeight + DOUBLE_BLUR_RADIUS },
		{ BoxWidth * 2 + BLUR_RADIUS * 6, 0, BoxWidth * 3 + BLUR_RADIUS * 8, BoxHeight + DOUBLE_BLUR_RADIUS }
	}
	self.StencilBoxParams = StencilBoxParams

	-- Texture needs to accomodate the total location bounding box size for the 3 colour variants, plus enough space
	-- around them to allow for blurring.
	local TextureWidth = BoxWidth * 3 + BLUR_RADIUS * 8
	local TextureHeight = BoxHeight + DOUBLE_BLUR_RADIUS

	self.TextureWidth = TextureWidth
	self.TextureHeight = TextureHeight

	self.HighlightBoxPosX = ScreenMinsX - BLUR_RADIUS
	self.HighlightBoxPosY = ScreenMinsY - BLUR_RADIUS
	self.HighlightBoxWidth = BoxWidth + DOUBLE_BLUR_RADIUS
	self.HighlightBoxHeight = BoxHeight + DOUBLE_BLUR_RADIUS

	local BlurPipeline = RenderPipeline.ApplyBlurToNode( {
		Width = TextureWidth,
		Height = TextureHeight,
		BlurRadius = BLUR_RADIUS,
		NodeToBlur = RenderPipeline.GUIViewNode {
			View = Shine.GetPluginFile( Plugin:GetName(), "minimap_view.lua" ),
			Input = MinimapNodeInput
		}
	} )
	self.HighlightPipeline = BlurPipeline:CopyWithAdditionalNodes( {
		RenderPipeline.GUIViewNode {
			View = Shine.GetPluginFile( Plugin:GetName(), "minimap_blend_view.lua" ),
			Input = BlendNodeInput
		}
	} )
	self.HighlightPipeline.Atlas = self
end

function LocationAtlas:UpdateMinimapStencilBoxes( Minimap )
	-- Update the screen-space stencil boxes once the highlight texture has been rendered to stop the main minimap
	-- rendering over the top of it.
	local NumBoxes = #self.StencilBoxParams
	for i = 1, NumBoxes do
		local Params = self.StencilBoxParams[ i ]
		local Box = GetStencilBox( Minimap, i )
		Box:SetPosition( Vector2( Params[ 1 ], Params[ 2 ] ) )
		Box:SetSize( Vector2( Params[ 3 ], Params[ 4 ] ) )
		Box:SetIsVisible( true )
		Box:SetIsStencil( true )
	end

	for i = NumBoxes + 1, #Minimap.HighlightStencilBoxes do
		Minimap.HighlightStencilBoxes[ i ]:SetIsVisible( false )
		Minimap.HighlightStencilBoxes[ i ]:SetIsStencil( false )
	end

	Minimap.StencilBoxesVisible = true
	Minimap.HighlightingState = HighlightingState.VISIBLE
	Minimap.LastLocationAtlas = self
end

function LocationAtlas.OnRefreshComplete( HighlightViewTexture, Pipeline )
	local self = Pipeline.Atlas
	local Minimap = self.Minimap
	if not Minimap.HighlightItem or Minimap.LastLocationName ~= self.LocationName then return end

	self:UpdateMinimapStencilBoxes( Minimap )

	Plugin.Logger:Debug( "Finished refreshing %s.", self )
end

function LocationAtlas.OnMinimapHighlightRenderCompleted( OutputTexture, Pipeline )
	local self = Pipeline.Atlas
	local Minimap = self.Minimap

	self.HighlightPipelineContext = nil

	if not Minimap.HighlightItem then
		Plugin.Logger:Debug(
			"Discarding %s as it its minimap is no longer applicable for highlighting.",
			OutputTexture
		)
		OutputTexture:Free()
		self.State = LocationAtlasState.EMPTY
		return
	end

	self.State = LocationAtlasState.RENDERED
	self.HighlightViewTexture = OutputTexture

	if Minimap.LastLocationName == self.LocationName then
		self:UpdateMinimapHighlightItem( Minimap, Minimap.LastColourIndex )
		Minimap.HighlightItem:SetIsVisible( not not GetLocationForHighlightOnMinimap( Minimap ) )
	end

	self.OnRefreshComplete( OutputTexture, Pipeline )
end

function LocationAtlas:Refresh()
	if self.HighlightPipelineContext then
		-- Not finished rendering for the first time, start again.
		Plugin.Logger:Debug( "Restarting in-progress pipeline rendering context for: %s", self )
		self.HighlightPipelineContext:Restart()
	elseif self.HighlightViewTexture then
		-- Previously rendered, trigger a refresh of the texture.
		Plugin.Logger:Debug( "Refreshing existing texture contents for: %s", self )
		self.HighlightViewTexture:Refresh( self.OnRefreshComplete )
	else
		-- Not rendered yet, trigger the first render.
		Plugin.Logger:Debug( "Creating render pipeline for: %s", self )
		self.HighlightPipelineContext = RenderPipeline.Execute(
			self.HighlightPipeline,
			self.TextureWidth,
			self.TextureHeight,
			self.OnMinimapHighlightRenderCompleted
		)
	end

	self.State = LocationAtlasState.RENDERING
end

function LocationAtlas:UpdateMinimapHighlightItem( Minimap, ColourIndex )
	Minimap.HighlightItem:SetTexture( self.HighlightViewTexture:GetName() )

	Minimap.HighlightItemPos.x = self.HighlightBoxPosX
	Minimap.HighlightItemPos.y = self.HighlightBoxPosY
	Minimap.HighlightItem:SetPosition( Minimap.HighlightItemPos )

	Minimap.HighlightItemSize.x = self.HighlightBoxWidth
	Minimap.HighlightItemSize.y = self.HighlightBoxHeight
	Minimap.HighlightItem:SetSize( Minimap.HighlightItemSize )

	local TextureCoordinates = self.PixelTextureCoordinates[ ColourIndex ]
	Minimap.HighlightItem:SetTexturePixelCoordinates(
		TextureCoordinates[ 1 ], TextureCoordinates[ 2 ],
		TextureCoordinates[ 3 ], TextureCoordinates[ 4 ]
	)
end

function LocationAtlas:Update( ColourIndex )
	if self.State == LocationAtlasState.EMPTY then
		self:Refresh()
	end

	if self.State ~= LocationAtlasState.RENDERED and not self.HighlightViewTexture then return end

	local Minimap = self.Minimap

	if Minimap.LastLocationAtlas ~= self then
		self:UpdateMinimapStencilBoxes( Minimap )
	end

	Minimap.HighlightItem:SetIsVisible( Minimap.HighlightingState ~= HighlightingState.HIDDEN )
	Minimap.minimap:SetStencilFunc( GUIItem.Equal )

	self:UpdateMinimapHighlightItem( Minimap, ColourIndex )
end

function LocationAtlas:Destroy()
	if self.HighlightViewTexture then
		self.HighlightViewTexture:Free()
		self.HighlightViewTexture = nil
	end

	if self.HighlightPipelineContext then
		self.HighlightPipelineContext:Destroy()
		self.HighlightPipelineContext = nil
	end
end

function LocationAtlas:__tostring()
	return StringFormat(
		"LocationAtlas[%q, Size = (%d, %d)]",
		self.LocationName,
		self.TextureWidth,
		self.TextureHeight
	)
end

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	self.Minimaps = Shine.Set()
	return true
end

local function ConfigColourToColourStruct( ConfiguredColour )
	return Colour( ConfiguredColour[ 1 ] / 255, ConfiguredColour[ 2 ] / 255, ConfiguredColour[ 3 ] / 255 )
end

function Plugin:GetConfiguredColour( Name )
	return ConfigColourToColourStruct( self.Config[ Name ] )
end

local function DestroyHighlightTextures( Minimap )
	if Minimap.LocationAtlasTextures then
		for LocationName, Atlas in Minimap.LocationAtlasTextures:Iterate() do
			Atlas:Destroy()
		end
		Minimap.LocationAtlasTextures = nil
	end

	Minimap.LastLocationAtlas = nil
end

function Plugin:OnGUIMinimapDestroy( Minimap )
	DestroyHighlightTextures( Minimap )

	self.Minimaps:Remove( Minimap )
end

function Plugin:DestroyAllHighlightTextures()
	for Minimap in self.Minimaps:Iterate() do
		-- Destroy any previously rendered highlight textures.
		DestroyHighlightTextures( Minimap )

		-- Force an update of the location highlight.
		Minimap.LocationAtlasTextures = Shine.UnorderedMap()
	end
end

-- If any parameters change, destroy the textures to force a gradual re-render of each location.
Plugin.OnResolutionChanged = Plugin.DestroyAllHighlightTextures
Plugin.SetAlienHighlightColour = Plugin.DestroyAllHighlightTextures
Plugin.SetMarineHighlightColour = Plugin.DestroyAllHighlightTextures
Plugin.SetHostileHighlightColour = Plugin.DestroyAllHighlightTextures

function Plugin:GetLocationsForName( Name )
	if not self.LocationIndex then
		local Locations = GetLocations()
		local LocationsByName = Shine.Multimap()
		for i = 1, #Locations do
			local Location = Locations[ i ]
			LocationsByName:Add( Location:GetName(), Location )
		end

		self.Logger:Debug(
			"Found %d locations on map totalling %d trigger volumes.",
			LocationsByName:GetKeyCount(),
			LocationsByName:GetCount()
		)
		self.LocationIndex = LocationsByName
	end

	return self.LocationIndex:Get( Name )
end

function Plugin:SetupMinimap( Minimap )
	if self.Minimaps:Contains( Minimap ) then return end

	local MinimapItem = Minimap.minimap
	if not Minimap.LocationAtlasTextures then
		Minimap.LocationAtlasTextures = Shine.UnorderedMap()
	end

	if not Minimap.HighlightItem then
		Minimap.HighlightItem = GUIManager:CreateGraphicItem()
		-- Ensure the user's minimap alpha setting is respected.
		Minimap.HighlightItem:SetInheritsParentAlpha( true )
		-- Put the highlight item behind the minimap to ensure the glowing edges that overlap with the minimap texture
		-- are blended correctly. Having the highlight item above the minimap results in harsh, obvious blending lines.
		-- Note that for users with minimap alpha = 1, no blending will be visible (but that's fine, it doesn't look bad
		-- unlike rendering above).
		Minimap.HighlightItem:SetLayer( -100 )
		-- Ignore the stencil boxes that are applied to the main minimap item, this should be rendered regardless.
		Minimap.HighlightItem:SetInheritsParentStencilSettings( false )
		Minimap.HighlightItem:SetStencilFunc( GUIItem.Always )
		Minimap.HighlightItem:SetIsVisible( false )
		Minimap.HighlightItem:SetAnchor( GUIItem.Middle, GUIItem.Center )
		Minimap.HighlightItemPos = Vector2( 0, 0 )
		Minimap.HighlightItemSize = Vector2( 0, 0 )
		MinimapItem:AddChild( Minimap.HighlightItem )

		Minimap.HighlightingState = HighlightingState.PENDING
	end

	Minimap.HighlightStencilBoxes = Minimap.HighlightStencilBoxes or {}
	Minimap.HighlightInitTime = SGUI.GetTime()

	self.Logger:Debug( "Initialised minimap highlighting for: %s", Minimap )

	self.Minimaps:Add( Minimap )
end

local function HideLocationBoxes( Minimap )
	if not Minimap.HighlightItem then return end
	if Minimap.HighlightingState == HighlightingState.HIDDEN then return end

	Plugin.Logger:Debug( "Hiding minimap location highlighting for: %s", Minimap )

	Minimap.HighlightItem:SetIsVisible( false )

	if Minimap.StencilBoxesVisible then
		for i = 1, #Minimap.HighlightStencilBoxes do
			local Box = Minimap.HighlightStencilBoxes[ i ]
			Box:SetIsVisible( false )
			Box:SetIsStencil( false )
		end
		Minimap.StencilBoxesVisible = false
	end

	Minimap.minimap:SetStencilFunc( Minimap.stencilFunc or GUIItem.Always )
	Minimap.HighlightingState = HighlightingState.HIDDEN
	Minimap.LastLocationAtlas = nil
end

function Plugin:OnGUIMinimapShowMap( Minimap )
	if not Minimap.background:GetIsVisible() then
		-- Hide the location boxes when the minimap is closed to prevent a few frames of an old location showing if the
		-- minimap is re-opened at a different location later.
		HideLocationBoxes( Minimap )
	end
end

function Plugin:OnGUIMinimapUpdatePlayerIcon( Minimap )
	local LocationName = GetLocationForHighlightOnMinimap( Minimap )
	if not LocationName then
		HideLocationBoxes( Minimap )
		return
	end

	-- Set up the location item and GUIView just-in-time to ensure they're only created for relevant minimaps.
	self:SetupMinimap( Minimap )

	local TeamNumber = PlayerUI_GetTeamNumber()
	local IsMarine = TeamNumber == kMarineTeamType
	local IsAlien = TeamNumber == kAlienTeamType

	-- This is a bad hack, but the alien team won't load the minimap texture until the minimap is first opened, at which
	-- point the texture streaming system can take a moment to load it. If the highlight view is triggered before the
	-- texture is loaded, it can render either a blank texture, or only the minimap with no highlight. By delaying the
	-- first render, the texture is given enough time to load. Unfortunately there's no way to interact with the texture
	-- stream system to determine if the texture has loaded, so this a best guess at a conservative loading time.
	if IsAlien and SGUI.GetTime() - Minimap.HighlightInitTime < 0.5 then return end

	local MinimapSize = Minimap.minimap:GetSize()
	local Atlas = Minimap.LocationAtlasTextures:Get( LocationName )
	if not Atlas or Atlas.MinimapSize ~= MinimapSize then
		if Atlas then
			self.Logger:Debug( "Destroying %s as it does not match the current minimap size: %s", Atlas, MinimapSize )
			Atlas:Destroy()
		end

		local Locations = self:GetLocationsForName( LocationName )
		if not Locations then return end

		Atlas = LocationAtlas( {
			LocationName = LocationName,
			LocationTriggerEntities = Locations,
			Minimap = Minimap,
			MinimapSize = MinimapSize,
			Colours = {
				self:GetConfiguredColour( "MarineHighlightColour" ),
				self:GetConfiguredColour( "AlienHighlightColour" ),
				self:GetConfiguredColour( "HostileHighlightColour" )
			}
		} )
		Minimap.LocationAtlasTextures:Add( LocationName, Atlas )

		self.Logger:Debug( "Created new texture atlas: %s", Atlas )
	end

	Minimap.LastLocationName = LocationName

	-- Also, if the power state has changed, the minimap needs updating.
	if IsMarine or IsAlien then
		local PowerNode = GetPowerPointForLocation( LocationName )
		Minimap.LastPowered = not not ( PowerNode and PowerNode:GetIsPowering() )
	else
		Minimap.LastPowered = nil
	end

	local ColourIndex = MARINE_HIGHLIGHT_INDEX
	if IsMarine then
		-- For marines, show unpowered rooms as hostile.
		if not Minimap.LastPowered then
			ColourIndex = HOSTILE_HIGHLIGHT_INDEX
		end
	elseif IsAlien then
		-- For aliens, show powered rooms as hostile.
		if not Minimap.LastPowered then
			ColourIndex = ALIEN_HIGHLIGHT_INDEX
		else
			ColourIndex = HOSTILE_HIGHLIGHT_INDEX
		end
	end

	Minimap.LastColourIndex = ColourIndex

	Atlas:Update( ColourIndex )
end

function Plugin:Cleanup()
	for Minimap in self.Minimaps:Iterate() do
		if Minimap.HighlightItem then
			GUI.DestroyItem( Minimap.HighlightItem )
			Minimap.HighlightItem = nil
			Minimap.HighlightItemSize = nil
			Minimap.HighlightItemPos = nil
		end

		if Minimap.HighlightStencilBoxes then
			for i = 1, #Minimap.HighlightStencilBoxes do
				GUI.DestroyItem( Minimap.HighlightStencilBoxes[ i ] )
				Minimap.HighlightStencilBoxes[ i ] = nil
			end
			Minimap.HighlightStencilBoxes = nil
			Minimap.StencilBoxesVisible = nil
		end

		DestroyHighlightTextures( Minimap )

		Minimap.minimap:SetStencilFunc( Minimap.stencilFunc or GUIItem.Always )

		Minimap.LastLocationName = nil
		Minimap.LastPowered = nil
		Minimap.HighlightInitTime = nil
		Minimap.HighlightingState = nil
	end

	self.Minimaps = nil

	return self.BaseClass.Cleanup( self )
end

Shine.LoadPluginModule( "logger.lua", Plugin )

Plugin.ConfigGroup = {
	Icon = Shine.GUI.Icons.Ionicons.Wrench
}
Plugin.ClientConfigSettings = {
	{
		ConfigKey = "AlienHighlightColour",
		Command = "sh_tweaks_alien_highlight_colour",
		Type = "Colour",
		CommandMessage = function( Value )
			return StringFormat(
				"Alien minimap highlight colour set to [ %d, %d, %d ].",
				Value[ 1 ], Value[ 2 ], Value[ 3 ]
			)
		end,
		OnChange = Plugin.SetAlienHighlightColour
	},
	{
		ConfigKey = "MarineHighlightColour",
		Command = "sh_tweaks_marine_highlight_colour",
		Type = "Colour",
		CommandMessage = function( Value )
			return StringFormat(
				"Marine minimap highlight colour set to [ %d, %d, %d ].",
				Value[ 1 ], Value[ 2 ], Value[ 3 ]
			)
		end,
		OnChange = Plugin.SetMarineHighlightColour
	},
	{
		ConfigKey = "HostileHighlightColour",
		Command = "sh_tweaks_hostile_highlight_colour",
		Type = "Colour",
		CommandMessage = function( Value )
			return StringFormat(
				"Hostile minimap highlight colour set to [ %d, %d, %d ].",
				Value[ 1 ], Value[ 2 ], Value[ 3 ]
			)
		end,
		OnChange = Plugin.SetHostileHighlightColour
	}
}

return Plugin
