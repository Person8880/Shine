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
	Counter = Counter + 1
	local TextureName = "*webview_shine_"..Counter

	self:CleanupWebView()

	self.WebView = Client.CreateWebView( W, H )
	self.WebView:SetTargetTexture( TextureName )
	self.WebView:LoadUrl( URL )

	self.Background:SetSize( Vector( W, H, 0 ) )
	self.Background:SetTexture( TextureName )
end

function Webpage:Think( DeltaTime )
	if not self.WebView then return end
	
	local In, X, Y = self:MouseIn( self.Background )

	if not In then return end
	
	self.WebView:OnMouseMove( X, Y )
end

function Webpage:PlayerKeyPress( Key, Down, Amount )
	if not self.WebView then return end
	if not self:MouseIn( self.Background ) then return end
	
	local MouseButton0 = InputKey.MouseButton0

	if Key == InputKey.MouseZ then
		self.WebView:OnMouseWheel( Amount > 0 and 30 or -30, 0 )

		return true
	elseif Key == MouseButton0 then
		local KeyCode = Key - MouseButton0

		if Down then
			self.WebView:OnMouseDown( KeyCode )
		else
			self.WebView:OnMouseUp( KeyCode )
		end

		return true
	end
end

function Webpage:Cleanup()
	self:CleanupWebView()

	self.BaseClass.Cleanup( self )
end

SGUI:Register( "Webpage", Webpage )
