--[[
	System notifications server-side.
]]

local SystemNotifications = Shine.SystemNotifications
SystemNotifications.Notifications = {}

local ACCESS_RIGHT = "sh_view_system_notifications"

--[[
	Adds a new notification to the system notifications list.
]]
function SystemNotifications:AddNotification( Notification )
	Shine.TypeCheck( Notification, "table", 1, "AddNotification" )
	Shine.TypeCheckField( Notification, "ID", { "string", "nil" }, "Notification" )
	Shine.AssertAtLevel( self.Type[ Notification.Type ], "Invalid notification type: %s", 3, Notification.Type )

	Shine.TypeCheckField( Notification, "Message", "table", "Notification" )
	Shine.TypeCheckField( Notification.Message, "Source", "string", "Notification.Message" )
	Shine.TypeCheckField( Notification.Message, "TranslationKey", "string", "Notification.Message" )
	Shine.TypeCheckField( Notification.Message, "Context", { "string", "nil" }, "Notification.Message" )

	Shine.TypeCheckField( Notification, "Source", "table", "Notification" )
	Shine.AssertAtLevel(
		self.Source[ Notification.Source.Type ], "Invalid source type: %s", 3, Notification.Source.Type
	)
	Shine.TypeCheckField( Notification.Source, "ID", { "string", "nil" }, "Notification.Source" )

	self.Notifications[ #self.Notifications + 1 ] = Notification

	local Severity = self.TypeOrdinal[ Notification.Type ]
	if Severity > ( self.CurrentSeverity or -1 ) then
		self.CurrentSeverity = Severity
	end
end

--[[
	Indicates the current maximum severity of all notifications.
]]
function SystemNotifications:GetSeverity()
	return self.CurrentSeverity or -1
end

local function SendNotification( Client, Notification, RequestID )
	Shine.SendNetworkMessage( Client, "Shine_SendSystemNotification", {
		RequestID = RequestID,

		ID = Notification.ID or "",
		Type = SystemNotifications.TypeOrdinal[ Notification.Type ],

		MessageSource = Notification.Message.Source,
		MessageKey = Notification.Message.TranslationKey,
		MessageContext = Notification.Message.Context or "",

		SourceType = SystemNotifications.SourceOrdinal[ Notification.Source.Type ],
		SourceID = Notification.Source.ID or ""
	}, true )
end

local function CanClientSeeNotifications( Client )
	return Shine:HasAccess( Client, ACCESS_RIGHT ) and Shine:HasAccess( Client, "sh_adminmenu" )
end

local function ReceiveNotificationListRequest( Client, RequestID )
	if not CanClientSeeNotifications( Client ) then
		-- Send network message indicating denial.
		Shine.SendNetworkMessage( Client, "Shine_StartSystemNotificationsResponse", {
			RequestID = RequestID,
			NumNotifications = 0,
			AllowedToViewNotifications = false
		}, true )
		return
	end

	-- Send notifications to client.
	Shine.SendNetworkMessage( Client, "Shine_StartSystemNotificationsResponse", {
		RequestID = RequestID,
		NumNotifications = #SystemNotifications.Notifications,
		AllowedToViewNotifications = true
	}, true )

	for i = 1, #SystemNotifications.Notifications do
		SendNotification( Client, SystemNotifications.Notifications[ i ], RequestID )
	end
end

Server.HookNetworkMessage( "Shine_GetSystemNotifications", function( Client, Message )
	ReceiveNotificationListRequest( Client, Message.RequestID )
end )

Shine.Hook.Add( "ClientConfirmConnect", SystemNotifications, function( Client )
	if #SystemNotifications.Notifications == 0 then return end

	local Severity = SystemNotifications:GetSeverity()
	if Severity < SystemNotifications.TypeOrdinal.WARNING then return end
	if not CanClientSeeNotifications( Client ) then return end

	local Messages = {
		[ SystemNotifications.TypeOrdinal.WARNING ] = "SYSTEM_NOTIFICATIONS_WARNINGS_NOTIFICATION",
		[ SystemNotifications.TypeOrdinal.ERROR ] = "SYSTEM_NOTIFICATIONS_ERRORS_NOTIFICATION"
	}

	Shine:SendTranslatedNotification(
		Client, Severity, Messages[ Severity ], nil, false, 10
	)
end )
