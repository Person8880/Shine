--[[
	Shine screen text rendering client side file.
]]

Shine = Shine or {}
local StringFormat = string.format

local Messages = {}
Shine.TextMessages = Messages

local Fonts = {
	"fonts/AgencyFB_small.fnt",
	"fonts/AgencyFB_medium.fnt",
	"fonts/AgencyFB_large.fnt"
}

function Shine:AddMessageToQueue( ID, x, y, Text, Duration, r, g, b, Alignment, Size, FadeIn, IgnoreFormat )
	FadeIn = FadeIn or 0.5
	Size = Size or 1

	local Font = Fonts[ Size ] or "fonts/AgencyFB_small.fnt"

	local ShouldFade = FadeIn > 0.05

	local Time = Shared.GetTime()

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
		TextObj.Colour = Color( r / 255, g / 255, b / 255, ShouldFade and 0 or 1 )
		TextObj.Duration = Duration
		TextObj.x = x
		TextObj.y = y

		local Obj = TextObj.Obj

		Obj:SetText( IgnoreFormat and Text or StringFormat( Text, string.TimeToString( Duration ) ) )
		Obj:SetScale( ScaleVec )
		Obj:SetPosition( Vector( Client.GetScreenWidth() * x, Client.GetScreenHeight() * y, 0 ) )
		Obj:SetColor( TextObj.Colour )
		Obj:SetFontName( Font )

		function TextObj:UpdateText()
			self.Obj:SetText( IgnoreFormat and self.Text or StringFormat( self.Text, string.TimeToString( self.Duration ) ) )
		end

		if ShouldFade then
			TextObj.Fading = true
			TextObj.FadedIn = true
			TextObj.FadingIn = true
			TextObj.FadeElapsed = 0
			TextObj.FadeDuration = FadeIn
		end

		TextObj.LastUpdate = Time

		return TextObj
	end

	local MessageTable = {
		Index = ID,
		Colour = Color( r / 255, g / 255, b / 255, ShouldFade and 0 or 1 ),
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

	Obj:SetFontName( Font )

	Obj:SetIsVisible( true )

	--Game will crash if we pass string.format the wrong number of arguments (dumb, but not urgent to fix I guess)!
	Obj:SetText( IgnoreFormat and Text or StringFormat( Text, string.TimeToString( Duration ) ) )
	Obj:SetColor( MessageTable.Colour )
	Obj:SetScale( ScaleVec )
	
	MessageTable.Obj = Obj

	if ShouldFade then
		MessageTable.Fading = true
		MessageTable.FadedIn = true
		MessageTable.FadingIn = true
		MessageTable.FadeElapsed = 0
		MessageTable.FadeDuration = FadeIn
	end

	MessageTable.LastUpdate = Time

	function MessageTable:UpdateText()
		self.Obj:SetText( IgnoreFormat and self.Text or StringFormat( self.Text, string.TimeToString( self.Duration ) ) )
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

local function ProcessQueue( Time )
	for Index, Message in pairs( Messages ) do
		if not Message.LastUpdate then
			Message.LastUpdate = Time
		end

		if Message.LastUpdate + 1 <= Time then
			Message.Duration = Message.Duration - 1
			Message.LastUpdate = Message.LastUpdate + 1

			Message:UpdateText()

			if Message.Think then
				Message:Think()
			end

			if Message.Duration == 0 then
				Message.FadingIn = false
				Message.Fading = true
				Message.FadeElapsed = 0
				Message.FadeDuration = 1
			end

			if Message.Duration == -1 then
				Shine:RemoveMessage( Index )
			end
		end
	end
end

--Not the lifeform...
local function ProcessFades( DeltaTime )
	for Index, Message in pairs( Messages ) do
		if Message.Fading then
			local In = Message.FadingIn

			Message.FadeElapsed = Message.FadeElapsed + DeltaTime

			if Message.FadeElapsed >= Message.FadeDuration then
				Message.Fading = false

				Message.Colour.a = In and 1 or 0
			
				Message.Obj:SetColor( Message.Colour )
			else
				local Progress = Message.FadeElapsed / Message.FadeDuration
				local Alpha = 1 * ( In and Progress or ( 1 - Progress ) )
				
				Message.Colour.a = Alpha

				Message.Obj:SetColor( Message.Colour )
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

Shine.Hook.Add( "Think", "ScreenText", function( DeltaTime )
	local Time = Shared.GetTime()

	ProcessQueue( Time )

	ProcessFades( DeltaTime )
end )

Client.HookNetworkMessage( "Shine_ScreenText", function( Message )
	Shine:AddMessageToQueue( Message.ID, Message.x, Message.y, Message.Message, Message.Duration, Message.r, Message.g, Message.b, Message.Align, Message.Size, Message.FadeIn )
end )

Client.HookNetworkMessage( "Shine_ScreenTextUpdate", function( Message )
	Shine:UpdateMessageText( Message )
end )

Client.HookNetworkMessage( "Shine_ScreenTextRemove", function( Message )
	local MessageTable = Messages[ Message.ID ]

	if not MessageTable then return end

	MessageTable.LastUpdate = Shared.GetTime() - 1
	MessageTable.Duration = 1
end )
