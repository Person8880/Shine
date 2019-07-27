--[[
	Shine custom chat message system.
]]

local Hook = Shine.Hook

local StringFormat = string.format

do
	local StringMessage = StringFormat( "string (%i)", kMaxChatLength * 4 + 1 )

	local ChatMessage = {
		Prefix = "string (25)",
		Name = StringFormat( "string (%i)", kMaxNameLength * 4 + 1 ),
		TeamNumber = StringFormat( "integer (%i to %i)", kTeamInvalid, kSpectatorIndex ),
		TeamType = StringFormat( "integer (%i to %i)", kNeutralTeamType, kAlienTeamType ),
		Message = StringMessage
	}

	function Shine.BuildChatMessage( Prefix, Name, TeamNumber, TeamType, Message )
		return {
			Prefix = Prefix,
			Name = Name,
			TeamNumber = TeamNumber,
			TeamType = TeamType,
			Message = Message
		}
	end

	Shared.RegisterNetworkMessage( "Shine_Chat", ChatMessage )
	Shared.RegisterNetworkMessage( "Shine_ChatCol", {
		RP = "integer (0 to 255)",
		GP = "integer (0 to 255)",
		BP = "integer (0 to 255)",
		Prefix = StringMessage,
		R = "integer (0 to 255)",
		G = "integer (0 to 255)",
		B = "integer (0 to 255)",
		Message = StringMessage
	} )
	Shared.RegisterNetworkMessage( "Shine_TranslatedChatCol", {
		RP = "integer (0 to 255)",
		GP = "integer (0 to 255)",
		BP = "integer (0 to 255)",
		Prefix = StringMessage,
		R = "integer (0 to 255)",
		G = "integer (0 to 255)",
		B = "integer (0 to 255)",
		Message = StringMessage,
		Source = "string (20)"
	} )
	Shared.RegisterNetworkMessage( "Shine_TranslatedConsoleMessage", {
		Source = "string (20)",
		MessageKey = "string (32)"
	} )
	Shared.RegisterNetworkMessage( "Shine_Notification", {
		Type = "integer (1 to 3)",
		Message = StringMessage,
		Duration = "integer (1 to 15)",
		OnlyIfAdminMenuOpen = "boolean"
	} )
	Shared.RegisterNetworkMessage( "Shine_TranslatedNotification", {
		Type = "integer (1 to 3)",
		Source = "string (20)",
		MessageKey = "string (32)",
		Duration = "integer (1 to 15)",
		OnlyIfAdminMenuOpen = "boolean"
	} )
	Shared.RegisterNetworkMessage( "Shine_ChatErrorMessage", {
		Message = StringMessage,
		Source = "string (20)"
	} )
end

if Client then
	Script.Load( "lua/shine/core/client/chat.lua" )
end
