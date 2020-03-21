--[[
	Provides a way for errors/warnings/recommendations to be recorded at startup and sent to admins when they connect.

	This avoids errors in configuration going unnoticed.

	A system notification has the following structure:
	{
		-- The ID of the notification.
		ID = "afkkick_CONFIG_JSON_INVALID",

		-- The type of notification (one of ERROR, WARNING or INFO).
		Type = SystemNotifications.Type.ERROR,

		-- The message to be displayed.
		Message = {
			-- The translation key source.
			Source = "core",
			-- The translation key to use.
			TranslationKey = "ERROR_PLUGIN_CONFIG_JSON_INVALID",
			-- Any extra context (e.g. error message).
			Context = "] expected at line 1, column 16"
		},

		-- The source of the notification
		Source = {
			-- The type of source (one of PLUGIN, CORE).
			Type = SystemNotifications.Source.PLUGIN,
			-- If Type == PLUGIN, then the name of the plugin.
			ID = "afkkick"
		}
	}
]]

local SystemNotifications = {}
Shine.SystemNotifications = SystemNotifications

do
	local StringFormat = string.format

	local TypeNames = {
		"INFO", "WARNING", "ERROR"
	}
	SystemNotifications.Type = table.AsEnum( TypeNames )
	SystemNotifications.TypeOrdinal = table.AsEnum( TypeNames, function( Index ) return Index end )

	local SourceNames = {
		"PLUGIN", "CORE"
	}
	SystemNotifications.Source = table.AsEnum( SourceNames )
	SystemNotifications.SourceOrdinal = table.AsEnum( SourceNames, function( Index ) return Index end )

	Shared.RegisterNetworkMessage( "Shine_GetSystemNotifications", {
		RequestID = "integer (0 to 255)"
	} )
	Shared.RegisterNetworkMessage( "Shine_StartSystemNotificationsResponse", {
		RequestID = "integer (0 to 255)",
		NumNotifications = "integer",
		AllowedToViewNotifications = "boolean"
	} )

	local NotificationMessage = {
		ID = "string (128)",
		Type = StringFormat( "integer (1 to %d)", #TypeNames ),

		MessageSource = "string (20)",
		MessageKey = "string (64)",
		MessageContext = "string (128)",

		SourceType = StringFormat( "integer (1 to %d)", #SourceNames ),
		SourceID = "string (20)"
	}

	Shared.RegisterNetworkMessage( "Shine_PushSystemNotification", NotificationMessage )
	Shared.RegisterNetworkMessage( "Shine_SendSystemNotification", table.ShallowMerge( NotificationMessage, {
		RequestID = "integer (0 to 255)"
	} ) )
	Shared.RegisterNetworkMessage( "Shine_SendSystemNotificationSummary", {
		Type = StringFormat( "integer (1 to %d)", #TypeNames )
	} )
end

if Server then
	Script.Load( "lua/shine/core/server/system_notifications.lua" )
else
	Script.Load( "lua/shine/core/client/system_notifications.lua" )
end
