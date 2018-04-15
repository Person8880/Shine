--[[
	Manages notifications.
]]

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units
local HighResScaled = Units.HighResScaled

local TableRemove = table.remove

local NotificationType = Shine.NotificationType

local Notifications = {}
local NotificationManager = {}

local Styles = {
	[ NotificationType.INFO ] = "Info",
	[ NotificationType.WARNING ] = "Warning",
	[ NotificationType.ERROR ] = "Danger"
}

local OFFSETX = HighResScaled( 32 )
local OFFSETY = HighResScaled( 192 )

local function OffsetAllNotifications( Offset, FromIndex, ToIndex )
	local XPos = -OFFSETX:GetValue()

	for i = FromIndex, ToIndex do
		local Notification = Notifications[ i ]
		if SGUI.IsValid( Notification ) then
			local NewPos = Vector2( XPos - Notification:GetSize().x, Notification.TargetPos.y - Offset )
			Notification.TargetPos = NewPos
			Notification:MoveTo( nil, nil, NewPos, 0, 0.3 )
		end
	end
end

local MARGIN = HighResScaled( 16 )
local PADDING = HighResScaled( 16 )
local FLAIR_WIDTH = HighResScaled( 48 )

function NotificationManager.AddNotification( Type, Message, Duration )
	Shine.AssertAtLevel( NotificationType[ Type ], 3, "No such notification type: %s", Type )
	Shine.TypeCheck( Message, "string", 2, "AddNotification" )
	Shine.TypeCheck( Duration, "number", 3, "AddNotification" )

	local W, H = SGUI.GetScreenSize()

	local Notification = SGUI:Create( "Notification" )
	Notification:SetStyleName( Styles[ Type ] )
	Notification:SetAnchor( "BottomRight" )
	Notification:SetPadding( PADDING:GetValue() )
	Notification:SetMaxWidth( W * 0.25 )
	Notification:SetFlairWidth( FLAIR_WIDTH:GetValue() )
	local Font, Scale = SGUI.FontManager.GetFont( SGUI.FontFamilies.Ionicons, 32 )
	Notification:SetIconScale( Scale )
	Notification:SetText( Message, SGUI.FontManager.GetFont( "kAgencyFB", 27 ) )
	Notification:SizeToContents()
	Notification:SetPos( Vector2( -OFFSETX:GetValue(), -OFFSETY:GetValue() - Notification:GetSize().y ) )

	local TargetPos = Notification:GetPos() - Vector2( Notification:GetSize().x, 0 )
	Notification.TargetPos = TargetPos
	Notification:MoveTo( nil, nil, TargetPos, 0, 0.3 )
	Notification:FadeIn()
	Notification:FadeOutAfter( Duration, function()
		for i = #Notifications, 1, -1 do
			if Notifications[ i ] == Notification then
				Notification:StopMoving()
				TableRemove( Notifications, i )
				OffsetAllNotifications( -Notification:GetSize().y - MARGIN:GetValue(), 1, i - 1 )
				break
			end
		end
	end )

	OffsetAllNotifications( Notification:GetSize().y + MARGIN:GetValue(), 1, #Notifications )

	Notifications[ #Notifications + 1 ] = Notification
end

Shine.Hook.Add( "OnResolutionChanged", "SGUINotifications", function()
	for i = 1, #Notifications do
		Notifications[ i ]:Destroy()
		Notifications[ i ] = nil
	end
end )

SGUI.NotificationManager = NotificationManager
