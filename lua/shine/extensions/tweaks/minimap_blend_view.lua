--[[
	A GUIView that renders the minimap over the top of a previously rendered blurred highlight background.

	This results in a glow around the current location, plus extra colour added on top of the minimap itself.

	This is done in a texture to make alpha blending apply to an opaque version of the texture rendered by this view,
	rather than applying to each layer rendered directly to the screen which then messes with how it looks.
]]

Width = 1024
Height = 1024

local Background
local Overlay
local Minimap
local Boxes = {}

local function MakeBox()
	local Box = GUI.CreateItem()
	Box:SetInheritsParentAlpha( false )
	Box:SetInheritsParentStencilSettings( false )
	Box:SetIsStencil( true )
	Box:SetClearsStencilBuffer( false )
	Box:SetAnchor( GUIItem.Middle, GUIItem.Center )

	Background:AddChild( Box )

	return Box
end

local function UpdateWithValues()
	local Size = Vector( _G.Width, _G.Height, 0 )
	Background:SetSize( Size )
	Minimap:SetSize( Size )
	Overlay:SetSize( Size )

	if _G.MinimapTexture then
		Minimap:SetTexture( _G.MinimapTexture )
	end

	if _G.BackgroundTexture then
		Background:SetTexture( _G.BackgroundTexture )
		Overlay:SetTexture( _G.BackgroundTexture )
	end

	local NumBoxes = _G.NumBoxes or 0

	-- Update the boxes to constrain the minimap texture rendering to just the current location.
	-- This will blend over the top of the background highlight to produce a glowing texture.
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
		end
	end

	_G.NeedsUpdate = false
end

function Initialise()
	-- Background draws the blurred highlight box behind the minimap, making it glow.
	Background = GUI.CreateItem()
	Background:SetBlendTechnique( GUIItem.Set )
	Background:SetColor( Color( 1, 1, 1, 1 ) )
	Background:SetIsVisible( true )

	-- Minimap is drawn over the top of the highlighting, but constrained to be within the current location only.
	Minimap = GUI.CreateItem()
	Minimap:SetLayer( 100 )
	Minimap:SetStencilFunc( GUIItem.NotEqual )
	Minimap:SetColor( Color( 1, 1, 1, 1 ) )
	Background:AddChild( Minimap )

	-- Overlay adds colour on top of the opaque minimap.
	Overlay = GUI.CreateItem()
	Overlay:SetIsVisible( true )
	Overlay:SetLayer( 150 )
	Overlay:SetColor( Color( 1, 1, 1, 0.4 ) )
	Overlay:SetBlendTechnique( GUIItem.Add )
	Background:AddChild( Overlay )

	UpdateWithValues()
end

function Update( DeltaTime )
	if _G.NeedsUpdate then
		UpdateWithValues()
	end
end

Initialise()
