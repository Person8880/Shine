--[[
	Shine web page display system.
]]

local WebOpen = {
	URL = "string (255)",
	Title = "string (32)"
}

Shared.RegisterNetworkMessage( "Shine_Web", WebOpen )

if Server then return end

local Hook = Shine.Hook

local SGUI = Shine.GUI

local CloseButtonCol = Colour( 0.6, 0.3, 0.1, 1 )
local CloseButtonHighlight = Colour( 0.8, 0.4, 0.1, 1 )
local SteamButtonCol = Colour( 0.1, 0.6, 0.2, 1 )
local SteamButtonHighlight = Colour( 0.15, 0.9, 0.3, 1 )

local LoadingFont = Fonts.kAgencyFB_Large
local TitleFont = Fonts.kAgencyFB_Small

local SteamButtonPos = Vector( -150, 0, 0 )
local SteamButtonSize = Vector( 116, 24, 0 )
local SteamButtonScale = 0.8

local PopupSize = Vector( 400, 176, 0 )
local PopupPos = Vector( -150, -100, 0 )

local NowButtonPos = Vector( -105, -37, 0 )
local PopupButtonSize = Vector( 100, 32, 0 )
local AlwaysButtonPos = Vector( 5, -37, 0 )

local PopupTextPos = Vector( 0, -32, 0 )

local PopupText = [[Open this page in the Steam overlay?
(If you choose always, type "sh_viewwebinsteam 0"
in the console to get this window back)]]

local Max = math.max

local function Scale( Value, WidthMult, HeightMult )
	return Vector( Value.x * WidthMult, Value.y * HeightMult, 0 )
end

local function OpenInSteamPopup( URL, ScrW, ScrH, TitleBarH, Font, TextScale )
	local WidthMult = Max( ScrW / 1920, 1 )
	local HeightMult = Max( ScrH / 1080, 1 )

	local Window = SGUI:Create( "Panel" )
	local WindowSize = Scale( PopupSize, WidthMult, HeightMult )
	Window:SetupFromTable{
		Size = WindowSize,
		Anchor = "CentreMiddle",
		Pos = Scale( PopupPos, WidthMult, HeightMult )
	}
	Window.TitleBarHeight = TitleBarH
	Window:AddTitleBar( "Open in Steam Overlay", Font, TextScale )

	local OldOnMouseDown = Window.OnMouseDown

	function Window:OnMouseDown( Key, DoubleClick )
		if not self:MouseIn( self.Background ) then
			self:Destroy()
			return
		end

		return OldOnMouseDown( self, Key, DoubleClick )
	end

	local Text = Window:Add( "Label" )
	Text:SetupFromTable{
		Anchor = "CentreMiddle",
		Pos = Scale( PopupTextPos, WidthMult, HeightMult ),
		Text = PopupText:gsub( "\n", " " ),
		Font = Font,
		TextAlignmentX = GUIItem.Align_Center,
		TextAlignmentY = GUIItem.Align_Center
	}
	if TextScale then
		Text:SetTextScale( TextScale )
	end
	SGUI.WordWrap( Text, Text:GetText(), 0, WindowSize.x * 0.9 )

	local NowButton = Window:Add( "Button" )
	NowButton:SetupFromTable{
		Anchor = "BottomMiddle",
		Pos = Scale( NowButtonPos, WidthMult, HeightMult ),
		Size = Scale( PopupButtonSize, WidthMult, HeightMult ),
		IsSchemed = false,
		Text = "Now",
		Font = Font,
		ActiveCol = CloseButtonHighlight,
		InactiveCol = CloseButtonCol
	}
	if TextScale then
		NowButton:SetTextScale( TextScale )
	end

	function NowButton:DoClick()
		Window:Destroy()

		Shine:CloseWebPage()

		Client.ShowWebpage( URL )
	end

	local AlwaysButton = Window:Add( "Button" )
	AlwaysButton:SetupFromTable{
		Anchor = "BottomMiddle",
		Pos = Scale( AlwaysButtonPos, WidthMult, HeightMult ),
		Size = Scale( PopupButtonSize, WidthMult, HeightMult ),
		IsSchemed = false,
		Text = "Always",
		Font = Font,
		ActiveCol = SteamButtonHighlight,
		InactiveCol = SteamButtonCol
	}
	if TextScale then
		AlwaysButton:SetTextScale( TextScale )
	end

	function AlwaysButton:DoClick()
		Window:Destroy()

		Shine:CloseWebPage()
		Shine.Config.ShowWebInSteamBrowser = true
		Shine:SaveClientBaseConfig()

		Client.ShowWebpage( URL )
	end

	return Window
