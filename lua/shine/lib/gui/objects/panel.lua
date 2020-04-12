--[[
	Basic panel object.

	Provides a background but with all the SGUI functions available to it.
]]

local SGUI = Shine.GUI

local Max = math.max
local Min = math.min

local Panel = {}

-- We're a window object!
Panel.IsWindow = true

local DefaultBuffer = 20
local ScrollPos = Vector( -10, 0, 0 )
local ZeroColour = Colour( 0, 0, 0, 0 )

SGUI.AddProperty( Panel, "AutoHideScrollbar" )
SGUI.AddProperty( Panel, "BlockEventsIfFocusedWindow", true )
SGUI.AddProperty( Panel, "Draggable" )
SGUI.AddProperty( Panel, "HorizontalScrollingEnabled", true )
SGUI.AddProperty( Panel, "ResizeLayoutForScrollbar" )
SGUI.AddProperty( Panel, "StickyScroll" )

SGUI.AddBoundProperty( Panel, "Colour", "Background:SetColor" )
SGUI.AddBoundProperty( Panel, "HideHorizontalScrollbar", "HorizontalScrollbar:SetHidden" )

function Panel:Initialise()
	self.BaseClass.Initialise( self )

	self.Background = self:MakeGUIItem()
	self.TitleBarHeight = 24
	self.OverflowX = false
	self.OverflowY = false
	self.HorizontalScrollingEnabled = true
	self.BlockEventsIfFocusedWindow = true
	self.AlwaysInMouseFocus = false
end

function Panel:SkinColour()
	-- Deprecated, does nothing.
end

function Panel:AddTitleBar( Title, Font, TextScale )
	local TitlePanel = SGUI:Create( "Panel", self )
	TitlePanel:SetSize( Vector( self:GetSize().x, self.TitleBarHeight, 0 ) )
	TitlePanel:SetStyleName( "TitleBar" )
	TitlePanel:SetAnchor( "TopLeft" )

	self.TitleBar = TitlePanel

	local TitleLabel = SGUI:Create( "Label", TitlePanel )
	TitleLabel:SetAnchor( "CentreMiddle" )
	TitleLabel:SetFont( Font or Fonts.kAgencyFB_Small )
	TitleLabel:SetText( Title )
	TitleLabel:SetTextAlignmentX( GUIItem.Align_Center )
	TitleLabel:SetTextAlignmentY( GUIItem.Align_Center )
	if TextScale then
		TitleLabel:SetTextScale( TextScale )
	end

	self.TitleLabel = TitleLabel

	self:AddCloseButton( TitlePanel )
end

function Panel:AddCloseButton( Parent )
	local CloseButton = SGUI:Create( "Button", Parent )
	CloseButton:SetSize( Vector( self.TitleBarHeight, self.TitleBarHeight, 0 ) )
	CloseButton:SetFontScale(
		SGUI.FontManager.GetFontForAbsoluteSize(
			SGUI.FontFamilies.Ionicons,
			self.TitleBarHeight
		)
	)
	CloseButton:SetText( SGUI.Icons.Ionicons.CloseRound )
	CloseButton:SetAnchor( "TopRight" )
	CloseButton:SetPos( Vector( -self.TitleBarHeight, 0, 0 ) )
	CloseButton:SetStyleName( "CloseButton" )

	function CloseButton.DoClick()
		self:Close()
	end

	self.CloseButton = CloseButton
end

function Panel:Close()
	self:SetIsVisible( false )
end

function Panel:SetTitle( Title )
	if not SGUI.IsValid( self.TitleLabel ) then return end

	self.TitleLabel:SetText( Title )
end

function Panel:SetScrollable()
	if self.CroppingBox then return end

	-- Establish a cropping box to keep elements from rendering outside the panel.
	-- Note that self.Background is not used as it would crop the scrollbars.
	local CroppingBox = self:MakeGUICroppingItem()
	CroppingBox:SetColor( ZeroColour )
	CroppingBox:SetSize( self.Background:GetSize() )
	self.Background:AddChild( CroppingBox )

	self.CroppingBox = CroppingBox

	local ScrollParent = self:MakeGUIItem()
	ScrollParent:SetColor( ZeroColour )

	CroppingBox:AddChild( ScrollParent )

	self.ScrollParent = ScrollParent

	self.BufferAmount = self.BufferAmount or DefaultBuffer

	self.AllowSmoothScroll = true
	self.ShowScrollbar = true

	self:SetSize( self:GetSize() )
