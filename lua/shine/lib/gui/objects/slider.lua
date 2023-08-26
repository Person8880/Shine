--[[
	Number slider control.
]]

local SGUI = Shine.GUI

local Abs = math.abs
local Clamp = math.Clamp
local Round = math.Round
local Max = math.max
local Min = math.min
local tostring = tostring
local type = type

local Slider = {}

local DefaultHandleSize = Vector2( 10, 32 )
local DefaultLineSize = Vector2( 250, 5 )
local DefaultUnfilledLineSize = Vector2( 0, 5 )
local DefaultSize = Vector2( 250, 32 )
local Padding = Vector2( 20, 0 )

local LinePos = Vector2( 0, -2.5 )
local UnfilledLinePos = Vector2( 250, -2.5 )

local IsType = Shine.IsType

SGUI.AddProperty( Slider, "Decimals" )

SGUI.AddBoundProperty( Slider, "Font", "Label" )
SGUI.AddBoundProperty( Slider, "TextColour", "Label:SetColour" )
SGUI.AddBoundProperty( Slider, "TextIsVisible", "Label:SetIsVisible" )
SGUI.AddBoundProperty( Slider, "TextScale", "Label" )
SGUI.AddBoundProperty( Slider, "TextShadow", "Label:SetShadow" )

SGUI.AddBoundColourProperty( Slider, "HandleColour", "Handle:SetColor" )
SGUI.AddBoundColourProperty( Slider, "LineColour", "Line:SetColor" )
SGUI.AddBoundProperty( Slider, "LineTexture", "Line:SetTexture" )
SGUI.AddBoundColourProperty( Slider, "DarkLineColour", "DarkLine:SetColor" )

local function OnTargetAlphaChanged( self, TargetAlpha )
	if self.HandleColour then
		self.Handle:SetColor( self:ApplyAlphaCompensationToChildItemColour( self.HandleColour, TargetAlpha ) )
	end

	if self.LineColour then
		self.Line:SetColor( self:ApplyAlphaCompensationToChildItemColour( self.LineColour, TargetAlpha ) )
	end

	if self.DarkLineColour then
		self.DarkLine:SetColor( self:ApplyAlphaCompensationToChildItemColour( self.DarkLineColour, TargetAlpha ) )
	end
end

function Slider:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	Background:SetSize( DefaultSize )
	Background:SetShader( SGUI.Shaders.Invisible )

	self.Background = Background

	local Line = self:MakeGUIItem()
	Line:SetAnchor( 0, 0.5 )
	Line:SetSize( DefaultLineSize )
	Line:SetPosition( LinePos )

	Background:AddChild( Line )

	self.Line = Line

	local UnfilledLine = self:MakeGUIItem()
	UnfilledLine:SetAnchor( 0, 0.5 )
	UnfilledLine:SetSize( DefaultUnfilledLineSize )
	UnfilledLine:SetPosition( UnfilledLinePos )

	Background:AddChild( UnfilledLine )

	self.DarkLine = UnfilledLine

	local Handle = self:MakeGUIItem()
	Handle:SetSize( DefaultHandleSize )

	Background:AddChild( Handle )

	self.Handle = Handle

	local Label = SGUI:Create( "Label", self )
	Label:SetIsSchemed( false )
	Label:SetAnchor( "CentreRight" )
	Label:SetTextAlignmentY( GUIItem.Align_Center )
	Label:SetPos( Padding )

	function Label.DoClick()
		if not self:IsEnabled() then return end

		Label:SetIsVisible( false )

		self.IgnoreStencilWarnings = true

		local TextEntry = SGUI:Create( "TextEntry", self )
		self.TextEntry = TextEntry

		TextEntry:SetStyleName( "SliderTextBox" )
		TextEntry:SetTextPadding( 0 )
		TextEntry:SetAnchor( self.Vertical and "TopMiddle" or "CentreRight" )

		local LabelPos = Label:GetPos()
		local TextEntryPos = Vector2( 0, 0 )
		local LabelSize = self:GetLabelSize()
		TextEntryPos[ self.MainAxis ] = LabelPos[ self.MainAxis ]
		TextEntryPos[ self.CrossAxis ] = -LabelSize[ self.CrossAxis ] * 0.5
		TextEntry:SetPos( TextEntryPos )
		TextEntry:SetSize( LabelSize )
		TextEntry:SetFontScale( Label:GetFont(), Label:GetTextScale() )
		TextEntry:SetText( tostring( self.Value ) )
		TextEntry:SetTextShadow( Label:GetShadow() )

		local Pattern = "^%d+$"
		if self.Decimals > 0 then
			Pattern = "^%d+%.?%d*$"
		end

		local StringMatch = string.match
		local StringUTF8Sub = string.UTF8Sub
		function TextEntry:ShouldAllowChar( Char )
			local Text = self:GetText()
			local Before = StringUTF8Sub( Text, 1, self.Column )
			local After = StringUTF8Sub( Text, self.Column + 1 )

			local NewText = Before..Char..After
			if not StringMatch( NewText, Pattern ) then
				return false
			end

			return true
		end

		function TextEntry.OnEnter()
			local NewValue = tonumber( TextEntry:GetText() )
			if NewValue then
				self:SetValue( NewValue )
			end
			TextEntry:OnEscape()
		end

		local Listener
		Listener = self:AddPropertyChangeListener( "Enabled", function( Slider, Enabled )
			if not Enabled then
				TextEntry.OnEscape()
			end
		end )

		function TextEntry.OnEscape()
			self:RemovePropertyChangeListener( "Enabled", Listener )

			TextEntry:Destroy()
			self.TextEntry = nil

			if SGUI.IsValid( Label ) then
				Label:SetIsVisible( true )
			end

			return true
		end
		TextEntry.OnLoseFocus = TextEntry.OnEscape

		TextEntry:RequestFocus()

		-- Pass along the click to the text entry so it moves the caret.
		TextEntry:OnMouseDown( InputKey.MouseButton0, false )
		TextEntry:OnMouseUp( InputKey.MouseButton0 )

		TextEntry:InvalidateLayout( true )
	end

	self.Label = Label
	self.Width = DefaultSize.x

	self.Fraction = 0
	self.Min = 0
	self.Max = 100
	self.Range = 100
	self.Value = 0
	self.Decimals = 0
	self.LineThicknessMultiplier = 0.25

	self.HandleSize = Vector2( 10, 32 )
	self.HandlePos = Vector2( 0, 0 )
	self.HandleThickness = 10

	self.LineSize = Vector2( 250, 5 )
	self.DarkLineSize = Vector2( 0, 5 )
	self.DarkLinePos = Vector2( 250, -2.5 )

	self.Vertical = false
	self.MainAxis = "x"
	self.CrossAxis = "y"
