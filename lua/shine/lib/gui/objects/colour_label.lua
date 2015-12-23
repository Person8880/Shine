--[[
	Multi-coloured label.
]]

local SGUI = Shine.GUI

local Max = math.max
local Vector2 = Vector2

local ColourLabel = {}

function ColourLabel:Initialise()
	self.Labels = {}
	self.Layout = SGUI.Layout:CreateLayout( "Horizontal", {} )
	self.Font = Fonts.kAgencyFB_Small

	local Manager = GetGUIManager()
	self.Background = Manager:CreateGraphicItem()
	self.Background:SetColor( Colour( 0, 0, 0, 0 ) )
end

function ColourLabel:SetSize()
	self:InvalidateLayout()
end

local function AddProperty( Key, Modifiers )
	SGUI.AddProperty( ColourLabel, Key, nil, Modifiers )

	local Setter = "Set"..Key
	local Old = ColourLabel[ Setter ]
	ColourLabel[ Setter ] = function( self, Value )
		Old( self, Value )
		self:ForEach( "Labels", Setter, Value )
	end
end

AddProperty( "Font", { "InvalidatesParent" } )
AddProperty( "TextScale", { "InvalidatesParent" } )
AddProperty( "Colour" )

function ColourLabel:AlphaTo( ... )
	self:ForEach( "Labels", "AlphaTo", ... )
end

function ColourLabel:SetText( TextContent )
	if #self.Labels > 0 then
		for i = 1, #self.Labels do
			local Label = self.Labels[ i ]
			Label:Destroy( true )

			self.Layout.Elements[ i ] = nil
			self.Labels[ i ] = nil
		end
	end

	local Count = 0
	for i = 1, #TextContent, 2 do
		local Colour = TextContent[ i ]
		local Text = TextContent[ i + 1 ]

		local Label = SGUI:Create( "Label", self )
		Label:SetFontScale( self.Font, self.TextScale )
		Label:SetText( Text )
		Label:SetColour( SGUI.CopyColour( Colour ) )
		self.Layout:AddElement( Label )

		Count = Count + 1
		self.Labels[ Count ] = Label
	end
end

function ColourLabel:GetSize()
	local Width = 0
	local Height = 0

	for i = 1, #self.Labels do
		local Label = self.Labels[ i ]
		local Size = Label:GetSize()
		Width = Width + Size.x
		Height = Max( Height, Size.y )
	end

	return Vector2( Width, Height )
end

function ColourLabel:Think( DeltaTime )
	self.BaseClass.Think( self, DeltaTime )
	self:CallOnChildren( "Think", DeltaTime )
end

SGUI:Register( "ColourLabel", ColourLabel )
