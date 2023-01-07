--[[
	Tabbed panel.

	Tab buttons are left aligned.
]]

local Binder = require "shine/lib/gui/binding/binder"

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local ToUnit = SGUI.Layout.ToUnit
local Units = SGUI.Layout.Units

local TableRemove = table.remove

local TabPanelButton = {}

function TabPanelButton:Initialise()
	Controls.Button.Initialise( self )

	-- We'll handle it ourselves.
	self:SetHighlightOnMouseOver( false )
end

function TabPanelButton:SetTab( Index, Name )
	self.Index = Index
	self.Name = Name

	self:SetText( Name )
end

function TabPanelButton:DoClick()
	self:SetSelected( true )
	self.Parent:ScrollIntoView( self )
	self.Parent.Parent:OnTabSelect( self )
end

function TabPanelButton:SetActiveCol( Col )
	self.ActiveCol = Col

	if self.Selected then
		self:SetBackgroundColour( Col )
	end
end

function TabPanelButton:SetInactiveCol( Col )
	self.InactiveCol = Col

	if not self.Selected then
		self:SetBackgroundColour( Col )
	end
end

function TabPanelButton:SetSelected( Selected )
	self.Selected = Selected

	if not self.Selected then
		self:SetBackgroundColour( self.InactiveCol )
		self:RemoveStylingState( "Selected" )
	else
		self:SetBackgroundColour( self.ActiveCol )
		self:AddStylingState( "Selected" )
	end
end

function TabPanelButton:OnMouseMove( Down )
	Controls.Button.OnMouseMove( self, Down )

	if self:HasMouseEntered() then
		self.Highlighted = true
		self:AddStylingState( "Highlighted" )
	else
		self.Highlighted = false
		self:RemoveStylingState( "Highlighted" )
	end
end

SGUI:Register( "TabPanelButton", TabPanelButton, "Button" )

local TabPanel = {}

TabPanel.IsWindow = true

TabPanel.TabWidth = 128
TabPanel.TabHeight = 96

TabPanel.VerticalLayoutModeType = {
	-- Legacy layout, uses large buttons with centre-aligned text that take up a large amount of space when expanded.
	LEGACY = 1,
	-- Newer layout, uses smaller horizontal buttons that take up a relatively small amount more space when expanded.
	COMPACT = 2
}

SGUI.AddBoundProperty( TabPanel, "TabBackgroundColour", "TabPanel:SetColour" )
SGUI.AddBoundProperty( TabPanel, "PanelColour", "ContentPanel:SetColour" )

SGUI.AddProperty( TabPanel, "Expanded", true, { "InvalidatesLayout" } )
SGUI.AddProperty( TabPanel, "CollapsedTabSize", Units.Integer( Units.HighResScaled( 48 ) ) )
SGUI.AddProperty( TabPanel, "TabListPaddingAmount", Units.HighResScaled( 8 ) )
SGUI.AddProperty( TabPanel, "VerticalLayoutMode", TabPanel.VerticalLayoutModeType.LEGACY )

function TabPanel:Initialise()
	Controls.Panel.Initialise( self )

	-- This panel holds the tab buttons.
	self.TabPanel = SGUI:Create( "Panel", self )
	self.TabPanel:SetHideHorizontalScrollbar( true )
	self.TabPanel:SetScrollable()
	self.TabPanel:SetScrollbarWidth( Units.HighResScaled( 8 ):GetValue() )
	self.TabPanel:SetScrollbarPos( Vector2( -Units.HighResScaled( 8 ):GetValue(), 0 ) )
	self.TabPanel:SetScrollbarHeightOffset( 0 )
	self.TabPanel.BufferAmount = 0
	self.TabPanel:SetIsSchemed( false )

	-- This panel is populated with a tab's content.
	self.ContentPanel = SGUI:Create( "Panel", self )
	self.ContentPanel:SetIsSchemed( false )
	self.ContentPanel:SetFill( true )

	self.Tabs = {}
	self.NumTabs = 0
	self.VerticalLayoutMode = self.VerticalLayoutModeType.LEGACY
	self:SetHorizontal( false )

	self:AddPropertyChangeListener( "TabListPaddingAmount", self.UpdateSizes )
end

do
	local OldSetExpanded = TabPanel.SetExpanded
	function TabPanel:SetExpanded( Expanded )
		-- Ignore requests to collapse when in horizontal mode.
		if not Expanded and self.Horizontal then return end

		return OldSetExpanded( self, Expanded )
	end