end

local function RefreshSizes( self )
	self.Fraction = Clamp( ( self.Value - self.Min ) / self.Range, 0, 1 )

	local MainAxis = self.MainAxis
	local MainSize = self.Vertical and self.Height or self.Width
	-- Vertical needs to flip the position fraction as the top of the slider represents the max value.
	local PositionFraction = self.Vertical and ( 1 - self.Fraction ) or self.Fraction

	self.HandlePos[ MainAxis ] = ( MainSize - self.HandleSize[ MainAxis ] ) * PositionFraction
	self.Handle:SetPosition( self.HandlePos )

	self.Label:SetText( tostring( self.Value ) )

	self:SizeLines()
end

local function OnTextSizeChanged( Label )
	-- For vertical sliders, the label's position depends on its text height.
	Label.Parent:SetPadding( Label.Parent:GetLabelPadding() )
end

function Slider:SetVertical( Vertical )
	if Vertical == self.Vertical then return false end

	self.Vertical = Vertical
	self.MainAxis = Vertical and "y" or "x"
	self.CrossAxis = Vertical and "x" or "y"

	local LineAnchorX = Vertical and 0.5 or 0
	local LineAnchorY = Vertical and 0 or 0.5

	self.Line:SetAnchor( LineAnchorX, LineAnchorY )
	self.DarkLine:SetAnchor( LineAnchorX, LineAnchorY )

	-- Update the label's padding and alignment. Vertical mode has the label above the slider, horizontal has it to the
	-- right.
	self:SetPadding( self:GetLabelPadding() )
	self.Label:SetAnchor( Vertical and "TopMiddle" or "CentreRight" )
	self.Label:SetTextAlignmentX( Vertical and GUIItem.Align_Center or GUIItem.Align_Min )
	self.Label:SetTextAlignmentY( Vertical and GUIItem.Align_Min or GUIItem.Align_Center )

	if Vertical then
		self.Label:AddPropertyChangeListener( "Font", OnTextSizeChanged )
		self.Label:AddPropertyChangeListener( "TextScale", OnTextSizeChanged )
	else
		self.Label:RemovePropertyChangeListener( "Font", OnTextSizeChanged )
		self.Label:RemovePropertyChangeListener( "TextScale", OnTextSizeChanged )
	end

	RefreshSizes( self )

	return true
end

