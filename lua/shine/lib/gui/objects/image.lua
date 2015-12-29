--[[
	Image control.
]]

local SGUI = Shine.GUI

local Image = {}

SGUI.AddBoundProperty( Image, "Colour", "Background:SetColor" )

function Image:Initialise()
	self.BaseClass.Initialise( self )
	self.Background = GetGUIManager():CreateGraphicItem()
end

SGUI:Register( "Image", Image )
