--[[
	Bans client.
]]

local Plugin = ...

Plugin.AdminTab = "Bans"

Plugin.BanCommand = "sh_banid"
Plugin.UnbanCommand = "sh_unban"

local SGUI = Shine.GUI

local Date = os.date
local Min = math.min
local StringFormat = string.format
local StringTimeToString = string.TimeToString
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableRemove = table.remove
local tonumber = tonumber

function Plugin:Initialise()
	self:SetupAdminMenu()

	self.Enabled = true

	return true
end

local function GetDurationLabel( self, Permanent, UnbanTime )
	return Permanent and self:GetPhrase( "NEVER" ) or Date( self:GetPhrase( "DATE_FORMAT" ), UnbanTime )
end

function Plugin:SetupAdminMenu()
	local Units = SGUI.Layout.Units
	local HighResScaled = Units.HighResScaled
	local Percentage = Units.Percentage
	local Spacing = Units.Spacing
	local UnitVector = Units.UnitVector
	local Auto = Units.Auto

	local Window
	local function OpenAddBanWindow( SteamIDToBan )
		if SGUI.IsValid( Window ) then
			SGUI:SetWindowFocus( Window )
			if SteamIDToBan then
				Window.IDEntry:SetText( SteamIDToBan )
			end

			return
		end

		local Layout = SGUI.Layout:CreateLayout( "Vertical", {
			Padding = Spacing( HighResScaled( 16 ), HighResScaled( 32 ),
				HighResScaled( 16 ), HighResScaled( 16 ) )
		} )

		local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )

		Window = SGUI:Create( "Panel" )
		Window:SetAnchor( "CentreMiddle" )
		Window:SetSize( Vector2( HighResScaled( 400 ):GetValue(), HighResScaled( 328 ):GetValue() ) )
		Window:SetPos( -Window:GetSize() * 0.5 )
		Window.TitleBarHeight = HighResScaled( 28 ):GetValue()
		Window:AddTitleBar( self:GetPhrase( "ADD_BAN_TITLE" ), Font, Scale )
		Window:SetDraggable( true )

		function Window.CloseButton.DoClick()
			Shine.AdminMenu:DontDestroyOnClose( Window )
			Window:Destroy()
			Window = nil
		end

		Shine.AdminMenu:DestroyOnClose( Window )

		Window:SetLayout( Layout )

		local DurationEntry
		local ReasonEntry

		local IDLabel = SGUI:Create( "Label", Window )
		IDLabel:SetText( "NS2ID:" )
		IDLabel:SetFontScale( Font, Scale )
		IDLabel:SetMargin( Spacing( 0, 0, 0, HighResScaled( 5 ) ) )
		Layout:AddElement( IDLabel )

		local SearchLayout = SGUI.Layout:CreateLayout( "Horizontal", {
			AutoSize = UnitVector( Percentage( 100 ), HighResScaled( 32 ) ),
			Margin = Spacing( 0, 0, 0, HighResScaled( 5 ) ),
			Fill = false
		} )

		local IDEntry = SGUI:Create( "TextEntry", Window )
		IDEntry:SetFill( true )
		IDEntry:SetFontScale( Font, Scale )
		IDEntry:SetNumeric( true )
		if SteamIDToBan then
			IDEntry:SetText( SteamIDToBan )
		end
		function IDEntry:OnTab()
			self:LoseFocus()

			DurationEntry:RequestFocus()
		end
		Window.IDEntry = IDEntry

		SearchLayout:AddElement( IDEntry )

		local GetEnts = Shared.GetEntitiesWithClassname
		local IterateEntList = ientitylist

		local MenuButton = SGUI:Create( "Button", Window )
		MenuButton:SetAutoSize( UnitVector( HighResScaled( 32 ), HighResScaled( 32 ) ) )
		MenuButton:SetText( SGUI.Icons.Ionicons.ArrowDownB )
		MenuButton:SetFontScale( SGUI.FontManager.GetHighResFont( "Ionicons", 29 ) )
		MenuButton:SetTooltip( self:GetPhrase( "SELECT_PLAYER" ) )

		SearchLayout:AddElement( MenuButton )
		Layout:AddElement( SearchLayout )

		MenuButton:SetOpenMenuOnClick( function( Button )
			return {
				MenuPos = Vector2( -IDEntry:GetSize().x, Button:GetSize().y ),
				Size = Vector2( IDEntry:GetSize().x + Button:GetSize().x, HighResScaled( 28 ):GetValue() ),
				Populate = function( Menu )
					Menu:SetMaxVisibleButtons( 12 )
					Shine.AdminMenu:DestroyOnClose( Menu )

					Menu:CallOnRemove( function()
						Shine.AdminMenu:DontDestroyOnClose( Menu )
					end )

					local PlayerEnts = GetEnts( "PlayerInfoEntity" )
					for _, Ent in IterateEntList( PlayerEnts ) do
						local SteamID = tostring( Ent.steamId )
						local Name = Ent.playerName

						Menu:AddButton( Name, function()
							if SGUI.IsValid( IDEntry ) then
								IDEntry:SetText( SteamID )
							end
							Menu:Destroy()
						end ):SetFontScale( Font, Scale )
					end
				end
			}
		end )

		local DurationLabel = SGUI:Create( "Label", Window )
		DurationLabel:SetText( self:GetPhrase( "DURATION_LABEL" ) )
		DurationLabel:SetFontScale( Font, Scale )
		DurationLabel:SetMargin( Spacing( 0, 0, 0, HighResScaled( 5 ) ) )

		Layout:AddElement( DurationLabel )

		DurationEntry = SGUI:Create( "TextEntry", Window )
		DurationEntry:SetAutoSize( UnitVector( Percentage( 100 ), HighResScaled( 32 ) ) )
		DurationEntry:SetFontScale( Font, Scale )
		DurationEntry:SetCharPattern( "[%w%.%-]" )
		DurationEntry:SetMargin( Spacing( 0, 0, 0, HighResScaled( 5 ) ) )
		function DurationEntry:OnTab()
			self:LoseFocus()

			ReasonEntry:RequestFocus()
		end
		Window.DurationEntry = DurationEntry

		Layout:AddElement( DurationEntry )

		local DurationValueLabel = SGUI:Create( "Label", Window )
		DurationValueLabel:SetText( self:GetPhrase( "DURATION_HINT" )  )
		DurationValueLabel:SetFontScale( Font, Scale )
		DurationValueLabel:SetMargin( Spacing( 0, 0, 0, HighResScaled( 5 ) ) )
		local DurationOptions = { Units = "minutes", Min = 0, Round = true }
		function DurationEntry.OnTextChanged( TextEntry, OldValue, NewValue )
			if NewValue == "" then
				DurationValueLabel:SetText( self:GetPhrase( "DURATION_HINT" ) )
				return
			end

			local Minutes = Shine.CommandUtil.ParamTypes.time.Parse( nil, NewValue, DurationOptions )
			if Minutes == 0 then
				DurationValueLabel:SetText( self:GetPhrase( "DURATION_PERMANENT" ) )
				return
			end

			DurationValueLabel:SetText( self:GetInterpolatedPhrase( "DURATION_TIME", {
				Time = StringTimeToString( Minutes * 60 )
			} ) )
		end

		Layout:AddElement( DurationValueLabel )

		local ReasonLabel = SGUI:Create( "Label", Window )
		ReasonLabel:SetText( self:GetPhrase( "REASON" ) )
		ReasonLabel:SetFontScale( Font, Scale )
		ReasonLabel:SetMargin( Spacing( 0, 0, 0, HighResScaled( 5 ) ) )

		Layout:AddElement( ReasonLabel )

		ReasonEntry = SGUI:Create( "TextEntry", Window )
		ReasonEntry:SetAutoSize( UnitVector( Percentage( 100 ), HighResScaled( 32 ) ) )
		ReasonEntry:SetFontScale( Font, Scale )
		function ReasonEntry:OnTab()
			self:LoseFocus()

			IDEntry:RequestFocus()
		end
		Window.ReasonEntry = ReasonEntry

		Layout:AddElement( ReasonEntry )

		local AddBan = SGUI:Create( "Button", Window )
		local ButtonLayout = SGUI.Layout:CreateLayout( "Horizontal", {
			Fill = false,
			AutoSize = UnitVector( Percentage( 100 ), Auto( AddBan ) + HighResScaled( 8 ) ),
			Alignment = SGUI.LayoutAlignment.MAX
		} )

		AddBan:SetText( self:GetPhrase( "ADD_BAN" ) )
		AddBan:SetStyleName( "SuccessButton" )
		AddBan:SetFontScale( Font, Scale )
		AddBan:SetAlignment( SGUI.LayoutAlignment.CENTRE )
		AddBan:SetAutoSize( UnitVector( Units.Max( Auto( AddBan ), HighResScaled( 128 ) ), Percentage( 100 ) ) )

		ButtonLayout:AddElement( AddBan )
		Layout:AddElement( ButtonLayout )

		function AddBan.DoClick()
			local ID = tonumber( IDEntry:GetText() )
			if not ID then return end

			local Duration = DurationEntry:GetText()
			if Duration == "" then return end

			local Reason = ReasonEntry:GetText()

			Shine.AdminMenu:RunCommand( self.BanCommand, StringFormat( "%s %s %s",
				ID, Duration, Reason ) )

			Shine.AdminMenu:DontDestroyOnClose( Window )
			Window:Destroy()
			Window = nil

			if self.BanMenuOpen then
				self:RequestBanPage( self.CurrentPage )
			end
		end
	end

	self:AddAdminMenuCommand(
		self:GetPhrase( "CATEGORY" ),
		self:GetPhrase( "BAN" ),
		"sh_banid",
		false,
		function( Button, IDs )
			OpenAddBanWindow( IDs[ 1 ] )
			Window.DurationEntry:RequestFocus()
		end,
		self:GetPhrase( "BAN_TIP" )
	)

	self:AddAdminMenuTab( self:GetPhrase( self.AdminTab ), {
		Icon = self.AdminMenuIcon or SGUI.Icons.Ionicons.AlertCircled,
		OnInit = function( Panel, Data )
			self.BanMenuOpen = true

			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( HighResScaled( 16 ), HighResScaled( 32 ),
					HighResScaled( 16 ), HighResScaled( 16 ) )
			} )

			local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )

			local SearchIcon = SGUI:Create( "Label", Panel )
			SearchIcon:SetFontScale( SGUI.FontManager.GetHighResFont( "Ionicons", 29 ) )
			SearchIcon:SetText( SGUI.Icons.Ionicons.Search )
			SearchIcon:SetMargin( Spacing( 0, 0, HighResScaled( 8 ), 0 ) )

			local SearchBox = SGUI:Create( "TextEntry", Panel )
			SearchBox:SetFontScale( Font, Scale )
			SearchBox:SetFill( true )
			SearchBox:SetPlaceholderText( self:GetPhrase( "SEARCH_HINT" ) )

			local SearchBar = SGUI.Layout:CreateLayout( "Horizontal", {
				Margin = Spacing( 0, 0, 0, HighResScaled( 16 ) ),
				AutoSize = UnitVector( Percentage( 100 ), Auto( SearchBox ) + 2 ),
				Fill = false
			} )

			SearchBar:AddElement( SearchIcon )
			SearchBar:AddElement( SearchBox )

			Layout:AddElement( SearchBar )

			local List = SGUI:Create( "List", Panel )
			List:SetColumns( self:GetPhrase( "NAME" ), self:GetPhrase( "BANNED_BY" ),
				self:GetPhrase( "EXPIRY" ) )
			List:SetSpacing( 0.35, 0.35, 0.3 )
			List:SetFill( true )

			Shine.AdminMenu.SetupListWithScaling( List )

			List:SetNumericColumn( 3 )
			List:SetSortedExternally( true )

			Layout:AddElement( List )

			self.BanList = List

			Data = Data or {
				Page = 1,
				MaxResults = 15,
				SortColumn = self.SortColumn.EXPIRY,
				SortAscending = true,
				Filter = ""
			}
			self.CurrentPage = Data

			function SearchBox.OnTextChanged( SearchBox, OldText, NewText )
				self.SearchTimer = self.SearchTimer or self:SimpleTimer( 0.3, function()
					self.SearchTimer = nil

					if not SGUI.IsValid( SearchBox ) then return end

					Data.Filter = SearchBox:GetText()

					self:RequestBanPage( Data )
				end )
				self.SearchTimer:Debounce()
			end

			function List.HandleExternalSorting( List, Column, Descending )
				Data.SortColumn = Column
				Data.SortAscending = not Descending

				self:RequestBanPage( Data )

				return true
			end

			local ControlLayout = SGUI.Layout:CreateLayout( "Horizontal", {
				Margin = Spacing( 0, HighResScaled( 16 ), 0, 0 ),
				Fill = false
			} )

			local PageButtonSize = UnitVector(
				Units.Max( HighResScaled( 32 ), Auto() + HighResScaled( 8 ) ),
				Percentage( 100 )
			)

			local PageBack = SGUI:Create( "Button", Panel )
			PageBack:SetIcon( SGUI.Icons.Ionicons.ArrowLeftB )
			PageBack:SetEnabled( Data.Page > 1 )
			PageBack:SetAutoSize( PageButtonSize )
			PageBack:SetAlignment( SGUI.LayoutAlignment.CENTRE )
			function PageBack.DoClick()
				Data.Page = Data.Page - 1
				self:RequestBanPage( Data )
			end
			self.PageBack = PageBack

			ControlLayout:AddElement( PageBack )

			local PageLabel = SGUI:Create( "Label", Panel )
			PageLabel:SetFontScale( Font, Scale )
			PageLabel:SetText( StringFormat( "%d / %d", Data.Page, Data.Page ) )
			PageLabel:SetAlignment( SGUI.LayoutAlignment.CENTRE )
			PageLabel:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )

			-- When clicking the page label, turn it into a text entry to allow specifying
			-- a precise page to jump to.
			function PageLabel.DoClick()
				local TextEntry = SGUI:Create( "TextEntry", Panel )
				TextEntry:SetFontScale( Font, Scale )
				TextEntry:SetSize( PageLabel:GetSize() )

				local Margin = PageLabel:GetMargin()
				TextEntry:SetMargin( Margin )

				TextEntry:SetText( tostring( Data.Page ) )
				TextEntry:SetNumeric( true )
				TextEntry:SetAlignment( SGUI.LayoutAlignment.CENTRE )
				TextEntry:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
				function TextEntry.OnEnter()
					local MaxPages = self.PageData and self.PageData.NumPages or Data.Page

					Data.Page = tonumber( TextEntry:GetText() )

					local PredictedPage = Min( Data.Page, MaxPages )
					PageLabel:SetText( StringFormat( "%d / %d", PredictedPage, MaxPages ) )

					self:RequestBanPage( Data )

					TextEntry:OnEscape()
				end
				function TextEntry.OnEscape()
					TextEntry:Destroy()
					PageLabel:SetIsVisible( true )
					ControlLayout:RemoveElement( TextEntry )
				end
				TextEntry.OnLoseFocus = TextEntry.OnEscape

				ControlLayout:InsertElementAfter( PageLabel, TextEntry )

				PageLabel:SetIsVisible( false )

				TextEntry:RequestFocus()
				TextEntry:SelectAll()
			end

			self.PageLabel = PageLabel

			ControlLayout:AddElement( PageLabel )

			local PageForward = SGUI:Create( "Button", Panel )
			PageForward:SetIcon( SGUI.Icons.Ionicons.ArrowRightB )
			PageForward:SetEnabled( false )
			PageForward:SetAutoSize( PageButtonSize )
			PageForward:SetAlignment( SGUI.LayoutAlignment.CENTRE )
			function PageForward.DoClick()
				Data.Page = Data.Page + 1
				self:RequestBanPage( Data )
			end
			self.PageForward = PageForward

			ControlLayout:AddElement( PageForward )

			local Unban = SGUI:Create( "Button", Panel )
			Unban:SetText( self:GetPhrase( "UNBAN" ) )
			Unban:SetFontScale( Font, Scale )
			Unban:SetStyleName( "DangerButton" )
			Unban:SetIcon( SGUI.Icons.Ionicons.TrashB )
			function Unban.DoClick()
				local Row = List:GetSelectedRow()
				if not Row then return end

				local BanData = Row.BanData
				if not BanData then return end

				Shine.AdminMenu:RunCommand( self.UnbanCommand, BanData.ID )

				self:RequestBanPage( Data )
			end
			Unban:SetEnabled( List:HasSelectedRow() )

			ControlLayout:AddElement( Unban )

			local AddBan = SGUI:Create( "Button", Panel )
			AddBan:SetText( self:GetPhrase( "ADD_BAN" ) )
			AddBan:SetFontScale( Font, Scale )
			AddBan:SetAlignment( SGUI.LayoutAlignment.MAX )
			AddBan:SetIcon( SGUI.Icons.Ionicons.Plus )
			function AddBan.DoClick()
				OpenAddBanWindow()
				Window.IDEntry:RequestFocus()
			end

			ControlLayout:AddElement( AddBan )

			local ButtonWidth = Units.Max(
				HighResScaled( 128 ),
				Auto( Unban ) + HighResScaled( 16 ),
				Auto( AddBan ) + HighResScaled( 16 )
			)
			Unban:SetAutoSize( UnitVector( ButtonWidth, Percentage( 100 ) ) )
			AddBan:SetAutoSize( UnitVector( ButtonWidth, Percentage( 100 ) ) )

			local ButtonHeight = Units.Max( Auto( AddBan ), Auto( PageForward ) ) + HighResScaled( 8 )
			ControlLayout:SetAutoSize( UnitVector( Percentage( 100 ), ButtonHeight ) )
			PageLabel:SetMargin( Spacing( HighResScaled( 16 ), 0, HighResScaled( 16 ), 0 ) )

			Layout:AddElement( ControlLayout )

			function List:OnRowSelected( Index, Row )
				Unban:SetEnabled( true )
			end

			function List:OnRowDeselected( Index, Row )
				Unban:SetEnabled( false )
			end

			Panel:SetLayout( Layout )
			Panel:InvalidateLayout( true )
			List:SortRows( Data.SortColumn, nil, not Data.SortAscending )
		end,

		OnCleanup = function( Panel )
			self.BanList = nil
			self.BanMenuOpen = false

			return self.CurrentPage
		end
	} )