end

function Panel:SetAllowSmoothScroll( Bool )
	self.AllowSmoothScroll = Bool and true or false
end

function Panel:RemoveScrollingBehaviour()
	if not self.CroppingBox then return end

	if self.Children then
		for Child in self.Children:Iterate() do
			Child:SetParent( self, self.Background )
		end
	end

	GUI.DestroyItem( self.CroppingBox )

	self.CroppingBox = nil
	self.ScrollParent = nil
	self:SetShowScrollbar( false )
end

local function ComputeMaxWidth( Child, PanelWidth )
	local Pos = Child:GetPos()
	local Width = Child:GetSize().x
	local AnchorX = Child:GetAnchor()

	if AnchorX == GUIItem.Left then
		return Pos.x + Width
	end

	if AnchorX == GUIItem.Middle then
		return PanelWidth * 0.5 + Pos.x + Width
	end

	return PanelWidth + Pos.x + Width
end

local function ComputeMaxHeight( Child, PanelHeight )
	local Pos = Child:GetPos()
	local Height = Child:GetSize().y
	local AnchorX, AnchorY = Child:GetAnchor()

	if AnchorY == GUIItem.Top then
		return Pos.y + Height
	end

	if AnchorY == GUIItem.Center then
		return PanelHeight * 0.5 + Pos.y + Height
	end

	return PanelHeight + Pos.y + Height
end

function Panel:RecomputeMaxWidth()
	local MaxWidth = self:GetSize().x

	if self.Children then
		local PanelWidth = MaxWidth

		for Child in self.Children:Iterate() do
			if Child:GetIsVisible() and Child ~= self.Scrollbar and Child ~= self.HorizontalScrollbar then
				local MaxX = ComputeMaxWidth( Child, PanelWidth )
				MaxWidth = Max( MaxWidth, MaxX )
			end
		end

		if self.Layout then
			-- Account for how the layout has positioned its elements.
			-- This only works *after* layout has completed.
			MaxWidth = Max( MaxWidth, self.Layout.MaxPosX or 0 )
		end
	end

	self:SetMaxWidth( MaxWidth )
end

function Panel:RecomputeMaxHeight()
	local MaxHeight = self:GetSize().y

	if self.Children then
		local PanelHeight = MaxHeight

		for Child in self.Children:Iterate() do
			if Child:GetIsVisible() and Child ~= self.Scrollbar and Child ~= self.HorizontalScrollbar then
				local MaxY = ComputeMaxHeight( Child, PanelHeight )
				MaxHeight = Max( MaxHeight, MaxY )
			end
		end

		if self.Layout then
			MaxHeight = Max( MaxHeight, self.Layout.MaxPosY or 0 )
		end
	end

	self:SetMaxHeight( MaxHeight )
end

local function UpdateMaxSize( Child )
	local Parent = Child.Parent
	if not Parent.ScrollParent or not Child:GetIsVisible() then return end

	Parent:InvalidateLayout()
end

function Panel:Add( Class, Created )
	local Element = Created or SGUI:Create( Class, self, self.ScrollParent )
	Element:SetParent( self, self.ScrollParent )

	if self.Stencilled then
		Element:SetInheritsParentStencilSettings( true )
		Element:SetStencilled( true )
	end

	Element:AddPropertyChangeListener( "Pos", UpdateMaxSize )
	Element:AddPropertyChangeListener( "Size", UpdateMaxSize )

	return Element
end

function Panel:SetSize( Size )
	local OldSize = self:GetSize()

	self.BaseClass.SetSize( self, Size )

	if self.CroppingBox then
		self.CroppingBox:SetSize( Size )
	end

	if Size == OldSize then return end

	self:UpdateScrollbarSize()

	if SGUI.IsValid( self.TitleBar ) then
		self.TitleBar:SetSize( Vector( Size.x, self.TitleBarHeight, 0 ) )
	end

	if self.MaxWidth then
		self:SetMaxWidth( self.MaxWidth )
	end
	if self.MaxHeight then
		self:SetMaxHeight( self.MaxHeight )
	end
