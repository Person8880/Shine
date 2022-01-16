--[[
	A checkbox with a label attached.

	This replaces the deprecated label property on "CheckBox" as this element properly accounts for the size of both
	the checkbox and its label during layout.
]]

local Binder = require "shine/lib/gui/binding/binder"

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local CheckBoxLabel = {}

SGUI.AddProperty( CheckBoxLabel, "Radio", "CheckBox" )
SGUI.AddProperty( CheckBoxLabel, "LabelPadding", 10, { "InvalidatesLayout" } )

SGUI.AddBoundProperty( CheckBoxLabel, "AutoEllipsis", "Label" )
SGUI.AddBoundProperty( CheckBoxLabel, "Font", "Label" )
SGUI.AddBoundProperty( CheckBoxLabel, "TextColour", "Label:SetColour" )
SGUI.AddBoundProperty( CheckBoxLabel, "TextScale", "Label" )
SGUI.AddBoundProperty( CheckBoxLabel, "TextShadow", "Label:SetShadow" )
SGUI.AddBoundProperty( CheckBoxLabel, "CheckBoxAutoSize", "CheckBox:SetAutoSize" )
SGUI.AddBoundProperty( CheckBoxLabel, "CheckBoxSize", "CheckBox:SetSize" )

function CheckBoxLabel:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	self.Background = Background
	self.Background:SetShader( SGUI.Shaders.Invisible )

	self:SetLayout( SGUI.Layout:CreateLayout( "Horizontal" ) )

	self.CheckBox = SGUI:Create( "CheckBox", self )
	self.CheckBox:AddPropertyChangeListener( "Checked", self.OnCheckedInternal )
	self.Layout:AddElement( self.CheckBox )
end

function CheckBoxLabel:OnCheckedInternal( Checked )
	-- Forward the event to the parent (self here is the "CheckBox" element).
	local Parent = self.Parent
	Parent:OnChecked( Checked )
	Parent:OnPropertyChanged( "Checked", Checked )
end

function CheckBoxLabel:GetChecked()
	return self.CheckBox:GetChecked()
end

function CheckBoxLabel:SetChecked( Value, DontFade )
	return self.CheckBox:SetChecked( Value, DontFade )
end

local OldSetLabelPadding = CheckBoxLabel.SetLabelPadding
function CheckBoxLabel:SetLabelPadding( Padding )
	if not OldSetLabelPadding( self, Padding ) then return false end

	if SGUI.IsValid( self.Label ) then
		self.Label:SetMargin( Units.Spacing( Padding, 0, 0, 0 ) )
	end

	return true
end

function CheckBoxLabel:AddLabel( Text )
	if self.Label then
		self.Label:SetText( Text )
		self:InvalidateLayout()

		return
	end

	local Label = SGUI:Create( "Label", self )
	Label:SetIsSchemed( false )
	Label:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
	Label:SetText( Text )
	Label:SetMargin( Units.Spacing( self:GetLabelPadding(), 0, 0, 0 ) )
	Label:SetFill( true )

	-- If the text is shortened due to space constraints, provide a tooltip with the full text.
	Binder():FromElement( Label, "AutoEllipsisApplied" )
		:ToElement( Label, "Tooltip", {
			Transformer = function( AutoEllipsisApplied )
				return AutoEllipsisApplied and Label:GetText() or nil
			end
		} ):BindProperty()

	if self.AutoEllipsis then
		Label:SetAutoEllipsis( true )
	end

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
	self.Layout:AddElement( Label )
end

function CheckBoxLabel:SetEnabled( Enabled )
	return self.CheckBox:SetEnabled( Enabled )
end

function CheckBoxLabel:IsEnabled()
	return self.CheckBox:IsEnabled()
end

function CheckBoxLabel:OnChecked( Checked )

end

function CheckBoxLabel:SetPadding( Padding )
	self.Layout:SetPadding( Padding )
end

function CheckBoxLabel:GetContentSizeForAxis( Axis )
	return self.Layout:GetContentSizeForAxis( Axis )
end

function CheckBoxLabel:GetMaxSizeAlongAxis( Axis )
	return self.Layout:GetMaxSizeAlongAxis( Axis )
end

SGUI:Register( "CheckBoxLabel", CheckBoxLabel )
