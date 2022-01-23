--[[
	A checkbox with a label attached.

	This replaces the deprecated label property on "CheckBox" as this element properly accounts for the size of both
	the checkbox and its label during layout.
]]

local Binder = require "shine/lib/gui/binding/binder"

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local CheckBoxWithLabel = {}

SGUI.AddProperty( CheckBoxWithLabel, "Radio", "CheckBox" )
SGUI.AddProperty( CheckBoxWithLabel, "LabelPadding", 10, { "InvalidatesLayout" } )

SGUI.AddBoundProperty( CheckBoxWithLabel, "AutoEllipsis", "Label" )
SGUI.AddBoundProperty( CheckBoxWithLabel, "Font", "Label" )
SGUI.AddBoundProperty( CheckBoxWithLabel, "TextColour", "Label:SetColour" )
SGUI.AddBoundProperty( CheckBoxWithLabel, "TextScale", "Label" )
SGUI.AddBoundProperty( CheckBoxWithLabel, "TextShadow", "Label:SetShadow" )
SGUI.AddBoundProperty( CheckBoxWithLabel, "CheckBoxAutoSize", "CheckBox:SetAutoSize" )
SGUI.AddBoundProperty( CheckBoxWithLabel, "CheckBoxSize", "CheckBox:SetSize" )

function CheckBoxWithLabel:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	self.Background = Background
	self.Background:SetShader( SGUI.Shaders.Invisible )

	self:SetLayout( SGUI.Layout:CreateLayout( "Horizontal" ) )

	self.CheckBox = SGUI:Create( "CheckBox", self )
	self.CheckBox:AddPropertyChangeListener( "Checked", self.OnCheckedInternal )
	self.Layout:AddElement( self.CheckBox )
end

function CheckBoxWithLabel:OnCheckedInternal( Checked )
	-- Forward the event to the parent (self here is the "CheckBox" element).
	local Parent = self.Parent
	Parent:OnChecked( Checked )
	Parent:OnPropertyChanged( "Checked", Checked )
end

function CheckBoxWithLabel:GetChecked()
	return self.CheckBox:GetChecked()
end

function CheckBoxWithLabel:SetChecked( Value, DontFade )
	return self.CheckBox:SetChecked( Value, DontFade )
end

local OldSetLabelPadding = CheckBoxWithLabel.SetLabelPadding
function CheckBoxWithLabel:SetLabelPadding( Padding )
	if not OldSetLabelPadding( self, Padding ) then return false end

	if SGUI.IsValid( self.Label ) then
		self.Label:SetMargin( Units.Spacing( Padding, 0, 0, 0 ) )
	end

	return true
end

function CheckBoxWithLabel:AddLabel( Text )
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

function CheckBoxWithLabel:SetEnabled( Enabled )
	return self.CheckBox:SetEnabled( Enabled )
end

function CheckBoxWithLabel:IsEnabled()
	return self.CheckBox:IsEnabled()
end

function CheckBoxWithLabel:OnChecked( Checked )

end

function CheckBoxWithLabel:SetPadding( Padding )
	self.Layout:SetPadding( Padding )
end

function CheckBoxWithLabel:GetContentSizeForAxis( Axis )
	return self.Layout:GetContentSizeForAxis( Axis )
end

function CheckBoxWithLabel:GetMaxSizeAlongAxis( Axis )
	return self.Layout:GetMaxSizeAlongAxis( Axis )
end

SGUI:Register( "CheckBoxWithLabel", CheckBoxWithLabel )
