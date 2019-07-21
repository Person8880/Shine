--[[
	Server-side chat overrides.
]]

local Hook = Shine.Hook

local StringUTF8Sub = string.UTF8Sub

local ChatsPerSecondAdded = 1
local MaxChatsInBucket = 5
local function CheckRateLimit( Client )
	-- Use the same name as the vanilla chat system to keep it consistent.
	Client.chatTokenBucket = Client.chatTokenBucket or CreateTokenBucket( ChatsPerSecondAdded, MaxChatsInBucket )
	return Client.chatTokenBucket:RemoveTokens( 1 )
end

local function ReceiveChat( Client, Data )
	if not CheckRateLimit( Client ) then return end

	local Message = StringUTF8Sub( Data.message, 1, kMaxChatLength )
	if #Message <= 0 then return end

	local Player = Client:GetControllingPlayer()
	if not Player then return end

	local Name = Player:GetName()
	local LocationID = Player.locationId
	local SteamID = Client:GetUserId()
	local TeamNumber = Player:GetTeamNumber()
	local TeamType = Player:GetTeamType()

	local Targets
	if Data.teamOnly then
		Targets = GetEntitiesForTeam( "Player", TeamNumber )
	end

	local MessageToSend = BuildChatMessage(
		not not Data.teamOnly, Name, LocationID, TeamNumber, TeamType, Message, SteamID
	)
	Shine:ApplyNetworkMessage( Targets, "Chat", MessageToSend, true )

	Print( "Chat %s - %s: %s", Data.teamOnly and "Team" or "All", Name, Message )
	Server.AddChatToHistory( Message, Name, SteamID, TeamNumber, Data.teamOnly )

	-- Allow vanilla to process chat commands.
	ProcessSayCommand( Player, Message )
end

Hook.Add( "HookNetworkMessage:ChatClient", "AddChatCallback", function( Message, Callback )
	return function( Client, Message )
		local Result = Hook.Call( "PlayerSay", Client, Message )
		if Result then
			if Result == "" then return end
			Message.message = Result
		end

		return ReceiveChat( Client, Message )
	end
end, Hook.MAX_PRIORITY )
