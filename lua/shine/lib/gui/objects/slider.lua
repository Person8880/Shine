--[[
	Number slider control.
]]

local SGUI = Shine.GUI

local Clamp = math.Clamp
local Round = math.Round
local Max = math.max
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

local Clear = Colour( 0, 0, 0, 0 )

local IsType = Shine.IsType

SGUI.AddProperty( Slider, "Decimals" )

SGUI.AddBoundProperty( Slider, "Font", "Label" )
SGUI.AddBoundProperty( Slider, "TextColour", "Label:SetColour" )
SGUI.AddBoundProperty( Slider, "TextScale", "Label" )
SGUI.AddBoundProperty( Slider, "HandleColour", "Handle:SetColor" )
SGUI.AddBoundProperty( Slider, "LineColour", "Line:SetColor" )
SGUI.AddBoundProperty( Slider, "DarkLineColour", "DarkLine:SetColor" )

function Slider:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	Background:SetSize( DefaultSize )
	Background:SetColor( Clear )

	self.Background = Background

	local Line = self:MakeGUIItem()
	Line:SetAnchor( GUIItem.Left, GUIItem.Center )
	Line:SetSize( DefaultLineSize )
	Line:SetPosition( LinePos )

	Background:AddChild( Line )

	self.Line = Line

	local UnfilledLine = self:MakeGUIItem()
	UnfilledLine:SetAnchor( GUIItem.Left, GUIItem.Center )
	UnfilledLine:SetSize( DefaultUnfilledLineSize )
	UnfilledLine:SetPosition( UnfilledLinePos )

	Background:AddChild( UnfilledLine )

	self.DarkLine = UnfilledLine

	local Handle = self:MakeGUIItem()
	Handle:SetAnchor( GUIItem.Left, GUIItem.Top )
	Handle:SetSize( DefaultHandleSize )

	Background:AddChild( Handle )

	self.Handle = Handle

	local Label = SGUI:Create( "Label", self )
	Label:SetIsSchemed( false )
	Label:SetAnchor( "CentreRight" )
	Label:SetTextAlignmentY( GUIItem.Align_Center )
	Label:SetPos( Padding )

	function Label.DoClick()
		Label:SetIsVisible( false )

		self.IgnoreStencilWarnings = true

		local TextEntry = SGUI:Create( "TextEntry", self )
		self.TextEntry = TextEntry

		local TextH = Label:GetTextHeight( "!" )

		TextEntry:SetStyleName( "SliderTextBox" )
		TextEntry.Padding = 0
		TextEntry.TextOffset = 0
		TextEntry:SetAnchor( "CentreRight" )
		TextEntry:SetPos( Vector2( Label:GetPos().x, -TextH * 0.5 ) )
		if self.Stencilled then
			TextEntry:DisableStencil()
		end

		local MaxCharW = 0
		for i = 0, 9 do
			MaxCharW = Max( MaxCharW, Label:GetTextWidth( tostring( i ) ) )
		end

		local MaxNumChars = #tostring( self.Max )
		if self.Decimals > 0 then
			MaxNumChars = MaxNumChars + self.Decimals + 1
		end

		TextEntry:SetSize( Vector2( MaxCharW * MaxNumChars, TextH ) )
		TextEntry:SetFontScale( Label:GetFont(), Label:GetTextScale() )
		TextEntry:SetText( tostring( self.Value ) )

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

		function TextEntry.OnEscape()
			TextEntry:Destroy()
			self.TextEntry = nil

			if SGUI.IsValid( Label ) then
				Label:SetIsVisible( true )
			end

			return true
		end
		TextEntry.OnLoseFocus = TextEntry.OnEscape

		-- Pass along the click to the text entry so it moves the caret.
		TextEntry:OnMouseDown( InputKey.MouseButton0, false )
		TextEntry:OnMouseUp( InputKey.MouseButton0 )
	end

	self.Label = Label
	self.Width = DefaultSize.x

	self.Fraction = 0
	self.Min = 0
	self.Max = 100
	self.Range = 100
	self.Value = 0
	self.Decimals = 0
	self.LineHeightMultiplier = 0.25

	self.HandleSize = Vector2( 10, 32 )
	self.HandlePos = Vector2( 0, 0 )
	self.LineSize = Vector2( 250, 5 )
	self.DarkLineSize = Vector2( 0, 5 )
	self.DarkLinePos = Vector2( 250, -2.5 )
