--[[
	Misc tweaks.
]]

local RenderPipeline = require "shine/lib/gui/util/pipeline"

local SGUI = Shine.GUI

local Ceil = math.ceil
local Floor = math.floor
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

do
	local Validator = Shine.Validator()

	local function EnsureFieldIsColour( FieldName )
		Validator:AddFieldRule( FieldName, Validator.IsType( "table", {} ) )
		Validator:AddFieldRule( FieldName, Validator.HasLength( 3, 255 ) )
		Validator:AddFieldRule( FieldName, Validator.AllValuesSatisfy(
			Validator.IsType( "number", 255 ),
			Validator.Clamp( 0, 255 )
		) )
	end

	EnsureFieldIsColour( "MarineHighlightColour" )
	EnsureFieldIsColour( "AlienHighlightColour" )
	EnsureFieldIsColour( "HostileHighlightColour" )

	Plugin.ConfigValidator = Validator
end

Shine.Hook.CallAfterFileLoad( "lua/GUIMinimap.lua", function()
	Shine.Hook.SetupClassHook( "GUIMinimap", "Uninitialize", "OnGUIMinimapDestroy", "PassivePost" )
	Shine.Hook.SetupClassHook( "GUIMinimap", "UpdatePlayerIcon", "OnGUIMinimapUpdatePlayerIcon", "PassivePost" )
end )

function Plugin:Initialise()
	self.Minimaps = Shine.Set()
	self:GenerateMinimapHighlightPipeline()
	return true
end

function Plugin:GenerateMinimapHighlightPipeline()
	-- Use the current screen resolution as the texture size to ensure that positions/sizes match exactly between the
	-- GUIView and the actual screen.
	local Width, Height = SGUI.GetScreenSize()
	local BlurPipeline = RenderPipeline.ApplyBlurToNode( {
		Width = Width,
		Height = Height,
		BlurRadius = 8,
		NodeToBlur = RenderPipeline.GUIViewNode {
			View = Shine.GetPluginFile( self:GetName(), "minimap_view.lua" ),
			Input = {}
		}
	} )
	self.HighlightPipeline = BlurPipeline:CopyWithAdditionalNodes( {
		RenderPipeline.GUIViewNode {
			View = Shine.GetPluginFile( self:GetName(), "minimap_blend_view.lua" ),
			Input = {}
		}
	} )
end

function Plugin:GetConfiguredColour( Name )
	local ConfiguredColour = self.Config[ Name ]
	return Colour( ConfiguredColour[ 1 ] / 255, ConfiguredColour[ 2 ] / 255, ConfiguredColour[ 3 ] / 255 )
end

local function CreateHighlightPipeline( self, Minimap )
	Minimap.HighlightPipeline = self.HighlightPipeline:Copy()
	Minimap.HighlightPipeline.Minimap = Minimap
end

local function DestroyHighlightPipeline( Minimap )
	if Minimap.HighlightViewTexture then
		Minimap.HighlightViewTexture:Free()
		Minimap.HighlightViewTexture = nil
	end

	if Minimap.HighlightPipelineContext then
		Minimap.HighlightPipelineContext:Terminate()
		Minimap.HighlightPipelineContext:RemoveHooks()
		Minimap.HighlightPipelineContext = nil
	end

	Minimap.HighlightPipeline = nil
end

function Plugin:OnGUIMinimapDestroy( Minimap )
	DestroyHighlightPipeline( Minimap )

	self.Minimaps:Remove( Minimap )
end

function Plugin:OnResolutionChanged()
	self:GenerateMinimapHighlightPipeline()

	for Minimap in self.Minimaps:Iterate() do
		-- Destroy any previously rendered highlight texture, as it needs to update to use the new screen resolution.
		DestroyHighlightPipeline( Minimap )

		CreateHighlightPipeline( self, Minimap )

		-- Force an update of the location highlight.
		Minimap.LastLocationName = nil
	end
end

function Plugin:GetLocationsForName( Name )
	if not self.LocationIndex then
		local Locations = GetLocations()
		local LocationsByName = Shine.Multimap()
		for i = 1, #Locations do
			local Location = Locations[ i ]
			LocationsByName:Add( Location:GetName(), Location )
		end

		self.LocationIndex = LocationsByName
	end

	return self.LocationIndex:Get( Name )
end

