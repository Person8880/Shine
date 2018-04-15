--[[
	Tabbed panel.

	Tab buttons are left aligned.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

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

SGUI:Register( "TabPanelButton", TabPanelButton, "Button" )

local TabPanel = {}

TabPanel.IsWindow = true

TabPanel.TabWidth = 128
TabPanel.TabHeight = 96

SGUI.AddBoundProperty( TabPanel, "TabBackgroundColour", "TabPanel:SetColour" )
SGUI.AddBoundProperty( TabPanel, "PanelColour", "ContentPanel:SetColour" )

function TabPanel:Initialise()
	Controls.Panel.Initialise( self )

	--This panel holds the tab buttons.
	self.TabPanel = SGUI:Create( "Panel", self )
	self.TabPanel:SetScrollable()
	self.TabPanel.ScrollPos = Vector( 0, 0, 0 )
	self.TabPanel.ScrollbarHeightOffset = 0
	self.TabPanel.BufferAmount = 0

	self.TabPanel.UseScheme = false

	--This panel is populated with a tab's content.
	self.ContentPanel = SGUI:Create( "Panel", self )
	self.ContentPanel:SetPos( Vector( self.TabWidth, 0, 0 ) )
	self.ContentPanel.UseScheme = false

	self.Tabs = {}
	self.NumTabs = 0
end

--Setting the tab width or tab height means we should resize the panels too.
function TabPanel:SetTabWidth( Width )
	self.TabWidth = Width
	self:SetSize( self:GetSize() )

	local Tabs = self.Tabs

	for i = 1, self.NumTabs do
		Tabs[ i ].TabButton:SetSize( Vector( Width, self.TabHeight, 0 ) )
	end
end

function TabPanel:SetTabHeight( Height )
	self.TabHeight = Height
	self:SetSize( self:GetSize() )

	local Tabs = self.Tabs
	for i = 1, self.NumTabs do
		local Button = Tabs[ i ].TabButton
		Button:SetPos( Vector( 0, Height * ( i - 1 ), 0 ) )
		Button:SetSize( Vector( self.TabWidth, Height, 0 ) )
	end
end

function TabPanel:SetSize( Size )
	Controls.Panel.SetSize( self, Size )

	self.TabPanel:SetSize( Vector( self.TabWidth, Size.y, 0 ) )
	self.ContentPanel:SetSize( Vector( Size.x - self.TabWidth, Size.y, 0 ) )
	self.ContentPanel:SetPos( Vector( self.TabWidth, 0, 0 ) )
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
	TabButton:SetSize( Vector( self.TabWidth, self.TabHeight, 0 ) )
	TabButton:SetPos( Vector( 0, self.NumTabs * self.TabHeight, 0 ) )

	if self.Font then
		TabButton:SetFont( self.Font )
	end
	if self.TextScale then
		TabButton:SetTextScale( self.TextScale )
	end

	self.NumTabs = self.NumTabs + 1

	Tabs[ self.NumTabs ] = { Name = Name, TabButton = TabButton, OnPopulate = OnPopulate }

	--We need to start off with the first tab showing.
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

	--In case someone wants to save information about the tab state.
	if not SuppressPre and self.OnPreTabChange and self.NumTabs > 1 then
		self:OnPreTabChange()
	end

	self.ContentPanel:Clear()

	if OnPopulate then
		OnPopulate( self.ContentPanel )
	end

	self.ActiveTab = Index

	--In case someone wants to restore information about the tab state.
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

	self.NumTabs = self.NumTabs - 1

	for i = 1, self.NumTabs do
		local Tab = Tabs[ i ].TabButton

		--These are both in the old index range.
		if Tab.Index == self.ActiveTab then
			self.ActiveTab = i
		end
		--Correct the tab's index.
		Tab.Index = i
		Tab:SetPos( Vector( 0, self.TabHeight * ( i - 1 ), 0 ) )
	end

	--If we removed the active tab, switch to tab 1.
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
