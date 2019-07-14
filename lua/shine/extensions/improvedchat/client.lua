--[[
	Improved chat plugin client-side.
]]

-- TODO:
-- * Build the rich text chat API, and make the chatbox participate in it.
--   * This means chat messages have a player attached to them (i.e. Steam ID).
--   * System messages would be taggable with their source (e.g. the plugin name).
--   * Potentially have some kind of filtering options to filter out unwanted messages client-side.

local Hook = Shine.Hook
local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local IsType = Shine.IsType
local StringFormat = string.format
local TableRemove = table.remove
local TableRemoveByValue = table.RemoveByValue

local Plugin = ...
Plugin.HasConfig = true
Plugin.ConfigName = "ImprovedChat.json"

Plugin.Version = "1.0"

Plugin.DefaultConfig = {
	BackgroundOpacity = 0.75,
	MaxVisibleMessages = 10
}

Plugin.CheckConfig = true
Plugin.SilentConfigSave = true

Plugin.SourceType = table.AsEnum{
	"PLAYER", "SYSTEM"
}

local IntToColour = ColorIntToColor

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

			local W, H = SGUI.GetScreenSize()
			local Pos = GUIScale( 1 ) * ( CurrentOffset + Vector2( 0, 200 ) )
			self.Panel:SetPos( Pos )
		end
	end

	local ChatMessageLifeTime = Client.GetOptionInteger( "chat-time", 6 )
	local MaxChatWidth = Client.GetOptionInteger( "chat-wrap", 25 ) * 0.01

	local function MakeFadeOutCallback( self, ChatLine )
		return function()
			if not TableRemoveByValue( self.ChatLines, ChatLine ) then
				return
			end

			ChatLine:SetIsVisible( false )
			ChatLine:Reset()

			self.ChatLinePool[ #self.ChatLinePool + 1 ] = ChatLine
		end
	end

	function ChatElement:AddChatLine( Populator, ... )
		local ChatLine = TableRemove( self.ChatLinePool ) or SGUI:Create( "ChatLine", self.Panel )

		self.ChatLines[ #self.ChatLines + 1 ] = ChatLine

		local Scaled = SGUI.Layout.Units.GUIScaled

		local PrefixMargin = Scaled( 5 )
		local LineMargin = Scaled( 2 )
		local PaddingAmount = Scaled( 8 ):GetValue()

		local Font, Scale
		local H = Client.GetScreenHeight()
		if H <= SGUI.ScreenHeight.Small then
			Font = Fonts.kAgencyFB_Tiny
		elseif H <= SGUI.ScreenHeight.Normal then
			Font = Fonts.kAgencyFB_Small
		else
			Font, Scale = SGUI.FontManager.GetFont( "kAgencyFB", 27 )
		end

		ChatLine:SetFont( Font )
		ChatLine:SetTextScale( Scale )
		ChatLine:SetPreMargin( PrefixMargin )
		ChatLine:SetLineSpacing( LineMargin )

		Populator( ChatLine, ... )

		ChatLine:SetSize( Vector2( Client.GetScreenWidth() * MaxChatWidth, 0 ) )
		ChatLine:AddBackground( Colour( 0, 0, 0, Plugin.Config.BackgroundOpacity ), "ui/chat_bg.tga", PaddingAmount )

		local StartPos = Vector2( 0, 0 )
		ChatLine:SetPos( StartPos )

		ChatLine:InvalidateLayout( true )
		ChatLine:SetIsVisible( true )

		local OutExpo = Easing.outExpo
		local function Ease( Progress )
			return OutExpo( Progress, 0, 1, 1 )
		end

		local AnimDuration = 0.3
		if self.visible then
			ChatLine:FadeIn( AnimDuration, Ease )
		else
			ChatLine:MakeVisible()
		end

		local NewLineHeight = ChatLine:GetSize().y
		local YOffset = StartPos.y
		local MaxHeight = -( Client.GetScreenHeight() + self.Panel:GetPos().y )
		local NumLines = #self.ChatLines
		local MaxVisibleMessages = NumLines - Plugin.Config.MaxVisibleMessages

		for i = #self.ChatLines, 1, -1 do
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
						Line:FadeOut( 1, MakeFadeOutCallback( self, Line ) )
					end
				end

				if self.visible then
					Line:MoveTo( nil, nil, NewPos, 0, AnimDuration )
				else
					Line:SetPos( NewPos )
				end
			end
		end

		ChatLine:FadeOutIn( ChatMessageLifeTime, 1, MakeFadeOutCallback( self, ChatLine ), Ease )

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

function Plugin:Initialise()
	self.ChatTagDefinitions = {}
	self.ChatTags = {}

	if self.GUIChat then
		self:SetupGUIChat( self.GUIChat )
	end

	return true
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

	local Pos = GUIScale( 1 ) * ( ChatElement:GetOffset() + Vector2( 0, 200 ) )
	ChatElement.Panel:SetPos( Pos )
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

-- Overrides the default chat behaviour, adding chat tags and turning the contents into rich text.
function Plugin:OnChatMessageReceived( Data )
	local Player = Client.GetLocalPlayer()
	if not Player then return true end

	if not Client.GetIsRunningServer() then
		local Prefix = "Chat All"
		if Data.TeamOnly then
			Prefix = StringFormat( "Chat Team %d", Data.TeamNumber )
		end

		Shared.Message( StringFormat( "%s - %s: %s", Prefix, Data.Name, Data.Message ) )
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
			Contents[ #Contents + 1 ] = {
				Type = "Image",
				Texture = ChatTag.Image,
				AutoSize = Units.UnitVector(
					0,
					Units.Percentage( 100 )
				),
				AspectRatio = 1
			}
		end
		Contents[ #Contents + 1 ] = ChatTag.Colour
		Contents[ #Contents + 1 ] = ( ChatTag.Image and " " or "" )..ChatTag.Text.." "
	end

	if IsCommander then
		Contents[ #Contents + 1 ] = IntToColour( kCommanderColor )
		Contents[ #Contents + 1 ] = "[C] "
	end

	if IsRookie then
		Contents[ #Contents + 1 ] = IntToColour( kNewPlayerColor )
		Contents[ #Contents + 1 ] = Locale.ResolveString( "ROOKIE_CHAT" ).." "
	end

	local Prefix = "(All) "
	if Data.TeamOnly then
		if Data.LocationID > 0 then
			Prefix = StringFormat( "(Team, %s) ", Shared.GetString( Data.LocationID ) )
		else
			Prefix = "(Team) "
		end
	end

	Prefix = StringFormat( "%s%s: ", Prefix, Data.Name )

	Contents[ #Contents + 1 ] = IntToColour( GetColorForTeamNumber( Data.TeamNumber ) )
	Contents[ #Contents + 1 ] = Prefix

	Contents[ #Contents + 1 ] = {
		Type = "WrappingAnchor"
	}

	Contents[ #Contents + 1 ] = kChatTextColor[ Data.TeamType ]
	Contents[ #Contents + 1 ] = Data.Message

	Hook.Call( "OnChatMessageParsed", Data, Contents )

	self:AddRichTextMessage( {
		Source = {
			Type = self.SourceType.PLAYER,
			ID = Data.SteamID,
			Details = Data
		},
		Message = Contents
	} )

	return true
end

function Plugin:SupportsRichText()
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

function Plugin:Cleanup()
	if self.GUIChat then
		self:ResetGUIChat( self.GUIChat )
	end

	return self.BaseClass.Cleanup( self )
end
