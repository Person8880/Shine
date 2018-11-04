--[[
	An extension of Label to allow for a shadow beneath the text.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local ShadowLabel = {}

SGUI.AddBoundProperty( ShadowLabel, "Font", { "Label:SetFontName", "LabelShadow:SetFontName" }, { "InvalidatesParent" } )
SGUI.AddBoundProperty( ShadowLabel, "Text", { "Label", "LabelShadow" }, { "InvalidatesParent" } )
SGUI.AddBoundProperty( ShadowLabel, "TextAlignmentX", { "Label", "LabelShadow" } )
SGUI.AddBoundProperty( ShadowLabel, "TextAlignmentY", { "Label", "LabelShadow" } )
SGUI.AddBoundProperty( ShadowLabel, "TextScale", { "Label:SetScale", "LabelShadow:SetScale" }, { "InvalidatesParent" } )

function ShadowLabel:Initialise()
	self.LabelShadow = GetGUIManager():CreateTextItem()
	self.LabelShadow:SetIsVisible( false )

	Controls.Label.Initialise( self )
end

function ShadowLabel:SetPos( Pos )
	self.BaseClass.SetPos( self, Pos )

	if self.ShadowOffset then
		self.LabelShadow:SetPosition( Pos + self.ShadowOffset )
	end
end

function ShadowLabel:SetAnchor( Anchor )
	self.BaseClass.SetAnchor( self, Anchor )
	self.LabelShadow:SetAnchor( self.Label:GetAnchor() )
end

function ShadowLabel:SetParent( Control, Element )
	-- Must add the shadow label to the parent first before the main label, otherwise
	-- it will draw on top (would be nice to have a z-index for GUIItems...)
	local ParentElement = Element or ( Control and Control.Background )
	if ParentElement then
		ParentElement:AddChild( self.LabelShadow )
	else
		local Parent = self.LabelShadow:GetParent()
		if Parent then
			Parent:RemoveChild( self.LabelShadow )
		end
	end

	self.BaseClass.SetParent( self, Control, Element )
end

function ShadowLabel:SetShadow( Params )
	self.Shadow = Params

	if not Params then
		self.ShadowOffset = nil
		self.LabelShadow:SetIsVisible( false )
		return
	end

	self.ShadowOffset = Params.Offset or Vector2( 2, 2 )
	self.LabelShadow:SetIsVisible( true )
	self.Label:SetPosition( self:GetPos() + self.ShadowOffset )
	self.LabelShadow:SetColor( Params.Colour )
end

function ShadowLabel:SetupStencil()
	Controls.Label.SetupStencil( self )

	self.LabelShadow:SetInheritsParentStencilSettings( false )
	self.LabelShadow:SetStencilFunc( GUIItem.NotEqual )
end

SGUI:Register( "ShadowLabel", ShadowLabel, "Label" )
