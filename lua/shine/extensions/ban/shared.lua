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
end

Shine:RegisterExtension( "ban", Plugin )

if Server then return end

local SGUI = Shine.GUI

local Date = os.date
local StringFormat = string.format
local TableEmpty = table.Empty
local TableRemove = table.remove

function Plugin:Initialise()
	self:SetupAdminMenu()

	self.Enabled = true

	return true
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
		Window:SetSize( Vector( 400, 296, 0 ) )
		Window:SetPos( Vector( -200, -148, 0 ) )
		Window:AddTitleBar( "Add ban" )
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

		local IDLabel = SGUI:Create( "Label", Window )
		IDLabel:SetText( "NS2ID:" )
		IDLabel:SetFont( "fonts/AgencyFB_small.fnt" )
		IDLabel:SetBright( true )
		IDLabel:SetPos( Vector( 16, 32, 0 ) )

		local IDEntry = SGUI:Create( "TextEntry", Window )
		IDEntry:SetSize( TextEntrySize - Vector( 32, 0, 0 ) )
		IDEntry:SetPos( Vector( 16, 64, 0 ) )
		IDEntry:SetFont( "fonts/AgencyFB_small.fnt" )
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
		MenuButton:SetFont( "fonts/AgencyFB_small.fnt" )
		MenuButton:SetPos( Vector( -48, 64, 0 ) )
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
					IDEntry:SetText( SteamID )

					Shine.AdminMenu:DontDestroyOnClose( Menu )
					Menu:Destroy()
					Menu = nil
				end )
			end
		end

		local DurationLabel = SGUI:Create( "Label", Window )
		DurationLabel:SetText( "Duration (in minutes, 0 for permanent):" )
		DurationLabel:SetFont( "fonts/AgencyFB_small.fnt" )
		DurationLabel:SetBright( true )
		DurationLabel:SetPos( Vector( 16, 104, 0 ) )

		DurationEntry = SGUI:Create( "TextEntry", Window )
		DurationEntry:SetSize( TextEntrySize )
		DurationEntry:SetPos( Vector( 16, 136, 0 ) )
		DurationEntry:SetFont( "fonts/AgencyFB_small.fnt" )
		function DurationEntry:OnTab()
			self:LoseFocus()

			ReasonEntry:RequestFocus()
		end

		local ReasonLabel = SGUI:Create( "Label", Window )
		ReasonLabel:SetText( "Reason:" )
		ReasonLabel:SetFont( "fonts/AgencyFB_small.fnt" )
		ReasonLabel:SetBright( true )
		ReasonLabel:SetPos( Vector( 16, 176, 0 ) )

		ReasonEntry = SGUI:Create( "TextEntry", Window )
		ReasonEntry:SetSize( TextEntrySize )
		ReasonEntry:SetPos( Vector( 16, 208, 0 ) )
		ReasonEntry:SetFont( "fonts/AgencyFB_small.fnt" )
		function ReasonEntry:OnTab()
			self:LoseFocus()

			IDEntry:RequestFocus()
		end

		local AddBan = SGUI:Create( "Button", Window )
		AddBan:SetAnchor( "BottomMiddle" )
		AddBan:SetSize( Vector( 128, 32, 0 ) )
		AddBan:SetPos( Vector( -64, -48, 0 ) )
		AddBan:SetText( "Add Ban" )
		AddBan:SetFont( "fonts/AgencyFB_small.fnt" )
		function AddBan.DoClick()
			local ID = tonumber( IDEntry:GetText() )
			if not ID then return end
			
			local Duration = tonumber( DurationEntry:GetText() )
			if not Duration then return end
			
			local Reason = ReasonEntry:GetText()

			Shine.AdminMenu:RunCommand( "sh_banid", StringFormat( "%s %s %s", ID, Duration, Reason ) )

			Shine.AdminMenu:DontDestroyOnClose( Window )
			Window:Destroy()
			Window = nil
		end
	end
	
	self:AddAdminMenuTab( "Bans", {
		OnInit = function( Panel, Data )
			local List = SGUI:Create( "List", Panel )
			List:SetAnchor( GUIItem.Left, GUIItem.Top )
			List:SetPos( Vector( 16, 24, 0 ) )
			List:SetColumns( 3, "Name", "Banned By", "Expiry" )
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
						Permanent and "Never" or Date( "%d %B %Y %H:%M", UnbanTime ) )

					Row.BanData = Data

					self.Rows[ Data.ID ] = Row
				end
			else
				self:RequestBanData()
			end

			if Data and Data.SortedColumn then
				List:SortRows( Data.SortedColumn, nil, Data.Descending )
			end

			local Unban = SGUI:Create( "Button", Panel )
			Unban:SetAnchor( "BottomLeft" )
			Unban:SetSize( Vector( 128, 32, 0 ) )
			Unban:SetPos( Vector( 16, -48, 0 ) )
			Unban:SetText( "Unban" )
			Unban:SetFont( "fonts/AgencyFB_small.fnt" )
			function Unban.DoClick()
				local Row = List:GetSelectedRow()
				if not Row then return end
				
				local Data = Row.BanData
				local ID = Data.ID

				Shine.AdminMenu:RunCommand( "sh_unban", ID )
			end

			local LoadMore = SGUI:Create( "Button", Panel )
			LoadMore:SetAnchor( "BottomMiddle" )
			LoadMore:SetSize( Vector( 128, 32, 0 ) )
			LoadMore:SetPos( Vector( -64, -48, 0 ) )
			LoadMore:SetText( "Load more" )
			LoadMore:SetFont( "fonts/AgencyFB_small.fnt" )
			function LoadMore.DoClick()
				self:RequestBanData()
			end

			local AddBan = SGUI:Create( "Button", Panel )
			AddBan:SetAnchor( "BottomRight" )
			AddBan:SetSize( Vector( 128, 32, 0 ) )
			AddBan:SetPos( Vector( -144, -48, 0 ) )
			AddBan:SetText( "Add Ban" )
			AddBan:SetFont( "fonts/AgencyFB_small.fnt" )
			function AddBan.DoClick()
				OpenAddBanWindow()
			end
		end,

		OnCleanup = function( Panel )
			TableEmpty( self.Rows )

			local SortedColumn = self.BanList.SortedColumn
			local Descending = self.BanList.Descending

			self.BanList = nil

			return {
				SortedColumn = SortedColumn,
				Descending = Descending
			}
		end } )
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
			local Expiry = Permanent and "Never" or Date( "%d %b %Y %H:%M", UnbanTime )
			if not Row then
				Row = List:AddRow( Name, BannedBy, Expiry )
				self.Rows[ Data.ID ] = Row
			else
				Row:SetColumnText( 1, Name )
				Row:SetColumnText( 2, BannedBy )
				Row:SetColumnText( 3, Expiry )
			end

			return
		end
	end

	BanData[ #BanData + 1 ] = RealData

	local List = self.BanList

	if not SGUI.IsValid( List ) then return end

	local UnbanTime = Data.UnbanTime
	local Permanent = UnbanTime == 0

	local Row = List:AddRow( Data.Name, Data.BannedBy,
		Permanent and "Never" or Date( "%d %b %Y %H:%M", UnbanTime ) )

	Row.BanData = RealData

	self.Rows[ Data.ID ] = Row
end
