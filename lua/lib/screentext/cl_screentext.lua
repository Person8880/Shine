--[[
	Shine screen text rendering client side file.
]]

Shine = Shine or {}
local StringFormat = string.format

local Messages = {}
Shine.TextMessages = Messages

function Shine:AddMessageToQueue( Message )
	local Scale = GUIScale( 1 )
	local ScaleVec = Vector( 1, 1, 1 ) * Scale

	local ID = Message.ID
	local TextObj = Messages[ ID ]

	local x, y = Message.x, Message.y
	local Text = Message.Message
	local r, g, b = Message.r, Message.g, Message.b
	local Duration = Message.Duration
	local Alignment = Message.Align

	if Alignment == 0 then
		Alignment = GUIItem.Align_Min
	elseif Alignment == 1 then
		Alignment = GUIItem.Align_Center
	else
		Alignment = GUIItem.Align_Max
	end

	if TextObj then
		TextObj.Text = Text
		TextObj.Colour = Color( r / 255, g / 255, b / 255 )
		TextObj.Duration = Duration
		TextObj.x = x
		TextObj.y = y

		local Obj = TextObj.Obj

		Obj:SetText( StringFormat( Text, string.TimeToString( Duration ) ) )
		Obj:SetScale( ScaleVec )
		Obj:SetPosition( Vector( Client.GetScreenWidth() * x, Client.GetScreenHeight() * y, 0 ) )
		Obj:SetColor( TextObj.Colour )

		function TextObj:UpdateText()
			self.Obj:SetText( StringFormat( Text, string.TimeToString( self.Duration ) ) )
		end

		return
	end

	local MessageTable = {
		Index = ID,
		Colour = Color( r / 255, g / 255, b / 255 ),
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

	Obj:SetFontName( "fonts/AgencyFB_small.fnt" )

	Obj:SetIsVisible( true )

	Obj:SetText( StringFormat( Text, string.TimeToString( Duration ) ) )
	Obj:SetColor( MessageTable.Colour )
	Obj:SetScale( ScaleVec )
	
	MessageTable.Obj = Obj

	function MessageTable:UpdateText()
		self.Obj:SetText( StringFormat( Text, string.TimeToString( self.Duration ) ) )
	end

	Messages[ ID ] = MessageTable
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

		if Message.Duration == 0 then
			self:RemoveMessage( Index )
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
end )

Client.HookNetworkMessage( "Shine_ScreenText", function( Message )
	Shine:AddMessageToQueue( Message )
end )

Client.HookNetworkMessage( "Shine_ScreenTextUpdate", function( Message )
	Shine:UpdateMessageText( Message )
end )
