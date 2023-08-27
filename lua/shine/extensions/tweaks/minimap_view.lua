--[[
	A GUIView that renders the minimap with boxes over the current location in 3 separate tiles, each with their own
	colour.

	This is done inside a GUIView as it allows the use of the "Set" blend technique which avoids overlapping boxes from
	making the highlight stronger.
]]

MinimapWidth = 1024
MinimapHeight = 1024

MinimapX = 0
MinimapY = 0

NumBoxes = 0
HighlightColour1 = Color( 1, 1, 1, 0 )
HighlightColour2 = HighlightColour1
HighlightColour3 = HighlightColour1

BoxWidth = 512
BoxHeight = 512
BlurRadius = 8

local TileRoots = { nil, nil, nil }
local Stencils = { nil, nil, nil }
local Boxes = { {}, {}, {} }

local function MakeBox()
	local Box = GUI.CreateItem()
	Box:SetInheritsParentAlpha( false )
	Box:SetInheritsParentStencilSettings( false )
	Box:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Box:SetStencilFunc( GUIItem.NotEqual )
	-- Use the "Set" technique to make sure overlapping boxes don't change the colour.
	Box:SetBlendTechnique( GUIItem.Set )
	return Box
end

local function UpdateWithValues( TileIndex )
	local BlurRadius = _G.BlurRadius
	local BoxWidth = _G.BoxWidth
	local BoxHeight = _G.BoxHeight

	-- Place the root item at the top-left of this tile, accounting for blur radius.
	local TileRoot = TileRoots[ TileIndex ]
	TileRoot:SetPosition( Vector( BlurRadius + ( BoxWidth + BlurRadius * 3 ) * ( TileIndex - 1 ), BlurRadius, 0 ) )

	-- Then position the minimap texture relative to the tile.
	local StencilItem = Stencils[ TileIndex ]
	StencilItem:SetSize( Vector( _G.MinimapWidth, _G.MinimapHeight, 0 ) )
	StencilItem:SetPosition( Vector( _G.MinimapX, _G.MinimapY, 0 ) )

	if _G.MinimapTexture then
		StencilItem:SetTexture( _G.MinimapTexture )
	end

	local RectColour = _G[ "HighlightColour"..TileIndex ]
	local NumBoxes = _G.NumBoxes
	local BoxesForStencil = Boxes[ TileIndex ]

	for i = 1, math.max( NumBoxes, #BoxesForStencil ) do
		local X = _G[ "X"..i ]
		local Y = _G[ "Y"..i ]
		local W = _G[ "W"..i ]
		local H = _G[ "H"..i ]

		local Box = BoxesForStencil[ i ]
		if not X or not Y or not W or not H or i > NumBoxes then
			if Box then Box:SetIsVisible( false ) end
		else
			if not Box then
				Box = MakeBox()
				StencilItem:AddChild( Box )
				BoxesForStencil[ i ] = Box
			end

			Box:SetIsVisible( true )
			Box:SetPosition( Vector( X, Y, 0 ) )
			Box:SetSize( Vector( W, H, 0 ) )
			Box:SetColor( RectColour )
		end
	end
end

function Initialise()
	_G.NeedsUpdate = false

	for i = 1, 3 do
		-- Root element provides the tile's origin.
		local TileRoot = GUI.CreateItem()
		TileRoot:SetColor( Color( 0, 0, 0, 0 ) )
		TileRoots[ i ] = TileRoot

		-- Stencil object is used to restrict the boxes to render inside the minimap texture for this tile.
		local Stencil = GUI.CreateItem()
		Stencil:SetIsStencil( true )
		Stencil:SetClearsStencilBuffer( true )
		TileRoot:AddChild( Stencil )

		Stencils[ i ] = Stencil

		UpdateWithValues( i )
	end
end

function Update( DeltaTime )
	if _G.NeedsUpdate then
		_G.NeedsUpdate = false
		for i = 1, 3 do
			UpdateWithValues( i )
		end
	end
end

Initialise()
