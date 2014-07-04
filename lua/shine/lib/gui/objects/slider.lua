--[[
	Number slider control.
]]

local SGUI = Shine.GUI

local Clamp = math.Clamp
local Round = math.Round
local tonumber = tonumber
local tostring = tostring
local type = type

local Slider = {}

local DefaultHandleSize = Vector( 10, 32, 0 )
local DefaultLineSize = Vector( 250, 5, 0 )
local DefaultUnfilledLineSize = Vector( 0, 5, 0 )
local DefaultSize = Vector( 250, 32, 0 )
local Padding = Vector( 20, 0, 0 )

local LinePos = Vector( 0, -2.5, 0 )
local UnfilledLinePos = Vector( 250, -2.5, 0 )

local Clear = Colour( 0, 0, 0, 0 )

local IsType = Shine.IsType

function Slider:Initialise()
	self.BaseClass.Initialise( self )

	local Manager = GetGUIManager()

	local Background = Manager:CreateGraphicItem()
	Background:SetSize( DefaultSize )
	Background:SetColor( Clear )

	self.Background = Background

	local Line = Manager:CreateGraphicItem()
	Line:SetAnchor( GUIItem.Left, GUIItem.Center )
	Line:SetSize( DefaultLineSize )
	Line:SetPosition( LinePos )

	Background:AddChild( Line )

	self.Line = Line

	local UnfilledLine = Manager:CreateGraphicItem()
	UnfilledLine:SetAnchor( GUIItem.Left, GUIItem.Center )
	UnfilledLine:SetSize( DefaultUnfilledLineSize )
	UnfilledLine:SetPosition( UnfilledLinePos )

	Background:AddChild( UnfilledLine )

	self.DarkLine = UnfilledLine

	local Handle = Manager:CreateGraphicItem()
	Handle:SetAnchor( GUIItem.Left, GUIItem.Top )
	Handle:SetSize( DefaultHandleSize )

	Background:AddChild( Handle )

	self.Handle = Handle

	local Label = SGUI:Create( "Label", self )
	Label:SetAnchor( GUIItem.Right, GUIItem.Center )
	Label:SetTextAlignmentY( GUIItem.Align_Center )
	Label:SetPos( Padding )

	self.Label = Label

	local Skin = SGUI:GetSkin()

	Handle:SetColor( Skin.SliderHandle )
	Line:SetColor( Skin.SliderFillLine )
	UnfilledLine:SetColor( Skin.SliderUnfilledLine )

	self.Width = DefaultSize.x

	self.Fraction = 0

	self.Min = 0
	self.Max = 100
	self.Range = 100

	self.Value = 0

	self.Decimals = 0

	self.HandleSize = Vector( 10, 32, 0 )
	self.HandlePos = Vector( 0, 0, 0 )
	self.LineSize = Vector( 250, 5, 0 )
	self.DarkLineSize = Vector( 0, 5, 0 )
	self.DarkLinePos = Vector( 250, -2.5, 0 )
end

function Slider:OnSchemeChange( Skin )
	self.Line:SetColor( Skin.SliderFillLine )
	self.DarkLine:SetColor( Skin.SliderUnfilledLine )
	self.Handle:SetColor( Skin.SliderHandle )
end

function Slider:SetupStencil()
	self.BaseClass.SetupStencil( self )

	self.Handle:SetInheritsParentStencilSettings( true )
	self.Line:SetInheritsParentStencilSettings( true )
	self.DarkLine:SetInheritsParentStencilSettings( true )
	self.Label.Text:SetInheritsParentStencilSettings( true )
end

function Slider:SizeLines()
	local LineWidth = self.Width * self.Fraction
	self.LineSize.x = LineWidth
	self.Line:SetSize( self.LineSize )

	self.DarkLinePos.x = LineWidth
	self.DarkLine:SetPosition( self.DarkLinePos )

	self.DarkLineSize.x = self.Width * ( 1 - self.Fraction )
	self.DarkLine:SetSize( self.DarkLineSize )

	self.HandleSize.y = self.Height
	self.Handle:SetSize( self.HandleSize )
end

function Slider:SetSize( Size )
	self.BaseClass.SetSize( self, Size )

	self.Height = Size.y
	self.Width = Size.x

	self:SizeLines()
end

function Slider:SetFont( Name )
	self.Label:SetFont( Name )
end

function Slider:SetTextColour( Col )
	self.Label:SetColour( Col )
end

function Slider:SetTextScale( Scale )
	self.Label:SetTextScale( Scale )
end

function Slider:SetHandleColour( Col )
	self.Handle:SetColor( Col )
end

function Slider:SetLineColour( Col )
	self.Line:SetColor( Col )
end

function Slider:SetDarkLineColour( Col )
	self.DarkLine:SetColor( Col )
end

function Slider:SetPadding( Value )
	self.Label:SetPos( Vector( Value, 0, 0 ) )
end

--[[
	Sets the slider's position by value.
]]
function Slider:SetValue( Value )
	if not IsType( Value, "number" ) then return end
	
	self.Value = Clamp( Round( Value, self.Decimals ), self.Min, self.Max )

	self.Fraction = Clamp( ( Value - self.Min ) / self.Range, 0, 1 )
	self.HandlePos.x = self.Width * self.Fraction

	self.Handle:SetPosition( self.HandlePos )

	self.Label:SetText( tostring( self.Value ) )

	self:SizeLines()
end

--[[
	Sets the slider's position by fraction.
]]
function Slider:SetFraction( Fraction )
	self.Value = Clamp( Round( self.Min + ( Fraction * self.Range ), self.Decimals ), self.Min, self.Max )
	self.Fraction = Clamp( ( self.Value - self.Min ) / self.Range, 0, 1 )

	self.HandlePos.x = self.Width * self.Fraction

	self.Handle:SetPosition( self.HandlePos )

	self.Label:SetText( tostring( self.Value ) )

	self:SizeLines()
end

function Slider:GetValue()
	return self.Value
end

--[[
	Set this to enforce rounding of the value.
]]
function Slider:SetDecimals( Decimals )
	self.Decimals = Decimals
end

function Slider:GetDecimals()
	return self.Decimals
end

--[[
	Sets the bounds of the slider.
]]
function Slider:SetBounds( Min, Max )
	self.Min = Min
	self.Max = Max

	self.Range = Max - Min

	--Update our slider value to clamp it inside the new bounds if needed.
	self:SetValue( self.Value )
end

local GetCursorPos

function Slider:OnMouseDown( Key )
	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Handle, 1.25 ) then return end

	GetCursorPos = GetCursorPos or Client.GetCursorPosScreen

	local X, Y = GetCursorPos()

	self.Dragging = true

	self.DragStart = X
	self.StartingPos = self.Handle:GetPosition()

	self.CurPos = Vector( self.StartingPos.x, 0, 0 )

	return true, self
end

function Slider:OnMouseUp( Key )
	if Key ~= InputKey.MouseButton0 then return end

	self.Dragging = false

	if self.OnValueChanged then
		self:OnValueChanged( self:GetValue() )
	end

	return true
end

function Slider:OnMouseMove( Down )
	if not Down then return end
	if not self.Dragging then return end

	local X, Y = GetCursorPos()

	local Diff = X - self.DragStart

	self.CurPos.x = Clamp( self.StartingPos.x + Diff, 0, self.Width )

	self:SetFraction( self.CurPos.x / self.Width )
end

SGUI:Register( "Slider", Slider )
