--[[
	Shine web page display system.
]]

Shine = Shine or {}

local WebOpen = {
	URL = "string (255)"
}

Shared.RegisterNetworkMessage( "Shine_Web", WebOpen )

if Server then return end

local WebWindow

Client.HookNetworkMessage( "Shine_Web", function( Message )
	local Manager = GetGUIManager()

	if WebWindow then
		Manager:DestroyGUIScript( WebWindow )
	end
	
	MouseTracker_SetIsVisible( true, "ui/Cursor_MenuDefault.dds", true )

	WebWindow = Manager:CreateGUIScript( "GUIWebView" )
	local OldSendKeyEvent = WebWindow.SendKeyEvent

	--Need to override this so the mouse is removed on close.
	function WebWindow:SendKeyEvent(key, down)
		if not self.background then
			return false
		end
		
		local isReleventKey = false
		
		if type(self.buttonDown[key]) == "boolean" then
			isReleventKey = true
		end
		
		local mouseX, mouseY = Client.GetCursorPosScreen()
		if isReleventKey then
		
			local containsPoint, withinX, withinY = GUIItemContainsPoint(self.background, mouseX, mouseY)
			if down and not containsPoint then
				MouseTracker_SetIsVisible( false, "ui/Cursor_MenuDefault.dds", true )
				self:Uninitialize()
				return true    
			end
			
			containsPoint, withinX, withinY = GUIItemContainsPoint(self.webContainer, mouseX, mouseY)
			
			if containsPoint or (not down and self.buttonDown[key]) then
			
				local buttonCode = key - InputKey.MouseButton0
				if down then
					self.webView:OnMouseDown(buttonCode)
				else
					self.webView:OnMouseUp(buttonCode)
				end
				
				self.buttonDown[key] = down
				
				return true
				
			elseif (key == InputKey.MouseButton0 and down and GUIItemContainsPoint(self.close, mouseX, mouseY)) then
				MouseTracker_SetIsVisible( false, "ui/Cursor_MenuDefault.dds", true )
				self:Uninitialize()
				return true
				
			end
			
		elseif key == InputKey.MouseZ then
			self.webView:OnMouseWheel(down and 30 or -30, 0)
		elseif key == InputKey.Escape then
			MouseTracker_SetIsVisible( false, "ui/Cursor_MenuDefault.dds", true )
			self:Uninitialize()
			return true
			
		end
		
		return false
		
	end

	WebWindow:LoadUrl( Message.URL, Client.GetScreenWidth() * 0.8, Client.GetScreenHeight() * 0.8 )

	local Background = WebWindow:GetBackground()

	Background:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Background:SetPosition( -Background:GetSize() / 2 )
	Background:SetLayer( kGUILayerMainMenuWeb )
	Background:SetIsVisible( true )
end )
