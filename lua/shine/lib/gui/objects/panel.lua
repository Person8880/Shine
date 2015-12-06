--[[
	Basic panel object.

	Provides a background but with all the SGUI functions available to it.
]]

local SGUI = Shine.GUI

local Panel = {}

--We're a window object!
Panel.IsWindow = true

local DefaultBuffer = 20
local ScrollPos = Vector( -20, 10, 0 )
local ZeroColour = Colour( 0, 0, 0, 0 )

function Panel:Initialise()
	self.BaseClass.Initialise( self )

	local Background = GetGUIManager():CreateGraphicItem()

	self.Background = Background
	self.TitleBarHeight = 24
end

function Panel:OnSchemeChange( Skin )
	if not self.UseScheme then return end

	self.Background:SetColor( Skin.WindowBackground )

	if SGUI.IsValid( self.TitleBar ) then
		self.TitleBar:SetColour( Skin.WindowTitle )
	end

	if SGUI.IsValid( self.CloseButton ) then
		self.CloseButton:SetActiveCol( Skin.CloseButtonActive )
		self.CloseButton:SetInactiveCol( Skin.CloseButtonInactive )
		self.CloseButton:SetTextColour( Skin.BrightText )
	end

	if SGUI.IsValid( self.TitleLabel ) then
		self.TitleLabel:SetColour( Skin.BrightText )
	end
end

function Panel:SkinColour()
	local Scheme = SGUI:GetSkin()

	self.Background:SetColor( Scheme.WindowBackground )

	self.UseScheme = true
end

function Panel:AddTitleBar( Title, Font, TextScale )
	local TitlePanel = SGUI:Create( "Panel", self )
	TitlePanel:SetSize( Vector( self:GetSize().x, self.TitleBarHeight, 0 ) )
	if self.UseScheme then
		local Skin = SGUI:GetSkin()

		TitlePanel:SetColour( Skin.WindowTitle )
	end
	TitlePanel:SetAnchor( "TopLeft" )

	self.TitleBar = TitlePanel

	local TitleLabel = SGUI:Create( "Label", TitlePanel )
	TitleLabel:SetAnchor( "CentreMiddle" )
	TitleLabel:SetFont( Font or Fonts.kAgencyFB_Small )
	TitleLabel:SetText( Title )
	TitleLabel:SetTextAlignmentX( GUIItem.Align_Center )
	TitleLabel:SetTextAlignmentY( GUIItem.Align_Center )
	if self.UseScheme then
		local Skin = SGUI:GetSkin()

		TitleLabel:SetColour( Skin.BrightText )
	end
	if TextScale then
		TitleLabel:SetTextScale( TextScale )
	end

	self.TitleLabel = TitleLabel

	local CloseButton = SGUI:Create( "Button", TitlePanel )
	CloseButton:SetSize( Vector( self.TitleBarHeight, self.TitleBarHeight, 0 ) )
	CloseButton:SetText( "X" )
	CloseButton:SetAnchor( "TopRight" )
	CloseButton:SetPos( Vector( -self.TitleBarHeight, 0, 0 ) )
	if self.UseScheme then
		local Skin = SGUI:GetSkin()

		CloseButton.UseScheme = false

		CloseButton:SetActiveCol( Skin.CloseButtonActive )
		CloseButton:SetInactiveCol( Skin.CloseButtonInactive )
		CloseButton:SetTextColour( Skin.BrightText )
	end

	function CloseButton.DoClick()
		self:SetIsVisible( false )
	end

	self.CloseButton = CloseButton
end

function Panel:SetTitle( Title )
	if not SGUI.IsValid( self.TitleLabel ) then return end

	self.TitleLabel:SetText( Title )
end

