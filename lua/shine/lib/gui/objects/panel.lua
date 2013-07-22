--[[
	Basic panel object.

	Provides a background but with all the SGUI functions available to it.
]]

local SGUI = Shine.GUI

local Panel = {}

local DefaultBuffer = 20
local ScrollPos = Vector( -20, 10, 0 )
local ZeroColour = Colour( 0, 0, 0, 0 )

function Panel:Initialise()
	self.BaseClass.Initialise( self )

	local Background = GetGUIManager():CreateGraphicItem()

	self.Background = Background

	--[[local Scheme = SGUI:GetSkin()

	Background:SetColor( Scheme.WindowBackground )]]
end

function Panel:SetScrollable()
	local Manager = GetGUIManager()

	local Stencil = Manager:CreateGraphicItem()
	Stencil:SetIsStencil( true )
	Stencil:SetInheritsParentStencilSettings( false )
	Stencil:SetClearsStencilBuffer( true )

	Stencil:SetSize( self.Background:GetSize() ) 

	self.Background:AddChild( Stencil )

	self.Stencil = Stencil

	local ScrollParent = Manager:CreateGraphicItem()
	ScrollParent:SetAnchor( GUIItem.Left, GUIItem.Top )
	ScrollParent:SetColor( ZeroColour ) 

	self.Background:AddChild( ScrollParent )

	self.ScrollParent = ScrollParent

	self.BufferAmount = self.BufferAmount or DefaultBuffer

	self.AllowSmoothScroll = true
end

function Panel:SetAllowSmoothScroll( Bool )
	self.AllowSmoothScroll = Bool and true or false
end

function Panel:Add( Class, Created )
	local Element = Created or SGUI:Create( Class )
	Element:SetParent( self, self.ScrollParent )

	if self.Stencil and Element.SetupStencil then
		Element:SetupStencil()
	end

	local Pan = self --CLANG!

	local OldSetPos = Element.SetPos
	function Element:SetPos( Pos )
		OldSetPos( self, Pos )
		
		if not Pan.ScrollParent then return end

		local Size = self:GetSize()
		local AnchorX, AnchorY = self:GetAnchor()

		if AnchorY == GUIItem.Top then
			local NewMaxHeight = Pos + Vector( 0, Size.y, 0 )

			if NewMaxHeight.y > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight.y + Pan.BufferAmount )
			end
		elseif AnchorY == GUIItem.Center then
			local NewMaxHeight = Pos + Vector( 0, Size.y * 0.5, 0 )

			if NewMaxHeight.y > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight.y + Pan.BufferAmount )
			end
		else
			if Pos.y > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight.y + Pan.BufferAmount )
			end
		end
	end

	local OldSetSize = Element.SetSize
	function Element:SetSize( Size )
		OldSetSize( self, Size )

		if not Pan.ScrollParent then return end

		local Pos = self:GetPos()
		
		local AnchorX, AnchorY = self:GetAnchor()

		if AnchorY == GUIItem.Top then
			local NewMaxHeight = Pos + Vector( 0, Size.y, 0 )

			if NewMaxHeight.y > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight.y + Pan.BufferAmount )
			end
		elseif AnchorY == GUIItem.Center then
			local NewMaxHeight = Pos + Vector( 0, Size.y * 0.5, 0 )

			if NewMaxHeight.y > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight.y + Pan.BufferAmount )
			end
		else
			if Pos.y > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight.y + Pan.BufferAmount )
			end
		end
	end

	return Element
end

function Panel:SetSize( Vec )
	self.BaseClass.SetSize( self, Vec )

	if not self.Stencil then return end
	
	self.Stencil:SetSize( Vec )

	if self.Scrollbar then
		self.Scrollbar:SetParent()
		self.Scrollbar:Remove()

		self.Scrollbar = nil

		self:SetMaxHeight( self.MaxHeight )
	end
end

function Panel:GetMaxHeight()
	return self.MaxHeight or self:GetSize().y
end

function Panel:SetIsVisible( Visible )
	self.BaseClass.SetIsVisible( self, Visible )

	local Children = self.Children

	if not Children then return end

	for Child in pairs( Children ) do
		Child:SetIsVisible( Visible )
	end
end

