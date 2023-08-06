--[[
	A GUIView that renders the minimap with boxes over the current location.

	This is done inside a GUIView as it allows the use of the "Set" blend technique which avoids overlapping boxes from
	making the highlight stronger.
]]

MinimapWidth = 1024
MinimapHeight = 1024

MinimapX = 0
MinimapY = 0

NumBoxes = 0
HighlightColour = Color( 1, 1, 1, 0 )

local Stencil
local Boxes = {}

local function MakeBox()
	local Box = GUI.CreateItem()
	Box:SetInheritsParentAlpha( false )
	Box:SetInheritsParentStencilSettings( false )
	Box:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Box:SetStencilFunc( GUIItem.NotEqual )
	-- Use the "Set" technique to make sure overlapping boxes don't change the colour.
	Box:SetBlendTechnique( GUIItem.Set )

	Stencil:AddChild( Box )

	return Box
end

local function UpdateWithValues()
	Stencil:SetSize( Vector( _G.MinimapWidth, _G.MinimapHeight, 0 ) )
	Stencil:SetPosition( Vector( _G.MinimapX, _G.MinimapY, 0 ) )

	if _G.MinimapTexture then
		Stencil:SetTexture( _G.MinimapTexture )
	end

	local RectColour = _G.HighlightColour
	local NumBoxes = _G.NumBoxes

	for i = 1, math.max( NumBoxes, #Boxes ) do
		local X = _G[ "X"..i ]
		local Y = _G[ "Y"..i ]
		local W = _G[ "W"..i ]
		local H = _G[ "H"..i ]

		local Box = Boxes[ i ]
		if not X or not Y or not W or not H or i > NumBoxes then
			if Box then Box:SetIsVisible( false ) end
		else
			if not Box then
				Box = MakeBox()
				Boxes[ i ] = Box
			end

			Box:SetIsVisible( true )
			Box:SetPosition( Vector( X, Y, 0 ) )
			Box:SetSize( Vector( W, H, 0 ) )
			Box:SetColor( RectColour )
		end
	end

	_G.NeedsUpdate = false
end

function Initialise()
	-- Stencil object is used to restrict the boxes to render inside the minimap texture.
	Stencil = GUI.CreateItem()
	Stencil:SetIsVisible( true )
	Stencil:SetIsStencil( true )
	Stencil:SetClearsStencilBuffer( true )

	UpdateWithValues()
end

function Update( DeltaTime )
	if _G.NeedsUpdate then
		UpdateWithValues()
	end
end

Initialise()
