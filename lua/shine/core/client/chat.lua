--[[
	Chat system client-side.
]]

local Hook = Shine.Hook

local StringFormat = string.format
local TableConcat = table.concat
local type = type

-- TODO: Move this to a require-able file.
local ChatAPI = {}

ChatAPI.SourceType = table.AsEnum{
	"PLAYER", "PLUGIN", "SYSTEM"
}

-- and this too...
local DefaultColour = Colour( 1, 1, 1 )
local DefaultProvider = {}

function DefaultProvider:SupportsRichText()
	return false
end

-- Converts a rich-text message into a 2-colour message.
-- Ideally clients of the API should use AddMessage instead when they know rich text is not supported.
function DefaultProvider:AddRichTextMessage( MessageData )
	local MessageParts = {}
	local CurrentText = {}

	local NumColours = 0
	local Contents = MessageData.Message

	for i = 1, #Contents do
		local Entry = Contents[ i ]
		local Type = type( Entry )

		if Type == "table" then
			if Entry.Type == "Text" then
				Type = "string"
				Entry = Entry.Value
			elseif Entry.Type == "Colour" then
				Type = "cdata"
				Entry = Entry.Value
			end
		end

		if Type == "string" then
			if #MessageParts == 0 then
				NumColours = NumColours + 1
				MessageParts[ #MessageParts + 1 ] = DefaultColour
			end
			CurrentText[ #CurrentText + 1 ] = Entry
		elseif Type == "cdata" then
			if NumColours < 2 then
				if #CurrentText > 0 then
					MessageParts[ #MessageParts + 1 ] = TableConcat( CurrentText )
					CurrentText = {}
				end

				if type( MessageParts[ #MessageParts ] ) == "cdata" then
					MessageParts[ #MessageParts ] = Entry
				else
					NumColours = NumColours + 1
					MessageParts[ #MessageParts + 1 ] = Entry
				end
			end
		end
	end

	if #MessageParts == 0 then return end

	MessageParts[ #MessageParts + 1 ] = TableConcat( CurrentText )

	if #MessageParts == 2 then
		-- Only a single colour, use the message component to display it.
		return self:AddMessage( DefaultColour, "", MessageParts[ 1 ], MessageParts[ 2 ] )
	end

	return self:AddMessage( MessageParts[ 1 ], MessageParts[ 2 ], MessageParts[ 3 ], MessageParts[ 4 ] )
end

function DefaultProvider:AddMessage( PrefixColour, Prefix, MessageColour, Message )
	Shine.AddChatText(
		PrefixColour.r * 255,
		PrefixColour.g * 255,
		PrefixColour.b * 255,
		Prefix,
		MessageColour.r,
		MessageColour.g,
		MessageColour.b,
		Message
	)
end

ChatAPI.CurrentProvider = DefaultProvider

function ChatAPI:SupportsRichText()
	return self.CurrentProvider:SupportsRichText()
end

function ChatAPI:AddMessage( PrefixColour, Prefix, MessageColour, Message )
	return self.CurrentProvider:AddMessage( PrefixColour, Prefix, MessageColour, Message )
end

--[[
	Adds a rich text message to the chat.

	Rich text messages must conform to the following structure:
	{
		Source = {
			-- Source allows filtering/extra information about the message to be known.
			-- For example, player messages may provide a right click menu to view the player's Steam/Hive profiles.
			Type = SourceType.PLAYER,
			ID = SteamID
		},
		Message = {
			-- Table of colours/text/textures.
		},
		-- Optionally, the chat sound may be suppressed.
		SuppressSound = true
	}

	By default, rich text messages are converted into 2-colour messages, and the source data is unused.
	However, a rich text aware provider may be able to make use of the extra data.
]]
function ChatAPI:AddRichTextMessage( Message )
	return self.CurrentProvider:AddRichTextMessage( Message )
end

function ChatAPI:SetProvider( Provider )
	Shine.TypeCheck( Provider, "table", 1, "SetProvider" )

	Shine.AssertAtLevel(
		Shine.IsCallable( Provider.AddMessage ),
		"Provider must have an AddMessage method!", 3
	)
	Shine.AssertAtLevel(
		Shine.IsCallable( Provider.AddRichTextMessage ),
		"Provider must have an AddRichTextMessage method!", 3
	)
	Shine.AssertAtLevel(
		Shine.IsCallable( Provider.SupportsRichText ),
		"Provider must have a SupportsRichText method!", 3
	)

	self.CurrentProvider = Provider
end

function ChatAPI:ResetProvider( Provider )
	if self.CurrentProvider == Provider then
		self.CurrentProvider = DefaultProvider
	end
end

Shine.Chat = ChatAPI

Client.HookNetworkMessage( "Shine_TranslatedConsoleMessage", function( Data )
	local Source = Data.Source
	if Source == "" then
		Source = "Core"
	end

	Shared.Message( Shine.Locale:GetPhrase( Source, Data.MessageKey ) )
end )

do
	local function CanDisplayNotification( Data )
		if not Data.OnlyIfAdminMenuOpen then return true end
		return Shine.AdminMenu:GetIsVisible()
	end

	Client.HookNetworkMessage( "Shine_Notification", function( Data )
		if not CanDisplayNotification( Data ) then return end

		Shine.GUI.NotificationManager.AddNotification( Data.Type, Data.Message, Data.Duration )
	end )
	Client.HookNetworkMessage( "Shine_TranslatedNotification", function( Data )
		if not CanDisplayNotification( Data ) then return end

		local Source = Data.Source
		if Source == "" then
			Source = "Core"
		end

		local Message = Shine.Locale:GetPhrase( Source, Data.MessageKey )
		Shine.GUI.NotificationManager.AddNotification( Data.Type, Message, Data.Duration )
	end )
end

local BitLShift = bit.lshift
local IsType = Shine.IsType
local tostring = tostring

local function RGBToHex( R, G, B )
	return BitLShift( R, 16 ) + BitLShift( G, 8 ) + B
end

local function AddChatMessage( Player, ChatMessages, PreHex, Prefix, Col, Message )
	ChatMessages[ #ChatMessages + 1 ] = PreHex
	ChatMessages[ #ChatMessages + 1 ] = Prefix

	ChatMessages[ #ChatMessages + 1 ] = Col
	ChatMessages[ #ChatMessages + 1 ] = Message

	ChatMessages[ #ChatMessages + 1 ] = false
	ChatMessages[ #ChatMessages + 1 ] = false

	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0

	if not StartSoundEffect or not Player.GetChatSound then return end

	StartSoundEffect( Player:GetChatSound() )
end

local GUIChatMessages
local function GetChatMessages()
	return GUIChatMessages
end

local function SetupChatMessages()
	if not GetChatMessages() then
		Shine.JoinUpValues( ChatUI_GetMessages, GetChatMessages, {
			chatMessages = "GUIChatMessages"
		} )
	end
end

local function SetupAndGetChatMessages()
	SetupChatMessages()

	local ChatMessages = GetChatMessages()
	if not ChatMessages then
		Shared.Message( "[Shine] Unable to retrieve message table!" )
		return nil
	end

	return ChatMessages
end

--[[
	Adds a message to the chat.

	Inputs:
		RP, GP, BP - Colour of the prefix.
		Prefix - Text to show before the message.
		R, G, B - Message colour.
		Message - Message text.
]]
function Shine.AddChatText( RP, GP, BP, Prefix, R, G, B, Message )
	local ChatMessages = SetupAndGetChatMessages()
	if not ChatMessages then return end

	local Player = Client.GetLocalPlayer()
	if not Player then return end

	AddChatMessage( Player, ChatMessages, RGBToHex( RP, GP, BP ),
		Prefix, Color( R, G, B, 1 ), Message )
end

--[[
	Client-side version of notify error, displays the translated error tag and the passed in message.
]]
function Shine:NotifyError( Message )
	self.AddChatText( 255, 0, 0, self.Locale:GetPhrase( "Core", "ERROR_TAG" ), 1, 1, 1, Message )
end

--Displays a coloured message.
Client.HookNetworkMessage( "Shine_ChatCol", function( Message )
	local R = Message.R / 255
	local G = Message.G / 255
	local B = Message.B / 255

	local String = Message.Message
	local Prefix = Message.Prefix

	Shine.AddChatText( Message.RP, Message.GP, Message.BP, Prefix, R, G, B, String )
end )

Client.HookNetworkMessage( "Shine_TranslatedChatCol", function( Message )
	local R = Message.R / 255
	local G = Message.G / 255
	local B = Message.B / 255

	local Source = Message.Source
	if Source == "" then
		Source = "Core"
	end

	local String = Shine.Locale:GetPhrase( Source, Message.Message )
	local Prefix = Shine.Locale:GetPhrase( Source, Message.Prefix )
	-- Fall back to core strings for prefix if not found.
	if Prefix == Message.Prefix and Source ~= "Core" then
		Prefix = Shine.Locale:GetPhrase( "Core", Message.Prefix )
	end

	Shine.AddChatText( Message.RP, Message.GP, Message.BP, Prefix, R, G, B, String )
end )

--Deprecated chat message. Only useful for PMs/Admin say messages.
Client.HookNetworkMessage( "Shine_Chat", function( Message )
	local ChatMessages = SetupAndGetChatMessages()
	if not ChatMessages then return end

	local Player = Client.GetLocalPlayer()
	if not Player then return end

	local Notify
	local PreHex = GetColorForTeamNumber( Message.TeamNumber )
	local Prefix = Message.Prefix
	local Name = Message.Name
	local String = Message.Message
	local TeamCol = kChatTextColor[ Message.TeamType ] or Color( 1, 1, 1, 1 )

	--This shows just the message, no name, no prefix (no longer used as it doesn't work).
	if Prefix == "" and Name == "" then
		Prefix = String
		String = "                     "

		Notify = true
	else
		Prefix = StringFormat( "%s%s: ", Prefix ~= "" and "("..Prefix..") " or "", Name )
	end

	AddChatMessage( Player, ChatMessages, PreHex, Prefix, TeamCol, String )

	if not Client.GetIsRunningServer() then
		if not Notify then
			Shared.Message( StringFormat( "Chat %s - %s: %s", Prefix, Name, String ) )
		else
			Shared.Message( String )
		end
	end
end )

Hook.CallAfterFileLoad( "lua/GUIChat.lua", function()
	local ChatElement = GUIChat

	local OldInit = ChatElement.Initialize
	local OldUninit = ChatElement.Uninitialize

	local GetOffset = Shine.GetUpValueAccessor( ChatElement.Update, "kOffset" )
	local OriginalOffset = Vector( GetOffset() )

	function ChatElement:GetOffset()
		return GetOffset()
	end

	function ChatElement:Initialize()
		Hook.Call( "OnGUIChatInitialised", self )

		return OldInit( self )
	end

	function ChatElement:Uninitialize()
		Hook.Call( "OnGUIChatDestroyed", self )

		return OldUninit( self )
	end

	function ChatElement:ResetScreenOffset()
		self:SetScreenOffset( GUIScale( OriginalOffset ) )
	end

	function ChatElement:SetScreenOffset( Offset )
		-- Alter the offset value by reference directly to avoid having to
		-- reposition elements constantly in the Update method.
		local CurrentOffset = GetOffset()
		if not CurrentOffset then return end

		local InverseScale = 1 / GUIScale( 1 )
		CurrentOffset.x = Offset.x * InverseScale
		CurrentOffset.y = Offset.y * InverseScale

		-- Update existing message's x-position as it's not changed in the
		-- Update() method.
		local Messages = self.messages
		for i = 1, #Messages do
			local Message = Messages[ i ]
			local Background = Message.Background

			if Background then
				local Pos = Background:GetPosition()
				Pos.x = Offset.x
				Background:SetPosition( Pos )
			end
		end
	end

	local function GetTag( Element )
		return {
			Colour = Element:GetColor(),
			Text = Element:GetText()
		}
	end

	local OldAddMessage = ChatElement.AddMessage
	function ChatElement:AddMessage( PlayerColour, PlayerName, MessageColour, MessageText, IsCommander, IsRookie )
		local Handled = Hook.Call(
			"OnChatAddMessage", self, PlayerColour, PlayerName, MessageColour, MessageText, IsCommander, IsRookie
		)
		if Handled then return end

		OldAddMessage( self, PlayerColour, PlayerName, MessageColour, MessageText, IsCommander, IsRookie )

		local JustAdded = self.messages[ #self.messages ]
		if not JustAdded then return end

		local Rookie = JustAdded.Rookie and JustAdded.Rookie:GetIsVisible()
		local Commander = JustAdded.Commander and JustAdded.Commander:GetIsVisible()

		local TagData
		if Rookie or Commander then
			TagData = {}

			if Commander then
				TagData[ 1 ] = GetTag( JustAdded.Commander )
			end

			if Rookie then
				TagData[ #TagData + 1 ] = GetTag( JustAdded.Rookie )
			end
		end

		Hook.Call( "OnChatMessageDisplayed", PlayerColour, PlayerName, MessageColour, MessageText, TagData )
	end

	if not ChatElement.SetIsVisible then
		function ChatElement:SetIsVisible( Visible )
			self.visible = not not Visible

			local Messages = self.messages
			if not Messages then return end

			for i = 1, #Messages do
				local Message = Messages[ i ]
				if IsType( Message, "table" ) and Message.Background then
					Message.Background:SetIsVisible( Visible )
				end
			end
		end
	end
end, Hook.MAX_PRIORITY )
