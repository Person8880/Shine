--[[
	Basic scrollbar.
]]

local SGUI = Shine.GUI

local Scrollbar = {}

local Clamp = math.Clamp
local Max = math.max
local Vector = Vector

SGUI.AddBoundProperty( Scrollbar, "BackgroundColour", "Background:SetColor" )
SGUI.AddBoundProperty( Scrollbar, "InactiveCol", "Bar:SetColor" )
SGUI.AddProperty( Scrollbar, "ActiveCol" )

function Scrollbar:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	self.Background = Background

	local Bar = self:MakeGUIItem()
	Background:AddChild( Bar )

	self.Bar = Bar
	self.BarPos = Vector( 0, 0, 0 )
	self.ScrollPosition = 0
	self.ScrollSize = 1

	self.Horizontal = false
	self.ScrollAxis = "y"
	self.ScrollEvent = "OnScrollChange"
end

function Scrollbar:SetHorizontal( Horizontal )
	self.Horizontal = Horizontal
	self.ScrollAxis = Horizontal and "x" or "y"
	self.ScrollEvent = Horizontal and "OnScrollChangeX" or "OnScrollChange"
end

function Scrollbar:FadeIn( Duration, Callback, EaseFunc )
	self:AlphaTo( self.Background, nil, self:GetNormalAlpha( self.Background ), 0, Duration, Callback, EaseFunc )
	self:AlphaTo( self.Bar, nil, self:GetNormalAlpha( self.Bar ), 0, Duration, nil, EaseFunc )
end

function Scrollbar:FadeOut( Duration, Callback, EaseFunc )
	self:AlphaTo( self.Background, nil, 0, 0, Duration, Callback, EaseFunc )
	self:AlphaTo( self.Bar, nil, 0, 0, Duration, nil, EaseFunc )
end

function Scrollbar:StopFading()
	if not self:GetEasing( "Alpha", self.Bar ) then return end

	self:StopAlpha( self.Background )
	self:StopAlpha( self.Bar )

	self:SetAlpha( self:GetNormalAlpha( self.Background ) )

	local BarColour = self.Bar:GetColor()
	BarColour.a = self:GetNormalAlpha( self.Bar )
	self.Bar:SetColor( BarColour )
end

function Scrollbar:SetHidden( Hidden )
	if Hidden then
		self:HideAndDisableInput()
	else
		self:ShowAndEnableInput()
	end
end

function Scrollbar:HideAndDisableInput()
	self.Background:SetIsVisible( false )
	self.Disabled = true
end

function Scrollbar:ShowAndEnableInput()
	self.Disabled = false
	self.Background:SetIsVisible( true )
end

function Scrollbar:GetNormalAlpha( Element )
	if Element == self.Background then
		local Colour = self:GetStyleValue( "BackgroundColour" )
		return Colour and Colour.a or 1
	end

	local Colour = self:GetStyleValue( "InactiveCol" )
	return Colour and Colour.a or 1
end

function Scrollbar:SetSize( Size )
	self.Size = Size
	self.BaseClass.SetSize( self, Size )

	self:UpdateScrollBarSize()
end

function Scrollbar:UpdateScrollBarSize()
	local Size = self.Size
	if not self.ScrollSizeVec then
		self.ScrollSizeVec = Vector2( Size.x, Size.y )
	end

	self.ScrollSizeVec[ self.ScrollAxis ] = Size[ self.ScrollAxis ] * self.ScrollSize
	self.Bar:SetSize( self.ScrollSizeVec )
end

function Scrollbar:SetScrollSize( Size )
	local OldPos = self.ScrollPosition or 0
	local OldDiff = self:GetDiffSize()

	self.ScrollSize = Size
	self:UpdateScrollBarSize()

	local NewDiff = self:GetDiffSize()
	-- If the scrolling size has shrunk, we may need to move up.
	if NewDiff < OldDiff then
		self:SetScroll( OldPos )
	end
end

--[[
	Sets how far down the scroll bar is.
]]
function Scrollbar:SetScroll( Scroll, Smoothed )
	local Diff = self:GetDiffSize()

	Scroll = Clamp( Scroll, 0, Diff )

	self.ScrollPosition = Scroll
	self.BarPos[ self.ScrollAxis ] = Scroll
	self.Bar:SetPosition( self.BarPos )

	if self.Parent and self.Parent[ self.ScrollEvent ] then
		self.Parent[ self.ScrollEvent ]( self.Parent, Scroll, Diff, Smoothed )
	end
end

function Scrollbar:GetDiffSize()
	return Max( self.Size[ self.ScrollAxis ] - self.ScrollSizeVec[ self.ScrollAxis ], 0 )
end

function Scrollbar:ScrollToBottom( Smoothed )
	self:SetScroll( self:GetDiffSize() )
end

local GetCursorPos = SGUI.GetCursorPos

function Scrollbar:OnMouseDown( Key, DoubleClick )
	if self.Disabled then return end
	if not self:GetIsVisible() then return end
	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Bar ) then return end

	self.Scrolling = true

	local X, Y = GetCursorPos()

	self.Scrolling = true

	self.StartingScrollPosition = self.ScrollPosition
	self.StartingX = X
	self.StartingY = Y

	self:StopFading()
	self.Bar:SetColor( self.ActiveCol )

	return true, self
end

SGUI.AddProperty( Scrollbar, "MouseWheelScroll" )

function Scrollbar:OnMouseWheel( Down )
	local Parent = self.Parent

	if Parent:HasMouseEntered() or self:MouseIn( self.Background ) then
		local ScrollMagnitude = self.MouseWheelScroll or SGUI.LinearScale( 32 )

		self:SetScroll( self.ScrollPosition + ( Down and -ScrollMagnitude or ScrollMagnitude ) * self.ScrollSize, true )

		return true
	end
end

function Scrollbar:OnMouseUp( Key )
	if Key ~= InputKey.MouseButton0 then return end
	if not self.Scrolling then return end

	self.Scrolling = false
	self.Bar:SetColor( self.InactiveCol )

	return true
end

function Scrollbar:OnMouseMove( Down )
	if not Down then return end
	if not self.Scrolling then return end

	local X, Y = GetCursorPos()
	local Diff = self.Horizontal and ( X - self.StartingX ) or ( Y - self.StartingY )

	self:SetScroll( self.StartingScrollPosition + Diff, true )
end

SGUI:Register( "Scrollbar", Scrollbar )