end

local function ResolveButtonStyleName( self, Horizontal )
	if Horizontal then
		return "Horizontal"
	end

	if self.VerticalLayoutMode == self.VerticalLayoutModeType.COMPACT then
		return "VerticalCompact"
	end

	return nil
end

do
	local function GetVerticalTabLayoutPadding( self, Expanded )
		if not Expanded or self.VerticalLayoutMode ~= self.VerticalLayoutModeType.COMPACT then return nil end

		local PaddingAmount = self:GetTabListPaddingAmount()
		return Units.Spacing(
			PaddingAmount, PaddingAmount, PaddingAmount, PaddingAmount
		)
	end

	local function GetVerticalTabLayoutSize( self, Expanded )
		local Width
		if Expanded then
			Width = ToUnit( self.TabWidth )
			if self.VerticalLayoutMode == self.VerticalLayoutModeType.COMPACT then
				Width = Width + self:GetTabListPaddingAmount() * 2
			end
		else
			Width = self:GetCollapsedTabSize()
		end
		return Units.UnitVector( Width, Units.Percentage.ONE_HUNDRED )
	end

	local LayoutSetup = {
		-- Setup horizontal layout (tabs on top horizontally, content below).
		[ true ] = function( self, InternalLayout )
			self.ExpanderLayout = nil
			if SGUI.IsValid( self.ExpanderButton ) then
				self.ExpanderButton:Destroy()
				self.ExpanderButton = nil
			end
			self.ExpanderVisibleBinding:Destroy()
			self.ExpanderVisibleBinding = nil

			-- Horizontal tabs can't be collapsed.
			self:SetExpanded( true )

			local TabsLayout = SGUI.Layout:CreateLayout( "Horizontal", {
				AutoSize = Units.UnitVector( Units.Percentage.ONE_HUNDRED, self.TabHeight ),
				Fill = false
			} )
			TabsLayout:AddElement( self.TabPanel )

			self.TabPanel:SetFill( true )
			self.TabPanel:SetAutoHideScrollbar( false )

			-- Add a button on the end of the tabs that provides a menu to select from
			-- all available tabs. This makes navigating tabs when they overflow easier.
			local AllTabsButton = SGUI:Create( "Button", self )
			AllTabsButton:SetAutoSize( Units.UnitVector(
				Units.Auto.INSTANCE + Units.HighResScaled( 8 ),
				Units.Percentage.ONE_HUNDRED
			) )
			AllTabsButton:SetAutoFont( {
				Family = SGUI.FontFamilies.Ionicons,
				Size = ToUnit( self.TabHeight )
			} )
			AllTabsButton:SetText( SGUI.Icons.Ionicons.AndroidMoreVertical )
			AllTabsButton:SetStyleName( "TabPanelTabListButton" )
			AllTabsButton:SetOpenMenuOnClick( function( Button )
				return {
					Size = Units.UnitVector(
						self.TabWidth,
						self.TabHeight
					):GetValue( self.TabPanel:GetSize(), Button ),
					MenuPos = Button.MenuPos.BOTTOM,
					Populate = function( Menu )
						Menu:SetFontScale( self.Font, self.TextScale )

						local MaxOfIcons = Units.Max()

						for i = 1, self.NumTabs do
							local Tab = self.Tabs[ i ]

							local MenuButton = Menu:AddButton( Tab.Name, function()
								if SGUI.IsValid( Tab.TabButton ) then
									Tab.TabButton:DoClick()
								end
								Menu:Destroy()
							end )
							MenuButton:SetIcon( Tab.TabButton:GetIcon() )

							local IconSize = MenuButton.Icon and Units.Auto( MenuButton.Icon ) or Units.Absolute( 0 )
							MaxOfIcons:AddValue( IconSize )

							MenuButton:SetStyleName( "TabPanelOverflowMenuButton" )
							MenuButton.Label:SetMargin(
								Units.Spacing(
									MaxOfIcons - IconSize, 0, 0, 0
								)
							)
						end
					end
				}
			end )

			TabsLayout:AddElement( AllTabsButton )
			self.TabsLayout = TabsLayout

			InternalLayout:AddElement( TabsLayout )

			-- Only show the all tabs button if there's overflow.
			Binder():FromElement( self.TabPanel, "OverflowX" )
				:ToElement( AllTabsButton, "IsVisible" )
				-- Invalidate immediately to avoid the button being positioned incorrectly for a frame.
				:ToListener( function() TabsLayout:InvalidateLayout( true ) end )
				:BindProperty()
		end,
		-- Setup vertical layout (tabs on the left vertically, content on the right).
		[ false ] = function( self, InternalLayout )
			if SGUI.IsValid( self.AllTabsButton ) then
				self.AllTabsButton:Destroy()
				self.AllTabsButton = nil
			end

			local TabsLayout = SGUI.Layout:CreateLayout( "Vertical", {
				AutoSize = GetVerticalTabLayoutSize( self, self:GetExpanded() ),
				Fill = false,
				Padding = GetVerticalTabLayoutPadding( self, self:GetExpanded() )
			} )
			self.TabsLayout = TabsLayout
			TabsLayout:AddElement( self.TabPanel )

			self.TabPanel:SetFill( true )
			self.TabPanel:SetAutoHideScrollbar( true )

			local ExpanderButton = SGUI:Create( "Button", self )
			ExpanderButton:SetAutoSize( Units.UnitVector( Units.Percentage.ONE_HUNDRED, self:GetCollapsedTabSize() ) )
			function ExpanderButton.DoClick()
				self:SetExpanded( not self:GetExpanded() )
			end

			self.ExpanderButton = ExpanderButton

			TabsLayout:AddElement( ExpanderButton )
			InternalLayout:AddElement( TabsLayout )

			-- Update the size of the expander button and its container when CollapsedTabSize changes.
			Binder():FromElement( self, "CollapsedTabSize" )
				:ToElement( TabsLayout, "AutoSize", {
					Filter = function() return not self.Expanded end,
					Transformer = function( CollapsedTabSize )
						return Units.UnitVector( CollapsedTabSize, Units.Percentage.ONE_HUNDRED )
					end
				} )
				:ToElement( ExpanderButton, "AutoSize", {
					Transformer = function( CollapsedTabSize )
						return Units.UnitVector( Units.Percentage.ONE_HUNDRED, CollapsedTabSize )
					end
				} ):BindProperty()

			-- Alter the icon of the expander button depending on whether the tabs are expanded.
			Binder():FromElement( self, "Expanded" )
				:ToElement( TabsLayout, "AutoSize", {
					Transformer = function( Expanded ) return GetVerticalTabLayoutSize( self, Expanded ) end
				} )
				:ToElement( TabsLayout, "Padding", {
					Transformer = function( Expanded ) return GetVerticalTabLayoutPadding( self, Expanded ) end
				} )
				:ToElement( ExpanderButton, "Icon", {
					Transformer = function( Expanded )
						return SGUI.Icons.Ionicons[ Expanded and "ChevronLeft" or "ChevronRight" ]
					end
				} ):BindProperty()

			-- Decide whether the expander layout/button is visible or not depending on whether every
			-- tab button has an icon or not. If any tab does not have an icon, the tabs can't be collapsed.
			self.ExpanderVisibleBinding = Binder()
				:ToElement( ExpanderButton, "IsVisible" )
				:ToElement( self, "Expanded", {
					Filter = function( AllButtonsHaveIcons )
						return not AllButtonsHaveIcons
					end,
					-- Force expand if any tab is missing an icon.
					Transformer = function() return true end
				} )
				:WithReducer( function( State, Icon )
					return State and Icon ~= nil
				end )
				:WithInitialState( true ):BindProperties()

			for i = 1, self.NumTabs do
				local Button = self.Tabs[ i ].TabButton
				self.ExpanderVisibleBinding:AddSource( Button:GetPropertySource( "Icon" ) )
			end
			self.ExpanderVisibleBinding:Refresh()
		end
	}

	function TabPanel:ApplySpacingsToTabButton( Button )
		local ButtonMargin
		local ButtonPadding
		local TextAlignment
		if not self.Horizontal and self.VerticalLayoutMode == self.VerticalLayoutModeType.COMPACT then
			local PaddingAmount = self:GetTabListPaddingAmount()
			ButtonMargin = Units.Spacing( 0, 0, 0, PaddingAmount )
			ButtonPadding = Units.Spacing( PaddingAmount, 0, PaddingAmount, 0 )
			TextAlignment = SGUI.LayoutAlignment.MIN
		else
			TextAlignment = SGUI.LayoutAlignment.CENTRE
		end
		Button:SetMargin( ButtonMargin )
		Button:SetPadding( ButtonPadding )
		Button:SetTextAlignment( TextAlignment )
	end

	local function UpdateButton( self, Button, Horizontal )
		local StyleName = ResolveButtonStyleName( self, Horizontal )
		Button:SetStyleName( StyleName )
		Button:SetHorizontal( StyleName ~= nil )
		self:ApplySpacingsToTabButton( Button )
	end

	function TabPanel:SetHorizontal( Horizontal )
		Horizontal = not not Horizontal

		if self.Horizontal == Horizontal then return end

		self.Horizontal = Horizontal
		self:SetStyleName( Horizontal and "Horizontal" or nil )

		local InternalLayout = SGUI.Layout:CreateLayout( Horizontal and "Vertical" or "Horizontal" )
		LayoutSetup[ Horizontal ]( self, InternalLayout )
		InternalLayout:AddElement( self.ContentPanel )

		self:SetLayout( InternalLayout, true )
		self:InvalidateLayout( true )

		local ButtonsLayout = SGUI.Layout:CreateLayout( Horizontal and "Horizontal" or "Vertical" )
		for i = 1, self.NumTabs do
			local Button = self.Tabs[ i ].TabButton
			UpdateButton( self, Button, Horizontal )
			ButtonsLayout:AddElement( Button )
		end

		self.TabPanel:SetLayout( ButtonsLayout, true )
		self.TabPanel:InvalidateLayout( true )

		self.TabPanel:RecomputeMaxHeight()
		self.TabPanel:RecomputeMaxWidth()
	end

	local SetVerticalLayoutMode = TabPanel.SetVerticalLayoutMode
	function TabPanel:SetVerticalLayoutMode( VerticalLayoutMode )
		if not SetVerticalLayoutMode( self, VerticalLayoutMode ) then return false end
		if self.Horizontal then return true end

		self.TabsLayout:SetAutoSize( GetVerticalTabLayoutSize( self, self:GetExpanded() ) )
		self.TabsLayout:SetPadding( GetVerticalTabLayoutPadding( self, self:GetExpanded() ) )

		for i = 1, self.NumTabs do
			UpdateButton( self, self.Tabs[ i ].TabButton, self.Horizontal )
		end

		self:UpdateSizes()

		return true
	end
