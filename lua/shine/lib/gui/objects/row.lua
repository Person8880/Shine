--[[
	A panel object with a horizontal layout built-in.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local Row = {}

function Row:Initialise()
	Controls.Panel.Initialise( self )

	self:SetLayout( SGUI.Layout:CreateLayout( "Horizontal" ), true )
end

function Row:GetContentSizeForAxis( Axis )
	return self.Layout:GetContentSizeForAxis( Axis )
end

SGUI:Register( "Row", Row, "Panel" )
