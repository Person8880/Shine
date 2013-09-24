--[[
	Shine web page display system.
]]

Shine = Shine or {}

local WebOpen = {
	URL = "string (255)",
	Title = "string (32)"
}

Shared.RegisterNetworkMessage( "Shine_Web", WebOpen )

if Server then return end

local Hook = Shine.Hook

local SGUI = Shine.GUI

local WindowColour = Colour( 0.3, 0.3, 0.3, 1 )
local TitleColour = Colour( 0.4, 0.4, 0.4, 1 )
local TextColour = Colour( 1, 1, 1, 1 )
local CloseButtonCol = Colour( 0.6, 0.3, 0.1, 1 )
local CloseButtonHighlight = Colour( 0.8, 0.4, 0.1, 1 )
local SteamButtonCol = Colour( 0.1, 0.6, 0.2, 1 )
local SteamButtonHighlight = Colour( 0.15, 0.9, 0.3, 1 )

local LoadingFont = "fonts/AgencyFB_large.fnt"
local TitleFont = "fonts/AgencyFB_small.fnt"

local CloseButtonPos = Vector( -22, 2, 0 )
local CloseButtonSize = Vector( 20, 20, 0 )

local SteamButtonPos = Vector( -150, 2, 0 )
local SteamButtonSize = Vector( 116, 20, 0 )
local SteamButtonScale = Vector( 0.8, 0.8, 0 )

local PopupSize = Vector( 400, 150, 0 )
local PopupPos = Vector( -150, -100, 0 )

local NowButtonPos = Vector( -105, -37, 0 )
local PopupButtonSize = Vector( 100, 32, 0 )
local AlwaysButtonPos = Vector( 5, -37, 0 )

local PopupTextPos = Vector( 0, -48, 0 )

local function OpenInSteamPopup( URL )
	local Window = SGUI:Create( "Panel" )
	Window:SetSize( PopupSize )
	Window:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Window:SetPos( PopupPos )
	Window:SetColour( WindowColour )

	local OldOnMouseDown = Window.OnMouseDown

	function Window:OnMouseDown( Key, DoubleClick )
		if not self:MouseIn( self.Background ) then
			self:Destroy()
			return
		end

		return OldOnMouseDown( self, Key, DoubleClick )
	end

	local Text = Window:Add( "Label" )
	Text:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Text:SetPos( PopupTextPos )
	Text:SetText( "Open this page in the Steam overlay?\n(If you choose always, type \"sh_viewwebinsteam 0\" in\nthe console to get this window back)" )
	Text:SetFont( TitleFont )
	Text:SetColour( TextColour )
	Text:SetTextAlignmentX( GUIItem.Align_Center )
	Text:SetTextAlignmentY( GUIItem.Align_Center )

	local NowButton = Window:Add( "Button" )
	NowButton:SetAnchor( GUIItem.Middle, GUIItem.Bottom )
	NowButton:SetPos( NowButtonPos )
	NowButton:SetSize( PopupButtonSize )
	NowButton:SetIsSchemed( false )
	NowButton:SetText( "Now" )
	NowButton:SetFont( TitleFont )
	NowButton:SetTextColour( TextColour )
	NowButton:SetActiveCol( CloseButtonHighlight )
	NowButton:SetInactiveCol( CloseButtonCol )

	function NowButton:DoClick()
		Window:Destroy()

		Shine:CloseWebPage()
	
		Client.ShowWebpage( URL )
	end

	local AlwaysButton = Window:Add( "Button" )
	AlwaysButton:SetAnchor( GUIItem.Middle, GUIItem.Bottom )
	AlwaysButton:SetPos( AlwaysButtonPos )
	AlwaysButton:SetSize( PopupButtonSize )
	AlwaysButton:SetIsSchemed( false )
	AlwaysButton:SetText( "Always" )
	AlwaysButton:SetFont( TitleFont )
	AlwaysButton:SetTextColour( TextColour )
	AlwaysButton:SetActiveCol( SteamButtonHighlight )
	AlwaysButton:SetInactiveCol( SteamButtonCol )

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
	
	if SGUI.IsValid( self.ActiveWebPage ) then
		self.ActiveWebPage:Destroy()
		self.ActiveWebPage = nil
	end

	local W = Client.GetScreenWidth()
	local H = Client.GetScreenHeight()

	local WindowWidth = W * 0.8
	local WindowHeight = H * 0.8 + 24

	local Window = SGUI:Create( "Panel" )
	Window:SetSize( Vector( WindowWidth, WindowHeight, 0 ) )
	Window:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Window:SetPos( Vector( -WindowWidth * 0.5, -WindowHeight * 0.5, 0 ) )
	Window:SetColour( WindowColour )
	--Window:SetLayer( kGUILayerMainMenuWeb )

	self.ActiveWebPage = Window

	local TitleBar = SGUI:Create( "Panel", Window )
	TitleBar:SetSize( Vector( WindowWidth, 24, 0 ) )
	TitleBar:SetColour( TitleColour )

	local Title = TitleBar:Add( "Label" )
	Title:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Title:SetText( TitleText or "Message of the day" )
	Title:SetFont( TitleFont )
	Title:SetColour( TextColour )
	Title:SetTextAlignmentX( GUIItem.Align_Center )
	Title:SetTextAlignmentY( GUIItem.Align_Center )

	local LoadingText = Window:Add( "Label" )
	LoadingText:SetAnchor( GUIItem.Middle, GUIItem.Center )
	LoadingText:SetText( "Loading..." )
	LoadingText:SetFont( LoadingFont )
	LoadingText:SetColour( TextColour )
	LoadingText:SetTextAlignmentX( GUIItem.Align_Center )
	LoadingText:SetTextAlignmentY( GUIItem.Align_Center )

	local WebpageWidth = WindowWidth - 10
	local WebpageHeight = WindowHeight - 34

	local Webpage = Window:Add( "Webpage" )
	Webpage:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Webpage:SetPos( Vector( -WebpageWidth * 0.5, -WebpageHeight * 0.5 + 12, 0 ) )
	Webpage:LoadURL( URL, WebpageWidth, WebpageHeight )

	local CloseButton = TitleBar:Add( "Button" )
	CloseButton:SetAnchor( GUIItem.Right, GUIItem.Top )
	CloseButton:SetPos( CloseButtonPos )
	CloseButton:SetSize( CloseButtonSize )
	CloseButton:SetIsSchemed( false )
	CloseButton:SetText( "X" )
	CloseButton:SetTextColour( TextColour )
	CloseButton:SetActiveCol( CloseButtonHighlight )
	CloseButton:SetInactiveCol( CloseButtonCol )

	function CloseButton:DoClick()
		Shine:CloseWebPage()
	end

	local OpenInSteam = TitleBar:Add( "Button" )
	OpenInSteam:SetAnchor( GUIItem.Right, GUIItem.Top )
	OpenInSteam:SetPos( SteamButtonPos )
	OpenInSteam:SetSize( SteamButtonSize )
	OpenInSteam:SetIsSchemed( false )
	OpenInSteam:SetText( "Open in Steam" )
	OpenInSteam:SetTextColour( TextColour )
	OpenInSteam:SetFont( TitleFont )
	OpenInSteam:SetTextScale( SteamButtonScale )
	OpenInSteam:SetActiveCol( SteamButtonHighlight )
	OpenInSteam:SetInactiveCol( SteamButtonCol )

	function OpenInSteam:DoClick()
		local Popup = OpenInSteamPopup( URL )

		Window:DeleteOnRemove( Popup )
	end

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
