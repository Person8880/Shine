--[[
	Web page window.
]]

local SGUI = Shine.GUI

local Clamp = math.Clamp
local StringByte = string.byte
local StringUTF8Encode = string.UTF8Encode

local Webpage = {}

Webpage.UsesKeyboardFocus = true

local Counter = 0

function Webpage:Initialise()
	local Background = self:MakeGUIItem()
	self.Background = Background
end

function Webpage:CleanupWebView()
	if self.WebView then
		Client.DestroyWebView( self.WebView )

		self.WebView = nil
	end
end

function Webpage:LoadURL( URL, W, H )
	if not self.WebView then
		Counter = Counter + 1
		local TextureName = "*webview_shine_"..Counter

		self.Width = W
		self.Height = H

		self.WebView = Client.CreateWebView( W, H )
		self.WebView:SetTargetTexture( TextureName )

		self.Background:SetSize( Vector( W, H, 0 ) )
		self.Background:SetTexture( TextureName )

		self.WebView:HookJSAlert( function( ... )
			self:OnJSAlert( ... )
		end )
	end

	self.WebView:LoadUrl( URL )
end

function Webpage:GetHasLoaded()
	if not self.WebView then return false end

	return self.WebView:GetUrlLoaded()
end

function Webpage:OnJSAlert( ... )
	-- Override to see JavaScript alerts...
end

function Webpage:ExecuteJS( JavaScript )
	if not self.WebView or not self:GetHasLoaded() then
		error( "Attempted to execute JavaScript before loading a page!", 2 )
	end

	self.WebView:ExecuteJS( JavaScript )
end

function Webpage:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end
	if not self:HasFocus() then return end
	if not self.WebView then return end
	if not Down then return end

	if Key == InputKey.Return then
		self.WebView:OnEnter( Down )
	elseif Key == InputKey.Back then
		self.WebView:OnBackSpace( Down )
	end

	if SGUI:IsControlDown() and Key == InputKey.V then
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

	local Num = StringByte( Char )
	if Num <= 255 then
		self.WebView:OnSendCharacter( Num )
	end

	return true
end

function Webpage:OnMouseMove( LMB )
	if not self.WebView then return end

	local In, X, Y = self:MouseIn( self.Background )

	X = Clamp( X, 0, self.Width )
	Y = Clamp( Y, 0, self.Height )

	self.WebView:OnMouseMove( X, Y )
end

function Webpage:OnMouseDown( Key, DoubleClick )
	if not self.WebView then return end
	if not self:MouseIn( self.Background ) then return end

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
end

function Webpage:OnMouseWheel( Down )
	if not self.WebView then return end
	if not self:MouseIn( self.Background ) then return end

	self.WebView:OnMouseWheel( Down and 30 or -30, 0 )

	return true
end

function Webpage:Cleanup()
	self:CleanupWebView()

	self.BaseClass.Cleanup( self )
end

SGUI:Register( "Webpage", Webpage )
