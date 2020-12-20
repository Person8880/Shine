--[[
	Chat system client-side.
]]

local Hook = Shine.Hook

local BitBAnd = bit.band
local BitLShift = bit.lshift
local IsType = Shine.IsType
local StringFormat = string.format
local tostring = tostring

Shine.HookNetworkMessage( "Shine_TranslatedConsoleMessage", function( Data )
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

	Shine.HookNetworkMessage( "Shine_Notification", function( Data )
		if not CanDisplayNotification( Data ) then return end

		Shine.GUI.NotificationManager.AddNotification( Data.Type, Data.Message, Data.Duration )
	end )
	Shine.HookNetworkMessage( "Shine_TranslatedNotification", function( Data )
		if not CanDisplayNotification( Data ) then return end

		local Source = Data.Source
		if Source == "" then
			Source = "Core"
		end

		local Message = Shine.Locale:GetPhrase( Source, Data.MessageKey )
		Shine.GUI.NotificationManager.AddNotification( Data.Type, Message, Data.Duration )
	end )
end

local function RGBToHex( R, G, B )
	return BitLShift( BitBAnd( R, 0xFF ), 16 ) + BitLShift( BitBAnd( G, 0xFF ), 8 ) + BitBAnd( B, 0xFF )
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

local function GetChatMessages()
	return nil
end

Hook.CallAfterFileLoad( "lua/Chat.lua", function()
	GetChatMessages = Shine.GetUpValueAccessor( ChatUI_GetMessages, "chatMessages", {
		Recursive = true,
		Predicate = Shine.UpValuePredicates.DefinedInFile( "lua/Chat.lua" )
	} )
end )

local function SetupAndGetChatMessages()
	local ChatMessages = GetChatMessages()
	if not ChatMessages then
		Shared.Message( "[Shine] Unable to retrieve message table!" )
		return nil
	end

	return ChatMessages
end

--[[
	Adds a message to the chat.

	This should be considered an internal function. All chat interaction should use the Chat API.

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

Shine.HookNetworkMessage( "Shine_ChatErrorMessage", function( Message )
	local Text = Message.Message
	if Message.Source ~= "" then
		Text = Shine.Locale:GetPhrase( Message.Source, Text )
	end
	Shine:NotifyError( Text )
end )

-- Displays a coloured message.
Shine.HookNetworkMessage( "Shine_ChatCol", function( Message )
	local R = Message.R / 255
	local G = Message.G / 255
	local B = Message.B / 255

	local String = Message.Message
	local Prefix = Message.Prefix

	Shine.AddChatText( Message.RP, Message.GP, Message.BP, Prefix, R, G, B, String )
end )

Shine.HookNetworkMessage( "Shine_TranslatedChatCol", function( Message )
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

-- Deprecated chat message. Only useful for PMs/Admin say messages.
Shine.HookNetworkMessage( "Shine_Chat", function( Message )
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

	-- This shows just the message, no name, no prefix (no longer used as it doesn't work).
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

	local GetOffset, SetOffset = Shine.GetUpValueAccessor( ChatElement.Update, "kOffset", {
		Recursive = true,
		Predicate = Shine.UpValuePredicates.DefinedInFile( "lua/GUIChat.lua" )
	} )

	local DefaultOffset = Vector( 100, -430, 0 )
	local OriginalOffset = GetOffset()
	if OriginalOffset then
		OriginalOffset = Vector( OriginalOffset )
	else
		OriginalOffset = DefaultOffset
	end

	function ChatElement:GetOffset()
		return GetOffset() or OriginalOffset
	end

	function ChatElement:Initialize()
		Hook.Broadcast( "OnGUIChatInitialised", self )

		OldInit( self )

		-- Reset the original offset so it accounts for any team-based changes.
		-- On older builds, this would only be called once the first time the element is created so this won't pick
		-- up changes made later.
		OriginalOffset = GetOffset() or OriginalOffset

		Hook.Broadcast( "PostGUIChatInitialised", self )
	end

	function ChatElement:Uninitialize()
		Hook.Broadcast( "OnGUIChatDestroyed", self )

		return OldUninit( self )
	end

	local OldUpdatePosition = ChatElement.UpdatePosition
	local OldOnLocalPlayerChanged = ChatElement.OnLocalPlayerChanged
	if OldUpdatePosition or OldOnLocalPlayerChanged then
		local OldMethod = OldUpdatePosition or OldOnLocalPlayerChanged
		local function HandleUpdate( self, Player, ... )
			OriginalOffset = nil

			OldMethod( self, Player, ... )
			self.HasMoved = false

			if not OriginalOffset then
				-- Ensure the offset is updated after a player-dependent position change.
				OriginalOffset = GetOffset() or DefaultOffset
			end

			Hook.Broadcast( "OnGUIChatOffsetChanged", self, Player )
		end

		ChatElement[ OldUpdatePosition and "UpdatePosition" or "OnLocalPlayerChanged" ] = HandleUpdate
	end

	function ChatElement:ResetScreenOffset()
		if not OriginalOffset then return end

		if self.OnLocalPlayerChanged then
			self.HasMoved = false
			-- Newer versions have per-team offsets.
			self:OnLocalPlayerChanged( Client.GetLocalPlayer() )
		else
			self:SetScreenOffset( GUIScale( OriginalOffset ) )
			self.HasMoved = false
		end
	end

	function ChatElement:SetScreenOffset( Offset )
		if not GetOffset() then return end

		local InverseScale = 1 / GUIScale( 1 )
		local NewOffset = Vector2( Offset.x * InverseScale, Offset.y * InverseScale )
		SetOffset( NewOffset )

		self.HasMoved = NewOffset ~= OriginalOffset

		-- Update existing message's x-position as it's not changed in the
		-- Update() method.
		local Messages = self.messages
		if not Messages then return end

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

	function ChatElement:ExtractTags( Message )
		local Rookie = Message.Rookie and Message.Rookie:GetIsVisible()
		local Commander = Message.Commander and Message.Commander:GetIsVisible()

		local TagData
		if Rookie or Commander then
			TagData = {}

			if Commander then
				TagData[ 1 ] = GetTag( Message.Commander )
			end

			if Rookie then
				TagData[ #TagData + 1 ] = GetTag( Message.Rookie )
			end
		end

		return TagData
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

		local TagData = self:ExtractTags( JustAdded )

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
