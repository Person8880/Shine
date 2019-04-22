--[[
	Shine admin menu.
]]

local Shine = Shine
local SGUI = Shine.GUI
local Hook = Shine.Hook
local Locale = Shine.Locale

local Units = SGUI.Layout.Units
local Percentage = Units.Percentage
local Spacing = Units.Spacing
local UnitVector = Units.UnitVector
local HighResScaled = Units.HighResScaled

local IsType = Shine.IsType
local StringFormat = string.format

Shine.AdminMenu = {}

local AdminMenu = Shine.AdminMenu
SGUI:AddMixin( AdminMenu, "Visibility" )

Client.HookNetworkMessage( "Shine_AdminMenu_Open", function( Data )
	local WasVisible = AdminMenu.Visible
	AdminMenu:Show()
	if not WasVisible and AdminMenu.Visible then
		Hook.Call( "OnAdminMenuOpened", AdminMenu )
	end
end )

AdminMenu.Commands = {}
AdminMenu.Tabs = {}

AdminMenu.DefaultSize = Vector( 930, 700, 0 )

function AdminMenu:Create()
	self.Created = true

	local Window = SGUI:Create( "TabPanel" )
	Window:SetAnchor( "CentreMiddle" )

	local Size = HighResScaled( self.DefaultSize ):GetValue()
	self.Size = Size
	self.Pos = -Size * 0.5

	Window:SetSize( Size )
	Window:SetPos( self.Pos )

	Window:SetTabWidth( HighResScaled( 128 ):GetValue() )
	Window:SetTabHeight( HighResScaled( 96 ):GetValue() )
	Window:SetFontScale( SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 ) )

	Window:CallOnRemove( function()
		if self.IgnoreRemove then return end

		if self.Visible then
			-- Make sure mouse is disabled in case of error.
			SGUI:EnableMouse( false )
			self.Visible = false
		end

		self.Created = false
		self.Window = nil
	end )

	Window:SetExpanded( Shine.Config.ExpandAdminMenuTabs )
	Window:AddPropertyChangeListener( "Expanded", function( Expanded )
		Shine:SetClientSetting( "ExpandAdminMenuTabs", Expanded )
	end )

	self.Window = Window

	Window.OnPreTabChange = function( Window )
		if not Window.ActiveTab then return end

		local Tab = Window.Tabs[ Window.ActiveTab ]

		if not Tab then return end

		self:OnTabCleanup( Window, Tab.Name )
	end

	Window.TitleBarHeight = HighResScaled( 24 ):GetValue()
	self:PopulateTabs( Window )

	Window:AddCloseButton()
	Window.OnClose = function()
		self:Close()
		return true
	end
end

function AdminMenu:Close( Now )
	if not self.Visible then return end

	self:ForceHide( Now )

	if self.ToDestroyOnClose then
		for Panel in pairs( self.ToDestroyOnClose ) do
			if Panel:IsValid() then
				Panel:Destroy()
			end

			self.ToDestroyOnClose[ Panel ] = nil
		end
	end

	Hook.Call( "OnAdminMenuClosed", self )
end

Shine.Hook.Add( "OnResolutionChanged", "AdminMenu_OnResolutionChanged", function()
	if not AdminMenu.Created then return end

	-- Close and destroy the menu, it'll be scaled correctly the next time it opens.
	AdminMenu:Close( true )
	AdminMenu.IgnoreRemove = true
	AdminMenu.Window:Destroy()
	AdminMenu.IgnoreRemove = false
	AdminMenu.Window = nil
	AdminMenu.Created = false
end )

function AdminMenu:DestroyOnClose( Object )
	self.ToDestroyOnClose = self.ToDestroyOnClose or {}

	self.ToDestroyOnClose[ Object ] = true
end

function AdminMenu:DontDestroyOnClose( Object )
	if not self.ToDestroyOnClose then return end

	self.ToDestroyOnClose[ Object ] = nil
end

AdminMenu.EasingTime = 0.25

