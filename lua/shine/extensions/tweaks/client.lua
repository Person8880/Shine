--[[
	Misc tweaks.
]]

local Max = math.max
local Min = math.min

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

local TARGET_TEXTURE_NAME = "*shine_tweaks_minimap_highlights"
local TextureCount = 0
local function GetMinimapTexture()
	TextureCount = TextureCount + 1
	return TARGET_TEXTURE_NAME..TextureCount
end

function Plugin:SetupMinimap( Minimap )
	if self.Minimaps:Contains( Minimap ) then return end

	local MinimapItem = Minimap.minimap
	if not Minimap.HighlightView then
		local Width, Height = 1024, 1024

		local TextureName = GetMinimapTexture()
		Minimap.HighlightViewTexture = TextureName

		Minimap.HighlightView = Client.CreateGUIView( Width, Height )
		Minimap.HighlightView:Load( Shine.GetPluginFile( self:GetName(), "minimap_view.lua" ) )
		Minimap.HighlightView:SetGlobal( "MinimapTexture", MinimapItem:GetTexture() )
		Minimap.HighlightView:SetGlobal( "Width", Width )
		Minimap.HighlightView:SetGlobal( "Height", Height )
		Minimap.HighlightView:SetGlobal( "NeedsRefresh", 1 )
		Minimap.HighlightView:SetTargetTexture( TextureName )
		Minimap.HighlightView:SetRenderCondition( GUIView.RenderOnce )
	end

	if not Minimap.HighlightItem then
		Minimap.HighlightItem = GUIManager:CreateGraphicItem()
		Minimap.HighlightItem:SetSize( MinimapItem:GetSize() )
		Minimap.HighlightItem:SetTexture( Minimap.HighlightViewTexture )
		Minimap.HighlightItem:SetIsVisible( false )
		MinimapItem:AddChild( Minimap.HighlightItem )
	end

	self.Minimaps:Add( Minimap )
end

local function HideLocationBoxes( Minimap )
	if not Minimap.HighlightItem then return end

	Minimap.HighlightItem:SetIsVisible( false )
end

local HostileColour = Colour( 1, 0, 0 )

function Plugin:OnGUIMinimapUpdatePlayerIcon( Minimap )
	if Minimap.comMode ~= GUIMinimapFrame.kModeBig or PlayerUI_IsOverhead() then
		HideLocationBoxes( Minimap )
		return
	end

	local LocationName = PlayerUI_GetLocationName()
	if not LocationName or LocationName == "" then
		HideLocationBoxes( Minimap )
		return
	end

	-- Set up the location item and GUIView just-in-time to ensure they're only created for relevant minimaps.
	self:SetupMinimap( Minimap )

	Minimap.HighlightItem:SetSize( Minimap.minimap:GetSize() )
	Minimap.HighlightItem:SetIsVisible( true )

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

	BackgroundColour.a = 0.3

	-- Locations are composed of multiple trigger entities, so draw a box for each one.
	local Locations = self:GetLocationsForName( LocationName )
	local NumLocations = #Locations
	local HighlightView = Minimap.HighlightView
	local Size = Minimap.HighlightItem:GetSize()

	HighlightView:SetGlobal( "NumBoxes", NumLocations )
	HighlightView:SetGlobal( "HighlightColour", BackgroundColour )

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

		HighlightView:SetGlobal( "X"..i, TopLeftX / Size.x * 1024 )
		HighlightView:SetGlobal( "Y"..i, TopLeftY / Size.y * 1024 )
		HighlightView:SetGlobal( "W"..i, Width / Size.x * 1024 )
		HighlightView:SetGlobal( "H"..i, Height / Size.y * 1024 )
	end

	HighlightView:SetGlobal( "NeedsRefresh", 1 )
	HighlightView:SetRenderCondition( GUIView.RenderOnce )
end

function Plugin:Cleanup()
	for Minimap in self.Minimaps:Iterate() do
		if Minimap.HighlightItem then
			GUI.DestroyItem( Minimap.HighlightItem )
			Minimap.HighlightItem = nil
		end

		if Minimap.HighlightView then
			Client.DestroyGUIView( Minimap.HighlightView )
			Minimap.HighlightView = nil
		end

		Minimap.LastLocationName = nil
		Minimap.LastPowered = nil
		Minimap.HighlightViewTexture = nil
	end

	self.Minimaps = nil

	return self.BaseClass.Cleanup( self )
end

return Plugin
