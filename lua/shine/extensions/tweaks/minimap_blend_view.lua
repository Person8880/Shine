--[[
	A GUIView that renders minimap tiles over the top of a previously rendered texture with blurred highlight
	background tiles.

	This results in a glow around the current location, plus extra colour added on top of the minimap itself for each
	tile.

	This is done in a texture to make alpha blending apply to an opaque version of the texture rendered by this view,
	rather than applying to each layer rendered directly to the screen which then messes with how it looks.
]]

Width = 1024
Height = 1024

MinimapWidth = 1024
MinimapHeight = 1024

MinimapX = 0
MinimapY = 0

NumBoxes = 0

BoxWidth = 512
BoxHeight = 512
BlurRadius = 8

local Background
local Overlay
local TileRoots = { nil, nil, nil }
local MinimapContainers = { nil, nil, nil }
local Minimaps = { nil, nil, nil }
local Boxes = { {}, {}, {} }

local function MakeBox( Index )
	local Box = GUI.CreateItem()
	Box:SetInheritsParentAlpha( false )
	Box:SetInheritsParentStencilSettings( false )
	Box:SetIsStencil( true )
	Box:SetClearsStencilBuffer( Index == 1 )
	Box:SetAnchor( GUIItem.Middle, GUIItem.Center )
	return Box
end

local function UpdateWithValues( TileIndex )
	local BlurRadius = _G.BlurRadius
	local BoxWidth = _G.BoxWidth
	local BoxHeight = _G.BoxHeight

	-- Place the root item at the top-left of this tile, accounting for blur radius.
	local TileRoot = TileRoots[ TileIndex ]
	TileRoot:SetPosition( Vector( BlurRadius + ( BoxWidth + BlurRadius * 3 ) * ( TileIndex - 1 ), BlurRadius, 0 ) )

	local MinimapContainer = MinimapContainers[ TileIndex ]
	local Minimap = Minimaps[ TileIndex ]
	-- Then position the minimap texture relative to the tile.
	MinimapContainer:SetPosition( Vector( _G.MinimapX, _G.MinimapY, 0 ) )

	local MinimapSize = Vector( _G.MinimapWidth, _G.MinimapHeight, 0 )
	MinimapContainer:SetSize( MinimapSize )
	Minimap:SetSize( MinimapSize )

	if _G.MinimapTexture then
		Minimap:SetTexture( _G.MinimapTexture )
	end

	local BoxesForTile = Boxes[ TileIndex ]
	local NumBoxes = _G.NumBoxes

	-- Update the boxes to constrain the minimap texture rendering to just the current location.
	-- This will blend over the top of the background highlight to produce a glowing texture.
	for i = 1, math.max( NumBoxes, #BoxesForTile ) do
		local X = _G[ "X"..i ]
		local Y = _G[ "Y"..i ]
		local W = _G[ "W"..i ]
		local H = _G[ "H"..i ]

		local Box = BoxesForTile[ i ]
		if not X or not Y or not W or not H or i > NumBoxes then
			if Box then Box:SetIsVisible( false ) end
		else
			if not Box then
				Box = MakeBox( i )
				MinimapContainer:AddChild( Box )
				BoxesForTile[ i ] = Box
			end

			Box:SetIsVisible( true )
			Box:SetPosition( Vector( X, Y, 0 ) )
			Box:SetSize( Vector( W, H, 0 ) )
		end
	end
end

function Initialise()
	_G.NeedsUpdate = false

	-- Background draws the blurred highlight box behind the minimap, making it glow.
	Background = GUI.CreateItem()
	Background:SetBlendTechnique( GUIItem.Set )
	Background:SetColor( Color( 1, 1, 1, 1 ) )

	-- For each tile, render the segment of the minimap over the previously drawn highlighting.
	for i = 1, 3 do
		-- Root element provides the tile's origin.
		local TileRoot = GUI.CreateItem()
		TileRoot:SetColor( Color( 0, 0, 0, 0 ) )
		Background:AddChild( TileRoot )

		TileRoots[ i ] = TileRoot

		-- Container provides a means of placing the stencil boxes and rendering them before the minimap itself.
		local MinimapContainer = GUI.CreateItem()
		MinimapContainer:SetColor( Color( 0, 0, 0, 0 ) )
		TileRoot:AddChild( MinimapContainer )

		MinimapContainers[ i ] = MinimapContainer

		-- Minimap is drawn over the top of the highlighting, but constrained to be within the current location
		-- by each of the boxes representing the trigger entities for the location.
		local Minimap = GUI.CreateItem()
		Minimap:SetLayer( 100 )
		Minimap:SetStencilFunc( GUIItem.NotEqual )
		Minimap:SetColor( Color( 1, 1, 1, 1 ) )
		MinimapContainer:AddChild( Minimap )

		Minimaps[ i ] = Minimap

		UpdateWithValues( i )
	end

	-- Overlay adds colour on top of the opaque minimap.
	Overlay = GUI.CreateItem()
	Overlay:SetLayer( 150 )
	Overlay:SetColor( Color( 1, 1, 1, 0.4 ) )
	Overlay:SetBlendTechnique( GUIItem.Add )
	Background:AddChild( Overlay )
end

function Update( DeltaTime )
	if _G.NeedsUpdate then
		_G.NeedsUpdate = false

		-- The background and overlay items contain the previously rendered screen-size texture, so they need to use the
		-- size of the GUIView itself.
		local Size = Vector( _G.Width, _G.Height, 0 )
		Background:SetSize( Size )
		Overlay:SetSize( Size )

		if _G.BackgroundTexture then
			Background:SetTexture( _G.BackgroundTexture )
			Overlay:SetTexture( _G.BackgroundTexture )
		end

		for i = 1, 3 do
			UpdateWithValues( i )
		end
	end
end

Initialise()
