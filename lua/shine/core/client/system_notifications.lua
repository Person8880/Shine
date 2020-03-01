--[[
	System notifications client-side.
]]

local Locale = Shine.Locale
local SGUI = Shine.GUI
local SystemNotifications = Shine.SystemNotifications

local RequestID = 0
local function GetRequestID()
	RequestID = ( RequestID % 255 ) + 1
	return RequestID
end

local OnCallbackError = Shine.BuildErrorHandler( "System notification callback error" )
local function CallRequestCallback( Request, Notifications )
	xpcall( Request.Callback, OnCallbackError, Notifications )
end

local Requests = {}

Client.HookNetworkMessage( "Shine_StartSystemNotificationsResponse", function( Message )
	local Request = Requests[ Message.RequestID ]
	if not Request then return end

	if not Message.AllowedToViewNotifications then
		CallRequestCallback( Request, nil )
		Requests[ Message.RequestID ] = nil
	elseif Message.NumNotifications == 0 then
		CallRequestCallback( Request, {} )
		Requests[ Message.RequestID ] = nil
	else
		Request.Notifications = {}
		Request.ExpectedNotificationCount = Message.NumNotifications
	end
end )

Client.HookNetworkMessage( "Shine_SendSystemNotification", function( Message )
	local Request = Requests[ Message.RequestID ]
	if not Request then return end

	local ID = Message.ID
	if ID == "" then
		ID = nil
	end

	local SourceID = Message.SourceID
	if SourceID == "" then
		SourceID = nil
	end

	Request.Notifications[ #Request.Notifications + 1 ] = {
		ID = ID,

		Type = SystemNotifications.Type[ Message.Type ],

		Message = {
			Source = Message.MessageSource,
			TranslationKey = Message.MessageKey,
			Context = Message.MessageContext
		},

		Source = {
			Type = SystemNotifications.Source[ Message.SourceType ],
			ID = SourceID
		}
	}

	if #Request.Notifications >= Request.ExpectedNotificationCount then
		CallRequestCallback( Request, Request.Notifications )
		Requests[ Message.RequestID ] = nil
	end
end )

function SystemNotifications.GetNotifications( Callback )
	-- Send request to server, on response call callback...
	local RequestID = GetRequestID()

	Requests[ RequestID ] = {
		Callback = Callback
	}

	Shine.SendNetworkMessage( "Shine_GetSystemNotifications", {
		RequestID = RequestID
	}, true )
end

local Units = SGUI.Layout.Units

local CanViewNotifications = true
local CachedNotifications
local IsTabVisible = false

local AgencyFBLarge = {
	Family = "kAgencyFB",
	Size = Units.HighResScaled( 41 )
}
local AgencyFBNormal = {
	Family = "kAgencyFB",
	Size = Units.HighResScaled( 27 )
}
local Ionicons = {
	Family = SGUI.FontFamilies.Ionicons,
	Size = Units.HighResScaled( 32 )
}
local IoniconsLarge = {
	Family = SGUI.FontFamilies.Ionicons,
	Size = Units.HighResScaled( 64 )
}

local function PopulateTabWithLoadingIndicator( Panel )
	Panel:Clear()

	SGUI:BuildTree( {
		Parent = Panel,
		{
			Class = "Vertical",
			Type = "Layout",
			Props = {
				Fill = true
			},
			Children = {
				{
					Class = "ProgressWheel",
					Props = {
						Alignment = SGUI.LayoutAlignment.CENTRE,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						AnimateLoading = true,
						SpinRate = -math.pi * 2,
						AutoSize = Units.UnitVector( Units.Percentage( 10 ), 0 ),
						AspectRatio = 1
					}
				},
				{
					Class = "Label",
					Props = {
						Alignment = SGUI.LayoutAlignment.CENTRE,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						AutoFont = AgencyFBLarge,
						Text = Locale:GetPhrase( "Core", "SYSTEM_NOTIFICATIONS_LOADING" )
					}
				}
			}
		}
	} )
end

