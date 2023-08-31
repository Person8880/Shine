--[[
	Switch control, used as an alternative to a checkbox where the action behind the switch is more prominent.
]]

local Easing = require "shine/lib/gui/util/easing"

local FadingOutEase = Easing.GetEaser( "OutExpo" )
local FadingInEase = Easing.GetEaser( "InExpo" )

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units
local ToUnit = SGUI.Layout.ToUnit

local Switch = {}

local SetActive = SGUI.AddProperty( Switch, "Active", false )
SGUI.AddProperty( Switch, "ActiveBackgroundColour", Colour( 0, 1, 0 ) )
SGUI.AddProperty( Switch, "ClickSound", "sound/NS2.fev/common/button_enter" )
SGUI.AddProperty( Switch, "InactiveBackgroundColour", Colour( 0, 0, 0, 0.25 ) )
SGUI.AddProperty( Switch, "KnobPadding", Units.MultipleOf2( Units.HighResScaled( 4 ) ) )

SGUI.AddBoundColourProperty( Switch, "KnobColour", "SwitchKnob:SetColor" )

local function GetAbsolutePadding( self, Padding, Size )
	return ToUnit( Padding ):GetValue( self, Size.x, 1 )
end

local function GetKnobPosition( Active, AbsolutePadding, Size )
	local KnobSize = Size.y - AbsolutePadding * 2
	local XPos
	if Active then
		XPos = Size.x - KnobSize - AbsolutePadding
	else
		XPos = AbsolutePadding
	end
	return XPos, AbsolutePadding, KnobSize
end

local function OnActiveBackgroundColourChanged( self, Colour )
	if self.Active then
		self:StopFade( self.Background )
		self:SetBackgroundColour( Colour )
	end
end

local function OnInactiveBackgroundColourChanged( self, Colour )
	if not self.Active then
		self:StopFade( self.Background )
		self:SetBackgroundColour( Colour )
	end
end

local function OnKnobPaddingChanged( self, Padding )
	local Size = self:GetSize()
	local AbsolutePadding = GetAbsolutePadding( self, Padding, Size )
	local XPos, YPos, KnobSize = GetKnobPosition( self.Active, AbsolutePadding, Size )

	self:StopMoving( self.SwitchKnob )
	self.SwitchKnob:SetPosition( Vector2( XPos, YPos ) )
	local KnobSizeVector = Vector2( KnobSize, KnobSize )
	self.SwitchKnob:SetSize( KnobSizeVector )

	if self.BorderRadii then
		self.SwitchKnob:SetShader( SGUI.Shaders.RoundedRect )
		self.SwitchKnob:SetFloat2Parameter( "size", KnobSizeVector )

		local AbsoluteRadii = self:EvaluateBorderRadii( KnobSizeVector, self.BorderRadii )
		self.SwitchKnob:SetFloat4Parameter( "radii", AbsoluteRadii )
	else
		self.SwitchKnob:SetShader( "shaders/GUIBasic.surface_shader" )
	end
end

local function OnSizeChanged( self, Size )
	OnKnobPaddingChanged( self, self:GetKnobPadding() )
end

function Switch:Initialise()
	self.BaseClass.Initialise( self )

	self.Background = self:MakeGUIItem()
	self:SetBackgroundColour( self:GetInactiveBackgroundColour() )

	self.SwitchKnob = self:MakeGUIItem()
	self.Background:AddChild( self.SwitchKnob )

	self:AddPropertyChangeListener( "ActiveBackgroundColour", OnActiveBackgroundColourChanged )
	self:AddPropertyChangeListener( "InactiveBackgroundColour", OnInactiveBackgroundColourChanged )
	self:AddPropertyChangeListener( "KnobPadding", OnKnobPaddingChanged )
	self:AddPropertyChangeListener( "Size", OnSizeChanged )
end

local function OnTargetAlphaChanged( self, TargetAlpha )
	if not self.KnobColour then return end

	self.Knob:SetColor( self:ApplyAlphaCompensationToChildItemColour( self.KnobColour, TargetAlpha ) )
end

function Switch:OnAutoInheritAlphaChanged( IsAutoInherit )
	if IsAutoInherit then
		OnTargetAlphaChanged( self, self:GetTargetAlpha() )

		self:AddPropertyChangeListener( "TargetAlpha", OnTargetAlphaChanged )
	else
		if self.KnobColour then
			self.Knob:SetColor( self.KnobColour )
		end
		self:RemovePropertyChangeListener( "TargetAlpha", OnTargetAlphaChanged )
	end
end

function Switch:SetActive( Active, SkipAnim )
	if not SetActive( self, Active ) then return false end

	local BackgroundColour
	local EasingFunction
	if Active then
		BackgroundColour = self:GetActiveBackgroundColour()
		EasingFunction = FadingInEase
		self:AddStylingState( "Active" )
	else
		BackgroundColour = self:GetInactiveBackgroundColour()
		EasingFunction = FadingOutEase
		self:RemoveStylingState( "Active" )
	end

	local Size = self:GetSize()
	local AbsolutePadding = GetAbsolutePadding( self, self:GetKnobPadding(), Size )
	local XPos, YPos = GetKnobPosition( Active, AbsolutePadding, Size )

	if not SkipAnim then
		self:ApplyTransition( {
			Type = "Fade",
			EndValue = BackgroundColour,
			Duration = 0.15,
			EasingFunction = EasingFunction
		} )
		self:ApplyTransition( {
			Element = self.SwitchKnob,
			Type = "Move",
			EndValue = Vector2( XPos, YPos ),
			Duration = 0.15,
			EasingFunction = EasingFunction
		} )
	else
		self:SetBackgroundColour( BackgroundColour )
		self.SwitchKnob:SetPosition( Vector2( XPos, YPos ) )
	end
end

function Switch:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )
	if Result then
		return true, Child
	end

	if Key ~= InputKey.MouseButton0 then return end
	if not self:IsEnabled() or not self:MouseInControl() then return end

	return true, self
end

function Switch:OnToggled( Active )
	-- To be overridden.
end

function Switch:OnMouseUp( Key )
	if not self:MouseInControl() or not self:IsEnabled() then return end

	local Active = not self:GetActive()
	self:SetActive( Active )
	self:OnToggled( Active )

	local Sound = self:GetClickSound()
	if Sound then
		Shared.PlaySound( nil, Sound )
	end

	return true
end

SGUI:AddMixin( Switch, "EnableMixin" )
SGUI:Register( "Switch", Switch )