function Slider:SetupStencil()
	self.BaseClass.SetupStencil( self )

	self.Handle:SetInheritsParentStencilSettings( true )
	self.Line:SetInheritsParentStencilSettings( true )
	self.DarkLine:SetInheritsParentStencilSettings( true )
	self.Label.Label:SetInheritsParentStencilSettings( true )
end

function Slider:OnAutoInheritAlphaChanged( IsAutoInherit )
	if IsAutoInherit then
		OnTargetAlphaChanged( self, self:GetTargetAlpha() )

		self:AddPropertyChangeListener( "TargetAlpha", OnTargetAlphaChanged )
	else
		if self.HandleColour then
			self.Handle:SetColor( self.HandleColour )
		end
		if self.LineColour then
			self.Line:SetColor( self.LineColour )
		end
		if self.DarkLineColour then
			self.DarkLine:SetColor( self.DarkLineColour )
		end
		self:RemovePropertyChangeListener( "TargetAlpha", OnTargetAlphaChanged )
	end
end

function Slider:SizeLines()
	if not self.Width or not self.Height then return end

	local MainAxis = self.MainAxis
	local CrossAxis = self.CrossAxis
	local MainSize = self.Vertical and self.Height or self.Width
	local CrossSize = self.Vertical and self.Width or self.Height

	self.LineSize[ CrossAxis ] = CrossSize * self.LineThicknessMultiplier

	local CurrentLinePos = Vector2( 0, 0 )
	CurrentLinePos[ CrossAxis ] = -self.LineSize[ CrossAxis ] * 0.5
	self.Line:SetPosition( CurrentLinePos )

	self.HandleSize[ MainAxis ] = self.HandleThickness
	self.HandleSize[ CrossAxis ] = CrossSize
	self.Handle:SetSize( self.HandleSize )

	local MaxLineSize = MainSize - self.HandleSize[ MainAxis ]
	local LineSize = MaxLineSize
	if self.DarkLine:GetIsVisible() then
		LineSize = LineSize * self.Fraction

		self.DarkLinePos[ MainAxis ] = Min( LineSize + self.HandleSize[ MainAxis ], MainSize )
		self.DarkLinePos[ CrossAxis ] = CurrentLinePos[ CrossAxis ]
		self.DarkLine:SetPosition( self.DarkLinePos )

		self.DarkLineSize[ MainAxis ] = MainSize - self.DarkLinePos[ MainAxis ]
		self.DarkLineSize[ CrossAxis ] = self.LineSize[ CrossAxis ]
		self.DarkLine:SetSize( self.DarkLineSize )
	else
		LineSize = MainSize
	end

	self.LineSize[ MainAxis ] = LineSize
	self.Line:SetSize( self.LineSize )
end

function Slider:SetLineThicknessMultiplier( Multiplier )
	if self.LineThicknessMultiplier == Multiplier then return false end

	self.LineThicknessMultiplier = Multiplier
	self:SizeLines()

	return true
end
-- Deprecated alias for backwards compatibility.
Slider.SetLineHeightMultiplier = Slider.SetLineThicknessMultiplier

function Slider:SetDarkLineVisible( DarkLineVisible )
	DarkLineVisible = not not DarkLineVisible

	if self.DarkLine:GetIsVisible() == DarkLineVisible then return false end

	self.DarkLine:SetIsVisible( DarkLineVisible )
	self:SizeLines()

	return true
end

function Slider:SetHandleThickness( Thickness )
	if self.HandleThickness == Thickness then return false end

	self.HandleThickness = Thickness
	self.HandleSize[ self.MainAxis ] = Thickness
	self.Handle:SetSize( self.HandleSize )

	return true
end
-- Deprecated alias for backwards compatibility.
Slider.SetHandleWidth = Slider.SetHandleThickness

function Slider:SetSize( Size )
	if not self.BaseClass.SetSize( self, Size ) then return false end

	self.Height = Size.y
	self.Width = Size.x

	RefreshSizes( self )

	return true
end

function Slider:SetPadding( Value )
	local Pos = Vector2( 0, 0 )
	local Offset
	if self.Vertical then
		Offset = -Value - self.Label:GetTextHeight( "1" )
	else
		Offset = Value
	end
	Pos[ self.MainAxis ] = Offset
	self.Label:SetPos( Pos )
end

function Slider:GetLabelPadding()
	return Abs( self.Label:GetPos()[ self.MainAxis ] )
end

