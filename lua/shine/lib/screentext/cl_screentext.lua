--[[
	Shine screen text rendering client side file.
]]

local IsType = Shine.IsType
local StringFormat = string.format

local Messages = Shine.Map()
Shine.TextMessages = Messages

local StandardFonts = {
	Fonts.kAgencyFB_Small,
	Fonts.kAgencyFB_Medium,
	Fonts.kAgencyFB_Large
}
local HighResFonts = {
	Fonts.kAgencyFB_Medium,
	Fonts.kAgencyFB_Large,
	{ Fonts.kAgencyFB_Huge, 0.6 }
}
local FourKFonts = {
	{ Fonts.kAgencyFB_Huge, 0.6 },
	{ Fonts.kAgencyFB_Huge, 0.8 },
	Fonts.kAgencyFB_Huge
}

function Shine:AddMessageToQueue( ID, x, y, Text, Duration, r, g, b, Alignment, Size, FadeIn, IgnoreFormat )
	FadeIn = FadeIn or 0.5
	Size = Size or 1

	local ScrW = Client.GetScreenWidth()
	local ScrH = Client.GetScreenHeight()
	local Font = StandardFonts[ Size ]

	if ScrW > 1920 and ScrW <= 2880 then
		Font = HighResFonts[ Size ]
	elseif ScrW > 2880 then
		Font = FourKFonts[ Size ]
	end

	local ShouldFade = FadeIn > 0.05

	local Time = Shared.GetTime()

	local ScaleVec
	if IsType( Font, "table" ) then
		ScaleVec = Vector( Font[ 2 ], Font[ 2 ], 0 )
		Font = Font[ 1 ]
	else
		ScaleVec = ScrW <= 1920 and GUIScale( Vector( 1, 1, 1 ) ) or Vector( 1, 1, 1 )
	end

	local TextObj = Messages:Get( ID )

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

		Obj:SetText( IgnoreFormat and Text or StringFormat( Text,
			string.TimeToString( Duration ) ) )
		Obj:SetScale( ScaleVec )
		Obj:SetPosition( Vector( ScrW * x, ScrH * y, 0 ) )
		Obj:SetColor( TextObj.Colour )
		Obj:SetFontName( Font )

		function TextObj:UpdateText()
			if IgnoreFormat then
				self.Obj:SetText( self.Text )
			else
				if self.Digital then
					self.Obj:SetText( StringFormat( self.Text,
						string.DigitalTime( self.Duration ) ) )
				else
					self.Obj:SetText( StringFormat( self.Text,
						string.TimeToString( self.Duration ) ) )
				end
			end
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

	Obj:SetPosition( Vector( ScrW * x, ScrH * y, 0 ) )

	Obj:SetTextAlignmentX( Alignment )
	Obj:SetTextAlignmentY( GUIItem.Align_Center )

	Obj:SetFontName( Font )

	Obj:SetIsVisible( true )

	Obj:SetText( IgnoreFormat and Text or StringFormat( Text,
		string.TimeToString( Duration ) ) )
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
		if IgnoreFormat then
			self.Obj:SetText( self.Text )
		else
			if self.Digital then
				self.Obj:SetText( StringFormat( self.Text,
					string.DigitalTime( self.Duration ) ) )
			else
				self.Obj:SetText( StringFormat( self.Text,
					string.TimeToString( self.Duration ) ) )
			end
		end
	end

	Messages:Add( ID, MessageTable )

	return MessageTable
end

function Shine:UpdateMessageText( Message )
	local ID = Message.ID
	local Text = Message.Message

	local MessageTable = Messages:Get( ID )
	if not MessageTable then return end

	MessageTable.Text = Text
	MessageTable.Obj:SetText( Text )
end

local function ProcessQueue( Time )
	for Index, Message in Messages:Iterate() do
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
	for Index, Message in Messages:Iterate() do
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
	local Message = Messages:Get( Index )
	if not Message then return end

	GUI.DestroyItem( Message.Obj )

	Messages:Remove( Index )
end

function Shine:EndMessage( Index )
	local MessageTable = Messages:Get( Index )

	if not MessageTable then return end

	MessageTable.LastUpdate = Shared.GetTime() - 1
	MessageTable.Duration = 1
end

Shine.Hook.Add( "Think", "ScreenText", function( DeltaTime )
	local Time = Shared.GetTime()

	ProcessQueue( Time )

	ProcessFades( DeltaTime )
end )

Client.HookNetworkMessage( "Shine_ScreenText", function( Message )
	Shine:AddMessageToQueue( Message.ID, Message.x, Message.y,
		Message.Message, Message.Duration, Message.r, Message.g, Message.b,
		Message.Align, Message.Size, Message.FadeIn )
end )

Client.HookNetworkMessage( "Shine_ScreenTextUpdate", function( Message )
	Shine:UpdateMessageText( Message )
end )

Client.HookNetworkMessage( "Shine_ScreenTextRemove", function( Message )
	Shine:EndMessage( Message.ID )
end )