end

function TabPanel:UpdateSizes()
	local TabWidth = self.TabWidth
	if self.Horizontal then
		self.TabsLayout:SetAutoSize( Units.UnitVector( Units.Percentage.ONE_HUNDRED, self.TabHeight ) )
	else
		local LeftWidth = ToUnit( TabWidth )
		if self.VerticalLayoutMode == self.VerticalLayoutModeType.COMPACT then
			LeftWidth = LeftWidth + self:GetTabListPaddingAmount() * 2
		end
		self.TabsLayout:SetAutoSize( Units.UnitVector( LeftWidth, Units.Percentage.ONE_HUNDRED ) )
	end

	for i = 1, self.NumTabs do
		local Button = self.Tabs[ i ].TabButton
		Button:SetAutoSize( Units.UnitVector( TabWidth, self.TabHeight ) )
	end
end

-- Setting the tab width or tab height means we should resize the panels too.
function TabPanel:SetTabWidth( Width )
	self.TabWidth = Width
	self:UpdateSizes()
	self:InvalidateLayout()
end

local function RefreshAutoTabWidth( self, PaddingAmount )
	self.AutoTabWidth:Clear()

	PaddingAmount = PaddingAmount * 2

	for i = 1, self.NumTabs do
		local TabButton = self.Tabs[ i ].TabButton
		TabButton:SetTextAutoEllipsis( true )
		TabButton.AutoTabWidth = Units.Auto( TabButton ) + PaddingAmount
		self.AutoTabWidth:AddValue( TabButton.AutoTabWidth )
	end

	self:UpdateSizes()
	self:InvalidateLayout()
