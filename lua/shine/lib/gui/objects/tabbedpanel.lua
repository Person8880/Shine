--[[
	Tabbed panel.

	Tab buttons are left aligned.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local ToUnit = SGUI.Layout.ToUnit
local Units = SGUI.Layout.Units

local TableRemove = table.remove

local TabPanelButton = {}

function TabPanelButton:Initialise()
	Controls.Button.Initialise( self )

	--We'll handle it ourselves.
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

function TabPanelButton:SetSelected( Selected )
	self.Selected = Selected

	if not self.Selected then
		self.Background:SetColor( self.InactiveCol )
	else
		self.Background:SetColor( self.ActiveCol )
	end
end

function TabPanelButton:OnMouseMove( Down )
	Controls.Button.OnMouseMove( self, Down )

	if self:MouseIn( self.Background, 0.9 ) then
		self.Highlighted = true
	else
		self.Highlighted = false
	end
end

function TabPanelButton:SetText( Text )
	Controls.Button.SetText( self, Text )

	if SGUI.IsValid( self.Icon ) then
		self.Label:SetPosition( Vector2( 0, 0.5 * self.Icon:GetSize().y ) )
	end
end

function TabPanelButton:SetIcon( IconName, Font, Scale )
	if not Font and not Scale then
		Font, Scale = SGUI.FontManager.GetHighResFont( SGUI.FontFamilies.Ionicons, 32 )
	else
		Font = Font or SGUI.Fonts.Ionicons
		Scale = Scale or 1
	end

	local Icon = SGUI:Create( "Label", self )
	Icon:SetFontScale( Font, Scale )
	Icon:SetColour( self:GetTextColour() )
	Icon:SetAnchor( "CentreMiddle" )
	Icon:SetTextAlignmentX( GUIItem.Align_Center )
	Icon:SetTextAlignmentY( GUIItem.Align_Center )
	Icon:SetText( IconName )
	Icon:SetPos( Vector2( 0, -0.5 * Icon:GetSize().y ) )

	self.Icon = Icon

	if self.Label then
		self.Label:SetPosition( Vector2( 0, 0.5 * Icon:GetSize().y ) )
	end
end

SGUI:Register( "TabPanelButton", TabPanelButton, "Button" )

local TabPanel = {}

TabPanel.IsWindow = true

TabPanel.TabWidth = 128
TabPanel.TabHeight = 96

SGUI.AddBoundProperty( TabPanel, "TabBackgroundColour", "TabPanel:SetColour" )
SGUI.AddBoundProperty( TabPanel, "PanelColour", "ContentPanel:SetColour" )

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
	self.TabPanel.UseScheme = false

	-- This panel is populated with a tab's content.
	self.ContentPanel = SGUI:Create( "Panel", self )
	self.ContentPanel.UseScheme = false
	self.ContentPanel:SetFill( true )

	self.Tabs = {}
	self.NumTabs = 0
	self:SetHorizontal( false )
end

do
	local LayoutSetup = {
		-- Setup horizontal layout (tabs on top horizontally, content below).
		[ true ] = function( self, InternalLayout )
			local TabsLayout = SGUI.Layout:CreateLayout( "Horizontal", {
				AutoSize = Units.UnitVector( Units.Percentage( 100 ), self.TabHeight ),
				Fill = false
			} )
			TabsLayout:AddElement( self.TabPanel )

			self.TabPanel:SetFill( true )
			self.TabPanel:SetAutoHideScrollbar( false )

			-- Add a button on the end of the tabs that provides a menu to select from
			-- all available tabs. This makes navigating tabs when they overflow easier.
			local AllTabsButton = SGUI:Create( "Button", self )
			AllTabsButton:SetAutoSize( Units.UnitVector(
				Units.Auto() + Units.HighResScaled( 8 ),
				Units.Percentage( 100 )
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

						for i = 1, self.NumTabs do
							local Tab = self.Tabs[ i ]
							Menu:AddButton( Tab.Name, function()
								if SGUI.IsValid( Tab.TabButton ) then
									Tab.TabButton:DoClick()
								end
								Menu:Destroy()
							end )
						end
					end
				}
			end )

			TabsLayout:AddElement( AllTabsButton )
			self.TabsLayout = TabsLayout

			InternalLayout:AddElement( TabsLayout )
		end,
		-- Setup vertical layout (tabs on the left vertically, content on the right).
		[ false ] = function( self, InternalLayout )
			self.TabsLayout = nil
			self.TabPanel:SetFill( false )
			self.TabPanel:SetAutoHideScrollbar( true )
			self.TabPanel:SetAutoSize( Units.UnitVector( self.TabWidth, Units.Percentage( 100 ) ) )

			if SGUI.IsValid( self.AllTabsButton ) then
				self.AllTabsButton:Destroy()
				self.AllTabsButton = nil
			end
			InternalLayout:AddElement( self.TabPanel )
		end
	}

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
			Button:SetStyleName( Horizontal and "Horizontal" or nil )
			ButtonsLayout:AddElement( Button )
		end

		self.TabPanel:SetLayout( ButtonsLayout, true )
		self.TabPanel:InvalidateLayout( true )

		self.TabPanel:RecomputeMaxHeight()
		self.TabPanel:RecomputeMaxWidth()
	end
end

function TabPanel:UpdateSizes()
	if self.Horizontal then
		self.TabsLayout:SetAutoSize( Units.UnitVector( Units.Percentage( 100 ), self.TabHeight ) )
	else
		self.TabPanel:SetAutoSize( Units.UnitVector( self.TabWidth, Units.Percentage( 100 ) ) )
	end

	for i = 1, self.NumTabs do
		local Button = self.Tabs[ i ].TabButton
		Button:SetAutoSize( Units.UnitVector( self.TabWidth, self.TabHeight ) )
	end
end

-- Setting the tab width or tab height means we should resize the panels too.
function TabPanel:SetTabWidth( Width )
	self.TabWidth = Width
	self:UpdateSizes()
	self:InvalidateLayout()
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

function TabPanel:AddTab( Name, OnPopulate )
	local Tabs = self.Tabs

	local TabButton = self.TabPanel:Add( "TabPanelButton" )
	TabButton:SetTab( self.NumTabs + 1, Name )
	TabButton:SetAutoSize( Units.UnitVector( self.TabWidth, self.TabHeight ) )
	TabButton:SetStyleName( self.Horizontal and "Horizontal" or nil )

	if self.Font then
		TabButton:SetFont( self.Font )
	end
	if self.TextScale then
		TabButton:SetTextScale( self.TextScale )
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

function TabPanel:GetActiveTab()
	return self.Tabs[ self.ActiveTab ]
end

function TabPanel:OnTabSelect( Tab, SuppressPre )
	local Index = Tab.Index
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
	TabButton:Destroy()

	TableRemove( Tabs, Index )

	self.TabPanel.Layout:RemoveElement( TabButton )
	self.NumTabs = self.NumTabs - 1

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
