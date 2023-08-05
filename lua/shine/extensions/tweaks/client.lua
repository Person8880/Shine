--[[
	Misc tweaks.
]]

local RenderPipeline = require "shine/lib/gui/util/pipeline"

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

local MINIMAP_WIDTH, MINIMAP_HEIGHT = 1024, 1024

function Plugin:Initialise()
	self.Minimaps = Shine.Set()

	local BlurPipeline = RenderPipeline.ApplyBlurToNode( {
		Width = MINIMAP_WIDTH,
		Height = MINIMAP_HEIGHT,
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

	return true
end

function Plugin:GetConfiguredColour( Name )
	local ConfiguredColour = self.Config[ Name ]
	return Colour( ConfiguredColour[ 1 ] / 255, ConfiguredColour[ 2 ] / 255, ConfiguredColour[ 3 ] / 255 )
end

function Plugin:OnGUIMinimapDestroy( Minimap )
	if Minimap.HighlightView then
		-- Clean up the GUI view as it's not part of the minimap item hierarchy.
		Client.DestroyGUIView( Minimap.HighlightView )
		Minimap.HighlightView = nil
	end

	self.Minimaps:Remove( Minimap )
end

function Plugin:InvalidateLocationCache()
	for Minimap in self.Minimaps:Iterate() do
		-- Force an update of the location box.
		Minimap.LastLocationName = nil
	end
end
Plugin.OnResolutionChanged = Plugin.InvalidateLocationCache

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
		Minimap.HighlightPipeline = self.HighlightPipeline:Copy()
		Minimap.HighlightPipeline.Minimap = Minimap
	end

	if not Minimap.HighlightItem then
		Minimap.HighlightItem = GUIManager:CreateGraphicItem()
		Minimap.HighlightItem:SetInheritsParentAlpha( true )
		Minimap.HighlightItem:SetSize( MinimapItem:GetSize() )
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
		Box:SetClearsStencilBuffer( Index == 1 )
		Box:SetAnchor( GUIItem.Middle, GUIItem.Center )
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

	for i = 1, #Minimap.StencilBoxParams do
		local Params = Minimap.StencilBoxParams[ i ]
		local Box = GetStencilBox( Minimap, i )
		Box:SetPosition( Vector2( math.floor( Params.X ), math.floor( Params.Y ) ) )
		Box:SetSize( Vector2( math.ceil( Params.W ), math.ceil( Params.H ) ) )
		Box:SetIsVisible( true )
		Box:SetIsStencil( true )
	end

	for i = #Minimap.StencilBoxParams + 1, #Minimap.HighlightStencilBoxes do
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
		Minimap.HighlightPipelineContext = RenderPipeline.Execute(
			Minimap.HighlightPipeline,
			MINIMAP_WIDTH,
			MINIMAP_HEIGHT,
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

	Minimap.HighlightItem:SetSize( Minimap.minimap:GetSize() )
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
	local Size = Minimap.HighlightItem:GetSize()

	local MinimapNodeInput = Minimap.HighlightPipeline.Nodes[ 1 ].Input
	local BlendNodeInput = Minimap.HighlightPipeline.Nodes[ 4 ].Input
	TableEmpty( MinimapNodeInput )
	TableEmpty( BlendNodeInput )

	MinimapNodeInput[ 1 ] = Input( "MinimapTexture", Minimap.minimap:GetTexture() )
	BlendNodeInput[ 1 ] = MinimapNodeInput[ 1 ]
	MinimapNodeInput[ 2 ] = Input( "NumBoxes", NumLocations )
	BlendNodeInput[ 2 ] = MinimapNodeInput[ 2 ]
	MinimapNodeInput[ 3 ] = Input( "HighlightColour", BackgroundColour )
	BlendNodeInput[ 3 ] = Input( "BackgroundTexture", RenderPipeline.TextureInput )

	local Count = 3
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

		-- TODO: Make GUIView texture size and box co-ordinates reflect the minimap item's size to avoid precision
		-- differences causing gaps in the rendering.
		local X = math.floor( TopLeftX ) / Size.x * MINIMAP_WIDTH
		local Y = math.floor( TopLeftY ) / Size.y * MINIMAP_HEIGHT
		local W = math.ceil( Width ) / Size.x * MINIMAP_WIDTH
		local H = math.ceil( Height ) / Size.y * MINIMAP_HEIGHT

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
			X = TopLeftX,
			Y = TopLeftY,
			W = Width,
			H = Height
		}
	end

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

		if Minimap.HighlightViewTexture then
			Minimap.HighlightViewTexture:Free()
			Minimap.HighlightViewTexture = nil
		end

		if Minimap.HighlightPipelineContext then
			Minimap.HighlightPipelineContext:Terminate()
			Minimap.HighlightPipelineContext:RemoveHooks()
			Minimap.HighlightPipelineContext = nil
		end

		Minimap.minimap:SetStencilFunc( Minimap.stencilFunc or GUIItem.Always )

		Minimap.HighlightPipeline = nil
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
