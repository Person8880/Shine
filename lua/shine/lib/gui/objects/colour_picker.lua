--[[
	Colour picker control, providing a means of selecting a colour using a standard HSV selector and/or RGB sliders.
]]

local Clamp = math.Clamp
local Round = math.Round
local StringTransformCase = string.TransformCase
local StringCaseFormatType = string.CaseFormatType

local SGUI = Shine.GUI
local Controls = SGUI.Controls
local Units = SGUI.Layout.Units

local GetCursorPos = SGUI.GetCursorPos

local SaturationValuePicker = SGUI:DefineControl( "SaturationValuePicker" )
do
	local SetSaturation = SGUI.AddProperty( SaturationValuePicker, "Saturation" )
	local SetValue = SGUI.AddProperty( SaturationValuePicker, "Value" )

	function SaturationValuePicker:Initialise()
		self.BaseClass.Initialise( self )

		local Background = self:MakeGUIItem()
		self.Background = Background

		local SaturationValueOverlay = self:MakeGUIItem()
		SaturationValueOverlay:SetTexture( "ui/newMenu/saturationValueRange.dds" )
		Background:AddChild( SaturationValueOverlay )
		self.SaturationValueOverlay = SaturationValueOverlay

		local CursorSize = Units.HighResScaled( 16 ):GetValue()
		local Cursor = self:MakeGUIItem()
		Cursor:SetTexture( "ui/newMenu/circle.dds" )
		Cursor:SetSize( Vector2( CursorSize, CursorSize ) )
		Cursor:SetHotSpot( 0.5, 0.5 )
		Background:AddChild( Cursor )
		self.Cursor = Cursor

		self.Saturation = 0
		self.Value = 1

		self.CursorPos = Cursor:GetPosition()
	end

	function SaturationValuePicker:SetSize( Size )
		if not self.BaseClass.SetSize( self, Size ) then return false end

		self.SaturationValueOverlay:SetSize( Size )

		self.CursorPos.x = Size.x * self.Saturation
		self.CursorPos.y = Size.y * ( 1 - self.Value )
		self.Cursor:SetPosition( self.CursorPos )

		return true
	end

	function SaturationValuePicker:SetSaturation( Saturation )
		Saturation = Clamp( Saturation, 0, 1 )

		if not SetSaturation( self, Saturation ) then return false end

		self.CursorPos.x = Saturation * self:GetSize().x
		self.Cursor:SetPosition( self.CursorPos )

		return true
	end

	function SaturationValuePicker:SetValue( Value )
		Value = Clamp( Value, 0, 1 )

		if not SetValue( self, Value ) then return false end

		self.CursorPos.y = ( 1 - Value ) * self:GetSize().y
		self.Cursor:SetPosition( self.CursorPos )

		return true
	end

	function SaturationValuePicker:OnDraggingCursor( Saturation, Value )
		-- To be overridden.
	end

	function SaturationValuePicker:OnChanged( Saturation, Value )
		-- To be overridden.
	end

	function SaturationValuePicker:OnMouseDown( Key, DoubleClick )
		if not self:GetIsVisible() then return end

		if Key ~= InputKey.MouseButton0 then return end
		if not self:MouseIn( self.Cursor, 1.25 ) then
			if self:HasMouseEntered() then
				self.ClickingBox = true
				return true, self
			end

			return
		end

		local X, Y = GetCursorPos()

		self.Dragging = true
		self.DragStart = Vector2( X, Y )
		self.StartingPos = Vector( self.CursorPos )

		return true, self
	end

	function SaturationValuePicker:OnMouseMove( Down )
		self.BaseClass.OnMouseMove( self, Down )

		if not Down then return end
		if not self.Dragging then return end

		local X, Y = GetCursorPos()

		local XDiff = X - self.DragStart.x
		local YDiff = Y - self.DragStart.y
		local Size = self:GetSize()

		local NewSaturation = Clamp( ( self.StartingPos.x + XDiff ) / Size.x, 0, 1 )
		local NewValue = 1 - Clamp( ( self.StartingPos.y + YDiff ) / Size.y, 0, 1 )

		self:SetSaturation( NewSaturation )
		self:SetValue( NewValue )
		self:OnDraggingCursor( NewSaturation, NewValue )
	end

	function SaturationValuePicker:OnMouseUp( Key )
		if Key ~= InputKey.MouseButton0 then return end

		if self.ClickingBox then
			self.ClickingBox = nil

			local In, X, Y = self:MouseInCached()
			if not In then return end

			local Size = self:GetSize()
			local Saturation = Clamp( X / Size.x, 0, 1 )
			local Value = 1 - Clamp( Y / Size.y, 0, 1 )

			self:SetSaturation( Saturation )
			self:SetValue( Value )
		else
			self.Dragging = false
		end

		self:OnChanged( self.Saturation, self.Value )

		return true
	end
