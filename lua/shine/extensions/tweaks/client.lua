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

function Plugin:SetupMinimap( Minimap )
	if not Minimap.MapStencil then
		Minimap.MapStencil = GUIManager:CreateGraphicItem()
		Minimap.MapStencil:SetAnchor( GUIItem.Left, GUIItem.Top )
		Minimap.MapStencil:SetPosition( Vector2( 0, 0 ) )
		Minimap.MapStencil:SetSize( Minimap.minimap:GetSize() )
		Minimap.MapStencil:SetTexture( Minimap.minimap:GetTexture() )
		Minimap.MapStencil:SetIsStencil( true )
		Minimap.MapStencil:SetClearsStencilBuffer( true )

		Minimap.minimap:AddChild( Minimap.MapStencil )
	end

	if not Minimap.CurrentLocationBoxes then
		Minimap.CurrentLocationBoxes = {}
	end

	self.Minimaps:Add( Minimap )
end

local function GetLocationBox( Minimap, Index )
	local Box = Minimap.CurrentLocationBoxes[ Index ]
	if not Box then
		Box = GUIManager:CreateGraphicItem()
		Box:SetAnchor( GUIItem.Middle, GUIItem.Center )
		Box:SetIsVisible( false )
		Box:SetInheritsParentStencilSettings( false )
		Box:SetStencilFunc( GUIItem.NotEqual )
		Minimap.minimap:AddChild( Box )

		Minimap.CurrentLocationBoxes[ Index ] = Box
	end

	return Box
end

local function HideLocationBoxes( Minimap )
	Minimap.LastLocationEntity = nil
	for i = 1, #Minimap.CurrentLocationBoxes do
		Minimap.CurrentLocationBoxes[ i ]:SetIsVisible( false )
	end
end

local UnpoweredColour = Colour( 1, 0, 0 )

function Plugin:OnGUIMinimapUpdatePlayerIcon( Minimap )
	if not Minimap.CurrentLocationBoxes then return end

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

	Minimap.MapStencil:SetSize( Minimap.minimap:GetSize() )

	local IsMarine = PlayerUI_IsOnMarineTeam()

	-- Avoid doing the same thing over and over when the location hasn't changed...
	if not IsMarine and Minimap.LastLocationEntity == LocationEntity then return end

	Minimap.LastLocationEntity = LocationEntity

	local BackgroundColour
	if IsMarine then
		local PowerNode = GetPowerPointForLocation( LocationEntity:GetName() )
		if not PowerNode or not PowerNode:GetIsPowering() then
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
	for i = 1, #Locations do
		local Location = Locations[ i ]
		local Box = GetLocationBox( Minimap, i )

		local Extents = Location.scale * 0.2395
		local Coords = Location:GetCoords()
		local Mins = Coords:TransformPoint( -Extents )
		local Maxs = Coords:TransformPoint( Extents )

		local TopLeftX, TopLeftY = Minimap:PlotToMap( Max( Maxs.x, Mins.x ), Min( Maxs.z, Mins.z ) )
		local BottomRightX, BottomRightY = Minimap:PlotToMap( Min( Maxs.x, Mins.x ), Max( Maxs.z, Mins.z ) )

		local Width = BottomRightX - TopLeftX
		local Height = BottomRightY - TopLeftY

		Box:SetIsVisible( true )
		Box:SetPosition( Vector2( TopLeftX, TopLeftY ) )
		Box:SetSize( Vector2( Width, Height ) )
		Box:SetColor( BackgroundColour )
	end

	for i = #Locations + 1, #Minimap.CurrentLocationBoxes do
		Minimap.CurrentLocationBoxes[ i ]:SetIsVisible( false )
	end
end

function Plugin:Cleanup()
	for Minimap in self.Minimaps:Iterate() do
		if Minimap.MapStencil then
			GUI.DestroyItem( Minimap.MapStencil )
			Minimap.MapStencil = nil
		end

		if Minimap.CurrentLocationBoxes then
			for i = 1, #Minimap.CurrentLocationBoxes do
				GUI.DestroyItem( Minimap.CurrentLocationBoxes[ i ] )
			end
			Minimap.CurrentLocationBoxes = nil
		end
	end

	self.Minimaps = nil

	return self.BaseClass.Cleanup( self )
end

return Plugin
