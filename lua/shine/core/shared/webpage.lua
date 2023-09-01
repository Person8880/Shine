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
local Locale = Shine.Locale
local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local Binder = require "shine/lib/gui/binding/binder"

local CloseButtonCol = Colour( 0.6, 0.3, 0.1, 1 )
local CloseButtonHighlight = Colour( 0.8, 0.4, 0.1, 1 )
local SteamButtonCol = Colour( 0.1, 0.5, 0.1, 1 )
local SteamButtonHighlight = Colour( 0.1, 0.6, 0.1, 1 )
local ButtonTextColour = Colour( 1, 1, 1, 1 )

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

local Max = math.max
local Random = math.random
local StringExplode = string.Explode
local StringFormat = string.format
local StringStartsWith = string.StartsWith
local StringSub = string.sub
local TableConcat = table.concat

local function Scale( Value, WidthMult, HeightMult )
	return Vector( Value.x * WidthMult, Value.y * HeightMult, 0 )
end

local function OpenInSteamPopup( URL, ScrW, ScrH, TitleBarH, Font, TextScale, WebPageWindow )
	local WidthMult = Max( ScrW / 1920, 1 )
	local HeightMult = Max( ScrH / 1080, 1 )

	local Window = SGUI:Create( "Modal" )
	local WindowSize = Scale( PopupSize, WidthMult, HeightMult )
	Window:SetupFromTable{
		Size = WindowSize,
		Anchor = "CentreMiddle",
		Pos = Scale( PopupPos, WidthMult, HeightMult )
	}
	Window.TitleBarHeight = TitleBarH
	Window:AddTitleBar( Locale:GetPhrase( "Core", "OPEN_IN_STEAM_OVERLAY" ), Font, TextScale )

	local Text = Window:Add( "Label" )
	Text:SetupFromTable{
		Anchor = "CentreMiddle",
		Pos = Scale( PopupTextPos, WidthMult, HeightMult ),
		Text = Locale:GetPhrase( "Core", "OPEN_IN_STEAM_OVERLAY_DESCRIPTION" ):gsub( "\n", " " ),
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
		Text = Locale:GetPhrase( "Core", "NOW" ),
		Font = Font,
		ActiveCol = CloseButtonHighlight,
		InactiveCol = CloseButtonCol,
		TextColour = ButtonTextColour
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
		Text = Locale:GetPhrase( "Core", "ALWAYS" ),
		Font = Font,
		ActiveCol = SteamButtonHighlight,
		InactiveCol = SteamButtonCol,
		TextColour = ButtonTextColour
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

	Window:PopUp( WebPageWindow )

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

	local TitleBarH = Units.HighResScaled( 32 ):GetValue()
	local Font, TextScale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )

	local WindowWidth = W * 0.8
	local WindowHeight = H * 0.8 + TitleBarH

	local Window = SGUI:Create( "Panel" )
	Window:SetupFromTable{
		Size = Vector( WindowWidth, WindowHeight, 0 ),
		Anchor = "CentreMiddle",
		Pos = Vector( -WindowWidth * 0.5, -WindowHeight * 0.5, 0 )
	}
	Window.TitleBarHeight = TitleBarH

	TitleText = TitleText and Locale:GetPhrase( "Core", TitleText )
	Window:AddTitleBar( TitleText or Locale:GetPhrase( "Core", "MESSAGE_OF_THE_DAY" ), Font, TextScale )
	Window:SetBoxShadow( {
		BlurRadius = 16,
		Colour = Colour( 0, 0, 0, 0.75 )
	} )

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
		Text = Locale:GetPhrase( "Core", "OPEN_IN_STEAM" ),
		Font = Font,
		TextScale = SteamButtonScale * ( TextScale or Vector( 1, 1, 0 ) ),
		ActiveCol = SteamButtonHighlight,
		InactiveCol = SteamButtonCol,
		TextColour = ButtonTextColour
	}

	function OpenInSteam:DoClick()
		local Popup = OpenInSteamPopup( URL, W, H, TitleBarH, Font, TextScale, Window )

		Window:DeleteOnRemove( Popup )
	end

	local LoadingIndicator = Window:Add( "ProgressWheel" )
	LoadingIndicator:SetupFromTable{
		Anchor = "CentreMiddle",
		HotSpot = "CentreMiddle",
		Size = Vector2( WindowWidth * 0.1, WindowWidth * 0.1 ),
		AnimateLoading = true,
		SpinRate = -math.pi * 2
	}

	local BarPadding = Units.HighResScaled( 5 ):GetValue()
	local WebpageWidth = WindowWidth - BarPadding * 2
	local WebpageHeight = WindowHeight - BarPadding * 3 - TitleBarH * 2

	local WebpageControls = Window:Add( "WebpageControls" )
	WebpageControls:SetPos( Vector2( BarPadding, TitleBarH + BarPadding ) )
	WebpageControls:SetSize( Vector2( WindowWidth - BarPadding * 2, TitleBarH ) )
	WebpageControls:SetFont( Font )
	WebpageControls:SetTextScale( TextScale )

	local Webpage = Window:Add( "Webpage" )
	Webpage:SetPos( Vector2( BarPadding, TitleBarH * 2 + BarPadding * 2 ) )
	-- Replace the initial data-URL to avoid being able to go back to it.
	Webpage:LoadURL( URL, WebpageWidth, WebpageHeight, true )

	WebpageControls:SetWebpage( Webpage )

	-- Hide/show the loading indicator depending on whether the page is actually loading.
	-- Some pages may have transparency which would make the loading indicator visible behind them.
	Binder():FromElement( Webpage, "IsLoading" )
		:ToElement( LoadingIndicator, "IsVisible" )
		:BindProperty()

	SGUI:EnableMouse( true, Window )

	return Webpage
end

function Shine:CloseWebPage()
	if not SGUI.IsValid( self.ActiveWebPage ) then return end

	SGUI:EnableMouse( false, self.ActiveWebPage )

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

Shine.HookNetworkMessage( "Shine_Web", function( Message )
	Shine:OpenWebpage( Message.URL, Message.Title )
end )