function Slider:GetLabelSize()
	local MaxCharW = 0
	for i = 0, 9 do
		MaxCharW = Max( MaxCharW, self.Label:GetTextWidth( tostring( i ) ) )
	end

	local MaxNumChars = #tostring( self.Max )
	if self.Decimals > 0 then
		MaxNumChars = MaxNumChars + self.Decimals + 1
	end

	return Vector2( MaxCharW * MaxNumChars, self.Label:GetTextHeight( "1" ) )
end

--[[
	Sets the slider's position by value.
]]
function Slider:SetValue( Value, SuppressChangeEvent )
	if not IsType( Value, "number" ) then return end

	local OldValue = self.Value

	self.Value = Clamp( Round( Value, self.Decimals ), self.Min, self.Max )

	-- Check after clamping/rounding in case the rules have changed.
	if OldValue == self.Value then return end

	RefreshSizes( self )

	if not SuppressChangeEvent then
		self:OnValueChanged( self.Value )
	end
	self:OnPropertyChanged( "Value", Value )

	return true
end

--[[
	Sets the slider's position by fraction.
]]
function Slider:SetFraction( Fraction, SuppressChangeEvent )
	return self:SetValue( self.Min + ( Fraction * self.Range ), SuppressChangeEvent )
end

function Slider:ChangeValue( Value )
	if self:SetValue( Value ) then
		self:OnSlide( self.Value )
	end
end

function Slider:GetValue()
	return self.Value
end

--[[
	Sets the bounds of the slider.
]]
function Slider:SetBounds( Min, Max )
	self.Min = Min
	self.Max = Max

	self.Range = Max - Min

	-- Update our slider value to clamp it inside the new bounds if needed.
	self:SetValue( self.Value )
end

function Slider:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end
	if not self:IsEnabled() then return end

	if self:CallOnChildren( "PlayerKeyPress", Key, Down ) then
		return true
	end

	if not Down or not self:HasMouseEntered() then return end

	if Key == InputKey.Left or Key == InputKey.Down then
		self:ChangeValue( self:GetValue() - 1 * 10 ^ -self.Decimals )
		return true
	end

	if Key == InputKey.Right or Key == InputKey.Up then
		self:ChangeValue( self:GetValue() + 1 * 10 ^ -self.Decimals )
		return true
	end
end

local GetCursorPos = SGUI.GetCursorPos

function Slider:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end
	if not self:IsEnabled() then return end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )
	if Result ~= nil then
		return Result, Child
	end

	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Handle, 1.25 ) then
		if self:HasMouseEntered() then
			self.ClickingLine = true

			return true, self
		end

		return
	end

	local X, Y = GetCursorPos()

	self.Dragging = true

	self.DragStart = self.Vertical and Y or X
	self.StartingPos = self.Handle:GetPosition()
	self.CurPos = self.StartingPos[ self.MainAxis ]

	return true, self
end

function Slider:OnMouseUp( Key )
	if Key ~= InputKey.MouseButton0 then return end

	if self.ClickingLine then
		self.ClickingLine = nil

		local In, X, Y = self:MouseInCached()
		if not In then return end

		local Fraction
		if self.Vertical then
			Fraction = ( self.Height - Y ) / self.Height
		else
			Fraction = X / self.Width
		end
		self:SetFraction( Fraction, true )
	else
		self.Dragging = false
	end

	self:OnValueChanged( self:GetValue() )

	return true
end

function Slider:OnMouseMove( Down )
	self.BaseClass.OnMouseMove( self, Down )

	if SGUI.IsValid( self.TextEntry ) then
		self.TextEntry:OnMouseMove( Down )
	end

	if not Down then return end
	if not self.Dragging then return end

	local X, Y = GetCursorPos()

	local Diff = ( self.Vertical and Y or X ) - self.DragStart
	local MainSize = self.Vertical and self.Height or self.Width
	local SizeWithoutHandle = MainSize - self.HandleSize[ self.MainAxis ]

	self.CurPos = Clamp( self.StartingPos[ self.MainAxis ] + Diff, 0, SizeWithoutHandle )

	local Fraction
	if self.Vertical then
		Fraction = ( SizeWithoutHandle - self.CurPos ) / SizeWithoutHandle
	else
		Fraction = self.CurPos / SizeWithoutHandle
	end

	if self:SetFraction( Fraction, true ) then
		self:OnSlide( self.Value )
	end
end

--[[
	Called when the slider has stopped being moved.
]]
function Slider:OnValueChanged( Value )

end

--[[
	Called as the slider is being moved.
]]
function Slider:OnSlide( Value )

end

SGUI:AddMixin( Slider, "EnableMixin" )
SGUI:Register( "Slider", Slider )