end

function TabPanel:UseAutoTabWidth()
	self.AutoTabWidth = Units.Max()
	self.TabWidth = Units.Min( self.AutoTabWidth, Units.PercentageOfElement( self, 25 ) )
	self.IconWidth = Units.Max()

	RefreshAutoTabWidth( self, self:GetTabListPaddingAmount() )

	self:AddPropertyChangeListener( "TabListPaddingAmount", RefreshAutoTabWidth )
end

function TabPanel:SetTabHeight( Height )
	self.TabHeight = Height

	if SGUI.IsValid( self.AllTabsButton ) then
		self.AllTabsButton:SetAutoFont( {
			Family = SGUI.FontFamilies.Ionicons,
			Size = ToUnit( self.TabHeight )
		} )
	end

	self:UpdateSizes()
	self:InvalidateLayout()
end

function TabPanel:SetFont( Font )
	self.Font = Font
	for i = 1, #self.Tabs do
		self.Tabs[ i ]:SetFont( Font )
	end
end

function TabPanel:SetTextScale( Scale )
	self.TextScale = Scale
	for i = 1, #self.Tabs do
		self.Tabs[ i ]:SetTextScale( Scale )
	end
end

local function GetButtonMargin( self )
	local PaddingAmount = self:GetTabListPaddingAmount()
	return Units.Spacing( 0, 0, 0, PaddingAmount )
