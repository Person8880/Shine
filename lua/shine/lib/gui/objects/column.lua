--[[
	A panel object with a vertical layout built-in.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local Column = {}

function Column:Initialise()
	Controls.Panel.Initialise( self )

	self:SetLayout( SGUI.Layout:CreateLayout( "Vertical" ), true )
end

function Column:Clear()
	local Layout = self.Layout
	Layout:Clear()
	Controls.Panel.Clear( self )
	-- Retain the layout as that's the point of this control.
	self.Layout = Layout
end

function Column:SetPadding( Padding )
	self.Layout:SetPadding( Padding )
end

function Column:GetContentSizeForAxis( Axis )
	return self.Layout:GetContentSizeForAxis( Axis )
end

function Column:GetMaxSizeAlongAxis( Axis )
	return self.Layout:GetMaxSizeAlongAxis( Axis )
end

SGUI:Register( "Column", Column, "Panel" )