end

function Panel:GetMaxWidth()
	return self.MaxWidth or self:GetSize().x
end

function Panel:GetMaxHeight()
	return self.MaxHeight or self:GetSize().y
end

--[[
	Clears the panel of objects to be repopulated.
]]
function Panel:Clear()
	if self.Children then
		for Element in self.Children:Iterate() do
			if Element ~= self.Scrollbar and Element ~= self.HorizontalScrollbar then
				Element:Destroy()
			end
		end
	end

	if self.Scrollbar then
		self:SetMaxHeight( self:GetSize().y )
	end

	if self.HorizontalScrollbar then
		self:SetMaxWidth( self:GetSize().x )
	end

	self.Layout = nil
end

function Panel:ScrollIntoView( Child, ForceInstantScroll )
	if Child.Parent ~= self then return end
	if not self.ScrollParent or not self.ScrollParentPos then return end

	local Size = self:GetSize()
	local ChildSize = Child:GetSize()

	local EndX = ComputeMaxWidth( Child, Size.x )
	local StartX = EndX - ChildSize.x

	local EndY = ComputeMaxHeight( Child, Size.y )
	local StartY = EndY - ChildSize.y

	local Pos = self.ScrollParentPos
	local IsOutOfView = ( StartX + Pos.x ) < 0 or ( Pos.x + EndX ) > Size.x
		or ( StartY + Pos.y ) < 0 or ( Pos.y + EndY ) > Size.y
	if not IsOutOfView then return end

	local PosToScrollTo = Vector2( 0, 0 )

	if SGUI.IsValid( self.HorizontalScrollbar ) then
		PosToScrollTo.x = Max( EndX - ChildSize.x * 0.5 - Size.x * 0.5, 0 )
	end
	if SGUI.IsValid( self.Scrollbar ) then
		PosToScrollTo.y = Max( EndY - ChildSize.y * 0.5 - Size.y * 0.5, 0 )
	end

	self:ScrollToPosition( PosToScrollTo, ForceInstantScroll )
end

function Panel:ScrollToPosition( Pos, ForceInstantScroll )
	if not self.ScrollParent then return end

	local Size = self:GetSize()
	if SGUI.IsValid( self.Scrollbar ) then
		local ScrollAsFraction = Max( Pos.y, 0 ) / ( self.MaxHeight - Size.y )
		local ScrollInBarSpace = ScrollAsFraction * self.Scrollbar:GetDiffSize()
		self.Scrollbar:SetScroll( ScrollInBarSpace, not ForceInstantScroll )
	end

	if SGUI.IsValid( self.HorizontalScrollbar ) then
		local ScrollAsFraction = Max( Pos.x, 0 ) / ( self.MaxWidth - Size.x )
		local ScrollInBarSpace = ScrollAsFraction * self.HorizontalScrollbar:GetDiffSize()
		self.HorizontalScrollbar:SetScroll( ScrollInBarSpace, not ForceInstantScroll )
	end
end

function Panel:UpdateScrollbarSize()
	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:SetSize( Vector2(
			( self.ScrollbarWidth or 10 ) * ( self.ScrollbarWidthMult or 1 ),
			self:GetSize().y - ( self.ScrollbarHeightOffset or 20 )
		) )
	end

	if SGUI.IsValid( self.HorizontalScrollbar ) then
		self.HorizontalScrollbar:SetSize( Vector2(
			self:GetSize().x,
			( self.ScrollbarWidth or 10 ) * ( self.ScrollbarWidthMult or 1 )
		) )
	end
end

function Panel:SetScrollbarHeightOffset( Offset )
	self.ScrollbarHeightOffset = Offset
	self:UpdateScrollbarSize()
end

function Panel:SetShowScrollbar( Show )
	self.ShowScrollbar = Show

	if not Show then
		if SGUI.IsValid( self.Scrollbar ) then
			self.Scrollbar:Destroy()
			self.Scrollbar = nil
		end
		if SGUI.IsValid( self.HorizontalScrollbar ) then
			self.HorizontalScrollbar:Destroy()
			self.HorizontalScrollbar = nil
		end
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

