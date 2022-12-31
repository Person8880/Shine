--[[
	A GUI view that takes a texture and renders it to another.

	This allows extracting textures from WebViews without having to spawn
	a new WebView every time we want a new texture.
]]

Width = 1024
Height = 1024

local Rect
local function UpdateWithValues()
	Rect:SetSize( Vector( Width, Height, 0 ) )
	if SourceTexture then
		Rect:SetTexture( SourceTexture )
	end
end

function Initialise()
	Rect = GUI.CreateItem()
	Rect:SetIsVisible( true )
	Rect:SetColor( Color( 1, 1, 1, 1 ) )
	Rect:SetSize( Vector( Width, Height, 0 ) )
	Rect:SetPosition( Vector( 0, 0, 0 ) )
	-- As this is a copy operation, the output should be exactly the same as the input without any blending.
	Rect:SetBlendTechnique( GUIItem.Set )

	UpdateWithValues()
end

function Update( DeltaTime )
	if _G.NeedsUpdate then
		_G.NeedsUpdate = false
		UpdateWithValues()
	end
end

Initialise()
