--[[
	Improved chat plugin client-side.
]]

local ChatAPI = require "shine/core/shared/chat/chat_api"

local ColourElement = require "shine/lib/gui/richtext/elements/colour"
local ImageElement = require "shine/lib/gui/richtext/elements/image"
local SpacerElement = require "shine/lib/gui/richtext/elements/spacer"
local TextElement = require "shine/lib/gui/richtext/elements/text"

local Hook = Shine.Hook
local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local IsType = Shine.IsType
local OSDate = os.date
local StringFormat = string.format
local StringFind = string.find
local TableRemove = table.remove
local TableRemoveByValue = table.RemoveByValue

local Plugin = ...
Plugin.HasConfig = true
Plugin.ConfigName = "ImprovedChat.json"

Plugin.Version = "1.0"
Plugin.MessageDisplayType = table.AsEnum{
	"UPWARDS", "DOWNWARDS"
}

Plugin.DefaultConfig = {
	-- Controls whether to animate messages (when they appear, they will always fade out).
	AnimateMessages = true,
	-- The alpha multiplier to apply to the background on chat messages.
	BackgroundOpacity = 0.75,
	-- The maximum number of messages to display before forcing the oldest to fade out (to avoid messages
	-- going off the screen).
	MaxVisibleMessages = 10,
	-- How to display messages:
	-- UPWARDS - new messages at the bottom and move up as more messages appear.
	-- DOWNWARDS - the vanilla method, new messages are added below older ones (in case anyone actually likes this).
	MessageDisplayType = Plugin.MessageDisplayType.UPWARDS
}

Plugin.CheckConfig = true
Plugin.SilentConfigSave = true

local IntToColour = ColorIntToColor
local DEFAULT_CHAT_OFFSET = Vector2( 0, 150 )
local ABOVE_MINIMAP_CHAT_OFFSET = Vector2( 0, 50 )
local NO_OFFSET = Vector2( 0, 0 )
local function ComputeChatOffset( GUIChatPos, DesiredOffset )
	return GUIScale( 1 ) * ( GUIChatPos + DesiredOffset )
end

