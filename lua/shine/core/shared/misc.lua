--[[
	Misc. stuff...
]]

Shared.RegisterNetworkMessage( "Shine_ClientConfirmConnect", {} )

do
	local SendNetMessage = Server and Server.SendNetworkMessage or Client.SendNetworkMessage

	-- Use the real thing, don't rely on a global other mods want to change which then breaks us...
	function Shine.SendNetworkMessage( ... )
		return SendNetMessage( ... )
	end
end

Script.Load( "lua/shine/core/shared/hotfix.lua" )

if Server then
	-- Called when the client first presses a button.
	Server.HookNetworkMessage( "Shine_ClientConfirmConnect", function( Client, Data )
		Shine.Hook.Call( "ClientConfirmConnect", Client )
	end )

	local IsType = Shine.IsType

	--[[
		Sends a network message to the given target.

		Inputs:
			1. Target - Either a single player/client, a table of players/clients
			or nil to send to all.
			2. MessageName - The name of the network message.
			3. MessageTable - The data to send.
			4. Reliable - Whether to send reliably.
	]]
	function Shine:ApplyNetworkMessage( Target, MessageName, MessageTable, Reliable )
		if not Target then
			self.SendNetworkMessage( MessageName, MessageTable, Reliable )
			return
		end

		if IsType( Target, "table" ) then
			for i = 1, #Target do
				self.SendNetworkMessage( Target[ i ], MessageName, MessageTable, Reliable )
			end

			return
		end

		self.SendNetworkMessage( Target, MessageName, MessageTable, Reliable )
	end

	return
end

Shine.Hook.Add( "PlayerKeyPress", "ConfirmConnect", function()
	Shine.Hook.Remove( "PlayerKeyPress", "ConfirmConnect" )
	Shine.SendNetworkMessage( "Shine_ClientConfirmConnect", {}, true )
end )