function Panel:OnAddScrollbar()
	if not self.Layout or not self.ResizeLayoutForScrollbar then return end

	local Pos = self.Scrollbar:GetPos()
	if Pos.x >= 0 then return end

	self.Layout:SetMargin( SGUI.Layout.Units.Spacing( 0, 0, -Pos.x, 0 ) )
end

function Panel:OnRemoveScrollbar()
	if not self.Layout or not self.ResizeLayoutForScrollbar then return end

	self.Layout:SetMargin( nil )
end

local function OnScrollChanged( self )
	self:InvalidateMouseState( true )
end

function Panel:OnScrollChangeX( Pos, MaxPos, Smoothed )
	local Fraction = MaxPos == 0 and 0 or Pos / MaxPos
	local Diff = self.MaxWidth - self:GetSize().x

	self.ScrollParentPos.x = -Diff * Fraction

	if Smoothed and self.AllowSmoothScroll then
		self:MoveTo( self.ScrollParent, nil, self.ScrollParentPos, 0, 0.2, OnScrollChanged, math.EaseOut, 3 )
	else
		self.ScrollParent:SetPosition( self.ScrollParentPos )
		OnScrollChanged( self )
	end
end

function Panel:SetMaxWidth( MaxWidth )
	self.MaxWidth = MaxWidth

	if not self.ShowScrollbar or not self.HorizontalScrollingEnabled then return end

	local ElementWidth = self:GetSize().x

	if ElementWidth >= MaxWidth then
		if SGUI.IsValid( self.HorizontalScrollbar ) then
			self.HorizontalScrollbar:Destroy()
			self.HorizontalScrollbar = nil
			self.MaxWidth = nil

			local Pos = self.ScrollParent:GetPosition()
			Pos.x = 0
			self.ScrollParent:SetPosition( Pos )
		end

		if self.OverflowX then
			-- Not exposed as a setter as it's an internal state value.
			self.OverflowX = false
			self:OnPropertyChanged( "OverflowX", false )
		end

		return
	end

	if not SGUI.IsValid( self.HorizontalScrollbar ) then
		local Scrollbar = SGUI:Create( "Scrollbar", self )
		self.HorizontalScrollbar = Scrollbar

		Scrollbar:SetAnchor( GUIItem.Left, GUIItem.Bottom )
		self:UpdateScrollbarSize()
		Scrollbar:SetPos( Vector2( 0, -Scrollbar:GetSize().y ) )
		Scrollbar:SetHorizontal( true )
		Scrollbar:SetScrollSize( ElementWidth / MaxWidth )

		self.ScrollParentPos = self.ScrollParentPos or Vector2( 0, 0 )

		Scrollbar._CallEventsManually = true

		if self.HideHorizontalScrollbar then
			-- Hide the scrollbar (but still accept mouse wheel input).
			Scrollbar:HideAndDisableInput()
		elseif self.AutoHideScrollbar and not self:MouseIn( self.Background ) then
			local BackCol = Scrollbar.Background:GetColor()
			BackCol.a = 0
			local BarCol = Scrollbar.Bar:GetColor()
			BarCol.a = 0

			Scrollbar.Background:SetColor( BackCol )
			Scrollbar.Bar:SetColor( BarCol )
		end

		self.OverflowX = true
		self:OnPropertyChanged( "OverflowX", true )

		return
	end

	self.HorizontalScrollbar:SetScrollSize( ElementWidth / MaxWidth )
end

function Panel:OnScrollChange( Pos, MaxPos, Smoothed )
	local Fraction = MaxPos == 0 and 0 or Pos / MaxPos
	local Diff = self.MaxHeight - self:GetSize().y

	self.ScrollParentPos.y = -Diff * Fraction

	if Smoothed and self.AllowSmoothScroll then
		self:MoveTo( self.ScrollParent, nil, self.ScrollParentPos, 0, 0.2, OnScrollChanged, math.EaseOut, 3 )
	else
		self.ScrollParent:SetPosition( self.ScrollParentPos )
		OnScrollChanged( self )
	end
end

