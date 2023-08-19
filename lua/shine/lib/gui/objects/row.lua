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

function Row:Clear()
	local Layout = self.Layout
	Layout:Clear()
	Controls.Panel.Clear( self )
	-- Retain the layout as that's the point of this control.
	self.Layout = Layout
end

function Row:SetPadding( Padding )
	self.Layout:SetPadding( Padding )
end

function Row:GetMaxSizeAlongAxis( Axis )
	return self.Layout:GetMaxSizeAlongAxis( Axis )
end

SGUI:Register( "Row", Row, "Panel" )
