--[[
	Web page window.
]]

local SGUI = Shine.GUI

local Webpage = {}

local Counter = 0

function Webpage:Initialise()
	local Background = GetGUIManager():CreateGraphicItem()

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

		self.WebView = Client.CreateWebView( W, H )
		self.WebView:SetTargetTexture( TextureName )
		
		self.Background:SetSize( Vector( W, H, 0 ) )
		self.Background:SetTexture( TextureName )
	end
	
	self.WebView:LoadUrl( URL )
end

function Webpage:GetHasLoaded()
	if not self.WebView then return false end
	
	return self.WebView:GetUrlLoaded()
end

function Webpage:OnMouseMove( LMB )
	if not self.WebView then return end
	
	local In, X, Y = self:MouseIn( self.Background )

	if not In then return end
	
	self.WebView:OnMouseMove( X, Y )
end

function Webpage:OnMouseDown( Key, DoubleClick )
	if not self.WebView then return end
	if not self:MouseIn( self.Background ) then return end

	local MouseButton0 = InputKey.MouseButton0
	if Key ~= MouseButton0 then return end
	
	local KeyCode = Key - MouseButton0
	self.WebView:OnMouseDown( KeyCode )

	return true
end

function Webpage:OnMouseUp( Key )
	if not self.WebView then return end
	if not self:MouseIn( self.Background ) then return end

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
