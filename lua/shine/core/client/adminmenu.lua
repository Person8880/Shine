--[[
	Shine admin menu.
]]

local Shine = Shine
local SGUI = Shine.GUI
local Hook = Shine.Hook
local Locale = Shine.Locale

local IsType = Shine.IsType
local StringFormat = string.format

Shine.AdminMenu = {}

local AdminMenu = Shine.AdminMenu

Client.HookNetworkMessage( "Shine_AdminMenu_Open", function( Data )
	AdminMenu:SetIsVisible( true )
end )

AdminMenu.Commands = {}
AdminMenu.Tabs = {}

AdminMenu.Pos = Vector( -400, -300, 0 )
AdminMenu.Size = Vector( 800, 600, 0 )

function AdminMenu:Create()
	self.Created = true

	local Window = SGUI:Create( "TabPanel" )
	Window:SetAnchor( "CentreMiddle" )
	Window:SetPos( self.Pos )
	Window:SetSize( self.Size )

	self.Window = Window

	Window.OnPreTabChange = function( Window )
		if not Window.ActiveTab then return end

		local Tab = Window.Tabs[ Window.ActiveTab ]

		if not Tab then return end

		self:OnTabCleanup( Window, Tab.Name )
	end

	self:PopulateTabs( Window )

	Window:AddCloseButton()
	Window.OnClose = function()
		self:Close()
		return true
	end
end

function AdminMenu:Close()
	self:SetIsVisible( false )

	if self.ToDestroyOnClose then
		for Panel in pairs( self.ToDestroyOnClose ) do
			if Panel:IsValid() then
				Panel:Destroy()
			end

			self.ToDestroyOnClose[ Panel ] = nil
		end
	end
end

function AdminMenu:DestroyOnClose( Object )
	self.ToDestroyOnClose = self.ToDestroyOnClose or {}

	self.ToDestroyOnClose[ Object ] = true
end

function AdminMenu:DontDestroyOnClose( Object )
	if not self.ToDestroyOnClose then return end

	self.ToDestroyOnClose[ Object ] = nil
end

AdminMenu.EasingTime = 0.25

function AdminMenu.AnimateVisibility( Window, Show, Visible, EasingTime, TargetPos )
	if not Show and Shine.Config.AnimateUI then
		Shine.Timer.Simple( EasingTime, function()
			if not SGUI.IsValid( Window ) then return end
			Window:SetIsVisible( false )
		end )
	else
		Window:SetIsVisible( Show )
	end

	if Show and not Visible then
		if Shine.Config.AnimateUI then
			Window:SetPos( Vector2( -Client.GetScreenWidth() + TargetPos.x, TargetPos.y ) )
			Window:MoveTo( nil, nil, TargetPos, 0, EasingTime )
		else
			Window:SetPos( TargetPos )
		end

		SGUI:EnableMouse( true )
	elseif not Show and Visible then
		SGUI:EnableMouse( false )

		if Shine.Config.AnimateUI then
			Window:MoveTo( nil, nil, Vector2( Client.GetScreenWidth() - TargetPos.x, TargetPos.y ), 0,
				EasingTime, nil, math.EaseIn )
		end
	end
end

function AdminMenu:SetIsVisible( Bool )
	if self.Visible == Bool then return end

	--Check if the NS2 HelpScreen is open
	if self._Visible == Bool then return end

	if not self.Created then
		self:Create()
	end

	self.AnimateVisibility( self.Window, Bool, self.Visible, self.EasingTime, self.Pos )
	self.Visible = Bool
end

function AdminMenu:PlayerKeyPress( Key, Down )
	if not self.Visible then return end

	if Key == InputKey.Escape and Down then
		self:Close()

		return true
	end
end

Hook.Add( "PlayerKeyPress", "AdminMenu_KeyPress", function( Key, Down )
	AdminMenu:PlayerKeyPress( Key, Down )
end, 1 )

function AdminMenu:OnHelpScreenDisplay()
	if not self.Visible then return end

	self._Visible = true
	
	self:SetIsVisible( false )
end

function AdminMenu:OnHelpScreenHide()
	if not self._Visible then return end
	
	self._Visible = nil

	self:SetIsVisible( true )
end

