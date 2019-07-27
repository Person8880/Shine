--[[
	Server-side chat overrides.
]]

local Hook = Shine.Hook

-- Add SteamID to chat network messages to allow the client to understand who the message originated from.
Hook.CallAfterFileLoad( "lua/NetworkMessages.lua", function()
	local OldBuildChatMessage = BuildChatMessage
	function BuildChatMessage(
		TeamOnly, PlayerName, PlayerLocationID, PlayerTeamNumber, PlayerTeamType, ChatMessage
	)
		local Message = OldBuildChatMessage(
			TeamOnly, PlayerName, PlayerLocationID, PlayerTeamNumber, PlayerTeamType, ChatMessage
		)

		-- Location ID is only provided for player messages, so we can use it to know when a message is from a player.
		-- Also, player names are guaranteed to be unique so looking up the Steam ID using them is fine (and is what
		-- the game's code does on the client).
		if PlayerLocationID >= 0 then
			local Client = Shine.GetClientByExactName( PlayerName )
			Message.steamId = Client and Client:GetUserId() or 0
		else
			Message.steamId = 0
		end

		return Message
	end
end )

Hook.Add( "HookNetworkMessage:ChatClient", "AddChatCallback", function( Message, Callback )
	return function( Client, Message )
		local Result = Hook.Call( "PlayerSay", Client, Message )
		if Result then
			if Result == "" then return end
			Message.message = Result
		end

		return Callback( Client, Message )
	end
end, Hook.MAX_PRIORITY )
