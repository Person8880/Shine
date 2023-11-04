--[[
	Web page window.
]]

local Binder = require "shine/lib/gui/binding/binder"

local SGUI = Shine.GUI
local Controls = SGUI.Controls
local Units = SGUI.Layout.Units

local Clamp = math.Clamp
local Random = math.random
local StringByte = string.byte
local StringExplode = string.Explode
local StringFormat = string.format
local StringGSub = string.gsub
local StringMatch = string.match
local StringStartsWith = string.StartsWith
local StringSub = string.sub
local StringUTF8CodePoint = string.UTF8CodePoint
local StringUTF8Encode = string.UTF8Encode
local TableConcat = table.concat

local JavaScriptStringReplacements = {
	[ "\\" ] = "\\\\",
	[ "\0" ] = "\\x00" ,
	[ "\b" ] = "\\b" ,
	[ "\t" ] = "\\t" ,
	[ "\n" ] = "\\n" ,
	[ "\v" ] = "\\v" ,
	[ "\f" ] = "\\f" ,
	[ "\r" ] = "\\r" ,
	[ "\"" ] = "\\\"",
	[ "'" ] = "\\'",
	[ "`" ] = "\\`",
	[ "$" ] = "\\$",
	[ "{" ] = "\\{",
	[ "}" ] = "\\}"
}
local function EscapeStringForJavaScript( String )
	local EscapedString = StringGSub( String, ".", JavaScriptStringReplacements )
	-- Escape line/paragraph break characters that get interpreted as line breaks in code.
	EscapedString = StringGSub( EscapedString, "\226\128\168", "\\\226\128\168" )
	EscapedString = StringGSub( EscapedString, "\226\128\169", "\\\226\128\169" )
	return EscapedString
end

local Webpage = {}

-- Expose as a helper, only really relevant here as this is the only place that interacts with JavaScript.
Webpage.EscapeStringForJavaScript = EscapeStringForJavaScript

Webpage.UsesKeyboardFocus = true

local Counter = 0

do
	local function FlushJSQueue( self, IsLoading )
		if IsLoading or #self.JSQueue == 0 then return end

		-- When the page has finished loading, execute any queued JS.
		for i = 1, #self.JSQueue do
			self.WebView:ExecuteJS( self.JSQueue[ i ] )
			self.JSQueue[ i ] = nil
		end
	end

	function Webpage:Initialise()
		self.Background = self:MakeGUIItem()

		self.JSQueue = {}
		self.IsLoading = false
		self.LocationURL = ""
		self.IsSecure = false

		self:AddPropertyChangeListener( "IsLoading", FlushJSQueue )
	end
end

function Webpage:CleanupWebView()
	if self.WebView then
		Client.DestroyWebView( self.WebView )

		self.WebView = nil
	end
end

local OnAlertError = Shine.BuildErrorHandler( "Webpage alert callback error" )

function Webpage:LoadURL( URL, W, H, Replace )
	if not self.WebView then
		Counter = Counter + 1
		local TextureName = "*webview_shine_"..Counter

		self.Width = W
		self.Height = H

		self.WebView = Client.CreateWebView( W, H )
		self.WebView:SetTargetTexture( TextureName )

		self:SetSize( Vector2( W, H ) )
		self.Background:SetTexture( TextureName )

		self.WebView:HookJSAlert( function( WebView, AlertText )
			xpcall( self.OnJSAlert, OnAlertError, self, WebView, AlertText )
		end )
	end

	if Replace then
		-- Overwrite the current URL with the given URL to avoid it showing up in the history.
		-- This is mainly useful for the initial URL load, as the first URL loaded is a basic data-URL with an empty
		-- HTML body which doesn't make sense to navigate back to.
		self:ExecuteJS( StringFormat( [[location.replace( "%s" );]], EscapeStringForJavaScript( URL ) ) )
	else
		self.WebView:LoadUrl( URL )
	end

	self.IsLoading = true
	self:OnPropertyChanged( "IsLoading", true )

	self.LocationURL = URL
	self:OnPropertyChanged( "LocationURL", URL )
end

--[[
	Loads the given HTML string as a data-URL. Note that beyond a certain size
	the WebView will reject the URL.

	If you need to create large HTML pages, consider injecting small bootstrapping
	HTML, then using ExecuteJS() to update the DOM as it has a larger limit.
]]
function Webpage:LoadHTML( HTML, W, H )
	return self:LoadURL( StringFormat( "data:text/html;%s", HTML ), W, H )
end

function Webpage:GetHasLoaded()
	if not self.WebView then return false end

	return self.WebView:GetUrlLoaded()
end

local UpdateLocationScript = [[alert(
	"%s:LOCATION_CHANGE:" + ( window.isSecureContext ? "1" : "0" ) + ":"  + location.href
);]]

function Webpage:UpdateLocation()
	self:ExecuteJS( StringFormat( UpdateLocationScript, self.AlertPrefix ) )
	self.NextLocationUpdate = SGUI.GetTime() + 0.1