function Panel:SetScrollable()
	if self.Stencil then return end

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
	self.ShowScrollbar = true

	self:SetSize( self:GetSize() )
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

		local OurSize = self:GetSize()
		local PanSize = Pan:GetSize()
		local AnchorX, AnchorY = self:GetAnchor()

		if AnchorY == GUIItem.Top then
			local NewMaxHeight = Pos.y + OurSize.y

			if NewMaxHeight > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight + Pan.BufferAmount )
			end
		elseif AnchorY == GUIItem.Center then
			local NewMaxHeight = PanSize.y * 0.5 + Pos.y + OurSize.y

			if NewMaxHeight > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight + Pan.BufferAmount )
			end
		else
			local NewMaxHeight = PanSize.y + Pos.y + OurSize.y

			if NewMaxHeight > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight + Pan.BufferAmount )
			end
		end
	end

	local OldSetSize = Element.SetSize
	function Element:SetSize( OurSize )
		OldSetSize( self, OurSize )

		if not Pan.ScrollParent then return end

		local Pos = self:GetPos()
		local PanSize = Pan:GetSize()

		local AnchorX, AnchorY = self:GetAnchor()

		if AnchorY == GUIItem.Top then
			local NewMaxHeight = Pos.y + OurSize.y

			if NewMaxHeight > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight + Pan.BufferAmount )
			end
		elseif AnchorY == GUIItem.Center then
			local NewMaxHeight = PanSize.y * 0.5 + Pos.y + OurSize.y

			if NewMaxHeight > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight + Pan.BufferAmount )
			end
		else
			local NewMaxHeight = PanSize.y + Pos.y + OurSize.y

			if NewMaxHeight > Pan:GetMaxHeight() then
				Pan:SetMaxHeight( NewMaxHeight + Pan.BufferAmount )
			end
		end
	end

	return Element
end

function Panel:SetSize( Size )
	self.BaseClass.SetSize( self, Size )

	if not self.Stencil then return end

	self.Stencil:SetSize( Size )

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:SetParent()
		self.Scrollbar:Destroy()

		self.Scrollbar = nil

		if Size.y < self.MaxHeight then
			self:SetMaxHeight( self.MaxHeight )
		else
			--Make sure the parent gets reset, and we clear the MaxHeight field
			--so auto-resize is calculated from the panel height which is now larger.
			self.ScrollParent:SetPosition( Vector( 0, 0, 0 ) )
			self.MaxHeight = nil
		end
	end

	if SGUI.IsValid( self.TitleBar ) then
		self.TitleBar:SetSize( Vector( Size.x, self.TitleBarHeight, 0 ) )
	end
end

function Panel:GetMaxHeight()
	return self.MaxHeight or self:GetSize().y
end

function Panel:SetIsVisible( Visible )
	self.BaseClass.SetIsVisible( self, Visible )

	local Children = self.Children

	if not Children then return end

	for Child in Children:Iterate() do
		Child:SetIsVisible( Visible )
	end
end

--[[
	Clears the panel of objects to be repopulated.
]]
function Panel:Clear()
	if self.Children then
		for Element in self.Children:Iterate() do
			if Element ~= self.Scrollbar then
				Element:SetParent()
				Element:Destroy()
			end
		end
	end

	if self.Scrollbar then
		self:SetMaxHeight( self:GetSize().y )
	end

	self.Layout = nil
end

function Panel:SetStickyScroll( Enable )
	self.StickyScroll = Enable and true or false
end

function Panel:UpdateScrollbarSize()
	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:SetSize( Vector( ( self.ScrollbarWidth or 10 ) * ( self.ScrollbarWidthMult or 1 ),
			self:GetSize().y - ( self.ScrollbarHeightOffset or 20 ), 0 ) )
	end
end

function Panel:SetScrollbarHeightOffset( Offset )
	self.ScrollbarHeightOffset = Offset
	self:UpdateScrollbarSize()
end

function Panel:SetShowScrollbar( Show )
	self.ShowScrollbar = Show

	if SGUI.IsValid( self.Scrollbar ) and not Show then
		self.Scrollbar:SetParent()
		self.Scrollbar:Destroy()

		self.Scrollbar = nil
	end
end