end

local ColourPicker = {}

ColourPicker.Sound = "sound/NS2.fev/common/button_enter"

local SetValue = SGUI.AddProperty( ColourPicker, "Value" )

function ColourPicker:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	self.Background = Background

	local Tree = SGUI:BuildTree( {
		Parent = self,
		{
			Class = "Horizontal",
			Type = "Layout",
			Props = {
				Padding = Units.Spacing.Uniform( Units.HighResScaled( 4 ) )
			},
			Children = {
				{
					ID = "ColourPreview",
					Class = "Image",
					Props = {
						Fill = true
					}
				}
			}
		}
	} )

	self.ColourPreview = Tree.ColourPreview
	self.Value = Colour( 1, 1, 1, 1 )
end

function ColourPicker:OnValueChanged( Value )
	-- To be overridden.
end

function ColourPicker:SetValue( Value )
	if not SetValue( self, Value ) then return false end

	self.ColourPreview:SetColour( Value )

	return true
end

function ColourPicker:DoClick()
	if self.ColourPickerPopupClosedFrame == self:GetLastMouseDownFrameNumber() then return end

	local R, G, B = self.Value.r, self.Value.g, self.Value.b
	local Hue, Saturation, Value = SGUI.RGBToHSV( R, G, B )
	local AgencyFBNormal = {
		Family = "kAgencyFB",
		Size = Units.HighResScaled( 27 )
	}

	local MaxSliderLabelWidth = Units.Max()
	local SliderSize = Units.UnitVector(
		Units.Percentage.ONE_HUNDRED - Units.HighResScaled( 48 + 8 ) - MaxSliderLabelWidth,
		Units.HighResScaled( 32 )
	)

	local function MakeSlider( ID, StyleName, Margin )
		local LabelKey = StringTransformCase(
			ID,
			StringCaseFormatType.UPPER_CAMEL,
			StringCaseFormatType.UPPER_UNDERSCORE
		).."_LABEL"

		return {
			Class = "Horizontal",
			Type = "Layout",
			Props = {
				Fill = false,
				AutoSize = Units.UnitVector( Units.Percentage.ONE_HUNDRED, Units.HighResScaled( 32 ) )
			},
			Children = {
				{
					Class = "Label",
					Props = {
						AutoFont = AgencyFBNormal,
						DebugName = ID.."Label",
						Margin = Units.Spacing( 0, 0, MaxSliderLabelWidth - Units.Auto() + Units.HighResScaled( 8 ), 0 ),
						Text = Shine.Locale:GetPhrase( "Core", LabelKey )
					},
					OnBuilt = function( self, Label )
						-- Align the sliders based on the largest label.
						MaxSliderLabelWidth:AddValue( Units.Auto( Label ) )
					end
				},
				{
					ID = ID,
					Class = "Slider",
					Props = {
						AutoFont = AgencyFBNormal,
						Decimals = 0,
						AutoSize = SliderSize,
						StyleName = StyleName,
						Margin = Margin
					}
				}
			}
		}
	end

	local Tree = SGUI:BuildTree( {
		{
			ID = "Popup",
			Class = "Column",
			Props = {
				InheritsParentAlpha = true,
				PropagateAlphaInheritance = true,
				Padding = Units.Spacing.Uniform( Units.HighResScaled( 8 ) ),
				Size = Vector2( Units.HighResScaled( 320 + 56 ):GetValue(), Units.HighResScaled( 320 + 128 ):GetValue() )
			},
			Children = {
				{
					Type = "Layout",
					Class = "Horizontal",
					Props = {
						Fill = true,
						Margin = Units.Spacing( 0, 0, 0, Units.HighResScaled( 8 ) )
					},
					Children = {
						{
							ID = "SaturationValuePicker",
							Class = SaturationValuePicker,
							Props = {
								BackgroundColour = Colour( SGUI.HSVToRGB( Hue, 1, 1 ) ),
								Saturation = Saturation,
								Value = Value,
								Fill = true
							}
						},
						{
							ID = "HueSlider",
							Class = "Slider",
							Props = {
								AutoSize = Units.UnitVector( Units.HighResScaled( 32 ), Units.Percentage.ONE_HUNDRED ),
								Vertical = true,
								HandleThickness = Units.HighResScaled( 5 ):GetValue(),
								StyleName = "HuePicker",
								Decimals = 6,
								TextIsVisible = false,
								Margin = Units.Spacing( Units.HighResScaled( 8 ), 0, 0, 0 )
							}
						}
					}
				},
				MakeSlider( "RedSlider", "RedPicker", Units.Spacing( 0, 0, 0, Units.HighResScaled( 4 ) ) ),
				MakeSlider( "GreenSlider", "GreenPicker", Units.Spacing( 0, 0, 0, Units.HighResScaled( 4 ) ) ),
				MakeSlider( "BlueSlider", "BluePicker" )
			}
		}
	} )

	self.ColourPickerPopup = Tree.Popup

	Tree.HueSlider:SetBounds( 0, 1 )
	Tree.HueSlider:SetValue( Hue, true )

	Tree.RedSlider:SetBounds( 0, 255 )
	Tree.RedSlider:SetValue( Round( self.Value.r * 255 ), true )
	Tree.RedSlider:InvalidateParent()

	Tree.GreenSlider:SetBounds( 0, 255 )
	Tree.GreenSlider:SetValue( Round( self.Value.g * 255 ), true )
	Tree.GreenSlider:InvalidateParent()

	Tree.BlueSlider:SetBounds( 0, 255 )
	Tree.BlueSlider:SetValue( Round( self.Value.b * 255 ), true )
	Tree.BlueSlider:InvalidateParent()

	local PopupSize = Tree.Popup:GetSize()
	local ScreenWidth, ScreenHeight = SGUI.GetScreenSize()
	local Pos = self:GetScreenPos()
	Pos.x = Clamp( Pos.x + self:GetSize().x, 0, ScreenWidth - PopupSize.x )
	Pos.y = Clamp( Pos.y, 0, ScreenHeight - PopupSize.y )

	Tree.Popup:SetPos( Pos )
	Tree.Popup:SetBoxShadow( {
		BlurRadius = Units.HighResScaled( 8 ):GetValue(),
		Colour = Colour( 0, 0, 0, 0.9 )
	} )
	Tree.Popup:ApplyTransition( {
		Type = "AlphaMultiplier",
		StartValue = 0,
		EndValue = 1,
		Duration = 0.15
	} )

	local OldOnMouseDown = Tree.Popup.OnMouseDown
	function Tree.Popup:OnMouseDown( Key, DoubleClick )
		local Handled, Child = OldOnMouseDown( self, Key, DoubleClick )
		if not Handled then
			-- Close if clicking outside the popup.
			self:Destroy()
		end
		return Handled, Child
	end

	local OldPlayerKeyPress = Tree.Popup.PlayerKeyPress
	function Tree.Popup:PlayerKeyPress( Key, Down )
		local Handled = OldPlayerKeyPress( self, Key, Down )
		if not Handled and Key == InputKey.Escape then
			Handled = true
			self:Destroy()
		end
		return Handled
	end

	Tree.Popup:CallOnRemove( function()
		self.ColourPickerPopupClosedFrame = SGUI.FrameNumber()
		self.ColourPickerPopup = nil
	end )

	local function RefreshColour()
		Tree.SaturationValuePicker:SetBackgroundColour( Colour( SGUI.HSVToRGB( Hue, 1, 1 ) ) )

		local NewColour = Colour( R, G, B )
		self:SetValue( NewColour )
		self:OnValueChanged( NewColour )
	end

	local function RefreshRGB()
		R, G, B = SGUI.HSVToRGB( Hue, Saturation, Value )
		Tree.RedSlider:SetValue( Round( R * 255 ), true )
		Tree.GreenSlider:SetValue( Round( G * 255 ), true )
		Tree.BlueSlider:SetValue( Round( B * 255 ), true )

		RefreshColour()
	end

	local function RefreshHSV()
		Hue, Saturation, Value = SGUI.RGBToHSV( R, G, B )

		Tree.HueSlider:SetValue( Hue, true )
		Tree.SaturationValuePicker:SetSaturation( Saturation )
		Tree.SaturationValuePicker:SetValue( Value )

		RefreshColour()
	end

	function Tree.SaturationValuePicker:OnChanged( NewSaturation, NewValue )
		Saturation = NewSaturation
		Value = NewValue
		RefreshRGB()
	end
	function Tree.SaturationValuePicker.OnDraggingCursor( Picker, NewSaturation, NewValue )
		self.ColourPreview:SetColour( Colour( SGUI.HSVToRGB( Hue, NewSaturation, NewValue ) ) )
	end

	local function UpdatePreview( NewColour )
		local H, S, V = SGUI.RGBToHSV( NewColour.r, NewColour.g, NewColour.b )
		Tree.SaturationValuePicker:SetBackgroundColour( Colour( SGUI.HSVToRGB( H, 1, 1 ) ) )
		self.ColourPreview:SetColour( NewColour )
	end

	function Tree.HueSlider:OnSlide( NewHue )
		R, G, B = SGUI.HSVToRGB( NewHue, Saturation, Value )
		UpdatePreview( Colour( R, G, B ) )
	end

	function Tree.HueSlider:OnValueChanged( Value )
		Hue = Value
		RefreshRGB()
	end

	function Tree.RedSlider:OnValueChanged( NewRed )
		R = NewRed / 255
		RefreshHSV()
	end
	function Tree.RedSlider:OnSlide( NewRed )
		UpdatePreview( Colour( NewRed / 255, G, B ) )
	end

	function Tree.GreenSlider:OnValueChanged( NewGreen )
		G = NewGreen / 255
		RefreshHSV()
	end
	function Tree.GreenSlider:OnSlide( NewGreen )
		UpdatePreview( Colour( R, NewGreen / 255, B ) )
	end

	function Tree.BlueSlider:OnValueChanged( NewBlue )
		B = NewBlue / 255
		RefreshHSV()
	end
	function Tree.BlueSlider:OnSlide( NewBlue )
		UpdatePreview( Colour( R, G, NewBlue / 255 ) )
	end

	Tree.Popup:InvalidateLayout( true )
end

function ColourPicker:DestroyPopup()
	if SGUI.IsValid( self.ColourPickerPopup ) then
		self.ColourPickerPopup:Destroy()
		self.ColourPickerPopup = nil
	end
end

function ColourPicker:OnEffectiveVisibilityChanged( IsEffectivelyVisible, UpdatedControl )
	if not IsEffectivelyVisible then
		self:DestroyPopup()
	end
end

function ColourPicker:Cleanup()
	self:DestroyPopup()
	return self.BaseClass.Cleanup( self )
end

SGUI:AddMixin( ColourPicker, "Clickable" )
SGUI:Register( "ColourPicker", ColourPicker )