end

local function GetButtonPadding( self )
	local PaddingAmount = self:GetTabListPaddingAmount()
	return Units.Spacing( PaddingAmount, 0, PaddingAmount, 0 )
end

function TabPanel:AddTab( Name, OnPopulate, IconName, IconFont, IconFontScale )
	local Tabs = self.Tabs
	local StyleName = ResolveButtonStyleName( self, self.Horizontal )

	local TabButton = self.TabPanel:Add( "TabPanelButton" )
	TabButton:SetDebugName( Name.."Tab" )
	TabButton:SetHorizontal( StyleName ~= nil )
	TabButton:SetTab( self.NumTabs + 1, Name )
	TabButton:SetAutoSize( Units.UnitVector( self.TabWidth, self.TabHeight ) )
	TabButton:SetStyleName( StyleName )

	self:ApplySpacingsToTabButton( TabButton )

	if self.Font then
		TabButton:SetFont( self.Font )
	end
	if self.TextScale then
		TabButton:SetTextScale( self.TextScale )
	end

	TabButton:SetIcon( IconName, IconFont, IconFontScale )

	if self.AutoTabWidth then
		-- Button size is constrained to not exceed 25% width, so may need to shorten text.
		TabButton:SetTextAutoEllipsis( true )

		local PaddingAmount = self:GetTabListPaddingAmount() * 2
		TabButton.AutoTabWidth = Units.Auto( TabButton ) + PaddingAmount
		self.AutoTabWidth:AddValue( TabButton.AutoTabWidth )

		-- Auto-align all button text after each button's icon to account for icon size differences.
		if TabButton.Icon then
			self.IconWidth:AddValue( Units.Auto( TabButton.Icon ) )
			TabButton:SetIconMargin(
				Units.Spacing( 0, 0, self.IconWidth - Units.Auto( TabButton.Icon ) + Units.HighResScaled( 8 ), 0 )
			)
		end
	end

	-- Show/hide the button's text depending on the expanded state, and resize it accordingly.
	Binder():FromElement( self, "Expanded" )
		:ToElement( TabButton, "TextIsVisible" )
		:ToElement( TabButton, "Tooltip", {
			Transformer = function( Expanded )
				return not Expanded and TabButton:GetText() or nil
			end
		} )
		:ToElement( TabButton, "IconAlignment", {
			Transformer = function( Expanded )
				if
					not Expanded or
					self.Horizontal or
					self.VerticalLayoutMode ~= self.VerticalLayoutModeType.COMPACT
				then
					return SGUI.LayoutAlignment.CENTRE
				end
				return SGUI.LayoutAlignment.MIN
			end
		} )
		:ToElement( TabButton, "AutoSize", {
			Transformer = function( Expanded )
				if Expanded then
					return Units.UnitVector( self.TabWidth, self.TabHeight )
				end
				local WidthHeight = self:GetCollapsedTabSize()
				return Units.UnitVector( WidthHeight, WidthHeight )
			end
		} )
		:ToElement( TabButton, "Margin", {
			Transformer = function( Expanded )
				if
					not Expanded or
					self.Horizontal or
					self.VerticalLayoutMode ~= self.VerticalLayoutModeType.COMPACT
				then
					return nil
				end
				return GetButtonMargin( self )
			end
		} )
		:ToElement( TabButton, "Padding", {
			Transformer = function( Expanded )
				if
					not Expanded or
					self.Horizontal or
					self.VerticalLayoutMode ~= self.VerticalLayoutModeType.COMPACT
				then
					return nil
				end
				return GetButtonPadding( self )
			end
		} ):BindProperty()
	-- Update the button's size when not expanded.
	Binder():FromElement( self, "CollapsedTabSize" )
		:ToElement( TabButton, "AutoSize", {
			Filter = function() return not self:GetExpanded() end,
			Transformer = function( Value )
				return Units.UnitVector( Value, Value )
			end
		} ):BindProperty()

	local function IsTabListPaddingRelevant()
		return self:GetExpanded() and not self.Horizontal
			and self.VerticalLayoutMode == self.VerticalLayoutModeType.COMPACT
	end

	Binder():FromElement( self, "TabListPaddingAmount" )
		:ToElement( TabButton, "Margin", {
			Filter = IsTabListPaddingRelevant,
			Transformer = function()
				return GetButtonMargin( self )
			end
		} )
		:ToElement( TabButton, "Padding", {
			Filter = IsTabListPaddingRelevant,
			Transformer = function()
				return GetButtonPadding( self )
			end
		} ):BindProperty()

	if self.ExpanderVisibleBinding then
		-- Update the expander binding to depend on the button having an icon.
		self.ExpanderVisibleBinding:AddSource( TabButton:GetPropertySource( "Icon" ) ):Refresh()
	end

	self.NumTabs = self.NumTabs + 1

	Tabs[ self.NumTabs ] = { Name = Name, TabButton = TabButton, OnPopulate = OnPopulate }

	self.TabPanel.Layout:AddElement( TabButton )

	-- We need to start off with the first tab showing.
	if self.NumTabs == 1 then
		TabButton:SetSelected( true )
		self:OnTabSelect( TabButton )
	end

	return Tabs[ self.NumTabs ]
