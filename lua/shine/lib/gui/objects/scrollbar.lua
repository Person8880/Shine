--[[
	Basic scrollbar.
]]

local SGUI = Shine.GUI

local Scrollbar = {}

local Clamp = math.Clamp
local Vector = Vector

function Scrollbar:Initialise()
	self.BaseClass.Initialise( self )

	local Manager = GetGUIManager()

	local Background = Manager:CreateGraphicItem()

	self.Background = Background

	local Bar = Manager:CreateGraphicItem()
	Bar:SetAnchor( GUIItem.Left, GUIItem.Top )

	Background:AddChild( Bar )

	local Scheme = SGUI:GetSkin()

	Background:SetColor( Scheme.ScrollbarBackground )
	Bar:SetColor( Scheme.Scrollbar )

	self.Bar = Bar

	self.BarPos = Vector( 0, 0, 0 )

	self.Pos = 0
	self.ScrollSize = 1
end

function Scrollbar:SetSize( Size )
	self.Size = Size

	if self.ScrollSizeVec then
		self.ScrollSizeVec.y = Size.y * self.ScrollSize
	else
		self.ScrollSizeVec = Vector( Size.x, Size.y * self.ScrollSize, 0 )
	end

	self.Background:SetSize( Size )
	self.Bar:SetSize( self.ScrollSizeVec )
end

function Scrollbar:SetScrollSize( Size )
	self.ScrollSize = Size

	if self.ScrollSizeVec then
		self.ScrollSizeVec.y = self.Size.y * Size
	else
		self.ScrollSizeVec = Vector( self.Size.x, self.Size.y * Size, 0 )
	end

	self.Bar:SetSize( self.ScrollSizeVec )
end

--[[
	Sets how far down the scroll bar is.
]]
function Scrollbar:SetScroll( Scroll, Smoothed )
	local Diff = self.Size.y - self.ScrollSizeVec.y

	Scroll = Clamp( Scroll, 0, Diff )

	self.Pos = Scroll

	self.BarPos.y = Scroll

	self.Bar:SetPosition( self.BarPos )

	if self.Parent and self.Parent.OnScrollChange then
		self.Parent:OnScrollChange( Scroll, Diff, Smoothed )
	end
end

function Scrollbar:GetDiffSize()
	return self.Size.y - self.ScrollSizeVec.y
end

function Scrollbar:ScrollToBottom( Smoothed )
	local Diff = self.Size.y - self.ScrollSizeVec.y

	self.Pos = Diff

	self.BarPos.y = Diff

	self.Bar:SetPosition( self.BarPos )

	if self.Parent and self.Parent.OnScrollChange then
		self.Parent:OnScrollChange( Diff, Diff, Smoothed )
	end
end

local GetCursorPos

function Scrollbar:OnMouseDown( Key, DoubleClick )
	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Bar ) then return end

	self.Scrolling = true

	GetCursorPos = GetCursorPos or Client.GetCursorPosScreen

	local X, Y = GetCursorPos()
	
	self.Scrolling = true

	self.StartingPos = self.Pos
	self.StartingY = Y
end

function Scrollbar:OnMouseWheel( Down )
	local Parent = self.Parent

	if self:MouseIn( self.Background ) or Parent:MouseIn( Parent.Background ) then
		self:SetScroll( self.Pos + ( Down and -32 or 32 ), true )
	end
end

function Scrollbar:OnMouseUp( Key )
	if Key ~= InputKey.MouseButton0 then return end
	self.Scrolling = false
end

function Scrollbar:OnMouseMove( Down )
	if not Down then return end
	if not self.Scrolling then return end
	
	local X, Y = GetCursorPos()

	local Diff = Y - self.StartingY

	self:SetScroll( self.StartingPos + Diff, true )
end

function Scrollbar:Cleanup()
	if self.Parent then return end
	
	if self.Background then
		GUI.DestroyItem( self.Background )
	end
end

SGUI:Register( "Scrollbar", Scrollbar )
