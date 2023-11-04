--[[
	Modal object.

	Used to popup a dialog box.
]]

local Easing = require "shine/lib/gui/util/easing"

local FadingOutEase = Easing.GetEaser( "OutExpo" )
local FadingInEase = Easing.GetEaser( "InExpo" )

local SGUI = Shine.GUI
local Controls = SGUI.Controls
local Units = SGUI.Layout.Units

local Max = math.max

local Modal = {}

Modal.IsWindow = true

SGUI.AddBoundProperty( Modal, "BlendTechnique", "VisibleBackground" )
SGUI.AddBoundProperty( Modal, "Colour", "VisibleBackground:SetColor" )
SGUI.AddBoundProperty( Modal, "Shader", "VisibleBackground" )
SGUI.AddBoundProperty( Modal, "Texture", "VisibleBackground" )

local STATE_NONE = 1
local STATE_POPUP = 2
local STATE_CLOSING = 3

local InitialScale = Vector2( 0.9, 0.9 )

function Modal:Initialise()
	Controls.Panel.Initialise( self )

	self.State = STATE_NONE

	-- Scale from the centre.
	self.Background:SetHotSpot( Vector2( 0.5, 0.5 ) )
	-- Use an invisible background to allow for alpha fading.
	self.Background:SetShader( SGUI.Shaders.Invisible )
	-- Start the element as an invisible box that's scaled down, the popup animation will fade this in and scale it up.
	self.Background:SetColor( Colour( 0, 0, 0, 0 ) )
	self.Background:SetScale( InitialScale )
	self:SetAlphaMultiplier( 0 )

	self.VisibleBackground = self:MakeGUIItem()
	self.VisibleBackground:SetInheritsParentAlpha( true )
	self.VisibleBackground:SetInheritsParentScaling( true )
	self.Background:AddChild( self.VisibleBackground )

	self:SetLayout( SGUI.Layout:CreateLayout( "Vertical" ), true )

	self.InheritsParentAlpha = true
	self.InheritsParentScaling = true

	-- Make all children automatically inherit alpha and scaling so they fade in properly without extra work.
	self:SetPropagateAlphaInheritance( true )
	self:SetPropagateScaleInheritance( true )
end

function Modal:AddTitleBar( Title, Font, TextScale )
	Controls.Panel.AddTitleBar( self, Title, Font, TextScale )

	-- Push down the layout content beneath the title bar.
	self:SetPadding( Units.Spacing( 0, self.TitleBarHeight, 0, 0 ) )
end

function Modal:PopUp( TargetWindow )
	if self.State ~= STATE_NONE then return end

	if SGUI.IsValid( TargetWindow ) and TargetWindow.Background then
		-- This will be automatically cleaned up on modal destruction as its parent is outside the modal's tree.
		self.WindowDarkenOverlay = self:MakeGUIItem()
		self.WindowDarkenOverlay:SetLayer( 1000 )
		self.WindowDarkenOverlay:SetColor( Colour( 0, 0, 0, 0 ) )
		self.WindowDarkenOverlay:SetSize( TargetWindow:GetSize() )
		TargetWindow.Background:AddChild( self.WindowDarkenOverlay )

		self.TargetWindowSizeListener = function( Window, Size )
			self.WindowDarkenOverlay:SetSize( Size )
		end

		TargetWindow:AddPropertyChangeListener( "Size", self.TargetWindowSizeListener )

		self.TargetWindow = TargetWindow

		self:ApplyTransition( {
			Type = "Alpha",
			EndValue = 0.75,
			Duration = 0.15,
			EasingFunction = FadingInEase,
			Element = self.WindowDarkenOverlay
		} )

		TargetWindow:DeleteOnRemove( self )
	end

	self.State = STATE_POPUP

	self:ApplyTransition( {
		Type = "AlphaMultiplier",
		EndValue = 1,
		Duration = 0.15,
		EasingFunction = FadingInEase
	} )
	self:ApplyTransition( {
		Type = "Scale",
		EndValue = Vector2( 1, 1 ),
		Duration = 0.15,
		EasingFunction = FadingInEase
	} )

	SGUI:EnableMouse( true, self )
end

function Modal:Close()
	if self.State == STATE_CLOSING then return end

	if SGUI.IsValid( self.TargetWindow ) then
		self:ApplyTransition( {
			Type = "Alpha",
			EndValue = 0,
			Duration = 0.15,
			EasingFunction = FadingOutEase,
			Element = self.WindowDarkenOverlay
		} )
	end

	self.State = STATE_CLOSING

	self:ApplyTransition( {
		Type = "AlphaMultiplier",
		EndValue = 0,
		Duration = 0.15,
		EasingFunction = FadingOutEase
	} )
	self:ApplyTransition( {
		Type = "Scale",
		EndValue = InitialScale,
		Duration = 0.15,
		EasingFunction = FadingOutEase,
		Callback = self.Destroy
	} )

	SGUI:EnableMouse( false, self )
end

function Modal:SetSize( Size )
	local OldSize = self:GetSize()
	if not Controls.Panel.SetSize( self, Size ) then return false end

	local Pos = self.Background:GetPosition()
	local Diff = Size - OldSize

	self.VisibleBackground:SetSize( Size )

	Pos = Pos + Diff * 0.5

	self.Background:SetPosition( Pos )

	return true
end

function Modal:SetPos( Pos )
	-- Compensate for the hotspot to interpret this position as top-left.
	return self.BaseClass.SetPos( self, Pos + self:GetSize() * 0.5 )
end

function Modal:GetPos()
	-- Return the position of the top-left corner, not the centre.
	local Pos = self.BaseClass.GetPos( self )
	Pos = Pos - self:GetSize() * 0.5
	return Pos
end

function Modal:GetMaxSizeAlongAxis( Axis )
	local MaxSize = self.Layout:GetMaxSizeAlongAxis( Axis )
	if SGUI.IsValid( self.TitleBar ) then
		MaxSize = Max(
			MaxSize,
			self.TitleBar:GetComputedSize( Axis, self:GetSizeForAxis( Axis ), self:GetSizeForOppositeAxis( Axis ) )
		)
	end
	return MaxSize
end

function Modal:OnMouseDown( Key, DoubleClick )
	if self.State == STATE_CLOSING then return end

	local Handled, Child = Controls.Panel.OnMouseDown( self, Key, DoubleClick )
	if not Handled then
		-- Close if clicking outside the modal.
		self:Close()
	end

	return Handled, Child
end

function Modal:OnMouseMove( Down )
	if self.State == STATE_CLOSING then return end
	return Controls.Panel.OnMouseMove( self, Down )
end

function Modal:Cleanup()
	if SGUI.IsValid( self.TargetWindow ) then
		self.TargetWindow:ResetDeleteOnRemove( self )
		self.TargetWindow:RemovePropertyChangeListener( "Size", self.TargetWindowSizeListener )
	end
	return Controls.Panel.Cleanup( self )
end

SGUI:Register( "Modal", Modal, "Panel" )
