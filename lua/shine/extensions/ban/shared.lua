--[[
	Shine bans plugin.
]]

local Plugin = {}

local BanData = {
	ID = "string (32)",
	Name = "string (32)",
	Duration = "integer",
	UnbanTime = "integer",
	BannedBy = "string (32)",
	BannerID = "integer",
	Reason = "string (128)",
	Issued = "integer"
}

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "RequestBanData", {}, "Server" )
	self:AddNetworkMessage( "BanData", BanData, "Client" )
	self:AddNetworkMessage( "Unban", { ID = "string (32)" }, "Client" )

	self:AddTranslatedMessage( "PLAYER_BANNED", {
		TargetName = self:GetNameNetworkField(),
		Duration = "integer",
		Reason = "string (128)"
	} )
end

Shine:RegisterExtension( "ban", Plugin )

if Server then return end

Plugin.AdminTab = "Bans"

Plugin.BanCommand = "sh_banid"
Plugin.UnbanCommand = "sh_unban"

local SGUI = Shine.GUI

local Date = os.date
local StringFormat = string.format
local StringTimeToString = string.TimeToString
local TableEmpty = table.Empty
local TableRemove = table.remove

function Plugin:Initialise()
	self:SetupAdminMenu()

	self.Enabled = true

	return true
end

local function GetDurationLabel( self, Permanent, UnbanTime )
	return Permanent and self:GetPhrase( "NEVER" ) or Date( self:GetPhrase( "DATE_FORMAT" ), UnbanTime )
end

