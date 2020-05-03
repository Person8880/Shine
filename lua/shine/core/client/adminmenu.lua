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
local TableSort = table.sort

Shine.AdminMenu = {}

local AdminMenu = Shine.AdminMenu
SGUI:AddMixin( AdminMenu, "Visibility" )

do
	local ErrorHandler = Shine.BuildErrorHandler( "Admin menu creation error" )
	local xpcall = xpcall

	Shine.HookNetworkMessage( "Shine_AdminMenu_Open", function( Data )
		local WasVisible = AdminMenu.Visible
		if xpcall( AdminMenu.Show, ErrorHandler, AdminMenu ) and not WasVisible and AdminMenu.Visible then
			Hook.Broadcast( "OnAdminMenuOpened", AdminMenu )
		end
	end )
end

AdminMenu.SystemTabPosition = table.AsEnum{
	"START", "END"
}

AdminMenu.Commands = {}
AdminMenu.Tabs = {}
AdminMenu.SystemTabs = {}
for i = 1, #AdminMenu.SystemTabPosition do
	AdminMenu.SystemTabs[ AdminMenu.SystemTabPosition[ i ] ] = {}
end

AdminMenu.DefaultSize = Vector( 930, 700, 0 )

function AdminMenu:Create()
	self.Created = true

	local Window = SGUI:Create( "TabPanel" )
	Window:SetDebugName( "AdminMenuWindow" )
	Window:SetAnchor( "CentreMiddle" )

	local Size = Vector2(
		Units.Integer( HighResScaled( self.DefaultSize.x ) ):GetValue(),
		Units.Integer( HighResScaled( self.DefaultSize.y ) ):GetValue()
	)

	self.Size = Size
	self.Pos = -Size * 0.5

	Window:SetSize( Size )
	Window:SetPos( self.Pos )

	Window:SetTabWidth( Units.Integer( HighResScaled( 128 ) ):GetValue() )
	Window:SetTabHeight( Units.Integer( HighResScaled( 88 ) ):GetValue() )
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
	Window:AddPropertyChangeListener( "Expanded", function( Window, Expanded )
		Shine:SetClientSetting( "ExpandAdminMenuTabs", Expanded )
	end )

	self.Window = Window

	Window.OnPreTabChange = function( Window )
		local Tab = Window:GetActiveTab()
		if not Tab then return end

		self:OnTabCleanup( Window, Tab )
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

	Hook.Broadcast( "OnAdminMenuClosed", self )
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

local function RefreshTabsIfNeeded( self )
	if not self.Created then return end

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

--[[
	Adds a standard tab to the admin menu.

	This should be used by plugins and anything that may wish to later remove the tab.
]]
function AdminMenu:AddTab( Name, TabDefinition )
	self.Tabs[ Name ] = TabDefinition
	RefreshTabsIfNeeded( self )
end

