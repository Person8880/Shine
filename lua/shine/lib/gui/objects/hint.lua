--[[
	Hint box to display information next to other controls.
]]

local Max = math.max

local SGUI = Shine.GUI

local Units = SGUI.Layout.Units
local HighResScaled = Units.HighResScaled
local Percentage = Units.Percentage
local Spacing = Units.Spacing
local UnitVector = Units.UnitVector

local ToUnit = SGUI.Layout.ToUnit

local Hint = {}

SGUI.AddBoundProperty( Hint, "Colour", "Background:SetColor" )
SGUI.AddBoundProperty( Hint, "FlairColour", "Flair:SetColor" )
SGUI.AddBoundProperty( Hint, "Text", "HelpText:SetText", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Hint, "TextColour", "HelpText:SetColour" )
SGUI.AddBoundProperty( Hint, "Font", "HelpText:SetFont", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Hint, "TextScale", "HelpText:SetTextScale", { "InvalidatesParent" } )

SGUI.AddProperty( Hint, "FlairWidth" )

function Hint:Initialise()
	self.BaseClass.Initialise( self )

	self.Background = self:MakeGUIItem()

	self.Flair = self:MakeGUIItem()
	self.Background:AddChild( self.Flair )

	self.FlairWidth = HighResScaled( 8 )

	local Padding = Spacing( HighResScaled( 16 ), HighResScaled( 8 ), HighResScaled( 8 ), HighResScaled( 8 ) )

	local Layout = SGUI.Layout:CreateLayout( "Horizontal", {
		Padding = Padding
	} )

	local HelpText = SGUI:Create( "Label", self )
	HelpText:SetIsSchemed( false )
	HelpText:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
	HelpText:SetFill( true )
	HelpText:SetAutoWrap( true )
	Layout:AddElement( HelpText )

	self.HelpText = HelpText

	self:SetLayout( Layout, true )
end

function Hint:GetContentSizeForAxis( Axis )
	if Axis == 1 then
		return 0
	end

	return self.HelpText:GetSize().y + Spacing.GetHeight( self.Layout:GetComputedPadding() )
end

function Hint:SetFlairWidth( FlairWidth )
	self.FlairWidth = ToUnit( FlairWidth )
	self:InvalidateLayout()
end

function Hint:PerformLayout()
	self.BaseClass.PerformLayout( self )

	local Size = self:GetSize()
	self.Flair:SetSize( Vector2( self.FlairWidth:GetValue( Size.x, self, 1 ), Size.y ) )
end

SGUI:Register( "Hint", Hint )