function Plugin:SetupAdminMenu()
	local Window
	local function OpenAddBanWindow()
		if SGUI.IsValid( Window ) then
			SGUI:SetWindowFocus( Window )

			return
		end

		Window = SGUI:Create( "Panel" )
		Window:SetAnchor( "CentreMiddle" )
		Window:SetSize( Vector( 400, 328, 0 ) )
		Window:SetPos( Vector( -200, -164, 0 ) )
		Window:AddTitleBar( self:GetPhrase( "ADD_BAN" ) )
		Window:SkinColour()

		function Window.CloseButton.DoClick()
			Shine.AdminMenu:DontDestroyOnClose( Window )
			Window:Destroy()
			Window = nil
		end

		Shine.AdminMenu:DestroyOnClose( Window )

		local TextEntrySize = Vector( 368, 32, 0 )

		local DurationEntry
		local ReasonEntry

		local X = 16
		local Y = 32

		local IDLabel = SGUI:Create( "Label", Window )
		IDLabel:SetText( "NS2ID:" )
		IDLabel:SetFont( Fonts.kAgencyFB_Small )
		IDLabel:SetBright( true )
		IDLabel:SetPos( Vector( X, Y, 0 ) )

		Y = Y + 32

		local IDEntry = SGUI:Create( "TextEntry", Window )
		IDEntry:SetSize( TextEntrySize - Vector( 32, 0, 0 ) )
		IDEntry:SetPos( Vector( X, Y, 0 ) )
		IDEntry:SetFont( Fonts.kAgencyFB_Small )
		IDEntry:SetNumeric( true )
		function IDEntry:OnTab()
			self:LoseFocus()

			DurationEntry:RequestFocus()
		end

		local GetEnts = Shared.GetEntitiesWithClassname
		local IterateEntList = ientitylist

		local MenuButton = SGUI:Create( "Button", Window )
		MenuButton:SetAnchor( "TopRight" )
		MenuButton:SetSize( Vector( 32, 32, 0 ) )
		MenuButton:SetText( ">" )
		MenuButton:SetFont( Fonts.kAgencyFB_Small )
		MenuButton:SetPos( Vector( -48, Y, 0 ) )
		MenuButton:SetTooltip( self:GetPhrase( "SELECT_PLAYER" ) )
		local Menu

		function MenuButton.DoClick( Button )
			if Menu then
				Shine.AdminMenu:DontDestroyOnClose( Menu )
				Menu:Destroy()
				Menu = nil
				return
			end

			local Pos = Button:GetScreenPos()
			Pos.x = Pos.x - TextEntrySize.x + 32
			Pos.y = Pos.y + TextEntrySize.y

			Menu = SGUI:Create( "Menu" )
			Menu:SetPos( Pos )
			Menu:SetButtonSize( Vector( TextEntrySize.x, 24, 0 ) )
			Menu:CallOnRemove( function()
				Menu = nil
			end )
			Shine.AdminMenu:DestroyOnClose( Menu )

			local PlayerEnts = GetEnts( "PlayerInfoEntity" )

			for _, Ent in IterateEntList( PlayerEnts ) do
				local SteamID = tostring( Ent.steamId )
				local Name = Ent.playerName

				Menu:AddButton( Name, function()
					if SGUI.IsValid( IDEntry ) then
						IDEntry:SetText( SteamID )
					end

					Shine.AdminMenu:DontDestroyOnClose( Menu )
					Menu:Destroy()
					Menu = nil
				end )
			end
		end

		Y = Y + 40

		local DurationLabel = SGUI:Create( "Label", Window )
		DurationLabel:SetText( self:GetPhrase( "DURATION_LABEL" ) )
		DurationLabel:SetFont( Fonts.kAgencyFB_Small )
		DurationLabel:SetBright( true )
		DurationLabel:SetPos( Vector( X, Y, 0 ) )

		Y = Y + 32

		DurationEntry = SGUI:Create( "TextEntry", Window )
		DurationEntry:SetSize( TextEntrySize )
		DurationEntry:SetPos( Vector( X, Y, 0 ) )
		DurationEntry:SetFont( Fonts.kAgencyFB_Small )
		DurationEntry:SetCharPattern( "[%w%.%-]" )
		function DurationEntry:OnTab()
			self:LoseFocus()

			ReasonEntry:RequestFocus()
		end

		Y = Y + 40

		local DurationValueLabel = SGUI:Create( "Label", Window )
		DurationValueLabel:SetText( self:GetPhrase( "DURATION_HINT" )  )
		DurationValueLabel:SetFont( Fonts.kAgencyFB_Small )
		DurationValueLabel:SetBright( true )
		DurationValueLabel:SetPos( Vector( X, Y, 0 ) )
		local DurationOptions = { Units = "minutes", Min = 0, Round = true }
		function DurationEntry.OnTextChanged( TextEntry, OldValue, NewValue )
			if NewValue == "" then
				DurationValueLabel:SetText( self:GetPhrase( "DURATION_HINT" ) )
				return
			end

			local Minutes = Shine.CommandUtil.ParamTypes.time( nil, NewValue, DurationOptions )
			if Minutes == 0 then
				DurationValueLabel:SetText( self:GetPhrase( "DURATION_PERMANENT" ) )
				return
			end

			DurationValueLabel:SetText( self:GetInterpolatedPhrase( "DURATION_TIME", {
				Time = StringTimeToString( Minutes * 60 )
			} ) )
		end

		Y = Y + 32

		local ReasonLabel = SGUI:Create( "Label", Window )
		ReasonLabel:SetText( self:GetPhrase( "REASON" ) )
		ReasonLabel:SetFont( Fonts.kAgencyFB_Small )
		ReasonLabel:SetBright( true )
		ReasonLabel:SetPos( Vector( X, Y, 0 ) )

		Y = Y + 32

		ReasonEntry = SGUI:Create( "TextEntry", Window )
		ReasonEntry:SetSize( TextEntrySize )
		ReasonEntry:SetPos( Vector( X, Y, 0 ) )
		ReasonEntry:SetFont( Fonts.kAgencyFB_Small )
		function ReasonEntry:OnTab()
			self:LoseFocus()

			IDEntry:RequestFocus()
		end

		local AddBan = SGUI:Create( "Button", Window )
		AddBan:SetAnchor( "BottomMiddle" )
		AddBan:SetSize( Vector( 128, 32, 0 ) )
		AddBan:SetPos( Vector( -64, -44, 0 ) )
		AddBan:SetText( self:GetPhrase( "ADD_BAN" ) )
		AddBan:SetFont( Fonts.kAgencyFB_Small )
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

			self:RequestBanData()
		end
	end

	self:AddAdminMenuTab( self:GetPhrase( self.AdminTab ), {
		OnInit = function( Panel, Data )
			local List = SGUI:Create( "List", Panel )
			List:SetAnchor( GUIItem.Left, GUIItem.Top )
			List:SetPos( Vector( 16, 28, 0 ) )
			List:SetColumns( 3, self:GetPhrase( "NAME" ), self:GetPhrase( "BANNED_BY" ), self:GetPhrase( "EXPIRY" ) )
			List:SetSpacing( 0.35, 0.35, 0.3 )
			List:SetSize( Vector( 640, 512, 0 ) )
			List.ScrollPos = Vector( 0, 32, 0 )

			self.BanList = List
			self.Rows = self.Rows or {}

			local BanData = self.BanData
			if BanData then
				for i = 1, #BanData do
					local Data = BanData[ i ]
					local UnbanTime = Data.UnbanTime
					local Permanent = UnbanTime == 0

					local Row = List:AddRow( Data.Name, Data.BannedBy,
						GetDurationLabel( self, Permanent, UnbanTime ) )

					Row.BanData = Data

					self.Rows[ Data.ID ] = Row
				end
			else
				self:RequestBanData()
			end

			Shine.AdminMenu.RestoreListState( List, Data )

			local Unban = SGUI:Create( "Button", Panel )
			Unban:SetAnchor( "BottomLeft" )
			Unban:SetSize( Vector( 128, 32, 0 ) )
			Unban:SetPos( Vector( 16, -48, 0 ) )
			Unban:SetText( self:GetPhrase( "UNBAN" ) )
			Unban:SetFont( Fonts.kAgencyFB_Small )
			function Unban.DoClick()
				local Row = List:GetSelectedRow()
				if not Row then return end

				local Data = Row.BanData
				if not Data then return end
				local ID = Data.ID

				Shine.AdminMenu:RunCommand( self.UnbanCommand, ID )
			end

			local LoadMore = SGUI:Create( "Button", Panel )
			LoadMore:SetAnchor( "BottomMiddle" )
			LoadMore:SetSize( Vector( 128, 32, 0 ) )
			LoadMore:SetPos( Vector( -64, -48, 0 ) )
			LoadMore:SetText( self:GetPhrase( "LOAD_MORE" ) )
			LoadMore:SetFont( Fonts.kAgencyFB_Small )
			function LoadMore.DoClick()
				self:RequestBanData()
			end
			LoadMore:SetTooltip( self:GetPhrase( "LOAD_MORE_TIP" ) )

			local AddBan = SGUI:Create( "Button", Panel )
			AddBan:SetAnchor( "BottomRight" )
			AddBan:SetSize( Vector( 128, 32, 0 ) )
			AddBan:SetPos( Vector( -144, -48, 0 ) )
			AddBan:SetText( self:GetPhrase( "ADD_BAN" ) )
			AddBan:SetFont( Fonts.kAgencyFB_Small )
			function AddBan.DoClick()
				OpenAddBanWindow()
			end
		end,

		OnCleanup = function( Panel )
			TableEmpty( self.Rows )

			local BanList = self.BanList
			self.BanList = nil

			return Shine.AdminMenu.GetListState( BanList )
		end
	} )
