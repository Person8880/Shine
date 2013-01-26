--[[
	Shine screen text rendering client side file.
]]

Shine = Shine or {}
local StringFormat = string.format

local Messages = {}
Shine.TextMessages = Messages

function Shine:AddMessageToQueue( ID, x, y, Text, Duration, r, g, b, Alignment, Size )
	Size = Size or 1
	local Scale = GUIScale( 1 )
	local ScaleVec = Vector( 1, 1, 1 ) * Scale

	local TextObj = Messages[ ID ]

	if Alignment == 0 then
		Alignment = GUIItem.Align_Min
	elseif Alignment == 1 then
		Alignment = GUIItem.Align_Center
	else
		Alignment = GUIItem.Align_Max
	end

	if TextObj then
		TextObj.Text = Text
		TextObj.Colour = Color( r / 255, g / 255, b / 255, 0 )
		TextObj.Duration = Duration
		TextObj.x = x
		TextObj.y = y

		local Obj = TextObj.Obj

		Obj:SetText( StringFormat( Text, string.TimeToString( Duration ) ) )
		Obj:SetScale( ScaleVec )
		Obj:SetPosition( Vector( Client.GetScreenWidth() * x, Client.GetScreenHeight() * y, 0 ) )
		Obj:SetColor( TextObj.Colour )

		function TextObj:UpdateText()
			self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ) ) )
		end

		TextObj.Fading = true
		TextObj.FadedIn = true
		TextObj.FadingIn = true
		TextObj.FadeEnd = Shared.GetTime() + 1

		return TextObj
	end

	local MessageTable = {
		Index = ID,
		Colour = Color( r / 255, g / 255, b / 255, 0 ),
		Text = Text,
		Duration = Duration,
		x = x,
		y = y
	}

	local Obj = GUI.CreateItem()

	Obj:SetOptionFlag( GUIItem.ManageRender )

	Obj:SetPosition( Vector( Client.GetScreenWidth() * x, Client.GetScreenHeight() * y, 0 ) )

	Obj:SetTextAlignmentX( Alignment )
	Obj:SetTextAlignmentY( GUIItem.Align_Center )

	Obj:SetFontName( Size == 1 and "fonts/AgencyFB_small.fnt" or "fonts/AgencyFB_large.fnt" )

	Obj:SetIsVisible( true )

	Obj:SetText( StringFormat( Text, string.TimeToString( Duration ) ) )
	Obj:SetColor( MessageTable.Colour )
	Obj:SetScale( ScaleVec )
	
	MessageTable.Obj = Obj

	MessageTable.Fading = true
	MessageTable.FadedIn = true
	MessageTable.FadingIn = true
	MessageTable.FadeEnd = Shared.GetTime() + 1

	function MessageTable:UpdateText()
		self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ) ) )
	end

	Messages[ ID ] = MessageTable

	return MessageTable
end

function Shine:UpdateMessageText( Message )
	local ID = Message.ID
	local Text = Message.Message

	local MessageTable = Messages[ ID ]

	if not MessageTable then return end

	MessageTable.Text = Text
	MessageTable.Obj:SetText( Text )
end

function Shine:ProcessQueue()
	for Index, Message in pairs( Messages ) do
		Message.Duration = Message.Duration - 1

		Message:UpdateText()

		if Message.Think then
			Message:Think()
		end

		if Message.Duration == 1 then
			Message.FadingIn = false
			Message.Fading = true
			Message.FadeEnd = Shared.GetTime() + 1
		end

		if Message.Duration == 0 then
			self:RemoveMessage( Index )
		end
	end
end

--Not the lifeform...
function Shine:ProcessFades()
	local Time = Shared.GetTime()

	for Index, Message in pairs( Messages ) do
		if Message.Fading then
			local In = Message.FadingIn
			local Progress = Message.FadeEnd - Time
			local Alpha = 1 * ( In and ( 1 - Progress ) or Progress )
			
			Message.Colour.a = Alpha

			Message.Obj:SetColor( Message.Colour )

			if Message.FadeEnd <= Time then
				Message.Fading = false
			end
		end
	end
end

function Shine:RemoveMessage( Index )
	local Message = Messages[ Index ]
	if not Message then return end
	
	GUI.DestroyItem( Message.Obj )

	Messages[ Index ] = nil
end

local LastUpdate = 0

Event.Hook( "UpdateClient", function()
	local Time = Shared.GetTime()

	if Time - LastUpdate > 1 then
		Shine:ProcessQueue()
		LastUpdate = Time
	end

	Shine:ProcessFades()
end )

Client.HookNetworkMessage( "Shine_ScreenText", function( Message )
	Shine:AddMessageToQueue( Message.ID, Message.x, Message.y, Message.Message, Message.Duration, Message.r, Message.g, Message.b, Message.Align, Message.Size )
end )

Client.HookNetworkMessage( "Shine_ScreenTextUpdate", function( Message )
	Shine:UpdateMessageText( Message )
end )