function Plugin:SetupMinimap( Minimap )
	if self.Minimaps:Contains( Minimap ) then return end

	local MinimapItem = Minimap.minimap
	if not Minimap.HighlightPipeline then
		CreateHighlightPipeline( self, Minimap )
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
		MinimapItem:AddChild( Minimap.HighlightItem )
	end

	Minimap.HighlightStencilBoxes = Minimap.HighlightStencilBoxes or {}

	self.Minimaps:Add( Minimap )
end

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

local function OnRefreshComplete( HighlightViewTexture, Pipeline )
	local Minimap = Pipeline.Minimap
	if not Minimap.HighlightItem or not Minimap.StencilBoxParams then return end

	-- Update the screen-space stencil boxes once the highlight texture has been updated to represent the current
	-- location to stop the main minimap rendering over the top of it.
	local NumBoxes = #Minimap.StencilBoxParams
	for i = 1, NumBoxes do
		local Params = Minimap.StencilBoxParams[ i ]
		local Box = GetStencilBox( Minimap, i )
		Box:SetPosition( Vector2( Params.X, Params.Y ) )
		Box:SetSize( Vector2( Params.W, Params.H ) )
		Box:SetIsVisible( true )
		Box:SetIsStencil( true )
	end

	for i = NumBoxes + 1, #Minimap.HighlightStencilBoxes do
		Minimap.HighlightStencilBoxes[ i ]:SetIsVisible( false )
		Minimap.HighlightStencilBoxes[ i ]:SetIsStencil( false )
	end

	Minimap.StencilBoxParams = nil
end

local function OnMinimapHighlightRenderCompleted( OutputTexture, Pipeline )
	local Minimap = Pipeline.Minimap
	Minimap.HighlightPipelineContext = nil

	if not Minimap.HighlightItem then
		OutputTexture:Free()
		return
	end

	local TextureName = OutputTexture:GetName()
	Minimap.HighlightViewTexture = OutputTexture
	Minimap.HighlightItem:SetTexture( TextureName )
	Minimap.HighlightItem:SetIsVisible( not not GetLocationForHighlightOnMinimap( Minimap ) )

	OnRefreshComplete( OutputTexture, Pipeline )
end

function Plugin:RefreshMinimapHighlightTexture( Minimap, StencilBoxParams )
	Minimap.StencilBoxParams = StencilBoxParams

	if Minimap.HighlightPipelineContext then
		-- Not finished rendering for the first time, start again.
		Minimap.HighlightPipelineContext:Restart()
	elseif Minimap.HighlightViewTexture then
		-- Previously rendered, trigger a refresh of the texture.
		Minimap.HighlightViewTexture:Refresh( OnRefreshComplete )
	else
		-- Not rendered yet, trigger the first render.
		local Width, Height = SGUI.GetScreenSize()
		Minimap.HighlightPipelineContext = RenderPipeline.Execute(
			Minimap.HighlightPipeline,
			Width,
			Height,
			OnMinimapHighlightRenderCompleted
		)
	end
end

local function HideLocationBoxes( Minimap )
	if not Minimap.HighlightItem then return end

	Minimap.HighlightItem:SetIsVisible( false )
end

local HostileColour = Colour( 1, 0, 0 )
local function Input( Key, Value )
	return { Key = Key, Value = Value }
end

