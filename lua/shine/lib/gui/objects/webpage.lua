--[[
	Web page window.
]]

local SGUI = Shine.GUI

local Clamp = math.Clamp
local StringByte = string.byte
local StringFormat = string.format
local StringGSub = string.gsub
local StringUTF8CodePoint = string.UTF8CodePoint
local StringUTF8Encode = string.UTF8Encode

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

		self:AddPropertyChangeListener( "IsLoading", FlushJSQueue )
	end
end

function Webpage:CleanupWebView()
	if self.WebView then
		Client.DestroyWebView( self.WebView )

		self.WebView = nil
	end
end

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
			self:OnJSAlert( WebView, AlertText )
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

function Webpage:OnJSAlert( WebView, AlertText )
	-- Override to see JavaScript alerts...
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
	self.BaseClass.Think( self, DeltaTime )
	self:CallOnChildren( "Think", DeltaTime )

	if self.IsLoading and self:GetHasLoaded() then
		self.IsLoading = false
		self:OnPropertyChanged( "IsLoading", false )
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
