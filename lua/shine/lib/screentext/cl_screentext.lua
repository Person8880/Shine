--[[
	Shine screen text rendering client side file.
]]

local DigitalTime = string.DigitalTime
local IsType = Shine.IsType
local SharedTime = Shared.GetTime
local StringFormat = string.format
local TimeToString = string.TimeToString
local xpcall = xpcall

local ScreenTextErrorHandler = Shine.BuildErrorHandler( "Screen text error" )

local SGUI = Shine.GUI

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

local ScreenText = {}

do
	local rawget = rawget
	local rawset = rawset

	local Text = setmetatable( {}, { __mode = "k" } )
	ScreenText.__index = function( self, Key )
		if Key == "Text" then
			return Text[ self ]
		end

		return ScreenText[ Key ]
	end

	ScreenText.__newindex = function( self, Key, Value )
		if Key == "Text" then
			-- Force a format validity check now to avoid invalid text being assigned.
			if not rawget( self, "IgnoreFormat" ) then
				StringFormat( Value, "" )
			end

			Text[ self ] = Value

			return
		end

		rawset( self, Key, Value )
	end
end

function ScreenText:UpdateText()
	if self.IgnoreFormat then
		self.Obj:SetText( self.Text )
		return
	end

	local TimeConverter = self.Digital and DigitalTime or TimeToString
	self.Obj:SetText( StringFormat( self.Text, TimeConverter( self.Duration ) ) )
end

function ScreenText:End()
	self.NextUpdate = SharedTime()
	self.Duration = self.UpdateRate
end

function ScreenText:Remove()
	Shine.ScreenText.Remove( self.Index )
end

function ScreenText:IsValid()
	return Messages:Get( self.Index ) ~= nil
end

function ScreenText:SetColour( Col )
	self.Colour = Col
	self.Obj:SetColor( Col )
end

function ScreenText:SetText( Text )
	self.Text = Text
	self.Obj:SetText( Text )
end

function ScreenText:SetIsVisible( Visible )
	self.Obj:SetIsVisible( Visible )
end

function ScreenText:GetIsVisible()
	return self.Obj:GetIsVisible()
end

function ScreenText:SetTextAlignmentX( Alignment )
	self.Obj:SetTextAlignmentX( Alignment )
end

function ScreenText:SetTextAlignmentY( Alignment )
	self.Obj:SetTextAlignmentY( Alignment )
end

function ScreenText:SetScaledPos( X, Y )
	local GUIObj = self.Obj
	if not GUIObj then return end

	self.x = X
	self.y = Y

	local ScrW = Client.GetScreenWidth()
	local ScrH = Client.GetScreenHeight()

	GUIObj:SetPosition( Vector( ScrW * self.x, ScrH * self.y, 0 ) )
end

function ScreenText:SetShadowEnabled( ShadowEnabled )
	self.Obj:SetDropShadowEnabled( ShadowEnabled )
end

function ScreenText:SetShadowOffset( ShadowOffset )
	self.Obj:SetDropShadowOffset( ShadowOffset )
end

function ScreenText:SetShadowColour( ShadowColour )
	self.Obj:SetDropShadowColor( ShadowColour )
end

local function GetFontAndScale( ScrW, ScrH, Size )
	local Font = StandardFonts[ Size ]

	if ScrH > SGUI.ScreenHeight.Normal and ScrH <= SGUI.ScreenHeight.Large then
		Font = HighResFonts[ Size ]
	elseif ScrH > SGUI.ScreenHeight.Large then
		Font = FourKFonts[ Size ]
	end

	local ScaleVec
	if IsType( Font, "table" ) then
		ScaleVec = Vector( Font[ 2 ], Font[ 2 ], 0 )
		Font = Font[ 1 ]
	else
		ScaleVec = ScrH <= SGUI.ScreenHeight.Normal and GUIScale( Vector( 1, 1, 1 ) ) or Vector( 1, 1, 1 )
	end

	return Font, ScaleVec
end

function ScreenText:Recompute()
	local GUIObj = self.Obj
	if not GUIObj then return end

	local ScrW = Client.GetScreenWidth()
	local ScrH = Client.GetScreenHeight()

	local Font, ScaleVec = GetFontAndScale( ScrW, ScrH, self.Size )

	GUIObj:SetScale( ScaleVec )
	GUIObj:SetPosition( Vector( ScrW * self.x, ScrH * self.y, 0 ) )
	GUIObj:SetFontName( Font )
end