function Panel:SetScrollbarWidthMult( Mult )
	self.ScrollbarWidthMult = Mult
	self:UpdateScrollbarSize()
end

function Panel:SetScrollbarWidth( Width )
	self.ScrollbarWidth = Width
	self:UpdateScrollbarSize()
end

function Panel:SetMaxHeight( Height )
	self.MaxHeight = Height

	if not self.ShowScrollbar then return end

	local MaxHeight = self:GetSize().y

	-- Height has reduced below the max height, so remove the scrollbar.
	if MaxHeight >= Height then
		if SGUI.IsValid( self.Scrollbar ) then
			self.Scrollbar:SetParent()
			self.Scrollbar:Destroy()
			self.Scrollbar = nil

			if self.ScrollParentPos then
				self.ScrollParentPos.y = 0
			end

			self.ScrollParent:SetPosition( self.ScrollParentPos or Vector( 0, 0, 0 ) )
		end

		return
	end

	if not SGUI.IsValid( self.Scrollbar ) then
		local Scrollbar = SGUI:Create( "Scrollbar", self )
		self.Scrollbar = Scrollbar

		Scrollbar:SetAnchor( GUIItem.Right, GUIItem.Top )
		Scrollbar:SetPos( self.ScrollPos or ScrollPos )
		self:UpdateScrollbarSize()
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
				self:MoveTo( self.ScrollParent, nil, self.ScrollParentPos, 0, 0.2, nil, math.EaseOut, 3 )
			else
				self.ScrollParent:SetPosition( self.ScrollParentPos )
			end
		end

		Scrollbar._CallEventsManually = true

		if self.StickyScroll then
			Scrollbar:ScrollToBottom( true )
		end

		if self.AutoHideScrollbar and not self:MouseIn( self.Background ) then
			local BackCol = Scrollbar.Background:GetColor()
			BackCol.a = 0
			local BarCol = Scrollbar.Bar:GetColor()
			BarCol.a = 0

			Scrollbar.Background:SetColor( BackCol )
			Scrollbar.Bar:SetColor( BarCol )
		end

		return
	end

	local OldPos = self.Scrollbar.Pos
	local OldSize = self.Scrollbar:GetDiffSize()

	local OldScrollSize = self.Scrollbar.ScrollSize
	local NewScrollSize = MaxHeight / Height

	self.Scrollbar:SetScrollSize( NewScrollSize )

	if self.StickyScroll and OldPos >= OldSize then
		local ShouldSmooth = NewScrollSize < OldScrollSize
		self.Scrollbar:ScrollToBottom( ShouldSmooth )
	end
end

function Panel:SetScrollbarPos( Pos )
	self.ScrollPos = Pos

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:SetPos( Pos )
	end
end

function Panel:SetColour( Col )
	self.Background:SetColor( Col )
end

function Panel:SetDraggable( Bool )
	self.Draggable = Bool and true or false
end

function Panel:SetTexture( Texture )
	self.Background:SetTexture( Texture )
end

SGUI.AddProperty( Panel, "AutoHideScrollbar" )

local GetCursorPos

local LastInput = 0
local Clock = os and os.clock or Shared.GetTime

function Panel:DragClick( Key, DoubleClick )
	if not self.Draggable then return end

	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Background, nil, nil, self:GetSize().y * 0.05 ) then return end

	if Clock() - LastInput < 0.2 then
		DoubleClick = true
	end

	LastInput = Clock()

	if DoubleClick and self.ReturnToDefaultPos then
		self:ReturnToDefaultPos()

		return true
	end

	GetCursorPos = GetCursorPos or Client.GetCursorPosScreen

	local X, Y = GetCursorPos()

	self.Dragging = true

	self.DragStartX = X
	self.DragStartY = Y

	self.CurPos = self:GetPos()
	self.StartPos = Vector( self.CurPos.x, self.CurPos.y, 0 )

	return true
end