function AdminMenu.AnimateVisibility( Window, Show, Visible, EasingTime, TargetPos, IgnoreAnim )
	local IsAnimated = Shine.Config.AnimateUI and not IgnoreAnim

	if not Show and IsAnimated then
		Shine.Timer.Simple( EasingTime, function()
			if not SGUI.IsValid( Window ) then return end
			Window:SetIsVisible( false )
		end )
	else
		Window:SetIsVisible( Show )
	end

	if Show and not Visible then
		if IsAnimated then
			Window:SetPos( Vector2( -Client.GetScreenWidth() + TargetPos.x, TargetPos.y ) )
			Window:MoveTo( nil, nil, TargetPos, 0, EasingTime )
		else
			Window:SetPos( TargetPos )
		end

		SGUI:EnableMouse( true )
	elseif not Show and Visible then
		SGUI:EnableMouse( false )

		if IsAnimated then
			Window:MoveTo( nil, nil, Vector2( Client.GetScreenWidth() - TargetPos.x, TargetPos.y ), 0,
				EasingTime, nil, math.EaseIn )
		end
	end
end

function AdminMenu:SetIsVisible( Bool, IgnoreAnim )
	if not self.Created then
		self:Create()
	end

	self.AnimateVisibility( self.Window, Bool, self.Visible, self.EasingTime, self.Pos, IgnoreAnim )
	self.Visible = Bool
end

function AdminMenu:GetIsVisible()
	return self.Visible or false
end

AdminMenu:BindVisibilityToEvents( "OnHelpScreenDisplay", "OnHelpScreenHide" )

function AdminMenu:PlayerKeyPress( Key, Down )
	if not self.Visible then return end

	if ( Key == InputKey.Escape or GetIsBinding( Key, "Use" ) ) and Down then
		self:Close()

		return Key == InputKey.Escape or nil
	end
end

Hook.Add( "PlayerKeyPress", "AdminMenu_KeyPress", function( Key, Down )
	return AdminMenu:PlayerKeyPress( Key, Down )
end, 1 )

-- Close when logging in/out of a command structure to avoid mouse problems.
Hook.Add( "OnCommanderLogout", "AdminMenuLogout", function()
	AdminMenu:Close()
end )
Hook.Add( "OnCommanderLogin", "AdminMenuLogin", function()
	AdminMenu:Close()
end )

function AdminMenu:AddTab( Name, Data )
	self.Tabs[ Name ] = Data

	if self.Created then
		local ActiveTab = self.Window:GetActiveTab()
		local Tabs = self.Window.Tabs

		-- A bit brute force, but its the easiest way to preserve tab order.
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
	end, SGUI.Icons.Ionicons.CodeWorking )
	CommandsTab.TabObj = Tab

	-- Remove them here so they're not in the pairs loop.
	self.Tabs.Commands = nil
	self.Tabs.About = nil

	for Name, Data in SortedPairs( self.Tabs ) do
		local Tab = Window:AddTab( Name, function( Panel )
			Data.OnInit( Panel, Data.Data )
		end, Data.Icon )
		Data.TabObj = Tab
	end

	-- Add them back.
	self.Tabs.Commands = CommandsTab
	self.Tabs.About = AboutTab

	Tab = Window:AddTab( Locale:GetPhrase( "Core", "ADMIN_MENU_ABOUT_TAB" ), function( Panel )
		AboutTab.OnInit( Panel )
	end, SGUI.Icons.Ionicons.HelpCircled )
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

function AdminMenu.SetupListWithScaling( List )
	List:SetLineSize( HighResScaled( 32 ):GetValue() )
	List:SetHeaderSize( List.LineSize )

	local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )
	List:SetHeaderFontScale( Font, Scale )
	List:SetRowFontScale( Font, Scale )

	List:SetScrollbarWidth( HighResScaled( 10 ):GetValue() )
end