Hook.Add( "OnHelpScreenDisplay", "AdminMenu_OnHelpScreenDisplay", function()
	AdminMenu:OnHelpScreenDisplay()
end)

Hook.Add( "OnHelpScreenHide", "AdminMenu_OnHelpScreenHide", function()
	AdminMenu:OnHelpScreenHide()
end)

function AdminMenu:AddTab( Name, Data )
	self.Tabs[ Name ] = Data

	if self.Created then
		local ActiveTab = self.Window:GetActiveTab()
		local Tabs = self.Window.Tabs

		--A bit brute force, but its the easiest way to preserve tab order.
		for i = 1, self.Window.NumTabs do
			self.Window:RemoveTab( 1 )
		end

		self:PopulateTabs( self.Window )

		local WindowTabs = self.Window.Tabs
		for i = 1, #WindowTabs do
			local Tab = WindowTabs[ i ]
			if Tab.Name == ActiveTab.Name then
				Tab.TabButton:DoClick()
				break
			end
		end
	end
end

function AdminMenu:RemoveTab( Name )
	local Data = self.Tabs[ Name ]

	if not Data then return end

	--Remove the actual menu tab.
	if Data.TabObj and SGUI.IsValid( Data.TabObj.TabButton ) then
		self.Window:RemoveTab( Data.TabObj.TabButton.Index )
	end

	self.Tabs[ Name ] = nil
end

function AdminMenu:PopulateTabs( Window )
	local CommandsTab = self.Tabs.Commands
	local AboutTab = self.Tabs.About

	local Tab = Window:AddTab( Locale:GetPhrase( "Core", "ADMIN_MENU_COMMANDS_TAB" ), function( Panel )
		CommandsTab.OnInit( Panel, CommandsTab.Data )
	end )
	CommandsTab.TabObj = Tab

	--Remove them here so they're not in the pairs loop.
	self.Tabs.Commands = nil
	self.Tabs.About = nil

	for Name, Data in SortedPairs( self.Tabs ) do
		local Tab = Window:AddTab( Name, function( Panel )
			Data.OnInit( Panel, Data.Data )
		end )
		Data.TabObj = Tab
	end

	--Add them back.
	self.Tabs.Commands = CommandsTab
	self.Tabs.About = AboutTab

	Tab = Window:AddTab( Locale:GetPhrase( "Core", "ADMIN_MENU_ABOUT_TAB" ), function( Panel )
		AboutTab.OnInit( Panel )
	end )
	AboutTab.TabObj = Tab
end

function AdminMenu:OnTabCleanup( Window, Name )
	local Tab = self.Tabs[ Name ]
	if not Tab then return end

	local OnCleanup = Tab.OnCleanup
	if not OnCleanup then return end

	local Ret = OnCleanup( Window.ContentPanel )
	if Ret then
		Tab.Data = Ret
	end
end

function AdminMenu.GetListState( List )
	local SelectedIndex

	if List.MultiSelect then
		local Selected = List:GetSelectedRows()

		if #Selected > 0 then
			SelectedIndex = {}
			for i = 1, #Selected do
				SelectedIndex[ i ] = Selected[ i ].Index
			end
		end
	else
		local Row = List:GetSelectedRow()
		if Row then
			SelectedIndex = Row.Index
		end
	end

	return {
		SortedColumn = List.SortedColumn,
		Descending = List.Descending,
		SelectedIndex = SelectedIndex
	}
end

function AdminMenu.RestoreListState( List, Data )
	if not Data then return end
	if not Data.SortedColumn and not Data.SelectedIndex then return end

	if Data.SortedColumn then
		List:SortRows( Data.SortedColumn, nil, Data.Descending )
	end

	if Data.SelectedIndex and List.Rows then
		if List.MultiSelect and IsType( Data.SelectedIndex, "table" ) then
			local Selected = Data.SelectedIndex

			for i = 1, #Selected do
				local Row = List.Rows[ Selected[ i ] ]

				if Row then
					Row:SetHighlighted( true, true )
					Row.Selected = true
				end
			end
		elseif not List.MultiSelect and IsType( Data.SelectedIndex, "number" ) then
			local Row = List.Rows[ Data.SelectedIndex ]
			if Row then
				List:OnRowSelect( Data.SelectedIndex, Row )
				Row:SetHighlighted( true, true )
				Row.Selected = true
			end
		end
	end

	return Data.SortedColumn ~= nil