function Panel:DragRelease( Key )
	if not self.Draggable then return end
	if Key ~= InputKey.MouseButton0 then return end
	self.Dragging = false

	if self.OnDragFinished then
		self:OnDragFinished( self:GetPos() )
	end
end

function Panel:DragMove( Down )
	if not self.Draggable then return end
	if not Down then return end
	if not self.Dragging then return end

	local X, Y = GetCursorPos()

	local XDiff = X - self.DragStartX
	local YDiff = Y - self.DragStartY

	self.CurPos.x = self.StartPos.x + XDiff
	self.CurPos.y = self.StartPos.y + YDiff

	self:SetPos( self.CurPos )
end

function Panel:SetBlockMouse( Bool )
	--self.BlockOnMouseDown = Bool and true or false
end

------------------- Event calling -------------------
function Panel:OnMouseDown( Key, DoubleClick )
	if SGUI.IsValid( self.Scrollbar ) then
		if self.Scrollbar:OnMouseDown( Key, DoubleClick ) then
			return true, self.Scrollbar
		end
	end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )

	if Result ~= nil then return true, Child end

	if self:DragClick( Key, DoubleClick ) then return true, self end

	if self.IsAWindow or self.BlockOnMouseDown then
		if self:MouseIn( self.Background ) then return true, self end
	end
end

function Panel:OnMouseUp( Key )
	self:DragRelease( Key )

	return true
end

function Panel:OnMouseMove( Down )
	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:OnMouseMove( Down )
	end

	self:CallOnChildren( "OnMouseMove", Down )
	self:DragMove( Down )

	local MouseIn
	if self.AutoHideScrollbar and SGUI.IsValid( self.Scrollbar ) then
		MouseIn = self:MouseIn( self.Background )

		if not MouseIn and self.ScrollbarIsVisible then
			if not self.Scrollbar:HasMouseFocus() then
				self.ScrollbarIsVisible = false
				self.Scrollbar:AlphaTo( nil, nil, 0, 0, 0.3 )
				self.Scrollbar:AlphaTo( self.Scrollbar.Bar, nil, 0, 0, 0.3 )
			end
		elseif MouseIn and not self.ScrollbarIsVisible then
			self.ScrollbarIsVisible = true

			local Background = self.Scrollbar.Background
			local Bar = self.Scrollbar.Bar

			self.Scrollbar:AlphaTo( nil, nil, self.Scrollbar:GetNormalAlpha( Background ), 0, 0.3 )
			self.Scrollbar:AlphaTo( Bar, nil, self.Scrollbar:GetNormalAlpha( Bar ), 0, 0.3 )
		end
	end

	--Block mouse movement for lower windows.
	if self.IsAWindow or self.BlockOnMouseDown then
		if MouseIn == nil then
			MouseIn = self:MouseIn( self.Background )
		end
		if MouseIn then return true end
	end
end

function Panel:Think( DeltaTime )
	self.BaseClass.Think( self, DeltaTime )

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:Think( DeltaTime )
	end

	self:CallOnChildren( "Think", DeltaTime )
end

function Panel:OnMouseWheel( Down )
	--Call children first, so they scroll before the main panel scroll.
	local Result = self:CallOnChildren( "OnMouseWheel", Down )

	if Result ~= nil then return true end

	if not SGUI.IsValid( self.Scrollbar ) then
		if self.IsAWindow then return true end

		return
	end

	self.Scrollbar:OnMouseWheel( Down )

	--We block the event, so that only the focused window can scroll.
	if self.IsAWindow then
		return false
	end
end

function Panel:PlayerKeyPress( Key, Down )
	if self:CallOnChildren( "PlayerKeyPress", Key, Down ) then
		return true
	end

	--Block the event so only the focused window receives input.
	if self.IsAWindow then
		return false
	end
end

function Panel:PlayerType( Char )
	if self:CallOnChildren( "PlayerType", Char ) then
		return true
	end

	if self.IsAWindow then
		return false
	end
end

SGUI:Register( "Panel", Panel )
