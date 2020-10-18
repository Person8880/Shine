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

local Ceil = math.ceil
local IsType = Shine.IsType
local OSDate = os.date
local RoundTo = math.RoundTo
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
Plugin.FontSizeMode = table.AsEnum{
	"AUTO", "FIXED"
}

Plugin.DefaultConfig = {
	-- Controls whether to animate messages (when they appear, they will always fade out).
	AnimateMessages = true,

	-- The alpha multiplier to apply to the background on chat messages.
	BackgroundOpacity = 0.75,

	-- The font sizing mode to use.
	-- * AUTO resizes the text based on screen resolution.
	-- * FIXED uses FontSizeInPixels to determine the size to use.
	FontSizeMode = Plugin.FontSizeMode.AUTO,

	-- The font size to use when FontSizeMode == FIXED.
	FontSizeInPixels = 27,

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

local CHAT_CONFIG_HINT_NAME = "ImprovedChatConfigHint"

local IntToColour = ColorIntToColor
local DEFAULT_CHAT_OFFSET = Vector2( 0, 150 )
local MOVED_CHAT_OFFSET = Vector2( 0, 300 )
local NO_OFFSET = Vector2( 0, 0 )
local function ComputeChatOffset( GUIChatPos, DesiredOffset )
	return GUIScale( 1 ) * ( GUIChatPos + DesiredOffset )
end

local function GetPaddingAmount()
	return RoundTo( Ceil( Units.GUIScaled( 8 ):GetValue() ), 2 )
end

local function UpdateUpwardsMessagePositions( self, PaddingAmount )
	local YOffset = 0
	for i = 1, #self.ChatLines do
		local ChatLine = self.ChatLines[ i ]
		local Pos = ChatLine:GetPos()
		Pos.y = YOffset

		ChatLine:SetPos( Pos )

		YOffset = YOffset + ChatLine:GetSize().y + PaddingAmount
	end

	local NewYOffset = -YOffset + PaddingAmount
	local Easing = self.MessagePanel:GetEasing( "Move" )
	if Easing then
		-- If easing, offset the start/end positions and current position to avoid a sudden jump.
		local YDiff = NewYOffset - Easing.End.y

		Easing.End.y = NewYOffset
		Easing.Start.y = NewYOffset - Easing.Diff.y

		self.MessagePanel:SetPos( Vector2( 0, self.MessagePanel:GetPos().y + YDiff ) )
	else
		-- Otherwise just move the panel instantly.
		self.MessagePanel:SetPos( Vector2( 0, NewYOffset ) )
	end
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
			local PanelOffset = self.HasMoved and MOVED_CHAT_OFFSET or DEFAULT_CHAT_OFFSET
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

	local Easing = require "shine/lib/gui/util/easing"

	-- Fade fast to avoid making text hard to read.
	local FadingEase = Easing.GetEaser( "OutExpo" )
	local FadingInEase = Easing.GetEaser( "InExpo" )

	-- Move more smoothly to avoid sudden jumps.
	local MovementEase = Easing.GetEaser( "OutSine" )

	local AnimDuration = 0.25
	local function IsAnimationEnabled( self )
		return self.visible and Plugin.Config.AnimateMessages
	end

	local function ResetChatLine( ChatLine )
		ChatLine:StopMoving()
		ChatLine:SetIsVisible( false )
		ChatLine:Reset()
		-- Release upfront to avoid the re-usability depending on the number of elements in the re-used message.
		ChatLine:ReleaseElements()
		ChatLine:SetParent( nil )
	end

	local FadeOutCallback = Shine.TypeDef()
	function FadeOutCallback:Init( GUIChat, ChatLine, PaddingAmount )
		self.GUIChat = GUIChat
		self.ChatLine = ChatLine
		self.PaddingAmount = PaddingAmount
		return self
	end

	function FadeOutCallback:__call()
		local ChatLine = self.ChatLine
		local GUIChat = self.GUIChat
		local PaddingAmount = self.PaddingAmount

		if not TableRemoveByValue( GUIChat.ChatLines, ChatLine ) then
			return
		end

		ResetChatLine( ChatLine )
		GUIChat.ChatLinePool[ #GUIChat.ChatLinePool + 1 ] = ChatLine

		if Plugin.Config.MessageDisplayType == Plugin.MessageDisplayType.DOWNWARDS then
			-- Move remaining messages upwards to fill in the gap.
			local YOffset = 0
			local ShouldAnimate = IsAnimationEnabled( GUIChat )

			for i = 1, #GUIChat.ChatLines do
				local ActiveChatLine = GUIChat.ChatLines[ i ]
				local Pos = ActiveChatLine:GetPos()
				Pos.y = YOffset

				if ShouldAnimate then
					ActiveChatLine:ApplyTransition( {
						Type = "Move",
						EndValue = Pos,
						Duration = AnimDuration,
						EasingFunction = MovementEase
					} )
				else
					ActiveChatLine:SetPos( Pos )
				end

				YOffset = YOffset + ActiveChatLine:GetSize().y + PaddingAmount
			end
		else
			-- Update local message positions and re-position the container panel downward to account for the
			-- lost message.
			UpdateUpwardsMessagePositions( GUIChat, PaddingAmount )
		end
	end

	local function MakeFadeOutCallback( self, ChatLine, PaddingAmount )
		return FadeOutCallback( self, ChatLine, PaddingAmount )
	end

	local function RemoveLineIfOffScreen( Line, Index, self )
		if Line:GetScreenPos().y + Line:GetSize().y < 0 then
			-- Line has gone off the screen, remove it from the active list now to avoid wasted processing.
			ResetChatLine( Line )

			self.ChatLinePool[ #self.ChatLinePool + 1 ] = Line

			return false
		end

		return true
	end

	local function RemoveOffscreenLines( self )
		local NumLines = #self.ChatLines

		self.ChatLinesStream:Filter( RemoveLineIfOffScreen, self )

		if NumLines ~= #self.ChatLines then
			UpdateUpwardsMessagePositions( self, GetPaddingAmount() )
		end
	end

	local RemoveOffscreenLinesCallback = Shine.TypeDef()
	function RemoveOffscreenLinesCallback:Init( GUIChat )
		self.GUIChat = GUIChat
		return self
	end
	function RemoveOffscreenLinesCallback:__call()
		RemoveOffscreenLines( self.GUIChat )
	end

	local function AddChatLineMovingUpwards( self, ChatLine, PaddingAmount, ShouldAnimate )
		local NewLineHeight = ChatLine:GetSize().y
		local YOffset = 0
		local NumLines = #self.ChatLines
		local MaxVisibleMessages = NumLines - Plugin.Config.MaxVisibleMessages

		local LastLine = self.ChatLines[ NumLines - 1 ]
		if LastLine then
			YOffset = LastLine:GetPos().y + LastLine:GetSize().y + PaddingAmount
		end

		-- Add the new line below the previous line.
		ChatLine:SetPos( Vector2( 0, YOffset ) )

		-- Move the backing panel upwards to accomodate the new line.
		-- This avoids messages overlapping if they appear together as they always remain a fixed distance apart.
		local MessagePanelPos = Vector2( 0, -YOffset - NewLineHeight )
		if ShouldAnimate then
			self.MessagePanel:ApplyTransition( {
				Type = "Move",
				EndValue = MessagePanelPos,
				Duration = AnimDuration,
				EasingFunction = MovementEase,
				Callback = RemoveOffscreenLinesCallback( self )
			} )
		else
			self.MessagePanel:SetPos( MessagePanelPos )
			RemoveOffscreenLines( self )
		end

		for i = 1, #self.ChatLines do
			local Line = self.ChatLines[ i ]
			if i <= MaxVisibleMessages then
				-- Avoid too many messages filling the screen.
				if not Line.FadingOut then
					Line:FadeOut( 0.25, MakeFadeOutCallback( self, Line, PaddingAmount ), FadingEase )
				end
			else
				break
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
					Line:FadeOut( 0.25, MakeFadeOutCallback( self, Line, PaddingAmount ), FadingEase )
				end
			end

			-- If the line is easing, then it should already be moving to its correct position.
			if not Line:GetEasing( "Move" ) then
				Line:SetPos( Vector2( 0, YOffset ) )
			end

			YOffset = YOffset + Line:GetSize().y + PaddingAmount
		end
	end

	local BackgroundTexture = PrecacheAsset "ui/shine/chat_bg.dds"

	function ChatElement:AddChatLine( Populator, Context )
		local ChatLine = TableRemove( self.ChatLinePool ) or SGUI:Create( "ChatLine" )
		ChatLine:SetParent( self.MessagePanel )

		self.ChatLines[ #self.ChatLines + 1 ] = ChatLine

		local LineMargin = Units.GUIScaled( 2 )
		local PaddingAmount = GetPaddingAmount()

		local Font, Scale = Plugin:GetFontSize()
		ChatLine:SetFont( Font )
		ChatLine:SetTextScale( Scale )
		ChatLine:SetLineSpacing( LineMargin )

		Populator( ChatLine, Context )

		if not ChatLine:HasVisibleElements() then
			-- Avoid displaying empty messages.
			ResetChatLine( ChatLine )

			TableRemoveByValue( self.ChatLines, ChatLine )
			self.ChatLinePool[ #self.ChatLinePool + 1 ] = ChatLine

			return nil
		end

		ChatLine:SetSize( Vector2( Client.GetScreenWidth() * MaxChatWidth, 0 ) )
		ChatLine:AddBackground( Colour( 0, 0, 0, Plugin.Config.BackgroundOpacity ), BackgroundTexture, PaddingAmount )
		-- The gradient texture seems to wrap right at the end of the gradient, making an awkward black bar.
		-- This hack prevents that from showing.
		ChatLine:SetBackgroundTextureCoordinates( 0, 0, 0.99, 1 )
		ChatLine:SetPos( Vector2( 0, 0 ) )
		ChatLine:InvalidateLayout( true )
		ChatLine:SetIsVisible( true )

		local IsUpward = Plugin.Config.MessageDisplayType == Plugin.MessageDisplayType.UPWARDS
		local ShouldAnimate = IsAnimationEnabled( self )
		if ShouldAnimate then
			ChatLine:FadeIn( AnimDuration, FadingInEase )
		else
			ChatLine:MakeVisible()
		end

		if IsUpward then
			AddChatLineMovingUpwards( self, ChatLine, PaddingAmount, ShouldAnimate, AnimDuration )
		else
			AddChatLineMovingDownwards( self, ChatLine, PaddingAmount )
		end

		ChatLine:FadeOutIn( ChatMessageLifeTime, 1, MakeFadeOutCallback( self, ChatLine, PaddingAmount ), FadingEase )

		if Shine.HasLocalPlayerActivityOccurred() then
			SGUI.NotificationManager.DisplayHint( CHAT_CONFIG_HINT_NAME )
		end

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
		-- Wait a frame before destroying everything in case the element is just being re-created in the same frame.
		Plugin.GUIChatDestroyTimer = Shine.Timer.Simple( 0, function()
			Plugin:ResetGUIChat( GUIChat )
		end, GUIChat )
		Plugin.GUIChat = nil
	end
end )

Plugin.ConfigGroup = {
	Icon = SGUI.Icons.Ionicons.Chatbox
}

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	self.ChatTagDefinitions = {}
	self.ChatTags = {}
	self.MessagesInTransit = {}

	if self.GUIChat then
		self:SetupGUIChat( self.GUIChat )
	end

	ChatAPI:SetProvider( self )

	return true
end

function Plugin:OnFirstThink()
	SGUI.NotificationManager.RegisterHint( CHAT_CONFIG_HINT_NAME, {
		MaxTimes = 1,
		MessageSupplier = function()
			if Shine:IsExtensionEnabled( "chatbox" ) then
				local ChatBoxSettingsTab = self:GetPhrase( "CHATBOX_SETTINGS_TAB_LABEL" )
				return self:GetInterpolatedPhrase( "CHAT_CONFIG_HINT_CHATBOX", {
					ChatBoxSettingsTab = ChatBoxSettingsTab
				} )
			end

			local ChatTabButton = self:GetPhrase( "CLIENT_CONFIG_TAB" )

			local VoteMenuButton = Shine.VoteButton
			if VoteMenuButton then
				return self:GetInterpolatedPhrase( "CHAT_CONFIG_HINT_VOTEMENU", {
					ChatTabButton = ChatTabButton,
					ClientConfigButton = Shine.Locale:GetPhrase( "Core", "CLIENT_CONFIG_MENU" ),
					VoteMenuButton = VoteMenuButton
				} )
			end

			return self:GetInterpolatedPhrase( "CHAT_CONFIG_HINT_CONSOLE", {
				ChatTabButton = ChatTabButton,
				ClientConfigButton = Shine.Locale:GetPhrase( "Core", "CLIENT_CONFIG_MENU" )
			} )
		end,
		HintDuration = 10
	} )
end

function Plugin:SetBackgroundOpacity( Opacity )
	if not self.GUIChat or not self.GUIChat.ChatLines then return end

	local ChatLines = self.GUIChat.ChatLines
	for i = 1, #ChatLines do
		ChatLines[ i ]:SetBackgroundAlpha( Opacity )
	end
end

do
	local MessageDisplayTypeActions = {
		[ Plugin.MessageDisplayType.UPWARDS ] = function( self )
			local Panel = self.GUIChat and self.GUIChat.Panel
			if not SGUI.IsValid( Panel ) then return end

			Panel:SetPos( ComputeChatOffset( self.GUIChat:GetOffset(), DEFAULT_CHAT_OFFSET ) )
			UpdateUpwardsMessagePositions( self.GUIChat, GetPaddingAmount() )

			local Player = Client.GetLocalPlayer()
			if Player then
				self:OnLocalPlayerChanged( Player )
			end
		end,
		[ Plugin.MessageDisplayType.DOWNWARDS ] = function( self )
			local Panel = self.GUIChat and self.GUIChat.Panel
			if not SGUI.IsValid( Panel ) then return end

			Panel:SetPos( ComputeChatOffset( self.GUIChat:GetOffset(), NO_OFFSET ) )
			self.GUIChat.MessagePanel:SetPos( Vector2( 0, 0 ) )
		end
	}

	function Plugin:SetMessageDisplayType( MessageDisplayType )
		local Action = MessageDisplayTypeActions[ MessageDisplayType ]
		if not Action then return end

		return Action( self )
	end
end

function Plugin:GetFontSize()
	if self.Config.FontSizeMode == self.FontSizeMode.AUTO then
		return ChatAPI.GetOptimalFontScale()
	end
	return SGUI.FontManager.GetFontForAbsoluteSize( "kAgencyFB", self.Config.FontSizeInPixels )
end

function Plugin:SetChatOffset( Offset )
	local Panel = self.GUIChat and self.GUIChat.Panel
	if not SGUI.IsValid( Panel ) then return end

	Panel:SetPos( ComputeChatOffset( self.GUIChat:GetOffset(), Offset ) )
end

do
	local BuildNumber = Shared.GetBuildNumber()
	local ABOVE_ALIEN_HEALTH_OFFSET = Vector2( 0, 75 )
	local ABOVE_MARINE_HEALTH_OFFSET
	-- Commander chat needs to be higher up due to possible control groups.
	local ABOVE_MINIMAP_COMMANDER_CHAT_OFFSET = Vector2( 0, -5 )
	-- Spectator chat needs to move to the right to avoid overlapping the marine team player elements.
	local ABOVE_MINIMAP_CHAT_OFFSET = Vector2( 125, 50 )

	if BuildNumber >= 335 then
		-- In 335 onwards, chat for specators/commanders is to the right of the minimap.
		-- This just moves it down a bit more than normal so most messages avoid going too high.
		ABOVE_MINIMAP_CHAT_OFFSET = Vector2( 0, DEFAULT_CHAT_OFFSET.y + 100 )
		-- Alien and marine chat end up moved significantly to the right as well, this stops upwards messages going too
		-- much into the centre of the screen in most cases.
		ABOVE_ALIEN_HEALTH_OFFSET = Vector2( 0, DEFAULT_CHAT_OFFSET.y + 100 )
		ABOVE_MARINE_HEALTH_OFFSET = Vector2( 0, DEFAULT_CHAT_OFFSET.y + 32 )
	end

	local function ShouldMoveChat( self )
		return self.GUIChat and not self.GUIChat.HasMoved
			and self.Config.MessageDisplayType ~= self.MessageDisplayType.DOWNWARDS
	end

	local function SetChatOffsetIfApplicable( self, Offset )
		if not ShouldMoveChat( self ) then return end

		self:SetChatOffset( Offset )
	end

	local function IsSpectator( Player )
		return Player.GetTeamNumber and Player:GetTeamNumber() == kSpectatorIndex
	end

	local function ShouldMoveChatAboveMinimap( Player )
		return Player and ( IsSpectator( Player ) or Player:isa( "Commander" ) )
	end

	local function ShouldMoveChatAboveAlienHealth( Player )
		return Player and Player:isa( "Alien" ) and Player.GetTeamNumber and Player:GetTeamNumber() == kTeam2Index
	end

	local function ShouldMoveChatAboveMarineHealth( Player )
		return BuildNumber >= 335 and Player and Player.GetTeamNumber and Player:GetTeamNumber() == kTeam1Index
	end

	function Plugin:UpdateChatOffset( Player )
		if ShouldMoveChatAboveMinimap( Player ) then
			local Offset = ABOVE_MINIMAP_CHAT_OFFSET
			if BuildNumber < 335 and Player:isa( "Commander" ) then
				Offset = ABOVE_MINIMAP_COMMANDER_CHAT_OFFSET
			end
			return SetChatOffsetIfApplicable( self, Offset )
		end

		if ShouldMoveChatAboveAlienHealth( Player ) then
			return SetChatOffsetIfApplicable( self, ABOVE_ALIEN_HEALTH_OFFSET )
		end

		if ShouldMoveChatAboveMarineHealth( Player ) then
			return SetChatOffsetIfApplicable( self, ABOVE_MARINE_HEALTH_OFFSET )
		end

		return SetChatOffsetIfApplicable( self, DEFAULT_CHAT_OFFSET )
	end

	-- If the player's chat is using its default position, move it when they change to a class whose HUD may obstruct
	-- or be obstructed by the chat (e.g. spectator/commander minimap, alien health status icons).
	function Plugin:OnLocalPlayerChanged( Player )
		-- Allow gamemodes to influence the position if they have different HUD layouts.
		local Offset = Hook.Call(
			"OnCalculateShineChatOffset", self, Player, Vector2( DEFAULT_CHAT_OFFSET.x, DEFAULT_CHAT_OFFSET.y )
		)
		if Offset then
			return self:SetChatOffset( Offset )
		end

		return self:UpdateChatOffset( Player )
	end
end

function Plugin:ReceiveCreateChatTagDefinition( Message )
	local ChatTag = {
		Image = Message.Image ~= "" and Message.Image or nil,
		Text = Message.Text,
		Colour = IntToColour( Message.Colour )
	}

	if ChatTag.Image and not GetFileExists( ChatTag.Image ) then
		ChatTag.Image = nil
	end

	self.ChatTagDefinitions[ Message.Index ] = ChatTag
end

function Plugin:ReceiveDeleteChatTagDefinition( Message )
	self.ChatTagDefinitions[ Message.Index ] = nil
end

function Plugin:ReceiveAssignChatTag( Message )
	self.ChatTags[ Message.SteamID ] = self.ChatTagDefinitions[ Message.Index ]
end

function Plugin:ReceiveResetChatTag( Message )
	self.ChatTags[ Message.SteamID ] = nil
end

local BasicMessageContext = {}
local function PopulateFromBasicMessage( ChatLine, Context )
	local PlayerColour = Context.PlayerColour
	if IsType( PlayerColour, "number" ) then
		PlayerColour = IntToColour( PlayerColour )
	end

	ChatLine:SetMessage( Context.TagData, PlayerColour, Context.PlayerName, Context.MessageColour, Context.MessageText )
end

function Plugin:SetupGUIChat( ChatElement )
	if self.GUIChatDestroyTimer and self.GUIChatDestroyTimer.Data == ChatElement then
		self.GUIChatDestroyTimer:Destroy()
		self.GUIChatDestroyTimer = nil
	end

	ChatElement.ChatLines = ChatElement.ChatLines or {}
	ChatElement.ChatLinePool = ChatElement.ChatLinePool or {}
	ChatElement.ChatLinesStream = Shine.Stream( ChatElement.ChatLines )

	if not SGUI.IsValid( ChatElement.Panel ) then
		ChatElement.Panel = SGUI:Create( "Panel" )
		ChatElement.Panel:SetDebugName( "ImprovedChatContainer" )
		ChatElement.Panel:SetIsSchemed( false )
		ChatElement.Panel:SetColour( Colour( 1, 1, 1, 0 ) )
		ChatElement.Panel:SetAnchor( "BottomLeft" )
		ChatElement.Panel:SetBlockEventsIfFocusedWindow( false )
	end

	if not SGUI.IsValid( ChatElement.MessagePanel ) then
		ChatElement.MessagePanel = SGUI:Create( "Panel", ChatElement.Panel )
		ChatElement.MessagePanel:SetDebugName( "ImprovedChatMessagePanel" )
		ChatElement.MessagePanel:SetIsSchemed( false )
		ChatElement.MessagePanel:SetColour( Colour( 1, 1, 1, 0 ) )
	end

	if kGUILayerChat then
		-- Use the same layer vanilla chat does.
		ChatElement.Panel:SetLayer( kGUILayerChat )
		ChatElement.Panel.OverrideLayer = kGUILayerChat
	end

	local Player = Client.GetLocalPlayer and Client.GetLocalPlayer()
	local Offset = Hook.Call(
		"OnCalculateShineChatOffset", self, Player, Vector2( DEFAULT_CHAT_OFFSET.x, DEFAULT_CHAT_OFFSET.y )
	)
	if Offset then
		self:SetChatOffset( Offset )
	elseif ChatElement.HasMoved and self.Config.MessageDisplayType == self.MessageDisplayType.UPWARDS then
		self:SetChatOffset( MOVED_CHAT_OFFSET )
	elseif self.Config.MessageDisplayType == self.MessageDisplayType.DOWNWARDS then
		self:SetChatOffset( NO_OFFSET )
	else
		self:UpdateChatOffset( Player )
	end

	if ChatElement.visible ~= nil then
		ChatElement.Panel:SetIsVisible( not not ChatElement.visible )
	end

	local Messages = ChatElement.messages
	if not IsType( Messages, "table" ) then return end

	-- Re-populate the chat element with the existing messages.
	for i = 1, #Messages do
		local Message = Messages[ i ]
		-- Hide the existing message immediately.
		Message.Time = 1000

		-- Extract the text from the existing element. There's no way to tell whether the new line was for
		-- a word or a text wrap, so just insert it as-is even though the text wrapping may be different.
		local TagData = ChatElement:ExtractTags( Message )
		local MessageText = Message.Message:GetText()
		if Message.Message2 and Message.Message2:GetIsVisible() and Message.Message2:GetText() ~= "" then
			MessageText = StringFormat( "%s\n%s", MessageText, Message.Message2:GetText() )
		end

		BasicMessageContext.PlayerColour = Message.Player:GetColor()
		BasicMessageContext.PlayerName = Message.Player:GetText()
		BasicMessageContext.MessageColour = Message.Message:GetColor()
		BasicMessageContext.MessageText = MessageText
		BasicMessageContext.TagData = TagData

		ChatElement:AddChatLine( PopulateFromBasicMessage, BasicMessageContext )
	end
end

function Plugin:ResetGUIChat( ChatElement )
	if SGUI.IsValid( ChatElement.Panel ) then
		ChatElement.Panel:Destroy()
		ChatElement.Panel = nil
	end
	ChatElement.ChatLines = nil
	ChatElement.ChatLinePool = nil
	ChatElement.ChatLinesStream = nil
	ChatElement.MessagePanel = nil
end

-- Replace adding standard messages to use ChatLine elements and the altered display behaviour.
function Plugin:OnChatAddMessage( GUIChat, PlayerColour, PlayerName, MessageColour, MessageText, IsCommander, IsRookie )
	if not GUIChat.AddChatLine or self.GUIChat ~= GUIChat then return end

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

	BasicMessageContext.PlayerColour = PlayerColour
	BasicMessageContext.PlayerName = PlayerName
	BasicMessageContext.MessageColour = MessageColour
	BasicMessageContext.MessageText = MessageText
	BasicMessageContext.TagData = TagData

	GUIChat:AddChatLine( PopulateFromBasicMessage, BasicMessageContext )

	Hook.Call( "OnChatMessageDisplayed", PlayerColour, PlayerName, MessageColour, MessageText, TagData )

	return true
end

local function IsVisibleToLocalPlayer( Player, TeamNumber )
	local PlayerTeam = Player.GetTeamNumber and Player:GetTeamNumber()
	return PlayerTeam == TeamNumber or PlayerTeam == kSpectatorIndex or PlayerTeam == kTeamReadyRoom
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
	Units.Percentage.ONE_HUNDRED
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

	-- Server sends -1 for ClientID if there is no client attached to the message.
	local Entry = Data.ClientID ~= -1 and Shine.GetScoreboardEntryByClientID( Data.ClientID )
	local IsCommander = Entry and Entry.IsCommander and IsVisibleToLocalPlayer( Player, Entry.EntityTeamNumber )
	local IsRookie = Entry and Entry.IsRookie

	local Contents = {}

	local ChatTag = self.ChatTags[ Data.SteamID ]
	if ChatTag and ( not Data.TeamOnly or self.dt.DisplayChatTagsInTeamChat ) then
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

	return self:AddRichTextMessage( {
		Source = {
			Type = ChatAPI.SourceTypeName.PLAYER,
			ID = Data.SteamID,
			Details = Data
		},
		Message = Contents
	} )
end

function Plugin:AddRichTextMessage( MessageData )
	if not self.GUIChat then
		-- This shouldn't happen, but fail gracefully if it does.
		self.Logger:Warn( "GUIChat not available, unable to display chat message." )
		return
	end

	if self.GUIChat:AddRichTextMessage( MessageData.Message ) then
		local Player = Client.GetLocalPlayer()
		if Player and not MessageData.SuppressSound and Player.GetChatSound then
			StartSoundEffect( Player:GetChatSound() )
		end

		Hook.Call( "OnRichTextChatMessageDisplayed", MessageData )
	end

	return true
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

			if Colour >= 0 then
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

Shine.LoadPluginModule( "logger.lua", Plugin )

Plugin.ClientConfigSettings = {
	{
		ConfigKey = "AnimateMessages",
		Command = "sh_chat_animatemessages",
		Type = "Boolean",
		CommandMessage = function( Value )
			return StringFormat( "Chat messages %s.", Value and "will now animate" or "will no longer animate" )
		end,
		Tooltip = true
	},
	{
		ConfigKey = "BackgroundOpacity",
		Command = "sh_chat_backgroundopacity",
		Type = "Slider",
		Min = 0,
		Max = 100,
		Decimals = 0,
		IsPercentage = true,
		CommandMessage = "Chat message background opacity set to: %s%%",
		OnChange = Plugin.SetBackgroundOpacity
	},
	{
		ConfigKey = "MaxVisibleMessages",
		Command = "sh_chat_maxvisiblemessages",
		Type = "Slider",
		Min = 5,
		Max = 20,
		Decimals = 0,
		CommandMessage = "Now displaying up to %s messages before fading.",
		Tooltip = true
	},
	{
		ConfigKey = "MessageDisplayType",
		Command = "sh_chat_messagedisplaytype",
		Type = "Radio",
		Options = Plugin.MessageDisplayType,
		CommandMessage = function( Value )
			local Descriptions = {
				[ Plugin.MessageDisplayType.UPWARDS ] = "will now move older messages upwards",
				[ Plugin.MessageDisplayType.DOWNWARDS ] = "will now add new messages below older ones"
			}

			return StringFormat( "Chat messages %s.", Descriptions[ Value ] )
		end,
		OnChange = Plugin.SetMessageDisplayType,
		OptionTooltips = true
	},
	{
		ConfigKey = "FontSizeMode",
		Command = "sh_chat_fontsizemode",
		Type = "Dropdown",
		Options = Plugin.FontSizeMode,
		CommandMessage = function( Value )
			local Descriptions = {
				[ Plugin.FontSizeMode.AUTO ] = "will now automatically change based on screen resolution",
				[ Plugin.FontSizeMode.FIXED ] = "will now use the configured size regardless of resolution"
			}
			return StringFormat( "Chat message font size %s.", Descriptions[ Value ] )
		end
	},
	{
		ConfigKey = "FontSizeInPixels",
		Command = "sh_chat_fontsize",
		Type = "Slider",
		Min = 8,
		Max = 64,
		Decimals = 0,
		CommandMessage = "Chat message font size set to %s pixels.",
		Bindings = {
			{
				From = {
					Element = "FontSizeMode",
					Property = "SelectedOption"
				},
				To = {
					Element = "Container",
					Property = "IsVisible",
					Transformer = function( Option )
						return Option.Value == Plugin.FontSizeMode.FIXED
					end
				}
			}
		}
	}
}

do
	local CaseFormatType = string.CaseFormatType
	local StringTransformCase = string.TransformCase

	local function GetLabel( Setting, Suffix )
		return Plugin:GetPhrase(
			StringTransformCase(
				Setting.ConfigKey, CaseFormatType.UPPER_CAMEL, CaseFormatType.UPPER_UNDERSCORE
			)..Suffix
		)
	end

	local ChatBoxSettings = {}
	local TypeMap = {
		Boolean = "CheckBox",
		Radio = "Dropdown"
	}

	local TypeConverters = {
		Slider = function( Setting, ChatBoxSetting )
			ChatBoxSetting.Bounds = { Setting.Min, Setting.Max }
			ChatBoxSetting.Decimals = Setting.Decimals

			if Setting.IsPercentage then
				ChatBoxSetting.Values = function()
					return Plugin.Config[ Setting.ConfigKey ] * 100
				end
			end
		end,
		Dropdown = function( Setting, ChatBoxSetting )
			ChatBoxSetting.Values = function()
				local Options = {}
				local SelectedOption

				for i = 1, #Setting.Options do
					local KeyPrefix = StringTransformCase(
						Setting.ConfigKey, CaseFormatType.UPPER_CAMEL, CaseFormatType.UPPER_UNDERSCORE
					)

					local Text
					if Setting.Type == "Radio" then
						Text = Setting.Options[ i ]
					else
						Text = StringFormat( "%s_%s", KeyPrefix, Setting.Options[ i ] )
					end

					local Tooltip
					if Setting.OptionTooltips then
						Tooltip = Plugin:GetPhrase( StringFormat( "%s_%s_TOOLTIP", KeyPrefix, Setting.Options[ i ] ) )
					end

					Options[ i ] = {
						Value = Setting.Options[ i ],
						Text = Plugin:GetPhrase( Text ),
						Tooltip = Tooltip
					}

					if Plugin.Config[ Setting.ConfigKey ] == Options[ i ].Value then
						SelectedOption = Options[ i ]
					end
				end

				return Options, SelectedOption
			end
		end
	}

	for i = 1, #Plugin.ClientConfigSettings do
		local Setting = Plugin.ClientConfigSettings[ i ]
		local ChatBoxSetting = {
			ID = "ImprovedChat"..Setting.ConfigKey,
			Type = TypeMap[ Setting.Type ] or Setting.Type,
			ConfigValue = function( ChatBox, Value )
				Shared.ConsoleCommand( StringFormat( "%s %s", Setting.Command, Value ) )
			end,
			Values = function()
				return Plugin.Config[ Setting.ConfigKey ], GetLabel( Setting, "_DESCRIPTION" )
			end,
			Command = Setting.Command,
			Tooltip = Setting.Tooltip and function() return GetLabel( Setting, "_TOOLTIP" ) end or nil
		}

		if TypeConverters[ ChatBoxSetting.Type ] then
			TypeConverters[ ChatBoxSetting.Type ]( Setting, ChatBoxSetting )
		end

		if Setting.Bindings then
			local Bindings = {}
			for i = 1, #Setting.Bindings do
				local Binding = Setting.Bindings[ i ]
				Bindings[ i ] = {
					From = {
						Element = "ImprovedChat"..Binding.From.Element,
						Property = Binding.From.Property
					},
					To = {
						Property = Binding.To.Property == "IsVisible" and "Enabled" or Binding.To.Property,
						Transformer = Binding.To.Transformer,
						Filter = Binding.To.Filter
					}
				}
			end
			ChatBoxSetting.Bindings = Bindings
		end

		if ChatBoxSetting.Type == "Slider" or ChatBoxSetting.Type == "Dropdown" then
			ChatBoxSettings[ #ChatBoxSettings + 1 ] = {
				ID = StringFormat( "ImprovedChat%sLabel", Setting.ConfigKey ),
				Type = "Label",
				Values = function()
					return GetLabel( Setting, "_DESCRIPTION" )
				end
			}
		end

		ChatBoxSettings[ #ChatBoxSettings + 1 ] = ChatBoxSetting
	end

	function Plugin:PopulateChatBoxSettings( ChatBox, SettingsTabs )
		SettingsTabs:AddAll( {
			Label = self:GetPhrase( "CHATBOX_SETTINGS_TAB_LABEL" ),
			Icon = SGUI.Icons.Ionicons.Chatbubbles
		}, ChatBoxSettings )
	end
end
