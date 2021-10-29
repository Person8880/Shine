--[[
	Misc tweaks.
]]

local Max = math.max
local Min = math.min

local Plugin = Shine.Plugin( ... )

Plugin.HasConfig = false
Plugin.Version = "1.0"

Shine.Hook.CallAfterFileLoad( "lua/GUIMinimap.lua", function()
	Shine.Hook.SetupClassHook( "GUIMinimap", "Initialize", "OnGUIMinimapInit", "PassivePost" )
	Shine.Hook.SetupClassHook( "GUIMinimap", "Uninitialize", "OnGUIMinimapDestroy", "PassivePost" )
	Shine.Hook.SetupClassHook( "GUIMinimap", "UpdatePlayerIcon", "OnGUIMinimapUpdatePlayerIcon", "PassivePost" )
end )

function Plugin:Initialise()
	self.Minimaps = Shine.Set()

	local Minimap = ClientUI.GetScript( "GUIMinimapFrame" )
	if Minimap then
		self:SetupMinimap( Minimap )
	end

	return true
end

function Plugin:OnGUIMinimapInit( Minimap )
	self:SetupMinimap( Minimap )
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
		Minimap.LastLocationEntity = nil
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
	Minimap.HighlightItem:SetIsVisible( false )
end

local UnpoweredColour = Colour( 1, 0, 0 )

function Plugin:OnGUIMinimapUpdatePlayerIcon( Minimap )
	if not Minimap.HighlightItem then return end

	if Minimap.comMode ~= GUIMinimapFrame.kModeBig or PlayerUI_IsOverhead() then
		HideLocationBoxes( Minimap )
		return
	end

	local Origin = PlayerUI_GetPositionOnMinimap()
	local LocationEntity = GetLocationForPoint( Origin )
	if not LocationEntity then
		HideLocationBoxes( Minimap )
		return
	end

	Minimap.HighlightItem:SetSize( Minimap.minimap:GetSize() )
	Minimap.HighlightItem:SetIsVisible( true )

	local IsMarine = PlayerUI_IsOnMarineTeam()

	-- Avoid doing the same thing over and over when the location hasn't changed...
	local NeedsUpdate = false
	if Minimap.LastLocationEntity ~= LocationEntity then
		NeedsUpdate = true
		Minimap.LastLocationEntity = LocationEntity
	elseif IsMarine then
		local PowerNode = GetPowerPointForLocation( LocationEntity:GetName() )
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
		if not Minimap.LastPowered then
			BackgroundColour = UnpoweredColour
		else
			BackgroundColour = Colour( kMarineTeamColorFloat )
		end
	elseif PlayerUI_IsOnAlienTeam() then
		BackgroundColour = Colour( kAlienTeamColorFloat )
	else
		BackgroundColour = Colour( 1, 1, 1, 1 )
	end

	BackgroundColour.a = 0.3

	-- Locations are composed of multiple trigger entities, so draw a box for each one.
	local Locations = self:GetLocationsForName( LocationEntity:GetName() )
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

		Minimap.LastLocationEntity = nil
		Minimap.LastPowered = nil
		Minimap.HighlightViewTexture = nil
	end

	self.Minimaps = nil

	return self.BaseClass.Cleanup( self )
end

return Plugin
