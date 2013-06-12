--[[
	Misc. stuff...
]]

--Called when the client first presses a button, this should be when they're ready to receive the MotD, among other things.
Shared.RegisterNetworkMessage( "Shine_ClientConfirmConnect", {} )

if Server then 
	Server.HookNetworkMessage( "Shine_ClientConfirmConnect", function( Client, Data )
		Shine.Hook.Call( "ClientConfirmConnect", Client )
	end )

	return 
end

Event.Hook( "LoadComplete", function()
	local OldKeyPress
	local SentRequest

	OldKeyPress = Shine.ReplaceClassMethod( "Player", "SendKeyEvent", function( self, Key, Down )
		if not SentRequest then
			Client.SendNetworkMessage( "Shine_ClientConfirmConnect", {}, true )
			
			SentRequest = true
		end

		return OldKeyPress( self, Key, Down )
	end )
end )
