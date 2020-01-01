--[[
	Server-side chat overrides.
]]

-- Add SteamID and ClientID to chat network messages to allow the client to understand who the message originated from.
Shine.Hook.CallAfterFileLoad( "lua/NetworkMessages.lua", function()
	local OldBuildChatMessage = BuildChatMessage
	function BuildChatMessage(
		TeamOnly, PlayerName, PlayerLocationID, PlayerTeamNumber, PlayerTeamType, ChatMessage
	)
		local Message = OldBuildChatMessage(
			TeamOnly, PlayerName, PlayerLocationID, PlayerTeamNumber, PlayerTeamType, ChatMessage
		)

		-- Location ID is only provided for player messages, so we can use it to know when a message is from a player.
		-- Also, player names are guaranteed to be unique so looking up players using them is fine (and is what
		-- the game's code does on the client).
		if PlayerLocationID >= 0 then
			local Client = Shine.GetClientByExactName( PlayerName )
			-- SteamID is used to know whether the chat message should be muted or not.
			Message.steamId = Client and Client:GetUserId() or 0
			-- ClientID is used to acquire the scoreboard data for the player for commander/rookie tags.
			Message.clientId = Client and Client:GetId() or -1
		else
			Message.steamId = 0
			Message.clientId = -1
		end

		return Message
	end
end )