-- Setup the commands tab.
do
	local GetEnts = Shared.GetEntitiesWithClassname
	local IterateEntList = ientitylist
	local StringGSub = string.gsub
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

	local function GenerateButton( Data )
		local Button = SGUI:Create( "Button" )
		Button:SetText( Data.Name )
		Button.DoClick = function( Button )
			Data.DoClick( Button, PlayerList:GetSelectedRow() )
		end
		Button:SetTooltip( Data.Tooltip )
		Button.MultiPlayer = Data.MultiPlayer

		local NumSelected = #PlayerList:GetSelectedRows()
		if NumSelected == 0 or NumSelected > 1 and not Data.MultiPlayer then
			Button:SetEnabled( false )
		end

		return Button
	end

	AdminMenu:AddTab( "Commands", {
		OnInit = function( Panel, Data )
			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( HighResScaled( 16 ), HighResScaled( 24 ),
					HighResScaled( 16 ), HighResScaled( 16 ) )
			} )

			local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )

			Label = SGUI:Create( "Label", Panel )
			Label:SetFontScale( Font, Scale )
			Label:SetText( Locale:GetPhrase( "Core", "ADMIN_MENU_PLAYERS_HELP" ) )
			Label:SetMargin( Spacing( 0, 0, 0, HighResScaled( 8 ) ) )
			Layout:AddElement( Label )

			local CommandLayout = SGUI.Layout:CreateLayout( "Horizontal", {} )

			PlayerList = SGUI:Create( "List", Panel )
			PlayerList:SetColumns( Locale:GetPhrase( "Core", "NAME" ), "NS2ID",
				Locale:GetPhrase( "Core", "TEAM" ) )
			PlayerList:SetSpacing( 0.45, 0.3, 0.25 )
			PlayerList:SetNumericColumn( 2 )
			PlayerList:SetMultiSelect( true )
			PlayerList:SetFill( true )
			PlayerList:SetSecondarySortColumn( 3, 1 )

			AdminMenu.SetupListWithScaling( PlayerList )

			PlayerList:SetMargin( Spacing( 0, 0, HighResScaled( 16 ), 0 ) )

			CommandLayout:AddElement( PlayerList )

			local ButtonHeight = Units.Auto() + HighResScaled( 6 )

			Commands = SGUI:Create( "CategoryPanel", Panel )
			Commands:SetCategoryHeight( HighResScaled( 24 ) )
			CommandLayout:AddElement( Commands )

			local Width = Units.Max()
			local Categories = AdminMenu.Commands

			TableSort( Categories, function( A, B )
				return A.Name < B.Name
			end )

			for i = 1, #Categories do
				local Category = Categories[ i ]
				local Name = Category.Name
				local CommandList = Category.Commands

				local CategoryButton = Commands:AddCategory( Name )
				CategoryButton:SetFontScale( Font, Scale )

				Width:AddValue( Units.Auto( CategoryButton ) + HighResScaled( 8 ) )

				for j = 1, #CommandList do
					local CommandData = CommandList[ j ]

					local Button = GenerateButton( CommandData )
					Button:SetFontScale( Font, Scale )
					Button:SetAutoSize( UnitVector( Percentage( 100 ), ButtonHeight ) )

					Width:AddValue( Units.Auto( Button ) + HighResScaled( 8 ) )
					Commands:AddObject( Name, Button )
				end
			end

			if Data and Data.CommandExpansions then
				for Category, Expanded in pairs( Data.CommandExpansions ) do
					if not Expanded then
						Commands:ContractCategory( Category )
					end
				end
			end

			Commands:SetAutoSize( UnitVector( Width, Percentage( 100 ) ) )

			function PlayerList:OnSelectionChanged( Rows )
				local Buttons = Commands:GetAllObjects()
				local NumRows = #Rows

				for i = 1, #Buttons do
					local Button = Buttons[ i ]
					Button:SetEnabled( NumRows > 0 and ( NumRows == 1 or Button.MultiPlayer ) )
				end
			end

			Layout:AddElement( CommandLayout )

			Panel:SetLayout( Layout )
			Panel:InvalidateLayout( true )

			if not AdminMenu.RestoreListState( PlayerList, Data ) then
				PlayerList:SortRows( 3 )
			end

			UpdatePlayers()

			Shine.Timer.Create( "AdminMenu_Update", 1, -1, function()
				if not SGUI.IsValid( PlayerList ) then return end

				UpdatePlayers()
			end )

			-- Forget selection when the admin menu is closed.
			Hook.Add( "OnAdminMenuClosed", "AdminMenu_CommandsTab", function()
				if not SGUI.IsValid( PlayerList ) then return end
				PlayerList:ResetSelection()
			end )
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
			Hook.Remove( "OnAdminMenuClosed", "AdminMenu_CommandsTab" )

			return Data
		end
	} )

	local TableConcat = table.concat
	function AdminMenu:RunCommand( Command, ... )
		if not ... then
			Shared.ConsoleCommand( Command )
		else
			Shared.ConsoleCommand( StringFormat( "%s %s", Command, TableConcat( { ... }, " " ) ) )
		end
	end

	local function GetArgFromRow( Row )
		local SteamID = Row:GetColumnText( 2 )
		if SteamID == "0" then
			-- It's a bot, so we need to use their name to target them.
			return StringGSub( Row:GetColumnText( 1 ), "\"", "\\\"" )
		end
		return SteamID
	end

	local function GetArgsFromRows( Rows, MultiPlayer )
		if MultiPlayer then
			return StringFormat( "\"%s\"", Shine.Stream( Rows ):Concat( ",", GetArgFromRow ) )
		end

		return StringFormat( "\"%s\"", GetArgFromRow( Rows[ 1 ] ) )
	end

	function AdminMenu:AddCommand( Category, Name, Command, MultiPlayer, DoClick, Tooltip )
		if not DoClick then
			DoClick = function( Button, Rows )
				if #Rows == 0 then return end

				if not MultiPlayer and #Rows > 1 then
					return
				end

				self:RunCommand( Command, GetArgsFromRows( Rows, MultiPlayer ) )
			end
		elseif IsType( DoClick, "function" ) then
			local OldDoClick = DoClick
			DoClick = function( Button, Rows )
				if #Rows == 0 then return end

				if not MultiPlayer and #Rows > 1 then
					return
				end

				OldDoClick( Button, Shine.Stream.Of( Rows ):Map( function( Row )
					return Row:GetColumnText( 2 )
				end ):AsTable() )
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
					return
				end

				local Args = GetArgsFromRows( Rows, MultiPlayer )

				Menu = Button:AddMenu( Vector2(
					HighResScaled( Data.Width or 144 ):GetValue(),
					HighResScaled( Data.ButtonHeight or 32 ):GetValue()
				) )
				Menu:CallOnRemove( function()
					Menu = nil
				end )
				self:DestroyOnClose( Menu )

				local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )
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
						end ):SetFontScale( Font, Scale )
					elseif IsType( Arg, "function" ) then
						Menu:AddButton( Option, function()
							Arg( Args )
							CleanupMenu()
						end ):SetFontScale( Font, Scale )
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
		local Data = {
			Name = Name,
			DoClick = DoClick,
			Tooltip = Tooltip,
			MultiPlayer = MultiPlayer
		}

		CommandsList[ #CommandsList + 1 ] = Data

		if Commands then
			if ShouldAdd then
				Commands:AddCategory( Category )
			end

			Commands:AddObject( Category, GenerateButton( Data ) )
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

	AdminMenu:AddTab( "About", {
		OnInit = function( Panel )
			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( HighResScaled( 16 ), HighResScaled( 24 ),
					HighResScaled( 16 ), HighResScaled( 24 ) )
			} )
			Panel:SetLayout( Layout )

			local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )

			for i = 1, #Text do
				local Label = SGUI:Create( "Label", Panel )
				Label:SetFontScale( Font, Scale )

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
			HomeButton:SetAutoSize( UnitVector( Percentage( 100 ), Units.Auto() + HighResScaled( 8 ) ) )
			HomeButton:SetAlignment( SGUI.LayoutAlignment.MAX )
			HomeButton:SetFontScale( Font, Scale )
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