end

function Plugin:RequestBanData()
	self:SendNetworkMessage( "RequestBanData", {}, true )
end

function Plugin:ReceiveUnban( Data )
	local ID = Data.ID

	if not self.BanData then return end

	local BanData = self.BanData
	local Rows = self.Rows
	local List = self.BanList

	for i = 1, #BanData do
		local Data = BanData[ i ]

		if Data.ID == ID then
			TableRemove( BanData, i )

			local Row = Rows[ ID ]
			if SGUI.IsValid( Row ) then
				List:RemoveRow( Row.Index )
			end

			break
		end
	end
end

function Plugin:ReceiveBanData( Data )
	self.BanData = self.BanData or {}

	local BanData = self.BanData
	local RealData = {
		ID = Data.ID,
		Name = Data.Name,
		Duration = Data.Duration,
		UnbanTime = Data.UnbanTime,
		BannedBy = Data.BannedBy,
		BannerID = Data.BannerID,
		Reason = Data.Reason,
		Issued = Data.Issued
	}

	for i = 1, #BanData do
		local CurData = BanData[ i ]

		if CurData.ID == Data.ID then
			BanData[ i ] = RealData

			local List = self.BanList

			if not SGUI.IsValid( List ) then return end

			local UnbanTime = Data.UnbanTime
			local Permanent = UnbanTime == 0

			local Row = self.Rows[ Data.ID ]

			local Name = Data.Name
			local BannedBy = Data.BannedBy
			local Expiry = GetDurationLabel( self, Permanent, UnbanTime )
			if not Row then
				Row = List:AddRow( Name, BannedBy, Expiry )
				self.Rows[ Data.ID ] = Row
			else
				Row:SetColumnText( 1, Name )
				Row:SetColumnText( 2, BannedBy )
				Row:SetColumnText( 3, Expiry )
			end

			Row.BanData = RealData

			return
		end
	end

	BanData[ #BanData + 1 ] = RealData

	local List = self.BanList

	if not SGUI.IsValid( List ) then return end

	local UnbanTime = Data.UnbanTime
	local Permanent = UnbanTime == 0

	local Row = List:AddRow( Data.Name, Data.BannedBy,
		GetDurationLabel( self, Permanent, UnbanTime ) )

	Row.BanData = RealData

	self.Rows[ Data.ID ] = Row
end