end

function Plugin:RequestBanPage( PageRequest )
	self:SendNetworkMessage( "RequestBanPage", PageRequest, true )
end

function Plugin:BuildTooltip( Data )
	local Text = {}

	if Data.Duration and ( Data.Duration ~= 0 or Data.UnbanTime == 0 ) then
		Text[ #Text + 1 ] = self:GetInterpolatedPhrase( "BAN_DURATION_TIP", { Duration = Data.Duration } )
	end

	if Data.Issued and Data.Issued ~= 0 then
		Text[ #Text + 1 ] = self:GetInterpolatedPhrase( "ISSUED_DATE_TIP", {
			Date = GetDurationLabel( self, false, Data.Issued )
		} )
	end

	if Data.Reason and Data.Reason ~= "" then
		Text[ #Text + 1 ] = self:GetInterpolatedPhrase( "REASON_TIP", {
			Reason = Data.Reason
		} )
	end

	return TableConcat( Text, "\n" )
end

function Plugin:AddBanRow( Data )
	if not SGUI.IsValid( self.BanList ) then return end

	local UnbanTime = Data.UnbanTime
	local Permanent = UnbanTime == 0

	local Name = StringFormat( "%s [%s]", Data.Name, Data.ID )
	local BannedBy = StringFormat( "%s [%s]", Data.BannedBy, Data.BannerID or "?" )
	local Expiry = GetDurationLabel( self, Permanent, UnbanTime )

	local Row = self.BanList:AddRow( Name, BannedBy, Expiry )
	Row:SetTooltip( self:BuildTooltip( Data ) )
	Row.BanData = Data

	return Row
end

function Plugin:ReceiveBanData( Data )
	self:AddBanRow( Data )
end

function Plugin:ReceiveBanPage( PageData )
	if not self.BanMenuOpen then return end

	self.BanList:Clear()

	self.CurrentPage.Page = PageData.Page
	self.CurrentPage.MaxResults = PageData.MaxResults

	self.PageData = PageData

	self.PageLabel:SetText( StringFormat( "%d / %d", PageData.Page, PageData.NumPages ) )
	self.PageLabel:SetTooltip( self:GetInterpolatedPhrase( "TOTAL_RESULTS_TIP", {
		TotalResults = PageData.TotalNumResults
	} ) )
	self.PageBack:SetEnabled( PageData.Page > 1 )
	self.PageForward:SetEnabled( PageData.Page < PageData.NumPages )
end