local function PopulatePanelWithOKStatus( Panel )
	Panel:Clear()

	SGUI:BuildTree( {
		Parent = Panel,
		{
			Class = "Vertical",
			Type = "Layout",
			Props = {
				Fill = true
			},
			Children = {
				{
					Class = "Label",
					Props = {
						Alignment = SGUI.LayoutAlignment.CENTRE,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						Text = SGUI.Icons.Ionicons.Checkmark,
						AutoFont = IoniconsLarge,
						-- TODO: Should this be styled?
						Colour = Colour( 0.1, 1, 0.1, 1 )
					}
				},
				{
					Class = "Label",
					Props = {
						Alignment = SGUI.LayoutAlignment.CENTRE,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						AutoFont = AgencyFBLarge,
						Text = Locale:GetPhrase( "Core", "SYSTEM_NOTIFICATIONS_OK" )
					}
				}
			}
		}
	} )
end

local function PopulatePanelWithError( Panel )
	Panel:Clear()

	SGUI:BuildTree( {
		Parent = Panel,
		{
			Class = "Vertical",
			Type = "Layout",
			Props = {
				Fill = true
			},
			Children = {
				{
					Class = "Label",
					Props = {
						Alignment = SGUI.LayoutAlignment.CENTRE,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						Text = SGUI.Icons.Ionicons.AlertCircled,
						AutoFont = IoniconsLarge,
						-- TODO: Should this be styled?
						Colour = Colour( 1, 0.2, 0.1, 1 )
					}
				},
				{
					Class = "Label",
					Props = {
						Alignment = SGUI.LayoutAlignment.CENTRE,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						AutoFont = AgencyFBLarge,
						Text = Locale:GetPhrase( "Core", "SYSTEM_NOTIFICATIONS_ACCESS_DENIED" )
					}
				}
			}
		}
	} )
end

local NotificationEntry = SGUI:DefineControl( "NotificationEntry", "Row" )
local ColoursByType = {
	[ SystemNotifications.Type.ERROR ] = Colour( 0.8, 0.2, 0 ),
	[ SystemNotifications.Type.WARNING ] = Colour( 1, 0.6, 0 ),
	[ SystemNotifications.Type.INFO ] = Colour( 0, 0.5, 0.75 )
}
local IconsByType = {
	[ SystemNotifications.Type.ERROR ] = SGUI.Icons.Ionicons.AlertCircled,
	[ SystemNotifications.Type.WARNING ] = SGUI.Icons.Ionicons.Alert,
	[ SystemNotifications.Type.INFO ] = SGUI.Icons.Ionicons.InformationCircled
}

function NotificationEntry:SetNotification( Notification )
	local PaddingAmount = Units.HighResScaled( 4 )

	self:SetShader( SGUI.Shaders.Invisible )

	local Title
	if Notification.Source.Type == SystemNotifications.Source.PLUGIN then
		Title = Notification.Source.ID
	else
		Title = Locale:GetPhrase( "Core", "SYSTEM_NOTIFICATIONS_CORE_HEADER" )
	end

	SGUI:BuildTree( {
		Parent = self,
		{
			ID = "IconContainer",
			Class = "Row",
			Props = {
				Fill = false,
				AutoSize = Units.UnitVector( Units.HighResScaled( 40 ), 0 ),
				Colour = ColoursByType[ Notification.Type ],
				Padding = Units.Spacing(
					PaddingAmount, PaddingAmount, PaddingAmount, PaddingAmount
				),
				IsSchemed = false
			},
			Children = {
				{
					Class = "Label",
					Props = {
						AutoFont = Ionicons,
						Text = IconsByType[ Notification.Type ],
						Alignment = SGUI.LayoutAlignment.CENTRE,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						Colour = Colour( 1, 1, 1 ),
						IsSchemed = false
					}
				}
			}
		},
		{
			ID = "TextContainer",
			Class = "Column",
			Props = {
				Fill = true,
				AutoSize = Units.UnitVector( Units.Auto(), Units.Auto() ),
				Colour = Colour( 0, 0, 0, 0.25 ),
				Padding = Units.Spacing(
					PaddingAmount, PaddingAmount, PaddingAmount, PaddingAmount
				),
				IsSchemed = false
			},
			Children = {
				{
					Class = "Label",
					Props = {
						AutoFont = AgencyFBNormal,
						Text = Title,
						Margin = Units.Spacing( 0, 0, 0, PaddingAmount )
					}
				},
				{
					Class = "Label",
					Props = {
						AutoFont = AgencyFBNormal,
						Text = Locale:GetInterpolatedPhrase( Notification.Message.Source, Notification.Message.TranslationKey, {
							Context = Notification.Message.Context
						} ),
						AutoSize = Units.UnitVector( Units.Percentage( 100 ), Units.Auto() ),
						AutoWrap = true
					}
				}
			}
		},
		OnBuilt = function( Elements )
			Elements.IconContainer.AutoSize[ 2 ] = Units.Auto( Elements.TextContainer )
		end
	} )
