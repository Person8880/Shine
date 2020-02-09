--[[
	Image control.
]]

local SGUI = Shine.GUI

local Image = {}

SGUI.AddBoundProperty( Image, "Colour", "Background:SetColor" )

function Image:Initialise()
	self.BaseClass.Initialise( self )
	self.Background = self:MakeGUIItem()
end

SGUI:AddMixin( Image, "Clickable" )
SGUI:Register( "Image", Image )