end

function TabPanel:SetSelectedTab( Tab )
	local TabButton = Tab.TabButton

	if SGUI.IsValid( TabButton ) then
		TabButton:DoClick()
		return true
	end

	return false
end

function TabPanel:GetActiveTab()
	return self.Tabs[ self.ActiveTab ]
end

function TabPanel:ForceTabRefresh( Index )
	if self.ActiveTab ~= Index or not self.Tabs[ Index ] then return end

	self.ActiveTab = nil
	self:OnTabSelect( self.Tabs[ Index ].TabButton )
end

function TabPanel:OnTabSelect( Tab, SuppressPre )
	local Index = Tab.Index
	if self.ActiveTab == Index then return end

	local Tabs = self.Tabs
	local OnPopulate = Tabs[ Index ] and Tabs[ Index ].OnPopulate

	-- In case someone wants to save information about the tab state.
	if not SuppressPre and self.OnPreTabChange and self.NumTabs > 1 then
		self:OnPreTabChange()
	end

	self.ContentPanel:Clear()

	if OnPopulate then
		OnPopulate( self.ContentPanel )
	end

	self.ActiveTab = Index

	-- In case someone wants to restore information about the tab state.
	if self.OnPostTabChange then
		self:OnPostTabChange()
	end

	Tab:SetSelected( true )

	for i = 1, self.NumTabs do
		if i ~= Index then
			local Tab = Tabs[ i ].TabButton
			Tab:SetSelected( false )
		end
	end
end

function TabPanel:RemoveTab( Index )
	local Tabs = self.Tabs
	if not Tabs[ Index ] then return end

	local TabButton = Tabs[ Index ].TabButton
	if self.ExpanderVisibleBinding then
		-- Sources are cached on elements, so this works.
		self.ExpanderVisibleBinding:RemoveSource( TabButton:GetPropertySource( "Icon" ) ):Refresh()
	end
	TabButton:Destroy()

	TableRemove( Tabs, Index )

	self.TabPanel.Layout:RemoveElement( TabButton )
	self.NumTabs = self.NumTabs - 1

	if self.AutoTabWidth then
		RefreshAutoTabWidth( self, self:GetTabListPaddingAmount() )

		if TabButton.Icon then
			self.IconWidth:RemoveValue( Units.Auto( TabButton.Icon ) )
		end
	end

	for i = 1, self.NumTabs do
		local Tab = Tabs[ i ].TabButton

		-- These are both in the old index range.
		if Tab.Index == self.ActiveTab then
			self.ActiveTab = i
		end
		-- Correct the tab's index.
		Tab.Index = i
	end

	-- If we removed the active tab, switch to tab 1.
	if Index == self.ActiveTab then
		if Tabs[ 1 ] then
			self:OnTabSelect( Tabs[ 1 ].TabButton, true )
		end
	end
end

function TabPanel:Close()
	-- Again for external usage.
	if self.OnClose then
		if self:OnClose() then
			return
		end
	end

	self:SetIsVisible( false )
end

function TabPanel:AddCloseButton()
	Controls.Panel.AddCloseButton( self, self )
end

SGUI:Register( "TabPanel", TabPanel, "Panel" )