end

--Setup the commands tab.
do
	local GetEnts = Shared.GetEntitiesWithClassname
	local IterateEntList = ientitylist
	local TableEmpty = table.Empty
	local TableFindByField = table.FindByField
	local TableRemove = table.remove
	local TableSort = table.sort

	local Label
	local PlayerList
	local Commands
	local Rows = {}

	local function AddPlayerToList( Ent )
		local Row = Rows[ Ent.clientId ]

		if SGUI.IsValid( Row ) then
			Row:SetColumnText( 1, Ent.playerName )
			Row:SetColumnText( 2, tostring( Ent.steamId ) )
			Row:SetColumnText( 3, Shine:GetTeamName( Ent.teamNumber, true ) )

			return
		end

		Rows[ Ent.clientId ] = PlayerList:AddRow( Ent.playerName, Ent.steamId,
			Shine:GetTeamName( Ent.teamNumber, true ) )
	end

	local function UpdatePlayers()
		local PlayerEnts = GetEnts( "PlayerInfoEntity" )
		local ExistingPlayers = {}

		for _, Ent in IterateEntList( PlayerEnts ) do
			AddPlayerToList( Ent )
			ExistingPlayers[ Ent.clientId ] = true
		end

		for ID, Row in pairs( Rows ) do
			if not ExistingPlayers[ ID ] then
				PlayerList:RemoveRow( Row.Index )
				Rows[ ID ] = nil
			end
		end
	end

	local function GenerateButton( Text, DoClick, Tooltip )
		local Button = SGUI:Create( "Button" )
		Button:SetSize( Vector( 192, 32, 0 ) )
		Button:SetText( Text )
		Button:SetFont( Fonts.kAgencyFB_Small )
		Button.DoClick = function( Button )
			DoClick( Button, PlayerList:GetSelectedRow() )
		end
		Button:SetTooltip( Tooltip )

		return Button
	end

	AdminMenu:AddTab( "Commands", {
		OnInit = function( Panel, Data )
			Label = SGUI:Create( "Label", Panel )
			Label:SetFont( Fonts.kAgencyFB_Small )
			Label:SetText( Locale:GetPhrase( "Core", "ADMIN_MENU_PLAYERS_HELP" ) )
			Label:SetPos( Vector( 16, 24, 0 ) )

			PlayerList = SGUI:Create( "List", Panel )
			PlayerList:SetAnchor( GUIItem.Left, GUIItem.Top )
			PlayerList:SetPos( Vector( 16, 72, 0 ) )
			PlayerList:SetColumns( Locale:GetPhrase( "Core", "NAME" ), "NS2ID",
				Locale:GetPhrase( "Core", "TEAM" ) )
			PlayerList:SetSpacing( 0.45, 0.3, 0.25 )
			PlayerList:SetSize( Vector( 640 - 192 - 16, 512, 0 ) )
			PlayerList:SetNumericColumn( 2 )
			PlayerList:SetMultiSelect( true )
			PlayerList:SetSecondarySortColumn( 3, 1 )
			PlayerList.ScrollPos = Vector( 0, 32, 0 )

			UpdatePlayers()

			Shine.Timer.Create( "AdminMenu_Update", 1, -1, function()
				if not SGUI.IsValid( PlayerList ) then return end

				UpdatePlayers()
			end )

			AdminMenu.RestoreListState( PlayerList, Data )

			Commands = SGUI:Create( "CategoryPanel", Panel )
			Commands:SetAnchor( "TopRight" )
			Commands:SetPos( Vector( -192 -16, 72, 0 ) )
			Commands:SetSize( Vector( 192, 512, 0 ) )

			local Categories = AdminMenu.Commands

			TableSort( Categories, function( A, B )
				return A.Name < B.Name
			end )

			for i = 1, #Categories do
				local Category = Categories[ i ]
				local Name = Category.Name
				local CommandList = Category.Commands

				Commands:AddCategory( Name )

				for j = 1, #CommandList do
					local CommandData = CommandList[ j ]
					local Command = CommandData.Name
					local DoClick = CommandData.DoClick
					local Tooltip = CommandData.Tooltip

					Commands:AddObject( Name, GenerateButton( Command, DoClick, Tooltip ) )
				end
			end

			if Data and Data.CommandExpansions then
				for Category, Expanded in pairs( Data.CommandExpansions ) do
					if not Expanded then
						Commands:ContractCategory( Category )
					end
				end
			end
		end,

		OnCleanup = function( Panel )
			--Save column sorting, and command category expansions.
			local Data = AdminMenu.GetListState( PlayerList )
			--Don't save selected players as the order/list can easily change.
			Data.SelectedIndex = nil
			Data.CommandExpansions = {}

			local Categories = Commands.Categories

			for i = 1, Commands.NumCategories do
				local Category = Categories[ i ]

				Data.CommandExpansions[ Category.Name ] = Category.Expanded
			end

			Label = nil
			PlayerList = nil
			Commands = nil

			TableEmpty( Rows )

			Shine.Timer.Destroy( "AdminMenu_Update" )

			return Data
		end
	} )

	function AdminMenu:RunCommand( Command, Args )
		if not Args then
			Shared.ConsoleCommand( Command )
		else
			Shared.ConsoleCommand( StringFormat( "%s %s", Command, Args ) )
		end
	end

	function AdminMenu:AskForSinglePlayer()
		local Window = SGUI:Create( "Panel" )
		Window:SetAnchor( "CentreMiddle" )
		Window:SetSize( Vector( 400, 200, 0 ) )
		Window:SetPos( Vector( -200, -100, 0 ) )

		Window:AddTitleBar( Locale:GetPhrase( "Core", "ERROR" ) )

		self:DestroyOnClose( Window )

		function Window.CloseButton.DoClick()
			self:DontDestroyOnClose( Window )
			Window:Destroy()
		end

		local Label = SGUI:Create( "Label", Window )
		Label:SetAnchor( "CentreMiddle" )
		Label:SetFont( Fonts.kAgencyFB_Small )
		Label:SetText( Locale:GetPhrase( "Core", "ADMIN_MENU_SELECT_SINGLE_PLAYER" ) )
		Label:SetPos( Vector( 0, -40, 0 ) )
		Label:SetTextAlignmentX( GUIItem.Align_Center )
		Label:SetTextAlignmentY( GUIItem.Align_Center )

		local OK = SGUI:Create( "Button", Window )
		OK:SetAnchor( "CentreMiddle" )
		OK:SetSize( Vector( 128, 32, 0 ) )
		OK:SetPos( Vector( -64, 40, 0 ) )
		OK:SetFont( Fonts.kAgencyFB_Small )
		OK:SetText( Locale:GetPhrase( "Core", "OK" ) )

		function OK.DoClick()
			self:DontDestroyOnClose( Window )
			Window:Destroy()
		end
	end

	local function GetArgsFromRows( Rows, MultiPlayer )
		if MultiPlayer then
			return Shine.Stream( Rows ):Concat( ",", function( Row )
				return Row:GetColumnText( 2 )
			end )
		end

		return Rows[ 1 ]:GetColumnText( 2 )
	end

	function AdminMenu:AddCommand( Category, Name, Command, MultiPlayer, DoClick, Tooltip )
		if not DoClick then
			DoClick = function( Button, Rows )
				if #Rows == 0 then return end

				if not MultiPlayer and #Rows > 1 then
					self:AskForSinglePlayer()
					return
				end

				self:RunCommand( Command, GetArgsFromRows( Rows, MultiPlayer ) )
			end
		elseif IsType( DoClick, "table" ) then
			local Data = DoClick

			local Menu
			local function CleanupMenu()
				self:DontDestroyOnClose( Menu )
				Menu:Destroy()
				Menu = nil
			end
			DoClick = function( Button, Rows )
				if #Rows == 0 then return end

				if Menu then
					CleanupMenu()
					return
				end

				if not MultiPlayer and #Rows > 1 then
					self:AskForSinglePlayer()
					return
				end

				local Args = GetArgsFromRows( Rows, MultiPlayer )

				Menu = Button:AddMenu( Vector( Data.Width or 144, Data.ButtonHeight or 32, 0 ) )
				Menu:CallOnRemove( function()
					Menu = nil
				end )
				self:DestroyOnClose( Menu )

				for i = 1, #Data, 2 do
					local Option = Data[ i ]
					local Arg = Data[ i + 1 ]

					if IsType( Arg, "string" ) then
						Menu:AddButton( Option, function()
							if Arg == "" then
								self:RunCommand( Command, Args )
							else
								self:RunCommand( Command, StringFormat( "%s %s", Args, Arg ) )
							end

							CleanupMenu()
						end )
					elseif IsType( Arg, "function" ) then
						Menu:AddButton( Option, function()
							Arg()
							CleanupMenu()
						end )
					elseif IsType( Arg, "table" ) and Arg.Setup then
						Arg.Setup( Menu, Command, Args, CleanupMenu )
					end
				end
			end
		end

		local Categories = self.Commands
		local CategoryObj = TableFindByField( Categories, "Name", Category )
		local ShouldAdd

		if not CategoryObj then
			CategoryObj = {
				Name = Category,
				Commands = {}
			}

			Categories[ #Categories + 1 ] = CategoryObj

			ShouldAdd = true
		end

		local CommandsList = CategoryObj.Commands

		CommandsList[ #CommandsList + 1 ] = { Name = Name, DoClick = DoClick, Tooltip = Tooltip }

		if Commands then
			if ShouldAdd then
				Commands:AddCategory( Category )
			end

			Commands:AddObject( Category, GenerateButton( Name, DoClick, Tooltip ) )
		end
	end

	function AdminMenu:RemoveCommandCategory( Category )
		local Categories = self.Commands
		local Obj, Index = TableFindByField( Categories, "Name", Category )
		if not Index then return end

		TableRemove( Categories, Index )

		if SGUI.IsValid( Commands ) then
			Commands:RemoveCategory( Category )
		end
	end
end

do
-- Apparently labels have a character limit.
local Text = {
[[Shine was created by Person8880.

Special thanks to:
- Ghoul for being the first major plugin author and helping with pull requests.
- Lance Hilliard for also helping with pull requests.
- DePara for being the first server admin to use Shine.
- You for using my mod and therefore reading this text!

Got an issue or a feature request? Head over to the mod's GitHub page and post an
issue, or leave a comment on the workshop page.
]],
[[The mod's GitHub issue tracker can be found here:]],
{
	Text = [[https://github.com/Person8880/Shine/issues]],
	StyleName = "Link",
	DoClick = function( self )
		Client.ShowWebpage( self:GetText() )
	end
},
[[

If you need help with how the mod functions, you can view the wiki by clicking the button
below. If you want to get to it outside the game, visit:]],
{
	Text = [[https://github.com/Person8880/Shine/wiki]],
	StyleName = "Link",
	DoClick = function( self )
		Client.ShowWebpage( self:GetText() )
	end
}
}

	local Units = SGUI.Layout.Units
	local Percentage = Units.Percentage
	local Spacing = Units.Spacing
	local UnitVector = Units.UnitVector

	AdminMenu:AddTab( "About", {
		OnInit = function( Panel )
			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( 16, 24, 16, 24 )
			} )
			Panel:SetLayout( Layout )

			for i = 1, #Text do
				local Label = SGUI:Create( "Label", Panel )
				Label:SetFont( Fonts.kAgencyFB_Small )

				local LabelText = Text[ i ]
				if IsType( LabelText, "string" ) then
					Label:SetText( LabelText )
				else
					Label:SetText( LabelText.Text )
					Label:SetStyleName( LabelText.StyleName )
					Label.DoClick = LabelText.DoClick
				end
				Layout:AddElement( Label )
			end

			local HomeButton = SGUI:Create( "Button", Panel )
			HomeButton:SetAutoSize( UnitVector( Percentage( 100 ), 32 ) )
			HomeButton:SetAlignment( SGUI.LayoutAlignment.MAX )
			HomeButton:SetFont( Fonts.kAgencyFB_Small )
			HomeButton:SetText( Locale:GetPhrase( "Core", "ADMIN_MENU_OPEN_WIKI" ) )
			function HomeButton:DoClick()
				Shine:OpenWebpage( "https://github.com/Person8880/Shine/wiki", "Shine Wiki" )
			end

			Layout:AddElement( HomeButton )
			Panel:InvalidateLayout( true )
		end,

		OnCleanup = function( Panel )

		end
	} )
end