function Panel:SetMaxHeight( MaxHeight, ForceInstantScroll )
	local OldMaxHeight = self.MaxHeight

	self.MaxHeight = MaxHeight

	if not self.ShowScrollbar then return end

	local ElementHeight = self:GetSize().y

	-- Height has reduced below the max height, so remove the scrollbar.
	if ElementHeight >= MaxHeight then
		if SGUI.IsValid( self.Scrollbar ) then
			self.Scrollbar:Destroy()
			self.Scrollbar = nil
			self.MaxHeight = nil

			local Pos = self.ScrollParent:GetPosition()
			Pos.y = 0
			self.ScrollParent:SetPosition( Pos )

			self:OnRemoveScrollbar()
		end

		if self.OverflowY then
			self.OverflowY = false
			self:OnPropertyChanged( "OverflowY", false )
		end

		return
	end

	if not SGUI.IsValid( self.Scrollbar ) then
		local Scrollbar = SGUI:Create( "Scrollbar", self )
		self.Scrollbar = Scrollbar

		Scrollbar:SetAnchor( GUIItem.Right, GUIItem.Top )
		Scrollbar:SetPos( self.ScrollPos or ScrollPos )
		self:UpdateScrollbarSize()
		Scrollbar:SetScrollSize( ElementHeight / MaxHeight )

		self.ScrollParentPos = self.ScrollParentPos or Vector2( 0, 0 )

		Scrollbar._CallEventsManually = true

		if self.StickyScroll then
			Scrollbar:ScrollToBottom( not ForceInstantScroll )
		end

		if self.AutoHideScrollbar and not self:MouseIn( self.Background ) then
			local BackCol = Scrollbar.Background:GetColor()
			BackCol.a = 0
			local BarCol = Scrollbar.Bar:GetColor()
			BarCol.a = 0

			Scrollbar.Background:SetColor( BackCol )
			Scrollbar.Bar:SetColor( BarCol )
		end

		self:OnAddScrollbar()

		self.OverflowY = true
		self:OnPropertyChanged( "OverflowY", true )

		return
	end

	local OldPos = self.Scrollbar.Pos
	local OldSize = self.Scrollbar:GetDiffSize()

	local OldScrollSize = self.Scrollbar.ScrollSize
	local NewScrollSize = ElementHeight / MaxHeight

	self.Scrollbar:SetScrollSize( NewScrollSize )

	if self.StickyScroll and OldPos >= OldSize and ( OldMaxHeight ~= MaxHeight or ForceInstantScroll ) then
		local ShouldSmooth = NewScrollSize < OldScrollSize and self:ComputeVisibility()
			and not ForceInstantScroll
		if not ShouldSmooth then
			self:StopMoving( self.ScrollParent )
		end

		self.Scrollbar:ScrollToBottom( ShouldSmooth )
	end
end

function Panel:ScrollToBottom( Smoothly )
	if not SGUI.IsValid( self.Scrollbar ) then return end

	self.Scrollbar:ScrollToBottom( Smoothly )
end

function Panel:SetScrollbarPos( Pos )
	self.ScrollPos = Pos

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:SetPos( Pos )
	end
end

local GetCursorPos = SGUI.GetCursorPos

local LastInput = 0
local Clock = Shared.GetSystemTimeReal

function Panel:DragClick( Key, DoubleClick )
	if not self.Draggable then return end

	if Key ~= InputKey.MouseButton0 then return end

	local Size = self:GetSize()
	if not self:MouseInBounds( self.Background, Size.x, Size.y * 0.05 ) then return end

	if Clock() - LastInput < 0.2 then
		DoubleClick = true
	end

	LastInput = Clock()

	if DoubleClick and self.ReturnToDefaultPos then
		self:ReturnToDefaultPos()

		return true
	end

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

------------------- Event calling -------------------
function Panel:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end

	if SGUI.IsValid( self.Scrollbar ) then
		if self.Scrollbar:OnMouseDown( Key, DoubleClick ) then
			return true, self.Scrollbar
		end
	end

	if SGUI.IsValid( self.HorizontalScrollbar ) then
		if self.HorizontalScrollbar:OnMouseDown( Key, DoubleClick ) then
			return true, self.HorizontalScrollbar
		end
	end

	if self.CroppingBox and not self:MouseInCached() then return end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )
	if Result ~= nil then return true, Child end

	if self:DragClick( Key, DoubleClick ) then return true, self end

	if
		( SGUI:IsWindow( self ) and self.BlockEventsIfFocusedWindow and self:MouseInCached() )
		or self.BlockOnMouseDown
	then
		return true, self
	end