Hook.CallAfterFileLoad( "lua/GUIChat.lua", function()
	IntToColour = ColorIntToColor

	local ChatElement = GUIChat

	local OldInit = ChatElement.Initialize
	local OldUninit = ChatElement.Uninitialize

	local OldSetScreenOffset = ChatElement.SetScreenOffset
	function ChatElement:SetScreenOffset( Offset )
		OldSetScreenOffset( self, Offset )

		if SGUI.IsValid( self.Panel ) then
			local CurrentOffset = self:GetOffset()
			local PanelOffset = DEFAULT_CHAT_OFFSET
			if Plugin.Config.MessageDisplayType == Plugin.MessageDisplayType.DOWNWARDS then
				PanelOffset = NO_OFFSET
			end
			self.Panel:SetPos( ComputeChatOffset( CurrentOffset, PanelOffset ) )
		end
	end

	local ChatMessageLifeTime = Client.GetOptionInteger( "chat-time", 6 )
	local MaxChatWidth = Client.GetOptionInteger( "chat-wrap", 25 ) * 0.01

	Hook.Add( "OnClientOptionChanged:chat-time", Plugin, function( Value )
		ChatMessageLifeTime = Value
	end )
	Hook.Add( "OnClientOptionChanged:chat-wrap", Plugin, function( Value )
		MaxChatWidth = Value * 0.01
	end )

	local function MakeFadeOutCallback( self, ChatLine, PaddingAmount )
		return function()
			if not TableRemoveByValue( self.ChatLines, ChatLine ) then
				return
			end

			ChatLine:SetIsVisible( false )
			ChatLine:Reset()

			if Plugin.Config.MessageDisplayType == Plugin.MessageDisplayType.DOWNWARDS then
				-- Move remaining messages upwards to fill in the gap.
				local YOffset = 0
				for i = 1, #self.ChatLines do
					local ChatLine = self.ChatLines[ i ]
					local Pos = ChatLine:GetPos()
					Pos.y = YOffset
					ChatLine:SetPos( Pos )

					YOffset = YOffset + ChatLine:GetSize().y + PaddingAmount
				end
			end

			self.ChatLinePool[ #self.ChatLinePool + 1 ] = ChatLine
		end
	end

	local function AddChatLineMovingUpwards( self, ChatLine, PaddingAmount, ShouldAnimate, AnimDuration, Ease )
		local NewLineHeight = ChatLine:GetSize().y
		local YOffset = 0
		local MaxHeight = -( Client.GetScreenHeight() + self.Panel:GetPos().y )
		local NumLines = #self.ChatLines
		local MaxVisibleMessages = NumLines - Plugin.Config.MaxVisibleMessages

		for i = NumLines, 1, -1 do
			local Line = self.ChatLines[ i ]
			local LineHeight = Line:GetSize().y

			YOffset = YOffset - LineHeight - PaddingAmount

			local NewPos = Vector2( 0, YOffset )

			if NewPos.y + LineHeight < MaxHeight then
				-- Line has gone off the screen, remove it from the active list now to avoid wasted processing.
				TableRemove( self.ChatLines, i )
				Line:SetIsVisible( false )
				Line:Reset()

				self.ChatLinePool[ #self.ChatLinePool + 1 ] = Line
			else
				if i <= MaxVisibleMessages then
					-- Avoid too many messages filling the screen.
					if not Line.FadingOut then
						Line:FadeOut( 1, MakeFadeOutCallback( self, Line, PaddingAmount ) )
					end
				end

				if ShouldAnimate then
					Line:MoveTo( nil, nil, NewPos, 0, AnimDuration, nil, Ease )
				else
					Line:SetPos( NewPos )
				end
			end
		end
	end

	local function AddChatLineMovingDownwards( self, ChatLine, PaddingAmount )
		local NumLines = #self.ChatLines
		local MaxVisibleMessages = NumLines - Plugin.Config.MaxVisibleMessages
		local YOffset = 0

		for i = 1, NumLines do
			local Line = self.ChatLines[ i ]
			if i <= MaxVisibleMessages then
				-- Avoid too many messages filling the screen.
				if not Line.FadingOut then
					Line:FadeOut( 1, MakeFadeOutCallback( self, Line, PaddingAmount ) )
				end
			end

			Line:SetPos( Vector2( 0, YOffset ) )

			YOffset = YOffset + Line:GetSize().y + PaddingAmount
		end
	end

	function ChatElement:AddChatLine( Populator, ... )
		local ChatLine = TableRemove( self.ChatLinePool ) or SGUI:Create( "ChatLine", self.Panel )

		self.ChatLines[ #self.ChatLines + 1 ] = ChatLine

		local Scaled = SGUI.Layout.Units.GUIScaled

		local PrefixMargin = Scaled( 5 )
		local LineMargin = Scaled( 2 )
		local PaddingAmount = Scaled( 8 ):GetValue()

		local Font, Scale = ChatAPI.GetOptimalFontScale()
		ChatLine:SetFont( Font )
		ChatLine:SetTextScale( Scale )
		ChatLine:SetPreMargin( PrefixMargin )
		ChatLine:SetLineSpacing( LineMargin )

		Populator( ChatLine, ... )

		ChatLine:SetSize( Vector2( Client.GetScreenWidth() * MaxChatWidth, 0 ) )
		ChatLine:AddBackground( Colour( 0, 0, 0, Plugin.Config.BackgroundOpacity ), "ui/chat_bg.tga", PaddingAmount )
		ChatLine:SetPos( Vector2( 0, 0 ) )
		ChatLine:InvalidateLayout( true )
		ChatLine:SetIsVisible( true )

		local IsUpward = Plugin.Config.MessageDisplayType == Plugin.MessageDisplayType.UPWARDS

		local OutExpo = Easing.outExpo
		local function Ease( Progress )
			return OutExpo( Progress, 0, 1, 1 )
		end

		local AnimDuration = 0.3
		local ShouldAnimate = self.visible and Plugin.Config.AnimateMessages and IsUpward
		if ShouldAnimate then
			ChatLine:FadeIn( AnimDuration, Ease )
		else
			ChatLine:MakeVisible()
		end

		if IsUpward then
			AddChatLineMovingUpwards( self, ChatLine, PaddingAmount, ShouldAnimate, AnimDuration, Ease )
		else
			AddChatLineMovingDownwards( self, ChatLine, PaddingAmount )
		end

		ChatLine:FadeOutIn( ChatMessageLifeTime, 1, MakeFadeOutCallback( self, ChatLine, PaddingAmount ), Ease )

		return ChatLine
	end

	local OnAddMessageError = Shine.BuildErrorHandler( "AddRichTextMessage error" )
	local function PopulateFromContents( ChatLine, Contents )
		ChatLine:SetContent( Contents )
	end

	function ChatElement:AddRichTextMessage( Contents )
		local Success, ChatLine = xpcall( self.AddChatLine, OnAddMessageError, self, PopulateFromContents, Contents )
		if Success then
			return ChatLine
		end
	end

	local OldSetIsVisible = ChatElement.SetIsVisible
	function ChatElement:SetIsVisible( Visible )
		OldSetIsVisible( self, Visible )

		if SGUI.IsValid( self.Panel ) then
			self.Panel:SetIsVisible( not not Visible )
		end
	end
end )

-- Note that these are not tied to the plugin table as they need to run regardless of whether
-- the plugin is enabled or not.
Hook.Add( "OnGUIChatInitialised", Plugin, function( GUIChat )
	Plugin.GUIChat = GUIChat

	if Plugin.Enabled then
		Plugin:SetupGUIChat( GUIChat )
	end
end )
Hook.Add( "OnGUIChatDestroyed", Plugin, function( GUIChat )
	if Plugin.GUIChat == GUIChat then
		Plugin:ResetGUIChat( GUIChat )
		Plugin.GUIChat = nil
	end
end )

Plugin.ConfigGroup = {
	Icon = SGUI.Icons.Ionicons.Chatbox
}

function Plugin:Initialise()
	self.ChatTagDefinitions = {}
	self.ChatTags = {}
	self.MessagesInTransit = {}

	if self.GUIChat then
		self:SetupGUIChat( self.GUIChat )
	end

	self:SetupClientConfig()

	ChatAPI:SetProvider( self )

	return true
end

function Plugin:SetupClientConfig()
	self:AddClientSettings( {
		{
			ConfigKey = "AnimateMessages",
			Command = "sh_chat_animatemessages",
			Type = "Boolean",
			Description = "ANIMATE_MESSAGES_DESCRIPTION",
			CommandMessage = function( Value )
				return StringFormat( "Chat messages %s.", Value and "will now animate" or "will no longer animate" )
			end
		},
		{
			ConfigKey = "BackgroundOpacity",
			Command = "sh_chat_backgroundopacity",
			Type = "Slider",
			Min = 0,
			Max = 100,
			Decimals = 0,
			Description = "BACKGROUND_OPACITY_DESCRIPTION",
			IsPercentage = true,
			CommandMessage = "Chat message background opacity set to: %s%%",
			OnChange = self.SetBackgroundOpacity
		},
		{
			ConfigKey = "MaxVisibleMessages",
			Command = "sh_chat_maxvisiblemessages",
			Type = "Slider",
			Min = 5,
			Max = 20,
			Decimals = 0,
			Description = "MAX_VISIBLE_MESSAGES_DESCRIPTION",
			CommandMessage = "Now displaying up to %s messages before fading."
		},
		{
			ConfigKey = "MessageDisplayType",
			Command = "sh_chat_messagedisplaytype",
			Type = "Radio",
			Options = self.MessageDisplayType,
			Description = "MESSAGE_DISPLAY_TYPE_DESCRIPTION",
			CommandMessage = function( Value )
				local Descriptions = {
					[ self.MessageDisplayType.UPWARDS ] = "will now move older messages upwards",
					[ self.MessageDisplayType.DOWNWARDS ] = "will now add new messages below older ones"
				}

				return StringFormat( "Chat messages %s.", Descriptions[ Value ] )
			end,
			OnChange = self.SetMessageDisplayType
		}
	} )
end

function Plugin:SetBackgroundOpacity( Opacity )
	if not self.GUIChat or not self.GUIChat.ChatLines then return end

	local ChatLines = self.GUIChat.ChatLines
	for i = 1, #ChatLines do
		ChatLines[ i ]:SetAlpha( Opacity )
	end
end

local MessageDisplayTypeActions = {
	[ Plugin.MessageDisplayType.UPWARDS ] = function( self )
		local Panel = self.GUIChat and self.GUIChat.Panel
		if not SGUI.IsValid( Panel ) then return end

		Panel:SetPos( ComputeChatOffset( self.GUIChat:GetOffset(), DEFAULT_CHAT_OFFSET ) )

		local Player = Client.GetLocalPlayer()
		if Player then
			self:OnLocalPlayerChanged( Player )
		end
	end,
	[ Plugin.MessageDisplayType.DOWNWARDS ] = function( self )
		local Panel = self.GUIChat and self.GUIChat.Panel
		if not SGUI.IsValid( Panel ) then return end

		Panel:SetPos( ComputeChatOffset( self.GUIChat:GetOffset(), NO_OFFSET ) )
	end
}

function Plugin:SetMessageDisplayType( MessageDisplayType )
	local Action = MessageDisplayTypeActions[ MessageDisplayType ]
	if not Action then return end

	return Action( self )
end

local function ShouldMoveChat( self )
	return self.GUIChat and not self.GUIChat.HasMoved
		and self.Config.MessageDisplayType ~= self.MessageDisplayType.DOWNWARDS
end

function Plugin:MoveChatAboveMinimap()
	if not ShouldMoveChat( self ) then return end

	local Panel = self.GUIChat.Panel
	if not SGUI.IsValid( Panel ) then return end

	Panel:SetPos( ComputeChatOffset( self.GUIChat:GetOffset(), ABOVE_MINIMAP_CHAT_OFFSET ) )
end

function Plugin:MoveChatDownFromAboveMinimap()
	if not ShouldMoveChat( self ) then return end

	local Panel = self.GUIChat.Panel
	if not SGUI.IsValid( Panel ) then return end

	Panel:SetPos( ComputeChatOffset( self.GUIChat:GetOffset(), DEFAULT_CHAT_OFFSET ) )
end

local function ShouldMoveChatUpFor( Player )
	return Player and ( Player:isa( "Spectator" ) or Player:isa( "Commander" ) )
end

-- If the player's chat is using its default position, move it when they change to a class that
-- has a minimap (i.e. spectating or commanding) so it doesn't overlap the minimap.
function Plugin:OnLocalPlayerChanged( Player )
	if ShouldMoveChatUpFor( Player ) then
		return self:MoveChatAboveMinimap()
	else
		return self:MoveChatDownFromAboveMinimap()
	end
end

function Plugin:ReceiveChatTag( Message )
	self.ChatTagDefinitions[ Message.Index ] = {
		Image = Message.Image ~= "" and Message.Image or nil,
		Text = Message.Text,
		Colour = IntToColour( Message.Colour )
	}
end

function Plugin:ReceiveAssignChatTag( Message )
	self.ChatTags[ Message.SteamID ] = self.ChatTagDefinitions[ Message.Index ]
end

function Plugin:ReceiveResetChatTag( Message )
	self.ChatTags[ Message.SteamID ] = nil
end

function Plugin:SetupGUIChat( ChatElement )
	ChatElement.ChatLines = {}
	ChatElement.ChatLinePool = {}

	ChatElement.Panel = SGUI:Create( "Panel" )
	ChatElement.Panel:SetIsSchemed( false )
	ChatElement.Panel:SetColour( Colour( 1, 1, 1, 0 ) )
	ChatElement.Panel:SetAnchor( "BottomLeft" )

	if kGUILayerChat then
		-- Use the same layer vanilla chat does.
		ChatElement.Panel:SetLayer( kGUILayerChat )
		ChatElement.Panel.OverrideLayer = kGUILayerChat
	end

	local Player = Client.GetLocalPlayer and Client.GetLocalPlayer()
	local Offset = ShouldMoveChatUpFor( Player ) and ABOVE_MINIMAP_CHAT_OFFSET or DEFAULT_CHAT_OFFSET

	if self.Config.MessageDisplayType == self.MessageDisplayType.DOWNWARDS then
		Offset = NO_OFFSET
	end

	ChatElement.Panel:SetPos( ComputeChatOffset( ChatElement:GetOffset(), Offset ) )

	local Messages = ChatElement.messages
	if not IsType( Messages, "table" ) then return end

	-- Hide all existing messages immediately (it's not really possible to reconstruct them due to the split
	-- into 2 text elements which could have been text wrapping or word wrapping).
	for i = 1, #Messages do
		local Message = Messages[ i ]
		Message.Time = 1000
	end
end

function Plugin:ResetGUIChat( ChatElement )
	if SGUI.IsValid( ChatElement.Panel ) then
		ChatElement.Panel:Destroy()
		ChatElement.Panel = nil
	end
	ChatElement.ChatLines = nil
	ChatElement.ChatLinePool = nil
end

local function PopulateFromBasicMessage( ChatLine, PlayerColour, PlayerName, MessageColour, MessageText, TagData )
	if IsType( PlayerColour, "number" ) then
		PlayerColour = IntToColour( PlayerColour )
	end

	ChatLine:SetMessage( TagData, PlayerColour, PlayerName, MessageColour, MessageText )
end

-- Replace adding standard messages to use ChatLine elements and the altered display behaviour.
function Plugin:OnChatAddMessage( GUIChat, PlayerColour, PlayerName, MessageColour, MessageText, IsCommander, IsRookie )
	if not GUIChat.AddChatLine then return end

	if IsCommander then
		TagData = {
			{
				Colour = IntToColour( kCommanderColor ),
				Text = "[C] "
			}
		}
	end

	if IsRookie then
		TagData = TagData or {}
		TagData[ #TagData + 1 ] = {
			Colour = IntToColour( kNewPlayerColor ),
			Text = Locale.ResolveString( "ROOKIE_CHAT" ).." "
		}
	end

	GUIChat:AddChatLine( PopulateFromBasicMessage, PlayerColour, PlayerName, MessageColour, MessageText, TagData )

	Hook.Call( "OnChatMessageDisplayed", PlayerColour, PlayerName, MessageColour, MessageText, TagData )

	return true
end

local function IsVisibleToLocalPlayer( Player, TeamNumber )
	local PlayerTeam = Player:GetTeamNumber()
	return PlayerTeam == TeamNumber or PlayerTeam == kSpectatorIndex
end

local function GetTeamPrefix( Data )
	if Data.LocationID > 0 then
		local Location = Shared.GetString( Data.LocationID )
		if StringFind( Location, "[^%s]" ) then
			return StringFormat( "(Team, %s) ", Location )
		end
	end

	return "(Team) "
end

local DEFAULT_IMAGE_SIZE = Units.UnitVector(
	0,
	Units.Percentage( 100 )
)

-- Overrides the default chat behaviour, adding chat tags and turning the contents into rich text.
function Plugin:OnChatMessageReceived( Data )
	local Player = Client.GetLocalPlayer()
	if not Player then return true end

	if not Client.GetIsRunningServer() then
		local Prefix = "Chat All"
		if Data.TeamOnly then
			Prefix = StringFormat( "Chat Team %d", Data.TeamNumber )
		end

		Shared.Message( StringFormat( "%s %s - %s: %s", OSDate( "[%H:%M:%S]" ), Prefix, Data.Name, Data.Message ) )
	end

	if Data.SteamID ~= 0 and ChatUI_GetSteamIdTextMuted( Data.SteamID ) then
		return true
	end

	local IsCommander
	local IsRookie

	local PlayerData = ScoreboardUI_GetAllScores()
	for i = 1, #PlayerData do
		local Entry = PlayerData[ i ]
		if Entry.SteamId == Data.SteamID then
			IsCommander = Entry.IsCommander and IsVisibleToLocalPlayer( Player, Entry.EntityTeamNumber )
			IsRookie = Entry.IsRookie
			break
		end
	end

	local Contents = {}

	local ChatTag = self.ChatTags[ Data.SteamID ]
	if ChatTag then
		if ChatTag.Image then
			Contents[ #Contents + 1 ] = ImageElement( {
				Texture = ChatTag.Image,
				AutoSize = DEFAULT_IMAGE_SIZE,
				AspectRatio = 1
			} )
		end
		Contents[ #Contents + 1 ] = ColourElement( ChatTag.Colour )
		Contents[ #Contents + 1 ] = TextElement( ( ChatTag.Image and " " or "" )..ChatTag.Text.." " )
	end

	if IsCommander then
		Contents[ #Contents + 1 ] = ColourElement( IntToColour( kCommanderColor ) )
		Contents[ #Contents + 1 ] = TextElement( "[C] " )
	end

	if IsRookie then
		Contents[ #Contents + 1 ] = ColourElement( IntToColour( kNewPlayerColor ) )
		Contents[ #Contents + 1 ] = TextElement( Locale.ResolveString( "ROOKIE_CHAT" ).." " )
	end

	local Prefix = "(All) "
	if Data.TeamOnly then
		Prefix = GetTeamPrefix( Data )
	end

	Prefix = StringFormat( "%s%s: ", Prefix, Data.Name )

	Contents[ #Contents + 1 ] = ColourElement( IntToColour( GetColorForTeamNumber( Data.TeamNumber ) ) )
	Contents[ #Contents + 1 ] = TextElement( Prefix )

	Contents[ #Contents + 1 ] = ColourElement( kChatTextColor[ Data.TeamType ] )
	Contents[ #Contents + 1 ] = TextElement( Data.Message )

	Hook.Call( "OnChatMessageParsed", Data, Contents )

	self:AddRichTextMessage( {
		Source = {
			Type = ChatAPI.SourceTypeName.PLAYER,
			ID = Data.SteamID,
			Details = Data
		},
		Message = Contents
	} )

	return true
end

function Plugin:AddRichTextMessage( MessageData )
	if self.GUIChat:AddRichTextMessage( MessageData.Message ) then
		local Player = Client.GetLocalPlayer()
		if Player and not MessageData.SuppressSound then
			StartSoundEffect( Player:GetChatSound() )
		end

		Hook.Call( "OnRichTextChatMessageDisplayed", MessageData )
	end
end

do
	local getmetatable = getmetatable
	local StringMatch = string.match
	local TableAdd = table.Add
	local TableConcat = table.concat
	local TableEmpty = table.Empty
	local tonumber = tonumber

	local Keys = {
		Colour = {},
		Value = {}
	}

	local ValueParsers = {
		t = function( Value )
			return #Value > 0 and TextElement( Value ) or nil
		end,
		i = function( Value )
			return ImageElement( {
				Texture = Value,
				-- For now, restricted to match the text size.
				-- Could possibly alter the format to include size data.
				AutoSize = DEFAULT_IMAGE_SIZE,
				AspectRatio = 1
			} )
		end
	}

	local function ParseChunk( NumValues, Chunk )
		local Contents = {}

		for i = 1, NumValues do
			local Colour = Chunk[ Keys.Colour[ i ] ]
			local Value = Chunk[ Keys.Value[ i ] ]

			if Colour > 0 then
				Contents[ #Contents + 1 ] = ColourElement( IntToColour( Colour ) )
			end

			local Prefix, TextValue = StringMatch( Value, "^([^:]+):(.*)$" )
			local Parser = ValueParsers[ Prefix ]
			if Parser then
				Contents[ #Contents + 1 ] = Parser( TextValue )
			end
		end

		return Contents
	end

	local TypeIDParsers = {
		[ ChatAPI.SourceTypeName.PLAYER ] = function( ID ) return tonumber( ID ) end
	}

	local function AddChunkToMessage( self, MessageID, Data, NumValues )
		local MessageChunks

		if Data.NumChunks > 1 then
			MessageChunks = self.MessagesInTransit[ MessageID ]

			if not MessageChunks then
				MessageChunks = {}
				self.MessagesInTransit[ MessageID ] = MessageChunks
			end

			MessageChunks[ Data.ChunkIndex ] = ParseChunk( NumValues, Data )
		else
			MessageChunks = { ParseChunk( NumValues, Data ) }
		end

		return MessageChunks
	end

	local function ParseMetadata( Holder, Data )
		local TypeName = ChatAPI.SourceTypeName[ Data.SourceType ]
		local Parser = TypeIDParsers[ TypeName ]

		Holder.Source = {
			Type = TypeName,
			ID = Parser and Parser( Data.SourceID ) or Data.SourceID
		}

		Holder.SuppressSound = Data.SuppressSound
	end

	for i = 1, Plugin.MAX_CHUNKS_PER_MESSAGE do
		Keys.Colour[ i ] = "Colour"..i
		Keys.Value[ i ] = "Value"..i

		Plugin[ "ReceiveRichTextChatMessage"..i ] = function( self, Data )
			local MessageID = Data.MessageID
			local MessageChunks = AddChunkToMessage( self, MessageID, Data, i )

			if Data.ChunkIndex == 1 then
				ParseMetadata( MessageChunks, Data )
			end

			if #MessageChunks ~= Data.NumChunks then return end

			self.MessagesInTransit[ MessageID ] = nil

			-- Message from the server may have split text into multiple elements. To ensure proper wrapping
			-- and lower overhead, merge them back together here.
			local FinalMessage = {}
			local CurrentText = {}
			for i = 1, #MessageChunks do
				local Chunk = MessageChunks[ i ]
				for j = 1, #Chunk do
					local Element = Chunk[ j ]
					if getmetatable( Element ) == TextElement then
						CurrentText[ #CurrentText + 1 ] = Element.Value
					else
						if #CurrentText > 0 then
							FinalMessage[ #FinalMessage + 1 ] = TextElement( TableConcat( CurrentText ) )
							TableEmpty( CurrentText )
						end

						FinalMessage[ #FinalMessage + 1 ] = Element
					end
				end
			end

			if #CurrentText > 0 then
				FinalMessage[ #FinalMessage + 1 ] = TextElement( TableConcat( CurrentText ) )
			end

			self:AddRichTextMessage( {
				Source = MessageChunks.Source,
				SuppressSound = MessageChunks.SuppressSound,
				Message = FinalMessage
			} )
		end
	end
end

function Plugin:Cleanup()
	ChatAPI:ResetProvider( self )

	if self.GUIChat then
		self:ResetGUIChat( self.GUIChat )
	end

	self.ChatTagDefinitions = nil
	self.ChatTags = nil

	return self.BaseClass.Cleanup( self )
end