end

local function OnLoadingChanged( self, IsLoading )
	if IsLoading then return end

	self:UpdateLocation()
end

function Webpage:ObserveLocationChanges( ShouldObserve )
	if ShouldObserve and not self.AlertPrefix then
		self.AlertPrefix = "SHINE_WEBPAGE_"..Random()
		self.NextLocationUpdate = 0
		self:AddPropertyChangeListener( "IsLoading", OnLoadingChanged )
	elseif not ShouldObserve and self.AlertPrefix then
		self.AlertPrefix = nil
		self.NextLocationUpdate = nil
		self:RemovePropertyChangeListener( "IsLoading", OnLoadingChanged )
	end
end

do
	local Actions = {
		LOCATION_CHANGE = function( self, Segments )
			local IsSecure = Segments[ 2 ] == "1"
			local URL = TableConcat( Segments, ":", 3 )

			if IsSecure ~= self.IsSecure then
				self.IsSecure = IsSecure
				self:OnPropertyChanged( "IsSecure", IsSecure )
			end

			if URL ~= self.LocationURL then
				self.LocationURL = URL
				self:OnPropertyChanged( "LocationURL", URL )
			end
		end
	}

	function Webpage:OnJSAlert( WebView, AlertText )
		if not self.AlertPrefix then return end
		if not StringStartsWith( AlertText, self.AlertPrefix ) then return end

		local Message = StringSub( AlertText, #self.AlertPrefix + 2 )
		local Segments = StringExplode( Message, ":", true )
		local Action = Segments[ 1 ]
		if not Actions[ Action ] then return end

		Actions[ Action ]( self, Segments )
	end
end

function Webpage:ExecuteJS( JavaScript )
	if not self.WebView then
		error( "Attempted to execute JavaScript before loading a page!", 2 )
	end

	if not self:GetHasLoaded() then
		-- Can't execute yet, so wait until we can.
		self.JSQueue[ #self.JSQueue + 1 ] = JavaScript
		return false
	end

	self.WebView:ExecuteJS( JavaScript )

	return true
end

function Webpage:Think( DeltaTime )
	if not self:GetIsVisible() then return end

	self.BaseClass.ThinkWithChildren( self, DeltaTime )

	if self.IsLoading then
		if not self:GetHasLoaded() then return end

		self.IsLoading = false
		self:OnPropertyChanged( "IsLoading", false )
	end

	-- Alerts never seem to be received by Lua when placed in callbacks at the JS level, so this polling hack is the
	-- only way to update the current URL.
	if self.AlertPrefix and SGUI.GetTime() >= self.NextLocationUpdate then
		self:UpdateLocation()
	end
end

function Webpage:NavigateBack()
	return self:ExecuteJS( "history.back();" )
end

function Webpage:NavigateForward()
	return self:ExecuteJS( "history.forward();" )
end

function Webpage:ReloadCurrentPage()
	if not self:GetHasLoaded() then return end
	return self:ExecuteJS( "location.reload();" )
end

function Webpage:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end
	if not self.WebView then return end

	if not Down and self:MouseInCached() then
		if Key == InputKey.MouseButton4 then
			self:NavigateForward()
			return true
		end

		if Key == InputKey.MouseButton3 then
			self:NavigateBack()
			return true
		end
	end

	if not self:HasFocus() then return end

	if Key == InputKey.Return then
		self.WebView:OnEnter( Down )
	elseif Key == InputKey.Back then
		self.WebView:OnBackSpace( Down )
	elseif Key == InputKey.Space then
		self.WebView:OnSpace( Down )
	elseif Key == InputKey.Escape then
		self.WebView:OnEscape( Down )
	end

	if Down and SGUI:IsControlDown() and Key == InputKey.V then
		local Chars = StringUTF8Encode( SGUI.GetClipboardText() )
		for i = 1, #Chars do
			self:PlayerType( Chars[ i ] )
		end
	end

	return true
end

function Webpage:PlayerType( Char )
	if not self:GetIsVisible() then return end
	if not self:HasFocus() then return end
	if not self.WebView then return end

	local CodePoint = StringUTF8CodePoint( StringByte( Char, 1, 4 ) )
	self.WebView:OnSendCharacter( CodePoint )

	return true
end

function Webpage:OnMouseMove( LMB )
	self.BaseClass.OnMouseMove( self, LMB )

	if not self.WebView then return end
	if not self:GetIsVisible() then return end

	local In, X, Y = self:MouseInCached()

	X = Clamp( X, 0, self.Width )
	Y = Clamp( Y, 0, self.Height )

	self.WebView:OnMouseMove( X, Y )
end

function Webpage:OnMouseDown( Key, DoubleClick )
	if not self.WebView then return end
	if not self:GetIsVisible() then return end
	if not self:HasMouseEntered() then return end

	local MouseButton0 = InputKey.MouseButton0
	if Key ~= MouseButton0 then return end

	local KeyCode = Key - MouseButton0
	self.WebView:OnMouseDown( KeyCode )

	self:RequestFocus()

	return true, self
end

function Webpage:OnMouseUp( Key )
	if not self.WebView then return end

	local MouseButton0 = InputKey.MouseButton0
	if Key ~= MouseButton0 then return end

	local KeyCode = Key - MouseButton0
	self.WebView:OnMouseUp( KeyCode )

	if self.AlertPrefix then
		self:UpdateLocation()
	end

	return true
end

function Webpage:OnMouseWheel( Down )
	if not self.WebView then return end
	if not self:GetIsVisible() then return end
	if not self:HasMouseEntered() then return end

	self.WebView:OnMouseWheel( Down and 30 or -30, 0 )

	return true
end

function Webpage:Cleanup()
	self:CleanupWebView()

	self.BaseClass.Cleanup( self )
end

SGUI:Register( "Webpage", Webpage )

-- Basic control bar for a Webpage element providing back + forward buttons, a security icon, a URL text entry, and a
-- refresh button.
local WebpageControls = {}
local SecureIconColours = {
	[ false ] = Colour( 0.7, 0, 0 ),
	[ true ] = Colour( 0, 0.6, 0 )
}

SGUI.AddBoundProperty( WebpageControls, "Font", "URLEntry" )
SGUI.AddBoundProperty( WebpageControls, "TextScale", "URLEntry" )
SGUI.AddBoundProperty( WebpageControls, "InputEnabled", "URLEntry:SetEnabled" )

function WebpageControls:Initialise()
	Controls.Row.Initialise( self )

	-- Do not allow arbitrary navigation by default, keep it to just the loaded page.
	self.InputEnabled = false
	self:SetShader( SGUI.Shaders.Invisible )

	local ButtonSize = Units.UnitVector( Units.OppositeAxisPercentage.ONE_HUNDRED, Units.Percentage.ONE_HUNDRED )
	local ElementMargin = Units.HighResScaled( 5 )

	local Elements = SGUI:BuildTree( {
		Parent = self,
		{
			Class = "Button",
			Props = {
				AutoSize = ButtonSize,
				Icon = SGUI.Icons.Ionicons.ArrowLeftC,
				DoClick = function()
					self.Webpage:NavigateBack()
				end
			}
		},
		{
			Class = "Button",
			Props = {
				AutoSize = ButtonSize,
				Icon = SGUI.Icons.Ionicons.ArrowRightC,
				DoClick = function()
					self.Webpage:NavigateForward()
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
				Margin = Units.Spacing( ElementMargin, 0, 0, 0 ),
				Text = SGUI.Icons.Ionicons.Locked,
				IsSchemed = false,
				CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE
			}
		},
		{
			Class = "TextEntry",
			ID = "URLEntry",
			Props = {
				Fill = true,
				Margin = Units.Spacing( ElementMargin, 0, ElementMargin, 0 ),
				Enabled = self.InputEnabled,
				-- If input is enabled, allow navigation when pressing enter.
				OnEnter = function()
					local URL = self.URLEntry:GetText()
					local Protocol = StringMatch( URL, "^(%w+)://" )
					if not Protocol then
						URL = StringFormat( "https://%s", URL )
					elseif Protocol ~= "http" and Protocol ~= "https" then
						return
					end

					self.Webpage:LoadURL( URL )
					self.URLEntry:LoseFocus()
				end
			}
		},
		{
			Class = "Button",
			Props = {
				AutoSize = ButtonSize,
				Icon = SGUI.Icons.Ionicons.Refresh,
				DoClick = function()
					self.Webpage:ReloadCurrentPage()
				end
			}
		}
	} )

	self.URLEntry = Elements.URLEntry
	self.SecureIcon = Elements.SecureIcon
end

function WebpageControls:SetWebpage( WebpageElement )
	self.Webpage = WebpageElement

	-- Change the secure icon based on the reported secure context state of the page.
	Binder():FromElement( WebpageElement, "IsSecure" )
		:ToElement( self.SecureIcon, "Text", {
			Transformer = function( IsSecure )
				return SGUI.Icons.Ionicons[ IsSecure and "Locked" or "Unlocked" ]
			end
		} )
		:ToElement( self.SecureIcon, "Colour", {
			Transformer = function( IsSecure )
				return SecureIconColours[ IsSecure == true ]
			end
		} ):BindProperty()

	-- Update the URL text entry with the current known URL, providing it's not in focus and the URL isn't internal.
	Binder():FromElement( WebpageElement, "LocationURL" )
		:ToElement( self.URLEntry, "Text", {
			Filter = function( LocationURL )
				return StringStartsWith( LocationURL, "http" ) and not self.URLEntry:HasFocus()
			end,
			Transform = function( LocationURL )
				return StringSub( LocationURL, 1, 255 )
			end
		} ):BindProperty()

	WebpageElement:ObserveLocationChanges( true )
end

SGUI:Register( "WebpageControls", WebpageControls, "Row" )
