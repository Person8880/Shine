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

local LoadingFont = "fonts/AgencyFB_large.fnt"
local TitleFont = "fonts/AgencyFB_small.fnt"

local CloseButtonPos = Vector( -22, 2, 0 )
local CloseButtonSize = Vector( 20, 20, 0 )

function Shine:OpenWebpage( URL, TitleText )
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
		SGUI:EnableMouse( false )

		Window:Destroy()

		Shine.ActiveWebPage = nil
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