end

function Shine:OpenWebpage( URL, TitleText )
	if self.Config.DisableWebWindows then return end
	if self.Config.ShowWebInSteamBrowser then
		Client.ShowWebpage( URL )

		return
	end

	self:CloseWebPage()

	local W = Client.GetScreenWidth()
	local H = Client.GetScreenHeight()

	local WidthMult = Max( W / 1920, 1 )
	local HeightMult = Max( H / 1080, 1 )

	local TitleBarH = 24
	local Font = Fonts.kAgencyFB_Small
	local TextScale
	if W > 1920 and W <= 2880 then
		TitleBarH = TitleBarH * 1.5
		Font = Fonts.kAgencyFB_Medium
	elseif W > 2880 then
		TitleBarH = TitleBarH * 2.5
		Font = Fonts.kAgencyFB_Huge
		TextScale = Vector( 0.6, 0.6, 0 )
	end

	local WindowWidth = W * 0.8
	local WindowHeight = H * 0.8 + TitleBarH

	local Window = SGUI:Create( "Panel" )
	Window:SetupFromTable{
		Size = Vector( WindowWidth, WindowHeight, 0 ),
		Anchor = "CentreMiddle",
		Pos = Vector( -WindowWidth * 0.5, -WindowHeight * 0.5, 0 )
	}
	Window.TitleBarHeight = TitleBarH
	Window:AddTitleBar( TitleText or "Message of the day", Font, TextScale )

	self.ActiveWebPage = Window

	function Window.CloseButton.DoClick()
		Shine:CloseWebPage()
	end

	local OpenInSteamSize = Scale( SteamButtonSize, WidthMult, HeightMult )
	OpenInSteamSize.y = TitleBarH
	local OpenInSteam = Window.TitleBar:Add( "Button" )
	OpenInSteam:SetupFromTable{
		Anchor = "TopRight",
		Pos = Scale( SteamButtonPos, WidthMult, HeightMult ),
		Size = OpenInSteamSize,
		IsSchemed = false,
		Text = "Open in Steam",
		Font = Font,
		TextScale = SteamButtonScale * ( TextScale or Vector( 1, 1, 0 ) ),
		ActiveCol = SteamButtonHighlight,
		InactiveCol = SteamButtonCol
	}

	function OpenInSteam:DoClick()
		local Popup = OpenInSteamPopup( URL, W, H, TitleBarH, Font, TextScale )

		Window:DeleteOnRemove( Popup )
	end

	local LoadingText = Window:Add( "Label" )
	LoadingText:SetupFromTable{
		Anchor = "CentreMiddle",
		Text = "Loading...",
		Font = LoadingFont,
		TextAlignmentX = GUIItem.Align_Center,
		TextAlignmentY = GUIItem.Align_Center
	}

	local WebpageWidth = WindowWidth - 10
	local WebpageHeight = WindowHeight - 10 - TitleBarH

	local Webpage = Window:Add( "Webpage" )
	Webpage:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Webpage:SetPos( Vector( -WebpageWidth * 0.5, -WebpageHeight * 0.5 + TitleBarH * 0.5, 0 ) )
	Webpage:LoadURL( URL, WebpageWidth, WebpageHeight )

	SGUI:EnableMouse( true )
end

function Shine:CloseWebPage()
	if not SGUI.IsValid( self.ActiveWebPage ) then return end

	SGUI:EnableMouse( false )

	self.ActiveWebPage:Destroy()
	self.ActiveWebPage = nil
end

Hook.Add( "PlayerKeyPress", "WebpageClose", function( Key, Down, Amount )
	if not SGUI.IsValid( Shine.ActiveWebPage ) then return end

	if Key == InputKey.Escape then
		Shine:CloseWebPage()

		return true
	end
end, 1 )

Hook.Add( "OnCommanderUILogout", "WebpageClose", function()
	Shine:CloseWebPage()
end )

Client.HookNetworkMessage( "Shine_Web", function( Message )
	Shine:OpenWebpage( Message.URL, Message.Title )
end )
