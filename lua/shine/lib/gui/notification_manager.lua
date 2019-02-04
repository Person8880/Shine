--[[
	Manages notifications.
]]

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units
local HighResScaled = Units.HighResScaled

local OSTime = os.time
local TableRemove = table.remove

local NotificationType = Shine.NotificationType

local Notifications = {}
local NotificationManager = {}

local HINTS_FILE = "config://shine/Hints.json"
local HintData = Shine.LoadJSONFile( HINTS_FILE ) or {}
local HintTypes = {}
local function UpdateHintData()
	Shine.SaveJSONFile( HintData, HINTS_FILE )
end

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

--[[
	Adds a notification to the screen.

	Inputs:
		1. The type to use (one of Shine.NotificationType).
		2. The notification's message.
		3. The duration in seconds the notification should last for before fading out.
	Output:
		The created Notification SGUI object. Do not reposition or change its size.
]]
function NotificationManager.AddNotification( Type, Message, Duration )
	Shine.AssertAtLevel( NotificationType[ Type ], "No such notification type: %s", 3, Type )
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

	-- Slide the notification in from the right, and fade in.
	local TargetPos = Notification:GetPos() - Vector2( Notification:GetSize().x, 0 )
	Notification.TargetPos = TargetPos
	Notification:MoveTo( nil, nil, TargetPos, 0, 0.3 )
	Notification:FadeIn()
	Notification:FadeOutAfter( Duration, function()
		for i = #Notifications, 1, -1 do
			if Notifications[ i ] == Notification then
				Notification:StopMoving()
				TableRemove( Notifications, i )
				-- Move any notifications above this one down to compensate for the gap.
				OffsetAllNotifications( -Notification:GetSize().y - MARGIN:GetValue(), 1, i - 1 )
				break
			end
		end
	end )

	-- Move all existing notifications up by the notification's size + margin.
	OffsetAllNotifications( Notification:GetSize().y + MARGIN:GetValue(), 1, #Notifications )

	Notifications[ #Notifications + 1 ] = Notification

	return Notification
end

Shine.Hook.Add( "OnResolutionChanged", "SGUINotifications", function()
	for i = 1, #Notifications do
		Notifications[ i ]:Destroy()
		Notifications[ i ] = nil
	end
end )

--[[
	Registers a hint type.

	Hints allow informing users about new functionality in a managed way,
	with the ability to constrain how often and how many times the user is
	notified.

	Hints can also be permanently disabled when a user uses the functionality.

	Inputs:
		1. The unique name of the hint type.
		2. A parameters table with the following fields:
		   * HintDuration - optional duration in seconds the hint's notification should display for. Default is 5 seconds.
		   * HintIntervalInSeconds - how long to wait after showing the hint before showing it again.
		   * MaxTimes - optional limit on the number of times the hint is displayed.
		   * MessageKey - the message key in the given source to use as the message.
		   * MessageSource - the name of the locale message source.
		   * NotificationType - optional notification type, defaults to NotificationType.INFO.
]]
function NotificationManager.RegisterHint( Name, Params )
	Shine.TypeCheck( Params, "table", 1, "RegisterHint" )

	Shine.TypeCheckField( Params, "HintDuration", { "number", "nil" }, "Params" )
	Shine.TypeCheckField( Params, "HintIntervalInSeconds", "number", "Params" )
	Shine.TypeCheckField( Params, "MaxTimes", { "number", "nil" }, "Params" )
	Shine.TypeCheckField( Params, "MessageKey", "string", "Params" )
	Shine.TypeCheckField( Params, "MessageSource", "string", "Params" )
	Shine.TypeCheckField( Params, "NotificationType", { "string", "nil" }, "Params" )

	if Params.NotificationType then
		Shine.AssertAtLevel( NotificationType[ Params.NotificationType ],
			"No such notification type: %s", 3, Params.NotificationType )
	end

	HintTypes[ Name ] = Params
end

--[[
	Disables the given hint, ensuring it is not displayed again.
]]
function NotificationManager.DisableHint( Name )
	local Data = HintData[ Name ] or {}
	if Data.Disabled then return end

	Data.Disabled = true
	HintData[ Name ] = Data
	UpdateHintData()
end

--[[
	Attempts to display the hint of the given type.

	If the hint has been disabled, displayed too many times, or displayed too
	recently, this will do nothing.

	Otherwise the hint will display and its next display time and occurence count
	will be updated.
]]
function NotificationManager.DisplayHint( Name )
	local Params = HintTypes[ Name ]
	if not Params then return end

	local Data = HintData[ Name ] or {}
	if Data.Disabled or ( Data.NumTimesDisplayed or 0 ) >= ( Params.MaxTimes or math.huge ) then
		-- No longer relevant, do not display.
		return
	end

	local Now = OSTime()
	if ( Data.NextHintTime or 0 ) > Now then
		-- Displayed too recently.
		return
	end

	Data.NextHintTime = Now + Params.HintIntervalInSeconds
	Data.NumTimesDisplayed = ( Data.NumTimesDisplayed or 0 ) + 1
	HintData[ Name ] = Data
	UpdateHintData()

	NotificationManager.AddNotification(
		Params.NotificationType or NotificationType.INFO,
		Shine.Locale:GetPhrase( Params.MessageSource, Params.MessageKey ),
		Params.HintDuration or 5
	)
end

SGUI.NotificationManager = NotificationManager
