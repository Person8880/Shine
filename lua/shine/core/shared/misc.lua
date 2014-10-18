--[[
	Misc. stuff...
]]

--Called when the client first presses a button.
Shared.RegisterNetworkMessage( "Shine_ClientConfirmConnect", {} )

local SendNetMessage = Server and Server.SendNetworkMessage or Client.SendNetworkMessage

--Use the real thing, don't rely on a global other mods want to change which then breaks us...
function Shine.SendNetworkMessage( ... )
	return SendNetMessage( ... )
end

if Server then 
	Server.HookNetworkMessage( "Shine_ClientConfirmConnect", function( Client, Data )
		Shine.Hook.Call( "ClientConfirmConnect", Client )
	end )

	return 
end

Shine.Hook.Add( "OnMapLoad", "SetupConfirmConnect", function()
	local OldKeyPress
	local SentRequest

	OldKeyPress = Shine.ReplaceClassMethod( "Player", "SendKeyEvent", function( self, Key, Down )
		if not SentRequest then
			Shine.SendNetworkMessage( "Shine_ClientConfirmConnect", {}, true )
			
			SentRequest = true
		end

		return OldKeyPress( self, Key, Down )
	end )
end )
