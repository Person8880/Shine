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

	local Webpage
	local BarPadding = Units.HighResScaled( 5 )
	local WebpageWidth = WindowWidth - BarPadding:GetValue() * 2
	local WebpageHeight = WindowHeight - BarPadding:GetValue() * 2 - TitleBarH * 2
	local SecureIconColours = {
		[ false ] = Colour( 0.7, 0, 0 ),
		[ true ] = Colour( 0, 0.6, 0 )
	}

	local ControlBar = SGUI:BuildTree( {
		Parent = Window,
		{
			Class = "Row",
			Props = {
				Pos = Vector2( 0, TitleBarH ),
				Size = Vector2( WindowWidth, TitleBarH ),
				Padding = Units.Spacing( BarPadding, BarPadding, BarPadding, 0 ),
			},
			Children = {
				{
					Class = "Button",
					Props = {
						AutoSize = Units.UnitVector( Units.HighResScaled( 32 ), Units.Percentage( 100 ) ),
						Icon = SGUI.Icons.Ionicons.ArrowLeftC,
						DoClick = function()
							Webpage:NavigateBack()
						end
					}
				},
				{
					Class = "Button",
					Props = {
						AutoSize = Units.UnitVector( Units.HighResScaled( 32 ), Units.Percentage( 100 ) ),
						Icon = SGUI.Icons.Ionicons.ArrowRightC,
						DoClick = function()
							Webpage:NavigateForward()
						end
					}
				},
				{
					Class = "Label",
					ID = "SecureIcon",
					Props = {
						AutoFont = {
							Family = SGUI.FontFamilies.Ionicons,
							Size = Units.HighResScaled( 27 )
						},
						Colour = SecureIconColours[ true ],
						Margin = Units.Spacing( BarPadding, 0, 0, 0 ),
						Text = SGUI.Icons.Ionicons.Locked,
						IsSchemed = false
					}
				},
				{
					Class = "TextEntry",
					ID = "URLEntry",
					Props = {
						Fill = true,
						Font = Font,
						Margin = Units.Spacing( BarPadding, 0, BarPadding, 0 ),
						-- Do not allow arbitrary navigation, keep it to just the loaded page.
						Enabled = false,
						Text = URL,
						TextScale = TextScale
					}
				},
				{
					Class = "Button",
					Props = {
						AutoSize = Units.UnitVector( Units.HighResScaled( 32 ), Units.Percentage( 100 ) ),
						Icon = SGUI.Icons.Ionicons.Refresh,
						DoClick = function()
							Webpage:ReloadCurrentPage()
						end
					}
				}
			}
		}
	} )

	Webpage = Window:Add( "Webpage" )
	Webpage:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Webpage:SetPos( Vector( -WebpageWidth * 0.5, -WebpageHeight * 0.5 + TitleBarH, 0 ) )
	-- Replace the initial data-URL to avoid being able to go back to it.
	Webpage:LoadURL( URL, WebpageWidth, WebpageHeight, true )

	local AlertPrefix = "SHINE_WEBPAGE_"..Random()
	local Actions = {
		LOCATION_CHANGE = function( Segments )
			local IsSecure = Segments[ 2 ] == "1"
			ControlBar.SecureIcon:SetText( SGUI.Icons.Ionicons[ IsSecure and "Locked" or "Unlocked" ] )
			ControlBar.SecureIcon:SetColour( SecureIconColours[ IsSecure ] )

			local URL = TableConcat( Segments, ":", 3 )
			-- Hide the internal data URL used at startup.
			if not StringStartsWith( URL, "http" ) then return end

			ControlBar.URLEntry:SetText( StringSub( URL, 1, 255 ) )
		end
	}
	function Webpage:OnJSAlert( _, Alert )
		if not StringStartsWith( Alert, AlertPrefix ) then return end

		local Message = StringSub( Alert, #AlertPrefix + 2 )
		local Segments = StringExplode( Message, ":", true )
		local Action = Segments[ 1 ]
		if not Actions[ Action ] then return end

		Actions[ Action ]( Segments )
	end

	local UpdateLocationScript = [[alert(
		"%s:LOCATION_CHANGE:" + ( window.isSecureContext ? "1" : "0" ) + ":"  + location.href
	);]]
	function Webpage:UpdateLocation()
		self:ExecuteJS( StringFormat( UpdateLocationScript, AlertPrefix ) )
	end

	local OldOnMouseUp = Webpage.OnMouseUp
	function Webpage:OnMouseUp( Key )
		if OldOnMouseUp( self, Key ) then
			self:UpdateLocation()
			return true
		end
	end

	Webpage:AddPropertyChangeListener( "IsLoading", function( Webpage, IsLoading )
		if not IsLoading then
			Webpage:UpdateLocation()

			-- Alerts never seem to be received by Lua when placed in callbacks at the JS level, so this polling
			-- hack is the only way to update the current URL.
			Shine.Timer.Create( "WebpageUpdate", 0.1, -1, function( Timer )
				if not SGUI.IsValid( Webpage ) then
					Timer:Destroy()
					return
				end

				Webpage:UpdateLocation()
			end )
		end
	end )

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

	Shine.Timer.Destroy( "WebpageUpdate" )
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
