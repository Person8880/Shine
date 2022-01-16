--[[
	Shine checkbox control.

	(More of a rectangle than a check.)
]]

local SGUI = Shine.GUI

local RoundTo = math.RoundTo

local CheckBox = {}

SGUI.AddProperty( CheckBox, "LabelPadding", 10, { "InvalidatesLayout" } )

function CheckBox:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	self.Background = Background

	local Box = self:MakeGUIItem()
	Box:SetAnchor( 0.5, 0.5 )

	Background:AddChild( Box )

	self.Box = Box
	self.Checked = false
end

function CheckBox:SetCheckedColour( Col )
	self.BoxCol = Col
	self.BoxHideCol = SGUI.CopyColour( Col )
	self.BoxHideCol.a = 0

	self.Box:SetColor( self.Checked and self.BoxCol or self.BoxHideCol )
end

function CheckBox:SetBackgroundColour( Col )
	self.BackgroundCol = Col

	self.Background:SetColor( Col )
end

function CheckBox:SetupStencil()
	self.BaseClass.SetupStencil( self )

	self.Box:SetInheritsParentStencilSettings( true )

	if self.Label then
		self.Label.Label:SetInheritsParentStencilSettings( true )
	end
end

function CheckBox:SetSize( Vec )
	Vec.x = RoundTo( Vec.x, 2 )
	Vec.y = RoundTo( Vec.y, 2 )

	self.BaseClass.SetSize( self, Vec )

	local BoxSize = Vec * 0.75
	BoxSize.x = RoundTo( BoxSize.x, 2 )
	BoxSize.y = RoundTo( BoxSize.y, 2 )

	self.Box:SetSize( BoxSize )
	self.Box:SetPosition( -BoxSize * 0.5 )
end

function CheckBox:GetChecked()
	return self.Checked
end

function CheckBox:SetChecked( Value, DontFade )
	if Value == self.Checked then return end

	if Value then
		self.Checked = true

		if DontFade then
			self.Box:SetColor( self.BoxCol )
		else
			self:FadeTo( self.Box, self.BoxHideCol, self.BoxCol, 0, 0.1 )
		end

		self:OnChecked( true )
		self:OnPropertyChanged( "Checked", true )

		return
	end

	self.Checked = false

	if DontFade then
		self.Box:SetColor( self.BoxHideCol )
	else
		self:FadeTo( self.Box, self.BoxCol, self.BoxHideCol, 0, 0.1 )
	end

	self:OnChecked( false )
	self:OnPropertyChanged( "Checked", false )
end

-- Include the attached label when checking for mouse entry.
function CheckBox:GetMouseBounds()
	local Size = self:GetSize()
	if SGUI.IsValid( self.Label ) then
		Size = Size + Vector2( Size.x + self:GetLabelPadding() + self.Label:GetSize().x, 0 )
	end
	return Size
end

function CheckBox:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() or not self:IsEnabled() then return end
	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Background ) then return end

	return true, self
end

function CheckBox:OnMouseUp( Key )
	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Background ) then return end

	if not self.Checked then
		self:SetChecked( true )
	elseif not self.Radio then
		self:SetChecked( false )
	end

	return true
end

function CheckBox:PerformLayout()
	if self.Label then
		local Size = self:GetSize().x
		self.Label:SetPos( Vector( Size + self:GetLabelPadding(), 0, 0 ) )
	end
end

--[[
	NOTE: This is deprecated. Use the "CheckBoxLabel" control as it properly wraps the checkbox and label in its own
	sizable box.
]]
function CheckBox:AddLabel( Text )
	if self.Label then
		self.Label:SetText( Text )
		self:InvalidateLayout()

		return
	end

	local Label = SGUI:Create( "Label", self )
	Label:SetIsSchemed( false )
	Label:SetAnchor( GUIItem.Left, GUIItem.Center )
	Label:SetTextAlignmentY( GUIItem.Align_Center )
	Label:SetText( Text )
	Label:SetPos( Vector( self:GetSize().x + self:GetLabelPadding(), 0, 0 ) )

	if self.Font then
		Label:SetFont( self.Font )
	end

	if self.TextScale then
		Label:SetTextScale( self.TextScale )
	end

	if self.TextColour then
		Label:SetColour( self.TextColour )
	end

	if self.Stencilled then
		Label.Label:SetInheritsParentStencilSettings( true )
	end

	self.Label = Label
end

function CheckBox:OnChecked( Checked )

end

SGUI.AddProperty( CheckBox, "Radio" )
SGUI.AddBoundProperty( CheckBox, "Font", "Label" )
SGUI.AddBoundProperty( CheckBox, "TextColour", "Label:SetColour" )
SGUI.AddBoundProperty( CheckBox, "TextScale", "Label" )
SGUI.AddBoundProperty( CheckBox, "TextShadow", "Label:SetShadow" )

SGUI:AddMixin( CheckBox, "EnableMixin" )
SGUI:Register( "CheckBox", CheckBox )