end

function Panel:OnMouseUp( Key )
	self:DragRelease( Key )

	return true
end

function Panel:OnMouseMove( Down )
	if not self:GetIsVisible() then return end

	self.__LastMouseMove = SGUI.FrameNumber()

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:OnMouseMove( Down )
	end

	if SGUI.IsValid( self.HorizontalScrollbar ) then
		self.HorizontalScrollbar:OnMouseMove( Down )
	end

	local MouseIn, StateChanged = self:EvaluateMouseState()
	if MouseIn or StateChanged or self.AlwaysInMouseFocus or SGUI:IsWindow( self ) then
		self:CallOnChildren( "OnMouseMove", Down )
	end

	self:DragMove( Down )

	if self.AutoHideScrollbar and ( SGUI.IsValid( self.Scrollbar ) or SGUI.IsValid( self.HorizontalScrollbar ) ) then
		if not MouseIn and self.ScrollbarIsVisible then
			local ScrollbarHasFocus = self.Scrollbar and self.Scrollbar:HasMouseFocus()
			local HorizontalScrollbarHasFocus = self.HorizontalScrollbar and self.HorizontalScrollbar:HasMouseFocus()

			if not ScrollbarHasFocus and not HorizontalScrollbarHasFocus then
				self.ScrollbarIsVisible = false

				if self.Scrollbar then
					self.Scrollbar:FadeOut( 0.3 )
				end
				if self.HorizontalScrollbar then
					self.HorizontalScrollbar:FadeOut( 0.3 )
				end
			end
		elseif MouseIn and not self.ScrollbarIsVisible then
			self.ScrollbarIsVisible = true

			if self.Scrollbar then
				self.Scrollbar:FadeIn( 0.3 )
			end
			if self.HorizontalScrollbar then
				self.HorizontalScrollbar:FadeIn( 0.3 )
			end
		end
	end

	-- Block mouse movement for lower windows.
	if ( SGUI:IsWindow( self ) and self.BlockEventsIfFocusedWindow ) or self.BlockOnMouseDown then
		if MouseIn then return true end
	end
end

function Panel:OnGainWindowFocus()
	self:InvalidateMouseState( true )
end

function Panel:Think( DeltaTime )
	if not self:GetIsVisible() then return end

	self.BaseClass.Think( self, DeltaTime )

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:Think( DeltaTime )
	end
	if SGUI.IsValid( self.HorizontalScrollbar ) then
		self.HorizontalScrollbar:Think( DeltaTime )
	end

	self:CallOnChildren( "Think", DeltaTime )
end

function Panel:PerformLayout()
	self.BaseClass.PerformLayout( self )

	if self.CroppingBox then
		-- Some elements may have moved to no longer be so far down/to the right.
		self:RecomputeMaxHeight()
		self:RecomputeMaxWidth()
	end
end

function Panel:OnMouseWheel( Down )
	if not self:GetIsVisible() then return end

	-- Call children first, so they scroll before the main panel scroll.
	local Result = self:CallOnChildren( "OnMouseWheel", Down )
	if Result ~= nil then return true end

	if SGUI.IsValid( self.Scrollbar ) then
		if self.Scrollbar:OnMouseWheel( Down ) then
			return true
		end
	elseif SGUI.IsValid( self.HorizontalScrollbar ) and self.HorizontalScrollbar:OnMouseWheel( Down ) then
		-- Only allow mouse-wheel input on the horizontal scrollbar if there is no vertical bar.
		return true
	end

	-- We block the event, so that only the focused window can scroll.
	if SGUI:IsWindow( self ) and self.BlockEventsIfFocusedWindow then
		return false
	end
end

function Panel:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end

	if self:CallOnChildren( "PlayerKeyPress", Key, Down ) then
		return true
	end

	-- Block the event so only the focused window receives input.
	if SGUI:IsWindow( self ) and self.BlockEventsIfFocusedWindow then
		return false
	end
end

function Panel:PlayerType( Char )
	if not self:GetIsVisible() then return end

	if self:CallOnChildren( "PlayerType", Char ) then
		return true
	end

	if SGUI:IsWindow( self ) and self.BlockEventsIfFocusedWindow then
		return false
	end
end

SGUI:Register( "Panel", Panel )
