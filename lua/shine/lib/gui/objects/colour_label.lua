--[[
	Multi-coloured label.
]]

local IsType = Shine.IsType
local SGUI = Shine.GUI

local Max = math.max
local Vector2 = Vector2

local ColourLabel = {}

SGUI.AddProperty( ColourLabel, "DefaultLabelType", "Label" )

function ColourLabel:Initialise()
	self.Labels = {}
	self.Layout = SGUI.Layout:CreateLayout( "Horizontal", {} )
	self.Font = Fonts.kAgencyFB_Small
	self.IsVertical = false

	self.Background = self:MakeGUIItem()
	self.Background:SetColor( Colour( 0, 0, 0, 0 ) )
end

function ColourLabel:MakeVertical()
	if self.IsVertical then return end

	self.Layout = SGUI.Layout:CreateLayout( "Vertical", {} )
	self.IsVertical = true
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

function ColourLabel:SetTextAlignmentX( XAlign )
	self:ForEach( "Labels", "SetTextAlignmentX", XAlign )
end

function ColourLabel:SetTextAlignmentY( YAlign )
	self:ForEach( "Labels", "SetTextAlignmentY", YAlign )
end

function ColourLabel:SetShadow( Params )
	self:ForEach( "Labels", "SetShadow", Params )
end

function ColourLabel:AlphaTo( ... )
	self:ForEach( "Labels", "AlphaTo", ... )
end

function ColourLabel:SetText( TextContent )
	local Easing
	if #self.Labels > 0 then
		for i = 1, #self.Labels do
			local Label = self.Labels[ i ]
			local LabelAlphaEase = Label:GetEasing( "Alpha" )
			if LabelAlphaEase and not Easing then
				Easing = LabelAlphaEase
			end
			Label:Destroy()

			self.Layout.Elements[ i ] = nil
			self.Labels[ i ] = nil
		end
	end

	local Count = 0
	local DefaultLabelType = self:GetDefaultLabelType()
	for i = 1, #TextContent, 2 do
		local Colour = TextContent[ i ]
		local Params = TextContent[ i + 1 ]
		local Type = DefaultLabelType
		local Text = Params

		if IsType( Params, "table" ) then
			Text = Params.Text
			Type = Params.Type or DefaultLabelType
		end

		local Label = SGUI:Create( Type, self )
		Label:SetFontScale( self.Font, self.TextScale )
		Label:SetText( Text )
		Label:SetColour( SGUI.CopyColour( Colour ) )
		self.Layout:AddElement( Label )

		Count = Count + 1
		self.Labels[ Count ] = Label
	end

	if Easing and Easing.Elapsed < Easing.Duration then
		self:AlphaTo( nil, Easing.Start, Easing.End, -Easing.Elapsed, Easing.Duration, Easing.Callback,
			Easing.EaseFunc, Easing.Power )
	end
end

function ColourLabel:GetSize()
	local Width = 0
	local Height = 0

	if self.IsVertical then
		for i = 1, #self.Labels do
			local Label = self.Labels[ i ]
			local Size = Label:GetSize()
			Width = Max( Width, Size.x )
			Height = Height + Size.y
		end
	else
		for i = 1, #self.Labels do
			local Label = self.Labels[ i ]
			local Size = Label:GetSize()
			Width = Width + Size.x
			Height = Max( Height, Size.y )
		end
	end

	return Vector2( Width, Height )
end

SGUI:AddMixin( ColourLabel, "Clickable" )
SGUI:Register( "ColourLabel", ColourLabel )