--[[
	Clears the panel of objects to be repopulated.
]]
function Panel:Clear()
	if self.Children then
		for Element in pairs( self.Children ) do
			if Element ~= self.Scrollbar then
				Element:SetParent()
				Element:Destroy()
			end
		end
	end

	if self.Scrollbar then
		self:SetMaxHeight( self:GetSize().y )
	end
end

function Panel:SetStickyScroll( Enable )
	self.StickyScroll = Enable and true or false
end

function Panel:SetScrollbarHeightOffset( Offset )
	self.ScrollbarHeightOffset = Offset
end

function Panel:SetMaxHeight( Height )
	self.MaxHeight = Height

	local MaxHeight = self:GetSize().y

	if not self.Scrollbar then
		local Scrollbar = SGUI:Create( "Scrollbar", self )
		Scrollbar:SetAnchor( GUIItem.Right, GUIItem.Top )
		Scrollbar:SetPos( self.ScrollPos or ScrollPos )
		Scrollbar:SetSize( Vector( 10, MaxHeight - ( self.ScrollbarHeightOffset or 20 ), 0 ) )
		Scrollbar:SetScrollSize( MaxHeight / Height )

		function self:OnScrollChange( Pos, MaxPos, Smoothed )
			local SetHeight = self:GetSize().y
			local MaxHeight = self.MaxHeight

			local Fraction = Pos / MaxPos

			local Diff = MaxHeight - SetHeight

			if self.ScrollParentPos then
				self.ScrollParentPos.y = -Diff * Fraction
			else
				self.ScrollParentPos = Vector( 0, -Diff * Fraction, 0 )
			end

			if Smoothed and self.AllowSmoothScroll then
				self:MoveTo( self.ScrollParentPos, 0, 0.2, math.EaseOut, 3, function( Panel )
					Panel.ScrollParent:SetPosition( self.ScrollParentPos )
				end, self.ScrollParent )
			else
				self.ScrollParent:SetPosition( self.ScrollParentPos )
			end
		end

		self.Scrollbar = Scrollbar

		if self.StickyScroll then
			Scrollbar:ScrollToBottom( true )
		end

		return
	end

	local OldPos = self.Scrollbar.Pos
	local OldSize = self.Scrollbar:GetDiffSize()

	self.Scrollbar:SetScrollSize( MaxHeight / Height )

	if self.StickyScroll and OldPos == OldSize then
		self.Scrollbar:ScrollToBottom( true )
	end
end

function Panel:SetScrollbarPos( Pos )
	self.ScrollPos = Pos
end

function Panel:SetColour( Col )
	self.Background:SetColor( Col )
end

function Panel:SetDraggable( Bool )
	self.Draggable = Bool and true or false

	if self.Draggable then
		local GetCursorPos

		local LastInput = 0
		local Clock = os and os.clock or Shared.GetTime

		function self:OnMouseDown( Key, DoubleClick )
			if Key ~= InputKey.MouseButton0 then return end
			if not self:MouseIn( self.Background, nil, nil, 20 ) then return end

			if Clock() - LastInput < 0.2 then
				DoubleClick = true
			end

			LastInput = Clock()

			if DoubleClick and self.ReturnToDefaultPos then
				self:ReturnToDefaultPos()

				return
			end

			GetCursorPos = GetCursorPos or Client.GetCursorPosScreen

			local X, Y = GetCursorPos()
			
			self.Dragging = true

			self.DragStartX = X
			self.DragStartY = Y
		
			self.CurPos = self:GetPos()
			self.StartPos = Vector( self.CurPos.x, self.CurPos.y, 0 )
		end

		function self:OnMouseUp( Key )
			if Key ~= InputKey.MouseButton0 then return end
			self.Dragging = false
		end

		function self:OnMouseMove( Down )
			if not Down then return end
			if not self.Dragging then return end
			
			local X, Y = GetCursorPos()

			local XDiff = X - self.DragStartX
			local YDiff = Y - self.DragStartY

			self.CurPos.x = self.StartPos.x + XDiff
			self.CurPos.y = self.StartPos.y + YDiff

			self:SetPos( self.CurPos )
		end
	else
		self.OnMouseDown = nil
		self.OnMouseUp = nil
		self.OnMouseMove = nil
	end
end

function Panel:SetTexture( Texture )
	self.Background:SetTexture( Texture )
end

SGUI:Register( "Panel", Panel )