--[[
	Adds or updates a text label with the given ID and parameters.
]]
function Shine.ScreenText.Add( ID, Params )
	local X = Params.X
	local Y = Params.Y
	local Text = Params.Text
	local Duration = Params.Duration
	local R, G, B = Params.R, Params.G, Params.B
	local Alignment = Params.Alignment
	local FadeIn = Params.FadeIn or 0.5
	local Size = Params.Size or 1
	local IgnoreFormat = Params.IgnoreFormat

	if not Duration then
		IgnoreFormat = true
	end

	local ScrW = Client.GetScreenWidth()
	local ScrH = Client.GetScreenHeight()

	local Font, ScaleVec = GetFontAndScale( ScrW, ScrH, Size )

	local MessageTable = Messages:Get( ID )
	local AlreadyExists = MessageTable ~= nil
	local GUIObj

	if Alignment == 0 then
		Alignment = GUIItem.Align_Min
	elseif Alignment == 1 then
		Alignment = GUIItem.Align_Center
	else
		Alignment = GUIItem.Align_Max
	end

	if not MessageTable then
		MessageTable = setmetatable( {
			Index = ID
		}, ScreenText )

		MessageTable.IgnoreFormat = IgnoreFormat

		-- Force text to be checked before we create a GUI item.
		MessageTable.Text = Text

		GUIObj = GUI.CreateItem()
		GUIObj:SetOptionFlag( GUIItem.ManageRender )
		GUIObj:SetTextAlignmentY( GUIItem.Align_Center )
		GUIObj:SetIsVisible( true )

		MessageTable.Obj = GUIObj
	else
		GUIObj = MessageTable.Obj
	end

	local ShouldFade = FadeIn > 0.05 and not AlreadyExists

	MessageTable.IgnoreFormat = IgnoreFormat
	MessageTable.Text = Text
	MessageTable.Colour = Color( R / 255, G / 255, B / 255, ShouldFade and 0 or 1 )
	MessageTable.Duration = Duration
	MessageTable.x = X
	MessageTable.y = Y
	MessageTable.Size = Size
	MessageTable.SuppressTextUpdates = false

	GUIObj:SetTextAlignmentX( Alignment )
	GUIObj:SetText( IgnoreFormat and Text or StringFormat( Text,
		TimeToString( Duration ) ) )
	GUIObj:SetScale( ScaleVec )
	GUIObj:SetPosition( Vector( ScrW * X, ScrH * Y, 0 ) )
	GUIObj:SetColor( MessageTable.Colour )
	GUIObj:SetFontName( Font )

	if Params.ShadowEnabled ~= false then
		GUIObj:SetDropShadowEnabled( true )
		GUIObj:SetDropShadowOffset( Params.ShadowOffset or Vector2( 2, 2 ) )
		GUIObj:SetDropShadowColor( Params.ShadowColour or Colour( 0, 0, 0, 0.6 ) )
	else
		GUIObj:SetDropShadowEnabled( false )
	end

	if ShouldFade then
		MessageTable.Fading = true
		MessageTable.FadingIn = true
		MessageTable.FadeElapsed = 0
		MessageTable.FadeDuration = FadeIn
	else
		MessageTable.Fading = false
	end

	MessageTable.UpdateRate = Params.UpdateRate or 1
	MessageTable.NextUpdate = SharedTime() + MessageTable.UpdateRate

	Messages:Add( ID, MessageTable )

	return MessageTable
end

--[[
	Gets the screen text instance with the given ID, if it exists.
]]
function Shine.ScreenText.Get( ID )
	return Messages:Get( ID )
end

--[[
	Changes the text of the screen text message with the given ID, if it exists.
]]
function Shine.ScreenText.SetText( ID, Text )
	local MessageTable = Messages:Get( ID )
	if not MessageTable then return end

	MessageTable:SetText( Text )
end

--[[
	Immediately removes the screen text message with the given ID, if it exists.
]]
function Shine.ScreenText.Remove( ID )
	local Message = Messages:Get( ID )
	if not Message then return end

	GUI.DestroyItem( Message.Obj )
	Messages:Remove( ID )
end

--[[
	Sets the screen text message with the given ID to fade out, starting from now.

	Looks better than removing, but takes time to complete.
]]
function Shine.ScreenText.End( ID )
	local MessageTable = Messages:Get( ID )
	if not MessageTable then return end

	MessageTable.SuppressTextUpdates = true
	MessageTable:End()
end

local function UpdateMessage( Index, Message, Time )
	if Message.NextUpdate > Time then return end

	local Duration = Message.Duration
	if Duration then
		Duration = Duration - Message.UpdateRate
		Message.Duration = Duration
	end

	Message.NextUpdate = Time + Message.UpdateRate
	if not Message.SuppressTextUpdates then
		xpcall( Message.UpdateText, ScreenTextErrorHandler, Message )

		if Message.Think then
			xpcall( Message.Think, ScreenTextErrorHandler, Message )
		end
	end

	if Duration and Duration <= 0 and Message.Colour.a > 0 and not Message.Fading then
		Message.FadingIn = false
		Message.Fading = true
		Message.FadeElapsed = 0
		Message.FadeDuration = 1
	end

	if Duration and Duration <= -1 then
		Shine.ScreenText.Remove( Index )
	end
end

local function ProcessQueue( Time )
	for Index, Message in Messages:Iterate() do
		UpdateMessage( Index, Message, Time )
	end
end

-- Not the lifeform...
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

Shine.Hook.Add( "Think", "ScreenText", function( DeltaTime )
	local Time = SharedTime()

	ProcessQueue( Time )
	ProcessFades( DeltaTime )
end )

Client.HookNetworkMessage( "Shine_ScreenText", function( Message )
	Shine.ScreenText.Add( Message.ID, Message )
end )

Client.HookNetworkMessage( "Shine_ScreenTextUpdate", function( Message )
	Shine.ScreenText.SetText( Message.ID, Message.Text )
end )

Client.HookNetworkMessage( "Shine_ScreenTextRemove", function( Message )
	Shine.ScreenText[ Message.Now and "Remove" or "End" ]( Message.ID )
end )

Shine.Hook.Add( "OnResolutionChanged", "ScreenText", function( OldX, OldY, NewX, NewY )
	for Index, Message in Messages:Iterate() do
		Message:Recompute()
	end
end )
