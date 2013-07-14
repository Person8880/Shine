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
local DefaultSize = Vector( 250, 32, 0 )
local Padding = Vector( 20, 0, 0 )

local LinePos = Vector( 0, -2.5, 0 )

local Clear = Colour( 0, 0, 0, 0 )

local function isnumber( Num )
	return type( Num ) == "number"
end

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
	Line:SetColor( Skin.SliderLines )

	self.Width = DefaultSize.x

	self.Fraction = 0

	self.Min = 0
	self.Max = 100

	self.Value = 0

	self.Decimals = 0

	self.HandlePos = Vector( 0, 0, 0 )
end

function Slider:SetupStencil()
	self.BaseClass.SetupStencil( self )

	self.Handle:SetInheritsParentStencilSettings( true )
	self.Line:SetInheritsParentStencilSettings( true )
	self.Label.Text:SetInheritsParentStencilSettings( true )
end

function Slider:SetSize( Size )
	self.BaseClass.SetSize( self, Size )

	self.Width = Size.x

	self.Line:SetSize( Vector( Size.x, 5, 0 ) )
end

function Slider:SetFont( Name )
	self.Label:SetFont( Name )
end

function Slider:SetTextColour( Col )
	self.Label:SetColour( Col )
end

function Slider:SetHandleColour( Col )
	self.Handle:SetColor( Col )
end

function Slider:SetLineColour( Col )
	self.Line:SetColor( Col )
end

--[[
	Sets the slider's position by value.
]]
function Slider:SetValue( Value )
	if not isnumber( Value ) then return end
	
	self.Value = Clamp( Round( Value, self.Decimals ), self.Min, self.Max )

	self.Fraction = Clamp( Value / self.Max, 0, 1 )
	self.HandlePos.x = self.Width * self.Fraction

	self.Handle:SetPosition( self.HandlePos )

	self.Label:SetText( tostring( self.Value ) )
end

--[[
	Sets the slider's position by fraction.
]]
function Slider:SetFraction( Fraction )
	self.Value = Clamp( Round( Fraction * self.Max, self.Decimals ), self.Min, self.Max )
	self.Fraction = Clamp( self.Value / self.Max, 0, 1 )

	self.HandlePos.x = self.Width * self.Fraction

	self.Handle:SetPosition( self.HandlePos )

	self.Label:SetText( tostring( self.Value ) )
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
end

function Slider:OnMouseUp( Key )
	if Key ~= InputKey.MouseButton0 then return end

	self.Dragging = false

	if self.OnValueChanged then
		self:OnValueChanged( self:GetValue() )
	end
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
