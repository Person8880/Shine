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
	self.FlairWidth = HighResScaled( 8 )

	local Elements = SGUI:BuildTree( {
		Parent = self,
		{
			Class = "Horizontal",
			Type = "Layout",
			Children = {
				{
					ID = "Flair",
					Class = "Image",
					Props = {
						IsSchemed = false
					}
				},
				{
					ID = "HelpTextContainer",
					Class = "Horizontal",
					Type = "Layout",
					Props = {
						AutoSize = UnitVector( 0, Units.Auto.INSTANCE ),
						Fill = true,
						Padding = Spacing.Uniform( HighResScaled( 8 ) )
					},
					Children = {
						{
							ID = "HelpText",
							Class = "Label",
							Props = {
								AutoSize = UnitVector( Percentage.ONE_HUNDRED, Units.Auto.INSTANCE ),
								AutoWrap = true,
								CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
								Fill = true,
								IsSchemed = false
							}
						}
					}
				}
			}
		}
	} )

	-- Make the flair as big as the text contents without using percentage to avoid a cyclic height calculation.
	Elements.Flair:SetAutoSize( UnitVector( self.FlairWidth, Units.Auto( Elements.HelpTextContainer ) ) )

	self.Flair = Elements.Flair
	self.HelpText = Elements.HelpText
end

function Hint:GetContentSizeForAxis( Axis )
	return self.Layout:GetContentSizeForAxis( Axis )
end

function Hint:SetFlairWidth( FlairWidth )
	self.FlairWidth = ToUnit( FlairWidth )
	self.Flair.AutoSize[ 1 ] = self.FlairWidth
	self:InvalidateLayout()
end

SGUI:Register( "Hint", Hint )