function Plugin:OnGUIMinimapUpdatePlayerIcon( Minimap )
	local LocationName = GetLocationForHighlightOnMinimap( Minimap )
	if not LocationName then
		HideLocationBoxes( Minimap )
		return
	end

	-- Set up the location item and GUIView just-in-time to ensure they're only created for relevant minimaps.
	self:SetupMinimap( Minimap )

	local Pos = Minimap.minimap:GetScreenPosition( SGUI.GetScreenSize() )
	local MinimapSize = Minimap.minimap:GetSize()
	Minimap.HighlightItem:SetSize( MinimapSize )
	Minimap.HighlightItem:SetTexturePixelCoordinates( Pos.x, Pos.y, Pos.x + MinimapSize.x, Pos.y + MinimapSize.y )
	Minimap.HighlightItem:SetIsVisible( not not Minimap.HighlightViewTexture )

	local TeamNumber = PlayerUI_GetTeamNumber()
	local IsMarine = TeamNumber == kMarineTeamType
	local IsAlien = TeamNumber == kAlienTeamType

	-- If the location has changed, the minimap needs updating.
	local NeedsUpdate = false
	if Minimap.LastLocationName ~= LocationName then
		NeedsUpdate = true
		Minimap.LastLocationName = LocationName
	end

	-- Also, if the power state has changed, the minimap needs updating.
	if IsMarine or IsAlien then
		local PowerNode = GetPowerPointForLocation( LocationName )
		local IsPowered = not not ( PowerNode and PowerNode:GetIsPowering() )
		if IsPowered ~= Minimap.LastPowered then
			NeedsUpdate = true
			Minimap.LastPowered = IsPowered
		end
	else
		Minimap.LastPowered = nil
	end

	if not NeedsUpdate then return end

	local BackgroundColour
	if IsMarine then
		-- For marines, show unpowered rooms as hostile.
		if not Minimap.LastPowered then
			BackgroundColour = self:GetConfiguredColour( "HostileHighlightColour" )
		else
			BackgroundColour = self:GetConfiguredColour( "MarineHighlightColour" )
		end
	elseif IsAlien then
		-- For aliens, show powered rooms as hostile.
		if not Minimap.LastPowered then
			BackgroundColour = self:GetConfiguredColour( "AlienHighlightColour" )
		else
			BackgroundColour = self:GetConfiguredColour( "HostileHighlightColour" )
		end
	else
		-- Shouldn't ever reach this, but if not playing, just highlight with a neutral colour.
		BackgroundColour = Colour( 1, 1, 1, 1 )
	end

	-- Locations are composed of multiple trigger entities, so draw a box for each one.
	local Locations = self:GetLocationsForName( LocationName )
	local NumLocations = #Locations

	local MinimapNodeInput = Minimap.HighlightPipeline.Nodes[ 1 ].Input
	local BlendNodeInput = Minimap.HighlightPipeline.Nodes[ 4 ].Input
	TableEmpty( MinimapNodeInput )
	TableEmpty( BlendNodeInput )

	-- Initial inputs are shared by both GUIViews, setting up the minimap's texture, position and size.
	MinimapNodeInput[ 1 ] = Input( "MinimapTexture", Minimap.minimap:GetTexture() )
	BlendNodeInput[ 1 ] = MinimapNodeInput[ 1 ]
	MinimapNodeInput[ 2 ] = Input( "NumBoxes", NumLocations )
	BlendNodeInput[ 2 ] = MinimapNodeInput[ 2 ]
	MinimapNodeInput[ 3 ] = Input( "MinimapWidth", MinimapSize.x )
	BlendNodeInput[ 3 ] = MinimapNodeInput[ 3 ]
	MinimapNodeInput[ 4 ] = Input( "MinimapHeight", MinimapSize.y )
	BlendNodeInput[ 4 ] = MinimapNodeInput[ 4 ]
	MinimapNodeInput[ 5 ] = Input( "MinimapX", Pos.x )
	BlendNodeInput[ 5 ] = MinimapNodeInput[ 5 ]
	MinimapNodeInput[ 6 ] = Input( "MinimapY", Pos.y )
	BlendNodeInput[ 6 ] = MinimapNodeInput[ 6 ]

	-- First GUIView renders the highlight, second produces the final output.
	MinimapNodeInput[ 7 ] = Input( "HighlightColour", BackgroundColour )
	BlendNodeInput[ 7 ] = Input( "BackgroundTexture", RenderPipeline.TextureInput )

	local Count = 7
	local StencilBoxParams = {}

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
			X = X,
			Y = Y,
			W = W,
			H = H
		}
	end

	-- Cut out the highlight item from the minimap, as the highlight item contains the minimap plus the highlight glow
	-- (equal means everything except the stencil, somewhat backwards).
	Minimap.minimap:SetStencilFunc( GUIItem.Equal )

	self:RefreshMinimapHighlightTexture( Minimap, StencilBoxParams )
end

function Plugin:Cleanup()
	for Minimap in self.Minimaps:Iterate() do
		if Minimap.HighlightItem then
			GUI.DestroyItem( Minimap.HighlightItem )
			Minimap.HighlightItem = nil
		end

		if Minimap.HighlightStencilBoxes then
			for i = 1, #Minimap.HighlightStencilBoxes do
				GUI.DestroyItem( Minimap.HighlightStencilBoxes[ i ] )
				Minimap.HighlightStencilBoxes[ i ] = nil
			end
			Minimap.HighlightStencilBoxes = nil
		end

		DestroyHighlightPipeline( Minimap )

		Minimap.minimap:SetStencilFunc( Minimap.stencilFunc or GUIItem.Always )

		Minimap.LastLocationName = nil
		Minimap.LastPowered = nil
	end

	self.Minimaps = nil
	self.HighlightPipeline = nil

	return self.BaseClass.Cleanup( self )
end

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
		end
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
		end
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
		end
	}
}

return Plugin