end

local function PopulatePanelWithNotifications( Panel )
	Panel:Clear()

	local Children = {}
	local NotificationsByType = Shine.Multimap()

	for i = 1, #CachedNotifications do
		local Notification = CachedNotifications[ i ]
		NotificationsByType:Add( Notification.Type, Notification )
	end

	local ListMargin = Units.HighResScaled( 4 )
	local PanelPadding = Units.HighResScaled( 16 )

	-- Show most severe notifications first.
	for i = #SystemNotifications.Type, 1, -1 do
		local Type = SystemNotifications.Type[ i ]
		local Notifications = NotificationsByType:Get( Type )
		if Notifications then
			Children[ #Children + 1 ] = {
				Class = "Label",
				Props = {
					AutoFont = {
						Family = "kAgencyFB",
						Size = Units.HighResScaled( 33 )
					},
					Text = Locale:GetPhrase( "Core", "SYSTEM_NOTIFICATIONS_HEADER_"..Type )
				}
			}

			for j = 1, #Notifications do
				Children[ #Children + 1 ] = {
					Class = NotificationEntry,
					Props = {
						Notification = Notifications[ j ],
						Margin = Units.Spacing( 0, ListMargin, 0, j == #Notifications and PanelPadding or 0 ),
						AutoSize = Units.UnitVector( Units.Percentage( 100 ), Units.Auto() )
					}
				}
			end
		end
	end

	-- Avoid extra space at the end if scrolling.
	local LastChild = Children[ #Children ]
	if LastChild then
		LastChild.Props.Margin[ 4 ] = Units.Absolute( 0 )
	end

	local ScrollbarWidth = Units.HighResScaled( 8 ):GetValue()
	SGUI:BuildTree( {
		Parent = Panel,
		{
			Class = "Vertical",
			Type = "Layout",
			Props = {
				Fill = true,
				Padding = Units.Spacing( PanelPadding, PanelPadding, PanelPadding, PanelPadding )
			},
			Children = {
				{
					Class = "Label",
					Props = {
						AutoFont = AgencyFBLarge,
						Text = Locale:GetPhrase( "Core", "SYSTEM_NOTIFICATIONS_TAB_HEADER" ),
						Margin = Units.Spacing( 0, 0, 0, PanelPadding )
					}
				},
				{
					Class = "Column",
					Props = {
						Scrollable = true,
						Fill = true,
						Colour = Colour( 0, 0, 0, 0 ),
						ScrollbarPos = Vector2( 0, 0 ),
						ScrollbarWidth = ScrollbarWidth,
						ScrollbarHeightOffset = 0
					},
					Children = Children
				}
			}
		}
	} )
end

Shine.AdminMenu:AddSystemTab( "Status", {
	TranslationKey = "ADMIN_MENU_STATUS_TAB",
	Icon = SGUI.Icons.Ionicons.iOSPulseStrong,
	Position = Shine.AdminMenu.SystemTabPosition.END,
	OnInit = function( Panel, Data )
		IsTabVisible = true

		if not CanViewNotifications then
			return PopulatePanelWithError( Panel )
		end

		if not CachedNotifications then
			PopulateTabWithLoadingIndicator( Panel )

			SystemNotifications.GetNotifications( function( Notifications )
				if not Notifications then
					CanViewNotifications = false

					if IsTabVisible then
						PopulatePanelWithError( Panel )
					end

					return
				end

				CachedNotifications = Notifications

				if #Notifications == 0 then
					if IsTabVisible then
						PopulatePanelWithOKStatus( Panel )
					end
				else
					if IsTabVisible then
						PopulatePanelWithNotifications( Panel )
					end
				end
			end )

			return
		end

		if #CachedNotifications == 0 then
			PopulatePanelWithOKStatus( Panel )
		else
			PopulatePanelWithNotifications( Panel )
		end
	end,

	OnCleanup = function( Panel )
		IsTabVisible = false
	end
} )
