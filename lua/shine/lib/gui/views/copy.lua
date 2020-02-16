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

	UpdateWithValues()
end

local ValuesToWatch = { "Width", "Height", "SourceTexture" }
local LastValues = {}
for i = 1, #ValuesToWatch do
	LastValues[ ValuesToWatch[ i ] ] = _G[ ValuesToWatch[ i ] ]
end

function Update( DeltaTime )
	local NeedsUpdate = false
	for i = 1, #ValuesToWatch do
		local Key = ValuesToWatch[ i ]
		local CurrentValue = _G[ Key ]
		if CurrentValue ~= LastValues[ Key ] then
			NeedsUpdate = true
		end
		LastValues[ Key ] = CurrentValue
	end

	if NeedsUpdate then
		UpdateWithValues()
	end
end

Initialise()
