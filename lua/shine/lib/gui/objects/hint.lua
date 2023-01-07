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

SGUI.AddBoundProperty( Hint, "Colour", "self:SetBackgroundColour" )
SGUI.AddBoundProperty( Hint, "FlairColour", "Flair:SetColour" )
SGUI.AddBoundProperty( Hint, "Text", "HelpText:SetText", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Hint, "TextColour", "HelpText:SetColour" )
SGUI.AddBoundProperty( Hint, "Font", "HelpText:SetFont", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Hint, "TextScale", "HelpText:SetTextScale", { "InvalidatesParent" } )

SGUI.AddProperty( Hint, "FlairWidth" )

function Hint:Initialise()
	self.BaseClass.Initialise( self )

	self.Background = self:MakeGUIItem()

	local Padding = Spacing( 0, HighResScaled( 8 ), HighResScaled( 8 ), HighResScaled( 8 ) )
	local Layout = SGUI.Layout:CreateLayout( "Horizontal", {
		Padding = Padding
	} )

	self.FlairWidth = HighResScaled( 8 )

	local Flair = SGUI:Create( "Image", self )
	Flair:SetIsSchemed( false )
	Flair:SetAutoSize( UnitVector( self.FlairWidth, Percentage.ONE_HUNDRED ) )
	Flair:SetMargin( Spacing( 0, 0, HighResScaled( 8 ), 0 ) )
	Layout:AddElement( Flair )

	self.Flair = Flair

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
	return self.Layout:GetContentSizeForAxis( Axis )
end

function Hint:SetFlairWidth( FlairWidth )
	self.FlairWidth = ToUnit( FlairWidth )
	self.Flair:SetAutoSize( UnitVector( self.FlairWidth, Percentage.ONE_HUNDRED ) )
	self:InvalidateLayout()
end

SGUI:Register( "Hint", Hint )
