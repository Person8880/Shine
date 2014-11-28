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
local SteamButtonScale = Vector( 0.8, 0.8, 0 )

local PopupSize = Vector( 400, 176, 0 )
local PopupPos = Vector( -150, -100, 0 )

local NowButtonPos = Vector( -105, -37, 0 )
local PopupButtonSize = Vector( 100, 32, 0 )
local AlwaysButtonPos = Vector( 5, -37, 0 )

local PopupTextPos = Vector( 0, -32, 0 )

local PopupText = [[Open this page in the Steam overlay?
(If you choose always, type "sh_viewwebinsteam 0" 
in the console to get this window back)]]

local function OpenInSteamPopup( URL )
	local Window = SGUI:Create( "Panel" )
	Window:SetupFromTable{
		Size = PopupSize,
		Anchor = "CentreMiddle",
		Pos = PopupPos
	}
	Window:AddTitleBar( "Open in Steam Overlay" )
	Window:SkinColour()

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
		Pos = PopupTextPos,
		Text = PopupText,
		Font = TitleFont,
		Bright = true,
		TextAlignmentX = GUIItem.Align_Center,
		TextAlignmentY = GUIItem.Align_Center
	}

	local NowButton = Window:Add( "Button" )
	NowButton:SetupFromTable{
		Anchor = "BottomMiddle",
		Pos = NowButtonPos,
		Size = PopupButtonSize,
		IsSchemed = false,
		Text = "Now",
		Font = TitleFont,
		ActiveCol = CloseButtonHighlight,
		InactiveCol = CloseButtonCol
	}

	function NowButton:DoClick()
		Window:Destroy()

		Shine:CloseWebPage()
	
		Client.ShowWebpage( URL )
	end

	local AlwaysButton = Window:Add( "Button" )
	AlwaysButton:SetupFromTable{
		Anchor = "BottomMiddle",
		Pos = AlwaysButtonPos,
		Size = PopupButtonSize,
		IsSchemed = false,
		Text = "Always",
		Font = TitleFont,
		ActiveCol = SteamButtonHighlight,
		InactiveCol = SteamButtonCol
	}

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

	local WindowWidth = W * 0.8
	local WindowHeight = H * 0.8 + 24

	local Window = SGUI:Create( "Panel" )
	Window:SetupFromTable{
		Size = Vector( WindowWidth, WindowHeight, 0 ),
		Anchor = "CentreMiddle",
		Pos = Vector( -WindowWidth * 0.5, -WindowHeight * 0.5, 0 )
	}
	Window:AddTitleBar( TitleText or "Message of the day" )
	Window:SkinColour()

	self.ActiveWebPage = Window

	function Window.CloseButton.DoClick()
		Shine:CloseWebPage()
	end

	local OpenInSteam = Window.TitleBar:Add( "Button" )
	OpenInSteam:SetupFromTable{
		Anchor = "TopRight",
		Pos = SteamButtonPos,
		Size = SteamButtonSize,
		IsSchemed = false,
		Text = "Open in Steam",
		Font = TitleFont,
		TextScale = SteamButtonScale,
		ActiveCol = SteamButtonHighlight,
		InactiveCol = SteamButtonCol
	}

	function OpenInSteam:DoClick()
		local Popup = OpenInSteamPopup( URL )

		Window:DeleteOnRemove( Popup )
	end

	local LoadingText = Window:Add( "Label" )
	LoadingText:SetupFromTable{
		Anchor = "CentreMiddle",
		Text = "Loading...",
		Font = LoadingFont,
		Bright = true,
		TextAlignmentX = GUIItem.Align_Center,
		TextAlignmentY = GUIItem.Align_Center
	}

	local WebpageWidth = WindowWidth - 10
	local WebpageHeight = WindowHeight - 34

	local Webpage = Window:Add( "Webpage" )
	Webpage:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Webpage:SetPos( Vector( -WebpageWidth * 0.5, -WebpageHeight * 0.5 + 12, 0 ) )
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