--[[
	Adds a system tab to the admin menu.

	System tabs are permanent and cannot be removed. They also position themselves around the dynamic tabs to remain
	in a fixed position (either at the start or end of the tab list).
]]
function AdminMenu:AddSystemTab( Name, TabDefinition )
	local Tabs = self.SystemTabs[ TabDefinition.Position or self.SystemTabPosition.END ]
	Shine.AssertAtLevel( Tabs, "Unknown system tab position type: %s", 3, TabDefinition.Position )

	Tabs[ #Tabs + 1 ] = { Name = Name, TabDefinition = TabDefinition }

	TableSort( Tabs, function( A, B )
		local LeftPrecedence = A.TabDefinition.Precedence or 0
		local RightPrecedence = B.TabDefinition.Precedence or 0

		if LeftPrecedence == RightPrecedence then
			return A.Name < B.Name
		end

		return LeftPrecedence < RightPrecedence
	end )

	RefreshTabsIfNeeded( self )
end

function AdminMenu:RemoveTab( Name )
	local TabDefinition = self.Tabs[ Name ]
	if not TabDefinition then return end

	-- Remove the actual menu tab.
	if TabDefinition.TabObj and SGUI.IsValid( TabDefinition.TabObj.TabButton ) then
		self.Window:RemoveTab( TabDefinition.TabObj.TabButton.Index )
	end

	self.Tabs[ Name ] = nil
end

local function AddTab( Window, Name, TabDefinition )
	local DisplayName = Name
	if TabDefinition.TranslationKey then
		DisplayName = Locale:GetPhrase( TabDefinition.TranslationSource or "Core", TabDefinition.TranslationKey )
	end

	local Tab = Window:AddTab( DisplayName, function( Panel )
		TabDefinition.OnInit( Panel, TabDefinition.Data )
		TabDefinition.Initialised = true
	end, TabDefinition.Icon )

	Tab.TabButton:SetDebugName( StringFormat( "AdminMenu%sTab", Name ) )

	TabDefinition.TabObj = Tab
	Tab.TabDefinition = TabDefinition
end

function AdminMenu:PopulateTabs( Window )
	local CommandsTab = self.Tabs.Commands
	local AboutTab = self.Tabs.About

	local StartTabs = self.SystemTabs[ self.SystemTabPosition.START ]
	for i = 1, #StartTabs do
		local Tab = StartTabs[ i ]
		AddTab( Window, Tab.Name, Tab.TabDefinition )
	end

	for Name, TabDefinition in SortedPairs( self.Tabs ) do
		AddTab( Window, Name, TabDefinition )
	end

	local EndTabs = self.SystemTabs[ self.SystemTabPosition.END ]
	for i = 1, #EndTabs do
		local Tab = EndTabs[ i ]
		AddTab( Window, Tab.Name, Tab.TabDefinition )
	end
end

function AdminMenu:OnTabCleanup( Window, Tab )
	local TabDefinition = Tab.TabDefinition
	if not TabDefinition or not TabDefinition.Initialised then return end

	local OnCleanup = TabDefinition.OnCleanup
	if not OnCleanup then return end

	local Ret = OnCleanup( Window.ContentPanel )
	if Ret then
		TabDefinition.Data = Ret
	end
	TabDefinition.Initialised = false
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
	local CommandsListWidth
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

	local ButtonHeight = Units.Auto() + HighResScaled( 6 )
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

	local function GetFontScale()
		return SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )
	end

	local function AddCommandButton( Category, CommandData, Font, Scale )
		local Button = GenerateButton( CommandData )
		Button:SetFontScale( Font, Scale )
		Button:SetAutoSize( UnitVector( Percentage( 100 ), ButtonHeight ) )

		local Width = Units.Auto( Button ) + HighResScaled( 8 )
		CommandsListWidth:AddValue( Width )

		Button:CallOnRemove( function()
			if not CommandsListWidth then return end

			-- If the commands tab is visible (i.e. a plugin has been disabled while it's open), remove this unit from
			-- the max width to avoid referencing the destroyed button at layout time.
			CommandsListWidth:RemoveValue( Width )
		end )

		return Commands:AddObject( Category, Button )
	end

	AdminMenu:AddSystemTab( "Commands", {
		TranslationKey = "ADMIN_MENU_COMMANDS_TAB",
		Icon = SGUI.Icons.Ionicons.CodeWorking,
		Position = AdminMenu.SystemTabPosition.START,
		-- Always place this tab at the very start.
		Precedence = -math.huge,
		OnInit = function( Panel, Data )
			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( HighResScaled( 16 ), HighResScaled( 24 ),
					HighResScaled( 16 ), HighResScaled( 16 ) )
			} )

			local Font, Scale = GetFontScale()

			Label = SGUI:Create( "Label", Panel )
			Label:SetFontScale( Font, Scale )
			Label:SetText( Locale:GetPhrase( "Core", "ADMIN_MENU_PLAYERS_HELP" ) )
			Label:SetMargin( Spacing( 0, 0, 0, HighResScaled( 8 ) ) )
			Layout:AddElement( Label )

			local CommandLayout = SGUI.Layout:CreateLayout( "Horizontal", {} )

			PlayerList = SGUI:Create( "List", Panel )
			PlayerList:SetDebugName( "AdminMenuCommandsTabPlayerList" )
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

			Commands = SGUI:Create( "CategoryPanel", Panel )
			Commands:SetDebugName( "AdminMenuCommandsTabCommandPanel" )
			-- Note that due to cropping, anything with a negative y-coordinate is not rendered at all.
			-- Thus this value must be greater-equal the font size.
			Commands:SetCategoryHeight( HighResScaled( 28 ) )
			CommandLayout:AddElement( Commands )

			CommandsListWidth = Units.Max( HighResScaled( 192 ) )
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

				local Width = Units.Auto( CategoryButton ) + HighResScaled( 8 )
				CommandsListWidth:AddValue( Width )
				CategoryButton:CallOnRemove( function()
					if not CommandsListWidth then return end

					CommandsListWidth:RemoveValue( Width )
				end )

				for j = 1, #CommandList do
					local CommandData = CommandList[ j ]
					CommandData.Button = AddCommandButton( Name, CommandData, Font, Scale )
				end
			end

			if Data and Data.CommandExpansions then
				for Category, Expanded in pairs( Data.CommandExpansions ) do
					if not Expanded then
						Commands:ContractCategory( Category )
					end
				end
			end

			Commands:SetAutoSize( UnitVector( CommandsListWidth, Percentage( 100 ) ) )

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
			CommandsListWidth = nil

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
			Command = Command,
			Name = Name,
			DoClick = DoClick,
			Tooltip = Tooltip,
			MultiPlayer = MultiPlayer
		}

		CommandsList[ #CommandsList + 1 ] = Data

		if SGUI.IsValid( Commands ) then
			if ShouldAdd then
				Commands:AddCategory( Category )
			end

			Data.Button = AddCommandButton( Category, Data, GetFontScale() )
			Commands.Parent:InvalidateLayout()
		end
	end

	function AdminMenu:RemoveCommand( Category, Command )
		local Categories = self.Commands
		local CategoryObj = TableFindByField( Categories, "Name", Category )
		if not CategoryObj then return false end

		local CommandEntry, Index = TableFindByField( CategoryObj.Commands, "Command", Command )
		if not Index then return false end

		TableRemove( CategoryObj.Commands, Index )

		if #CategoryObj.Commands == 0 then
			return self:RemoveCommandCategory( Category )
		end

		if SGUI.IsValid( Commands ) then
			Commands:RemoveObject( Category, CommandEntry.Button )
			Commands.Parent:InvalidateLayout()
		end

		return true
	end

	function AdminMenu:RemoveCommandCategory( Category )
		local Categories = self.Commands
		local Obj, Index = TableFindByField( Categories, "Name", Category )
		if not Index then return false end

		TableRemove( Categories, Index )

		if SGUI.IsValid( Commands ) then
			Commands:RemoveCategory( Category )
		end

		return true
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

	AdminMenu:AddSystemTab( "About", {
		TranslationKey = "ADMIN_MENU_ABOUT_TAB",
		Icon = SGUI.Icons.Ionicons.HelpCircled,
		Position = AdminMenu.SystemTabPosition.END,
		-- Always place this tab at the very end.
		Precedence = math.huge,
		OnInit = function( Panel )
			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( HighResScaled( 16 ), HighResScaled( 24 ),
					HighResScaled( 16 ), HighResScaled( 16 ) )
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