end

function Slider:SetupStencil()
	self.BaseClass.SetupStencil( self )

	self.Handle:SetInheritsParentStencilSettings( true )
	self.Line:SetInheritsParentStencilSettings( true )
	self.DarkLine:SetInheritsParentStencilSettings( true )
	self.Label.Label:SetInheritsParentStencilSettings( true )
end

function Slider:SizeLines()
	if not self.Width or not self.Height then return end

	local LineWidth = self.Width * self.Fraction
	self.LineSize.x = LineWidth
	self.LineSize.y = self.Height * self.LineHeightMultiplier
	self.Line:SetSize( self.LineSize )

	local CurrentLinePos = Vector2( 0, -self.LineSize.y * 0.5 )
	self.Line:SetPosition( CurrentLinePos )

	self.DarkLinePos.x = LineWidth
	self.DarkLinePos.y = CurrentLinePos.y
	self.DarkLine:SetPosition( self.DarkLinePos )

	self.DarkLineSize.x = self.Width * ( 1 - self.Fraction )
	self.DarkLineSize.y = self.LineSize.y
	self.DarkLine:SetSize( self.DarkLineSize )

	self.HandleSize.y = self.Height
	self.Handle:SetSize( self.HandleSize )
end

function Slider:SetLineHeightMultiplier( Multiplier )
	self.LineHeightMultiplier = Multiplier
	self:SizeLines()
end

function Slider:SetHandleWidth( Width )
	self.HandleSize.x = Width
	self.Handle:SetSize( self.HandleSize )
end

local function RefreshSizes( self )
	self.Fraction = Clamp( ( self.Value - self.Min ) / self.Range, 0, 1 )
	self.HandlePos.x = self.Width * self.Fraction

	self.Handle:SetPosition( self.HandlePos )
	self.Label:SetText( tostring( self.Value ) )
	self:SizeLines()
end

function Slider:SetSize( Size )
	self.BaseClass.SetSize( self, Size )

	self.Height = Size.y
	self.Width = Size.x

	RefreshSizes( self )
end

function Slider:SetPadding( Value )
	self.Label:SetPos( Vector2( Value, 0 ) )
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

	if self:CallOnChildren( "PlayerKeyPress", Key, Down ) then
		return true
	end

	if not self:MouseIn( self.Background ) then return end

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

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )
	if Result ~= nil then
		return Result, Child
	end

	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Handle, 1.25 ) then
		if self:MouseIn( self.Background ) then
			self.ClickingLine = true

			return true, self
		end

		return
	end

	local X, Y = GetCursorPos()

	self.Dragging = true

	self.DragStart = X
	self.StartingPos = self.Handle:GetPosition()

	self.CurPos = Vector2( self.StartingPos.x, 0 )

	return true, self
end

function Slider:OnMouseUp( Key )
	if Key ~= InputKey.MouseButton0 then return end

	if self.ClickingLine then
		self.ClickingLine = nil

		local In, X, Y = self:MouseIn( self.Background )
		if not In then return end

		local Fraction = X / self.Width
		self:SetFraction( Fraction, true )
	else
		self.Dragging = false
	end

	self:OnValueChanged( self:GetValue() )

	return true
end

function Slider:OnMouseMove( Down )
	self:CallOnChildren( "OnMouseMove", Down )

	if not Down then return end
	if not self.Dragging then return end

	local X, Y = GetCursorPos()

	local Diff = X - self.DragStart

	self.CurPos.x = Clamp( self.StartingPos.x + Diff, 0, self.Width )

	if self:SetFraction( self.CurPos.x / self.Width, true ) then
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

SGUI:Register( "Slider", Slider )
