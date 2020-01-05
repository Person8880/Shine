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
