--[[
	Shine chatbox.

	I can't believe the game doesn't have one.
]]

local Binder = require "shine/lib/gui/binding/binder"
local ChatAPI = require "shine/core/shared/chat/chat_api"

local Shine = Shine

local Hook = Shine.Hook
local SGUI = Shine.GUI
local IsType = Shine.IsType

local Ceil = math.ceil
local Clamp = math.Clamp
local Clock = os.clock
local Floor = math.floor
local Max = math.max
local Min = math.min
local pairs = pairs
local select = select
local StringFind = string.find
local StringFormat = string.format
local StringLen = string.len
local StringSub = string.sub
local StringUTF8Length = string.UTF8Length
local StringUTF8Sub = string.UTF8Sub
local TableEmpty = table.Empty
local TableRemove = table.remove
local TableRemoveByValue = table.RemoveByValue
local TableShallowMerge = table.ShallowMerge
local type = type

local Plugin = Shine.Plugin( ... )

Plugin.HasConfig = true
Plugin.ConfigName = "ChatBox.json"

Plugin.Version = "1.1"

Plugin.FontSizeMode = table.AsEnum{
	"AUTO", "FIXED"
}

Plugin.DefaultConfig = {
	AutoClose = true, -- Should the chatbox close after sending a message?
	DeleteOnClose = true, -- Should whatever's entered be deleted if the chatbox is closed before sending?
	MessageMemory = 50, -- How many messages should the chatbox store before removing old ones?
	MoveVanillaChat = false, -- Whether to move the vanilla chat position.
	SmoothScroll = true, -- Should the scrolling be smoothed?
	ScrollToBottomOnOpen = false, -- Should the chatbox scroll to the bottom when re-opened?
	ShowTimestamps = false, -- Should the chatbox should timestamps with messages?
	Opacity = 0.4, -- How opaque should the chatbox be?
	Pos = {}, -- Remembers the position of the chatbox when it's moved.
	Scale = 1, -- Sets a scale multiplier, requires recreating the chatbox when changed.
	FontSizeMode = Plugin.FontSizeMode.AUTO,
	FontSizeInPixels = 27
}

Plugin.CheckConfig = true
Plugin.SilentConfigSave = true

function Plugin:HookChat( ChatElement )
	local OldSendKey = ChatElement.SendKeyEvent

	function ChatElement:SendKeyEvent( Key, Down )
		if Plugin.Enabled then return end
		return OldSendKey( self, Key, Down )
	end

	local OldAddMessage = ChatElement.AddMessage
	function ChatElement:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName, IsCommander, IsRookie )
		OldAddMessage( self, PlayerColour, PlayerName, MessageColour, MessageName, IsCommander, IsRookie )

		if not Plugin.Enabled then return end

		local JustAdded = self.messages[ #self.messages ]
		if not JustAdded then return end

		if Plugin.Visible and JustAdded.Background then
			JustAdded.Background:SetIsVisible( false )
		end
	end
end

-- We hook the class here for certain functions before we find the actual instance of it.
Hook.CallAfterFileLoad( "lua/GUIChat.lua", function()
	Plugin:HookChat( GUIChat )
end )

Hook.Add( "OnGUIChatInitialised", Plugin, function( GUIChat )
	Plugin.GUIChat = GUIChat
end )
Hook.Add( "OnGUIChatDestroyed", Plugin, function( GUIChat )
	if Plugin.GUIChat == GUIChat then
		Plugin.GUIChat = nil
	end
end )

function Plugin:Initialise()
	-- Not using a plugin method as that is placed before SGUI, which we don't want to override.
	Hook.Add( "PlayerKeyPress", self, function( Key, Down )
		if Down and Key == InputKey.Escape and self.Visible then
			self:CloseChat()
			return true
		end
	end, Hook.DEFAULT_PRIORITY + 1 )

	self.Messages = self.Messages or {}
	self.Enabled = true

	return true
end

function Plugin:OnChatMessageDisplayed( PlayerColour, PlayerName, MessageColour, MessageName, TagData )
	self:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName, Tags )
end

function Plugin:OnRichTextChatMessageDisplayed( MessageData )
	self:AddMessageFromRichText( MessageData )
end

local Units = SGUI.Layout.Units

local Percentage = Units.Percentage
local UnitVector = Units.UnitVector
local Scaled = Units.Scaled
local Spacing = Units.Spacing

local Colours = {
	Background = Colour( 0.6, 0.6, 0.6, 0.4 ),
	Team1Background = Colour( 104 / 255, 191 / 255, 1, 0.4 ),
	Team2Background = Colour( 0.8, 0.5, 0.1, 0.4 ),
	NeutralTeamBackground = Colour( 1, 1, 1, 0.4 ),

	Dark = Colour( 0.2, 0.2, 0.2, 0.8 ),
	Highlight = Colour( 0.5, 0.5, 0.5, 0.8 ),
	ModeText = Colour( 1, 1, 1, 1 ),
	AutoCompleteCommand = Colour( 1, 0.8, 0 ),
	AutoCompleteParams = Colour( 1, 0.5, 0 )
}

local Skin = {
	Button = {
		Default = {
			ActiveCol = Colours.Highlight,
			InactiveCol = Colours.Dark,
			TextColour = Colours.ModeText,
			States = {
				Open = {
					InactiveCol = Colours.Highlight
				}
			}
		}
	},
	Panel = {
		Default = {
			Colour = Colours.Background,
			States = {
				Team1 = {
					Colour = Colours.Team1Background
				},
				Team2 = {
					Colour = Colours.Team2Background
				},
				NeutralTeam = {
					Colour = Colours.NeutralTeamBackground
				}
			}
		},
		MessageList = {
			Colour = Colours.Dark
		}
	},
	TextEntry = {
		Default = {
			FocusColour = Colours.Dark,
			DarkColour = Colours.Dark,
			BorderColour = Colour( 0, 0, 0, 0 ),
			TextColour = Colour( 1, 1, 1, 1 ),
			PlaceholderTextColour = Colour( 0.8, 0.8, 0.8, 0.5 )
		}
	}
}

function Plugin:OnFirstThink()
	-- Copy over default skin values to ensure they are applied regardless of the chosen
	-- default skin.
	local DefaultSkin = SGUI.SkinManager:GetSkinsByName().Default
	TableShallowMerge( DefaultSkin, Skin )
	TableShallowMerge( DefaultSkin.TextEntry, Skin.TextEntry )
	TableShallowMerge( DefaultSkin.Button, Skin.Button )
end

local LayoutData = {
	Sizes = {
		ChatBox = Vector2( 800, 350 ),
		SettingsClosed = Vector2( 0, 350 ),
		Settings = Vector2( 360, 350 ),
		SettingsButton = 36,
		ChatBoxPadding = 5
	},

	Positions = {
		Scrollbar = Vector2( -8, 0 ),
		Settings = Vector2( 0, 0 )
	}
}

local SliderTextPadding = 20
local TextScale = Vector2( 1, 1 )

-- Scales alpha value for elements that default to 0.8 rather than 0.4 alpha.
local function AlphaScale( Alpha )
	if Alpha <= 0.4 then
		return Alpha * 2
	end

	return 0.8 + ( ( Alpha - 0.4 ) / 3 )
end

-- UWE's vector type has no Hadamard product defined.
local function VectorMultiply( Vec1, Vec2 )
	return Vector2( Vec1.x * Vec2.x, Vec1.y * Vec2.y )
end

function Plugin:GetFont()
	return self.Font
end

function Plugin:GetTextScale()
	return self.TextScale
end

local OpacityVariantControls = {
	"MainPanel",
	"ChatBox",
	"TextEntry",
	"SettingsButton",
	"SettingsPanel"
}

local function UpdateOpacity( self, Opacity )
	local ScaledOpacity = AlphaScale( Opacity )

	Colours.Background.a = Opacity
	Colours.Team1Background.a = Opacity
	Colours.Team2Background.a = Opacity
	Colours.NeutralTeamBackground.a = Opacity
	Colours.Dark.a = ScaledOpacity
	Colours.Highlight.a = ScaledOpacity

	for i = 1, #OpacityVariantControls do
		local Control = self[ OpacityVariantControls[ i ] ]
		-- Force the skin to refresh.
		if SGUI.IsValid( Control ) then
			Control:SetStyleName( Control:GetStyleName() )
		end
	end
end

function Plugin:ResetVanillaChatPos()
	self.GUIChat:ResetScreenOffset()
end

function Plugin:MoveVanillaChat()
	if not self.UpdateVanillaChatHistoryPos or not SGUI.IsValid( self.MainPanel ) then
		return
	end

	self.UpdateVanillaChatHistoryPos( self.MainPanel:GetPos() )
end

function Plugin:SetFontSizeMode( FontSizeMode )
	local NewFont, NewScale
	if FontSizeMode == self.FontSizeMode.AUTO then
		self:RefreshFontScale( self.Font, self.MessageTextScale )
		return
	end

	self:SetFontSizeInPixels( self.Config.FontSizeInPixels )
end

function Plugin:SetFontSizeInPixels( FontSizeInPixels )
	if self.Config.FontSizeMode == self.FontSizeMode.AUTO then return end

	self.ManualFont, self.ManualFontScale = SGUI.FontManager.GetFontForAbsoluteSize(
		"kAgencyFB", self.Config.FontSizeInPixels
	)
	self:RefreshFontScale( self.ManualFont, self.ManualFontScale )
end

function Plugin:RefreshFontScale( Font, Scale )
	local Messages = self.Messages

	for i = 1, #Messages do
		Messages[ i ]:SetFontScale( Font, Scale )
	end

	self.ChatBox:InvalidateLayout( true )
end

--[[
	Creates the chatbox UI elements.

	Essentially,
		1. An outer panel to contain everything.
		2. A smaller panel to contain the chat messages, scrollable.
		3. A text entry for entering chat messages (with placeholder text indicating team/all mode).
		4. A settings button that opens up the chatbox settings.
]]
function Plugin:CreateChatbox()
	local UIScale = GUIScale( Vector( 1, 1, 1 ) ) * self.Config.Scale
	local ScalarScale = GUIScale( 1 ) * self.Config.Scale

	local ScreenWidth, ScreenHeight = SGUI.GetScreenSize()
	ScreenWidth = ScreenWidth * self.Config.Scale
	ScreenHeight = ScreenHeight * self.Config.Scale

	local WidthMult = 1
	local HeightMult = 1
	local FourToThreeHeight = ( ScreenWidth / 4 ) * 3
	-- Use a more boxy box for 4:3 monitors.
	if FourToThreeHeight == ScreenHeight then
		WidthMult = WidthMult * 0.72
	end

	UIScale.x = UIScale.x * WidthMult
	UIScale.y = UIScale.y * HeightMult

	ScalarScale = ScalarScale * ( WidthMult + HeightMult ) * 0.5

	self.UIScale = UIScale
	self.ScalarScale = ScalarScale

	self.Font, self.MessageTextScale = ChatAPI.GetOptimalFontScale( ScreenHeight )
	self.TextScale = self.MessageTextScale
	self:SetFontSizeInPixels( self.Config.FontSizeInPixels )

	local Opacity = self.Config.Opacity
	UpdateOpacity( self, Opacity )

	local Pos = self.Config.Pos
	local ChatBoxPos
	local PanelSize = VectorMultiply( LayoutData.Sizes.ChatBox, UIScale )
	local DefaultPos = self.GUIChat.inputItem:GetPosition() - Vector( 0, 100 * UIScale.y, 0 )

	if not Pos.x or not Pos.y then
		ChatBoxPos = DefaultPos
	else
		ChatBoxPos = Vector( Pos.x, Pos.y, 0 )
	end

	ChatBoxPos.x = Clamp( ChatBoxPos.x, 0, ScreenWidth - PanelSize.x )
	ChatBoxPos.y = Clamp( ChatBoxPos.y, -ScreenHeight + PanelSize.y, -PanelSize.y )

	local Border = SGUI:Create( "Panel" )
	Border:SetupFromTable{
		Anchor = "BottomLeft",
		Size = PanelSize,
		Pos = ChatBoxPos,
		Skin = Skin,
		Draggable = true
	}

	-- Double click the title bar to return it to the default position.
	function Border:ReturnToDefaultPos()
		self:SetPos( DefaultPos )
		self:OnDragFinished( DefaultPos )
	end

	-- If, for some reason, there's an error in a panel hook, then this is removed.
	-- We don't want to leave the mouse showing if that happens.
	Border:CallOnRemove( function()
		if self.IgnoreRemove then return end

		if self.Visible then
			SGUI:EnableMouse( false )
			self.Visible = false
			self.GUIChat:SetIsVisible( true )
		end

		TableEmpty( self.Messages )
	end )

	self.MainPanel = Border

	local PaddingUnit = Scaled( LayoutData.Sizes.ChatBoxPadding, ScalarScale )
	local Padding = Spacing( PaddingUnit, PaddingUnit, PaddingUnit, PaddingUnit )

	local ChatBoxLayout = SGUI.Layout:CreateLayout( "Vertical", {
		Padding = Padding
	} )

	local function UpdateVanillaChatHistoryPos( Pos )
		if not self.Config.MoveVanillaChat then return end

		-- Update the external chat history position to match the chatbox.
		local AbsolutePadding = PaddingUnit:GetValue()
		self.GUIChat:SetScreenOffset( Pos + Vector2( AbsolutePadding * 2, AbsolutePadding * 2 ) )
	end
	self.UpdateVanillaChatHistoryPos = UpdateVanillaChatHistoryPos

	UpdateVanillaChatHistoryPos( ChatBoxPos )

	-- Update our saved position on drag finish.
	function Border.OnDragFinished( Panel, Pos )
		self.Config.Pos.x = Pos.x
		self.Config.Pos.y = Pos.y

		UpdateVanillaChatHistoryPos( Pos )

		self:SaveConfig()
	end

	--Panel for messages.
	local Box = SGUI:Create( "Panel", Border )
	local ScrollbarPos = LayoutData.Positions.Scrollbar * WidthMult
	ScrollbarPos.x = Ceil( ScrollbarPos.x )
	Box:SetupFromTable{
		ScrollbarPos = ScrollbarPos,
		ScrollbarWidth = Ceil( 8 * WidthMult ),
		ScrollbarHeightOffset = 0,
		Scrollable = true,
		HorizontalScrollingEnabled = false,
		AllowSmoothScroll = self.Config.SmoothScroll,
		StickyScroll = true,
		Skin = Skin,
		StyleName = "MessageList",
		AutoHideScrollbar = true,
		Layout = SGUI.Layout:CreateLayout( "Vertical", {
			Elements = self.Messages,
			Padding = Padding
		} ),
		Fill = true,
		Margin = Spacing( 0, 0, 0, PaddingUnit )
	}
	Box.BufferAmount = PaddingUnit:GetValue()
	ChatBoxLayout:AddElement( Box )

	self.ChatBox = Box

	local SettingsButtonSize = LayoutData.Sizes.SettingsButton
	local TextEntryLayout = SGUI.Layout:CreateLayout( "Horizontal", {
		AutoSize = UnitVector( Percentage( 100 ), Scaled( SettingsButtonSize, ScalarScale ) ),
		Fill = false
	} )
	ChatBoxLayout:AddElement( TextEntryLayout )

	local Font = self:GetFont()

	--Where messages are entered.
	local TextEntry = SGUI:Create( "TextEntry", Border )
	TextEntry:SetupFromTable{
		BorderSize = Vector2( 0, 0 ),
		Text = "",
		StickyFocus = true,
		Skin = Skin,
		Font = Font,
		Fill = true,
		MaxLength = kMaxChatLength
	}
	if self.TextScale ~= 1 then
		TextEntry:SetTextScale( self.TextScale )
	end
	if Font == Fonts.kAgencyFB_Tiny then
		--For some reason, the tiny font is always 1 behind where it should be...
		TextEntry.Padding = 3
		TextEntry.CaretOffset = -1
		TextEntry:SetupCaret()
	end

	TextEntryLayout:AddElement( TextEntry )

	--Send the message when the client presses enter.
	function TextEntry:OnEnter()
		local Text = self:GetText()

		--Don't go sending blank messages.
		if #Text > 0 and Text:find( "[^%s]" ) then
			Shine.SendNetworkMessage( "ChatClient",
				BuildChatClientMessage( Plugin.TeamChat,
					StringUTF8Sub( Text, 1, kMaxChatLength ) ), true )
		end

		self:SetText( "" )
		self:ResetUndoState()

		Plugin:DestroyAutoCompletePanel()

		if Plugin.Config.AutoClose then
			Plugin:CloseChat()
		end
	end

	function TextEntry:OnEscape()
		Plugin:CloseChat()
		return true
	end

	--We don't want to allow characters after hitting the max length message.
	function TextEntry:ShouldAllowChar( Char )
		local Text = self:GetText()

		if self:IsAtMaxLength() then
			return false
		end

		--We also don't want the player's chat button bind making it into the text entry.
		if ( Plugin.OpenTime or 0 ) + 0.05 > Clock() then
			return false
		end
	end

	function TextEntry.OnUnhandledKey( TextEntry, Key, Down )
		if Down and ( Key == InputKey.Down or Key == InputKey.Up ) then
			self:ScrollAutoComplete( Key == InputKey.Down and 1 or -1 )
		end
	end

	function TextEntry.OnTextChanged( TextEntry, OldText, NewText )
		self:AutoCompleteCommand( NewText )
	end

	self:SetupAutoComplete( TextEntry )

	self.TextEntry = TextEntry

	local SettingsButton = SGUI:Create( "Button", Border )
	SettingsButton:SetupFromTable{
		Text = SGUI.Icons.Ionicons.GearB,
		Skin = Skin,
		Font = SGUI.Fonts.Ionicons,
		AutoSize = UnitVector( Scaled( SettingsButtonSize, ScalarScale ),
			Scaled( SettingsButtonSize, ScalarScale ) ),
		Margin = Spacing( PaddingUnit, 0, 0, 0 )
	}
	SettingsButton:SetTextScale( SGUI.LinearScaleByScreenHeight( Vector2( 1, 1 ) ) )

	function SettingsButton:DoClick()
		return Plugin:OpenSettings( Border, UIScale, ScalarScale )
	end

	SettingsButton:SetTooltip( self:GetPhrase( "SETTINGS_TOOLTIP" ) )

	TextEntryLayout:AddElement( SettingsButton )

	self.SettingsButton = SettingsButton

	Border:SetLayout( ChatBoxLayout )
	Border:InvalidateLayout( true )

	return true
end

do
	local LocationNames
	local function FindLocations()
		return Shine.Stream( EntityListToTable( Shared.GetEntitiesWithClassname( "Location" ) ) )
			:Map( function( Location ) return Location:GetName() end )
			:Distinct()
			:Sort()
			:AsTable()
	end

	local function GetLocations()
		if not LocationNames then
			LocationNames = FindLocations()
		end
		return LocationNames
	end

	function Plugin:SetupAutoComplete( TextEntry )
		local function GetPlayerNames()
			return Shine.Stream( EntityListToTable( Shared.GetEntitiesWithClassname( "PlayerInfoEntity" ) ) )
				:Map( function( PlayerInfo ) return PlayerInfo.playerName end )
				:AsTable()
		end

		-- Auto-complete location names and player names.
		local AutoCompleteHandler = TextEntry.StandardAutoComplete( function()
			return {
				-- Rank locations as higher priority to player names.
				GetLocations(),
				GetPlayerNames()
			}
		end )
		-- Also, replace "me" with the player's current location (as a priority match over other matches).
		AutoCompleteHandler:AddMatcherToStart( function( Context )
			if Context.Input == "me" then
				local LocationName = PlayerUI_GetLocationName()
				if not LocationName or LocationName == "" then return end

				Context:AddMatch( 1, 1, LocationName.." " )
			end
		end )

		TextEntry:SetAutoCompleteHandler( AutoCompleteHandler )
	end
end

do
	local unpack = unpack

	local function UpdateConfigValue( self, Key, Value )
		if self.Config[ Key ] == Value then return false end

		self.Config[ Key ] = Value
		self:SaveConfig()

		return true
	end

	local ElementCreators = {
		CheckBox = {
			Create = function( self, SettingsPanel, Layout, IsLastElement, Size, Checked, Label )
				local CheckBox = SettingsPanel:Add( "CheckBox" )
				CheckBox:SetupFromTable{
					AutoSize = Size,
					Font = self:GetFont()
				}
				if not IsLastElement then
					CheckBox:SetMargin( Spacing( 0, 0, 0, Scaled( 4, self.UIScale.y ) ) )
				end
				CheckBox:AddLabel( self:GetPhrase( Label ) )
				CheckBox:SetChecked( Checked, true )

				if self.TextScale ~= 1 then
					CheckBox:SetTextScale( self.TextScale )
				end

				Layout:AddElement( CheckBox )

				return CheckBox
			end,
			Setup = function( self, Object, Data )
				if IsType( Data.ConfigValue, "string" ) then
					Object.OnChecked = function( Object, Value )
						UpdateConfigValue( self, Data.ConfigValue, Value )
					end

					return
				end

				Object.OnChecked = function( Object, Value )
					Data.ConfigValue( self, Value )
				end
			end
		},
		Label = {
			Create = function( self, SettingsPanel, Layout, IsLastElement, Text )
				local Label = SettingsPanel:Add( "Label" )
				Label:SetupFromTable{
					Font = self:GetFont(),
					Text = self:GetPhrase( Text )
				}
				if not IsLastElement then
					Label:SetMargin( Spacing( 0, 0, 0, Scaled( 4, self.UIScale.y ) ) )
				end

				if self.TextScale ~= 1 then
					Label:SetTextScale( self.TextScale )
				end

				Layout:AddElement( Label )

				return Label
			end
		},
		Slider = {
			Create = function( self, SettingsPanel, Layout, IsLastElement, Size, Value )
				local Slider = SettingsPanel:Add( "Slider" )
				Slider:SetupFromTable{
					AutoSize = Size,
					Value = Value,
					Font = self:GetFont(),
					Padding = SliderTextPadding * self.ScalarScale,
				}
				if not IsLastElement then
					Slider:SetMargin( Spacing( 0, 0, 0, Scaled( 4, self.UIScale.y ) ) )
				end

				if self.TextScale ~= 1 then
					Slider:SetTextScale( self.TextScale )
				end

				Layout:AddElement( Slider )

				return Slider
			end,
			Setup = function( self, Object, Data, Size, Value )
				Object:SetBounds( unpack( Data.Bounds ) )
				if Data.Decimals then
					Object:SetDecimals( Data.Decimals )
				end
				Object:SetValue( Value )

				if Data.OnSlide then
					Object.OnSlide = Data.OnSlide
				end

				if IsType( Data.ConfigValue, "string" ) then
					Object.OnValueChanged = function( Object, Value )
						UpdateConfigValue( self, Data.ConfigValue, Value )
					end

					return
				end

				Object.OnValueChanged = function( Object, Value )
					Data.ConfigValue( self, Value )
				end
			end
		},
		Dropdown = {
			Create = function( self, SettingsPanel, Layout, IsLastElement, Size, Options, SelectedOption )
				local Dropdown = SettingsPanel:Add( "Dropdown" )
				Dropdown:SetupFromTable{
					AutoSize = Size,
					Options = Options,
					Font = self:GetFont()
				}
				Dropdown:SetSelectedOption( SelectedOption )
				if not IsLastElement then
					Dropdown:SetMargin( Spacing( 0, 0, 0, Scaled( 4, self.UIScale.y ) ) )
				end

				if self.TextScale ~= 1 then
					Dropdown:SetTextScale( self.TextScale )
				end

				Layout:AddElement( Dropdown )

				return Dropdown
			end,
			Setup = function( self, Object, Data )
				if IsType( Data.ConfigValue, "string" ) then
					Object:AddPropertyChangeListener( "SelectedOption", function( Option )
						UpdateConfigValue( self, Data.ConfigValue, Option.Value )
					end )
				else
					Object:AddPropertyChangeListener( "SelectedOption", function( Option )
						Data.ConfigValue( self, Option.Value )
					end )
				end
			end
		}
	}

	local SETTINGS_PADDING_AMOUNT = 5

	local function GetCheckBoxSize( self )
		return UnitVector( Scaled( 28, self.ScalarScale ), Scaled( 28, self.ScalarScale ) )
	end

	-- These use a fixed scaled size as Percentage units would end up resizing with the panel as it animates.
	local function GetSliderSize( self )
		return UnitVector( Scaled( 0.8 * LayoutData.Sizes.Settings.x, self.UIScale.x ), Scaled( 24, self.UIScale.y ) )
	end

	local function GetDropdownSize( self )
		return UnitVector(
			Scaled( LayoutData.Sizes.Settings.x - SETTINGS_PADDING_AMOUNT * 3, self.UIScale.x ),
			Scaled( 28, self.UIScale.y )
		)
	end

	local Elements = {
		{
			Type = "CheckBox",
			ConfigValue = "AutoClose",
			Values = function( self )
				return GetCheckBoxSize( self ), self.Config.AutoClose, "AUTO_CLOSE"
			end
		},
		{
			Type = "CheckBox",
			ConfigValue = "DeleteOnClose",
			Values = function( self )
				return GetCheckBoxSize( self ), self.Config.DeleteOnClose, "AUTO_DELETE"
			end
		},
		{
			Type = "CheckBox",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "SmoothScroll", Value ) then return end
				Plugin.ChatBox:SetAllowSmoothScroll( Value )
			end,
			Values = function( self )
				return GetCheckBoxSize( self ), self.Config.SmoothScroll, "SMOOTH_SCROLL"
			end
		},
		{
			Type = "CheckBox",
			ConfigValue = "ScrollToBottomOnOpen",
			Values = function( self )
				return GetCheckBoxSize( self ), self.Config.ScrollToBottomOnOpen, "SCROLL_TO_BOTTOM"
			end
		},
		{
			Type = "CheckBox",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "MoveVanillaChat", Value ) then return end

				if Value then
					self:MoveVanillaChat()
				else
					self:ResetVanillaChatPos()
				end
			end,
			Values = function( self )
				return GetCheckBoxSize( self ), self.Config.MoveVanillaChat, "MOVE_VANILLA_CHAT"
			end
		},
		{
			Type = "CheckBox",
			ConfigValue = "ShowTimestamps",
			Values = function( self )
				return GetCheckBoxSize( self ), self.Config.ShowTimestamps, "SHOW_TIMESTAMPS"
			end
		},
		{
			Type = "Label",
			Values = { "MESSAGE_MEMORY" }
		},
		{
			Type = "Slider",
			ConfigValue = "MessageMemory",
			Bounds = { 10, 100 },
			Values = function( self )
				return GetSliderSize( self ), self.Config.MessageMemory
			end
		},
		{
			Type = "Label",
			Values = { "OPACITY" }
		},
		{
			Type = "Slider",
			ConfigValue = function( self, Value )
				Value = Value * 0.01

				if not UpdateConfigValue( self, "Opacity", Value ) then return end

				UpdateOpacity( self, Value )
			end,
			OnSlide = function( Slider, Value )
				UpdateOpacity( Plugin, Value * 0.01 )
			end,
			Bounds = { 0, 100 },
			Values = function( self )
				return GetSliderSize( self ), self.Config.Opacity * 100
			end
		},
		{
			Type = "Label",
			Values = { "SCALE" }
		},
		{
			Type = "Slider",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "Scale", Value ) then return end
				-- Re-create it after a scale change.
				self:OnResolutionChanged()
			end,
			Bounds = { 0.75, 1.25 },
			Decimals = 2,
			Values = function( self )
				return GetSliderSize( self ), self.Config.Scale
			end
		},
		{
			Type = "Label",
			Values = { "FONT_SIZE_MODE" }
		},
		{
			ID = "FontSizeMode",
			Type = "Dropdown",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "FontSizeMode", Value ) then return end

				self:SetFontSizeMode( Value )
			end,
			Values = function( self )
				local Options = {}
				local SelectedOption
				for i = 1, #self.FontSizeMode do
					Options[ i ] = {
						Value = self.FontSizeMode[ i ],
						Text = self:GetPhrase( "FONT_SIZE_MODE_"..self.FontSizeMode[ i ] )
					}
					if self.Config.FontSizeMode == Options[ i ].Value then
						SelectedOption = Options[ i ]
					end
				end
				return GetDropdownSize( self ), Options, SelectedOption
			end
		},
		{
			ID = "FontSizeInPixels",
			Type = "Slider",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "FontSizeInPixels", Value ) then return end

				self:SetFontSizeInPixels( Value )
			end,
			Bounds = { 8, 64 },
			Decimals = 0,
			Values = function( self )
				return GetSliderSize( self ), self.Config.FontSizeInPixels
			end,
			Bindings = {
				{
					From = {
						Element = "FontSizeMode",
						Property = "SelectedOption"
					},
					To = {
						Property = "Enabled",
						Transformer = function( Option )
							return Option.Value == Plugin.FontSizeMode.FIXED
						end
					}
				}
			}
		}
	}

	function Plugin:CreateSettings( MainPanel, UIScale, ScalarScale )
		local PaddingAmountY = Scaled( SETTINGS_PADDING_AMOUNT, UIScale.y )
		local Padding = Spacing(
			Scaled( SETTINGS_PADDING_AMOUNT, UIScale.x ),
			PaddingAmountY,
			-- Right hand side needs double padding to mirror the padding correctly.
			Scaled( SETTINGS_PADDING_AMOUNT * 2, UIScale.x ),
			PaddingAmountY
		)

		local Layout = SGUI.Layout:CreateLayout( "Vertical", {
			Padding = Padding
		} )

		local SettingsPanel = SGUI:Create( "Panel", MainPanel )
		SettingsPanel:SetupFromTable{
			Anchor = "TopRight",
			Pos = VectorMultiply( LayoutData.Positions.Settings, UIScale ),
			Scrollable = true,
			ScrollbarHeightOffset = 0,
			ScrollbarWidth = 8 * UIScale.x,
			ScrollbarPos = Vector2( -8 * UIScale.x, 0 ),
			HorizontalScrollingEnabled = false,
			AutoHideScrollbar = true,
			Size = VectorMultiply( LayoutData.Sizes.SettingsClosed, UIScale ),
			Skin = Skin,
			StylingState = self.MainPanel:GetStylingState()
		}

		self.SettingsPanel = SettingsPanel

		local ElementsByID = {}
		for i = 1, #Elements do
			local Data = Elements[ i ]
			local Values = IsType( Data.Values, "table" ) and Data.Values or { Data.Values( self ) }

			local Creator = ElementCreators[ Data.Type ]

			local Object = Creator.Create( self, SettingsPanel, Layout, i == #Elements, unpack( Values ) )
			if Creator.Setup then
				Creator.Setup( self, Object, Data, unpack( Values ) )
			end

			if Data.ID then
				ElementsByID[ Data.ID ] = Object
			end
		end

		for i = 1, #Elements do
			local Data = Elements[ i ]
			local Bindings = Data.Bindings
			if Bindings then
				for j = 1, #Bindings do
					local Binding = Bindings[ j ]
					local FromElement = ElementsByID[ Binding.From.Element ]
					if FromElement then
						Binder():FromElement( FromElement, Binding.From.Property )
							:ToElement( ElementsByID[ Data.ID ], Binding.To.Property, Binding.To )
							:BindProperty()
					end
				end
			end
		end

		SettingsPanel:SetLayout( Layout )
	end
end

function Plugin:OpenSettings( MainPanel, UIScale, ScalarScale )
	if not SGUI.IsValid( self.SettingsPanel ) then
		self:CreateSettings( MainPanel, UIScale, ScalarScale )
	end

	local SettingsButton = self.SettingsButton
	if SettingsButton.Expanding then return false end

	SettingsButton.Expanding = true

	local SettingsPanel = self.SettingsPanel
	local Start, End, Expanded

	local SettingsPanelSize = SettingsPanel:GetSize()
	if not SettingsButton.Expanded then
		Start = Vector2( UIScale.x * LayoutData.Sizes.SettingsClosed.x, SettingsPanelSize.y )
		End = Vector2( UIScale.x * LayoutData.Sizes.Settings.x, SettingsPanelSize.y )
		Expanded = true

		SettingsPanel:SetIsVisible( true )
		SettingsButton:AddStylingState( "Open" )
	else
		Start = Vector2( UIScale.x * LayoutData.Sizes.Settings.x, SettingsPanelSize.y )
		End = Vector2( UIScale.x * LayoutData.Sizes.SettingsClosed.x, SettingsPanelSize.y )
		Expanded = false
	end

	SettingsPanel:SizeTo( SettingsPanel.Background, Start, End, 0, 0.25, function( Panel )
		SettingsButton.Expanded = Expanded

		if Expanded then
			SettingsButton:AddStylingState( "Open" )
		else
			SettingsButton:RemoveStylingState( "Open" )
			SettingsPanel:SetIsVisible( false )
		end

		SettingsButton.Expanding = false
	end )

	return true
end

function Plugin:OnResolutionChanged( OldX, OldY, NewX, NewY )
	if not SGUI.IsValid( self.MainPanel ) then return end

	local Messages = self.Messages
	local Recreate = {}

	for i = 1, #Messages do
		Recreate[ i ] = {
			Lines = Messages[ i ].Lines
		}
	end

	local SettingsWasExpanded = self.SettingsButton.Expanded

	-- Recreate the entire chat box, it's easier than rescaling.
	self.IgnoreRemove = true
	self.MainPanel:Destroy()
	self.IgnoreRemove = nil

	TableEmpty( Messages )

	if not self:CreateChatbox() then return end

	if not self.Visible then
		self.MainPanel:SetIsVisible( false )
	else
		self:CloseChat()
		self:StartChat( self.TeamChat )

		if SettingsWasExpanded then
			self.SettingsButton:DoClick()
		end
	end

	for i = 1, #Recreate do
		local Message = Recreate[ i ]
		self:AddMessageFromLines( Message.Lines )
	end
end

function Plugin:AddMessageFromPopulator( Populator, ... )
	if not SGUI.IsValid( self.MainPanel ) then
		self:CreateChatbox()

		if not self.Visible then
			self.MainPanel:SetIsVisible( false )
		end
	end

	local Messages = self.Messages
	local Scaled = SGUI.Layout.Units.Scaled
	local PrefixMargin = Scaled( 5, self.ScalarScale )
	local LineMargin = Scaled( 2, self.ScalarScale )

	local NextIndex = #Messages + 1
	local ReUse

	-- We've gone past the message memory limit.
	if NextIndex > self.Config.MessageMemory then
		local FirstMessage = Messages[ 1 ]
		self.ChatBox.Layout:RemoveElement( FirstMessage )

		ReUse = FirstMessage
	end

	local Font, Scale
	if self.Config.FontSizeMode == self.FontSizeMode.AUTO then
		Font, Scale = self:GetFont(), self.MessageTextScale
	else
		Font, Scale = self.ManualFont, self.ManualFontScale
	end

	local ChatLine = ReUse or self.ChatBox:Add( "ChatLine" )
	ChatLine:SetFontScale( Font, Scale )
	ChatLine:SetPreMargin( PrefixMargin )
	ChatLine:SetLineSpacing( LineMargin )

	Populator( ChatLine, ... )

	self.ChatBox.Layout:AddElement( ChatLine )

	if not self.Visible then return end

	self:RefreshLayout()
end

do
	local function AddMessageFromRichText( ChatLine, Contents, ShowTimestamps )
		ChatLine:SetContent( Contents, ShowTimestamps )
	end

	function Plugin:AddMessageFromRichText( MessageData )
		return self:AddMessageFromPopulator(
			AddMessageFromRichText, MessageData.Message, self.Config.ShowTimestamps
		)
	end
end

do
	local function AddMessageFromLines( ChatLine, Lines )
		ChatLine:RestoreFromLines( Lines )
	end

	function Plugin:AddMessageFromLines( Lines )
		return self:AddMessageFromPopulator( AddMessageFromLines, Lines )
	end
end

do
	local IntToColour

	local function AddSimpleChatMessage( ChatLine, ... )
		ChatLine:SetMessage( ... )
	end

	--[[
		Adds a message to the chatbox.

		Inputs are derived from the GUIChat inputs as we want to maintain compatability.

		Theoretically, we can make messages with any number of colours, but for now this will do.
	]]
	function Plugin:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName, TagData )
		--Don't add anything if one of the elements is the wrong type. Default chat will error instead.
		if not ( IsType( PlayerColour, "number" ) or IsType( PlayerColour, "cdata" ) )
		or not IsType( PlayerName, "string" ) or not IsType( MessageColour, "cdata" )
		or not IsType( MessageName, "string" ) then
			return
		end

		IntToColour = IntToColour or ColorIntToColor

		-- Why did they use int for the first colour, then colour object for the second?
		if IsType( PlayerColour, "number" ) then
			PlayerColour = IntToColour( PlayerColour )
		end

		self:AddMessageFromPopulator(
			AddSimpleChatMessage, TagData, PlayerColour, PlayerName, MessageColour, MessageName,
			self.Config.ShowTimestamps
		)
	end
end

function Plugin:RefreshLayout( ForceInstantScroll )
	if #self.Messages == 0 then return end

	-- Force layout refresh now so we can update the scrollbar.
	self.ChatBox:InvalidateLayout( true )

	if SGUI.IsValid( self.ChatBox.Scrollbar ) then
		local ChatLine = self.Messages[ #self.Messages ]
		local NewMaxHeight = ChatLine:GetPos().y + ChatLine:GetSize().y + self.ChatBox.BufferAmount
		if NewMaxHeight < self.ChatBox:GetMaxHeight() or ForceInstantScroll then
			self.ChatBox:SetMaxHeight( NewMaxHeight, ForceInstantScroll )
		end
	end
end

local MaxAutoCompleteResult = 3

--[[
	Scrolls the auto-complete suggestion up/down, setting the text in the text entry to
	the completed command. This does not trigger a new auto-complete request.
]]
function Plugin:ScrollAutoComplete( Amount )
	if not self.AutoCompleteResults then return end

	local Results = self.AutoCompleteResults
	if #Results == 0 then return end

	self.CurrentResult = ( self.CurrentResult or 0 ) + Amount
	if self.CurrentResult > Min( MaxAutoCompleteResult, #Results ) then
		self.CurrentResult = 1
	elseif self.CurrentResult < 1 then
		self.CurrentResult = #Results
	end

	local Text = StringFormat( "%s%s ", self.AutoCompleteLetter,
		Results[ self.CurrentResult ].ChatCommand )
	self.TextEntry:SetText( Text )
end

--[[
	Submits a request to the server for auto-completion of chat commands.

	If the current text is the same request as last time (i.e. typing past the first word),
	no request is sent.
]]
function Plugin:SubmitAutoCompleteRequest( Text )
	local FirstLetter = StringSub( Text, 1, 1 )
	self.AutoCompleteLetter = FirstLetter

	-- Cut the text down to just the first word.
	local FirstSpace = StringFind( Text, " " )
	local SearchText = StringSub( Text, 2, FirstSpace and ( FirstSpace - 1 ) or StringLen( Text ) )

	if self.LastSearch == SearchText then return end

	self.LastSearch = SearchText

	-- On receiving the results, add labels beneath the chatbox showing the completed command(s).
	Shine.AutoComplete.Request( SearchText, Shine.AutoComplete.CHAT_COMMAND, MaxAutoCompleteResult, function( Results )
		if not self.Visible then return end
		if not self:ShouldAutoComplete( self.TextEntry:GetText() ) then return end

		self.AutoCompleteResults = Results

		local ResultPanel = self.AutoCompletePanel
		if not ResultPanel then
			ResultPanel = SGUI:Create( "Panel", self.MainPanel )
			ResultPanel:SetIsSchemed( false )
			self.AutoCompletePanel = ResultPanel

			ResultPanel:SetAnchor( "BottomLeft" )

			local Padding = self.MainPanel.Layout:GetPadding()
			ResultPanel:SetColour( Colour( 0, 0, 0, 0.65 ) )
			ResultPanel:SetLayout( SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Padding
			} ) )
		end

		local Layout = ResultPanel.Layout
		local Elements = Layout.Elements

		local ResultPanelPadding = ResultPanel.Layout:GetComputedPadding()
		local XPadding = ResultPanelPadding[ 1 ] + ResultPanelPadding[ 3 ]
		local YPadding = ResultPanelPadding[ 2 ] + ResultPanelPadding[ 4 ]
		local Size = Vector2( self.MainPanel:GetSize().x, YPadding )

		for i = 1, Max( #Results, #Elements ) do
			local Label = Elements[ i ]
			if not Results[ i ] then
				if Label then
					Label:AlphaTo( nil, nil, 0, 0, 0.3, function()
						if not Label then return end

						Label:Destroy()
						Label = nil
						Elements[ i ] = nil
					end )
				end
			else
				local ShouldFade
				if not Label then
					ShouldFade = true
					Label = SGUI:Create( "ColourLabel", ResultPanel )
					Label:SetIsSchemed( false )
					Label:SetMargin( Spacing( 0, 0, 0, Scaled( 2, self.ScalarScale ) ) )
					Elements[ i ] = Label
				end

				local Result = Results[ i ]

				Label:SetFont( self:GetFont() )
				Label:SetTextScale( self.MessageTextScale )

				-- Completion of the form: !command <param> Help text.
				local TextContent = {
					Colours.ModeText, FirstLetter,
					Colours.AutoCompleteCommand, Result.ChatCommand.." "
				}
				if Result.Parameters ~= "" then
					TextContent[ #TextContent + 1 ] = Colours.AutoCompleteParams
					TextContent[ #TextContent + 1 ] = Result.Parameters.." "
				end

				TextContent[ #TextContent + 1 ] = Colours.ModeText
				TextContent[ #TextContent + 1 ] = Result.Description

				Label:SetText( TextContent )
				Label:InvalidateLayout( true )

				if ShouldFade then
					Label:AlphaTo( nil, 0, 1, 0, 0.3, nil, math.EaseIn )
				end

				local LabelSize = Label:GetSize()
				Size.x = Max( Size.x, LabelSize.x + XPadding )
				Size.y = Size.y + LabelSize.y
			end
		end

		if #Results == 0 then
			Size.x = 0
			Size.y = 0
		end

		ResultPanel:SetSize( Size )
		ResultPanel:InvalidateLayout( true )
	end )
end

function Plugin:DestroyAutoCompletePanel()
	if not self.AutoCompletePanel then return end

	if self.AutoCompleteTimer then
		self.AutoCompleteTimer:Destroy()
		self.AutoCompleteTimer = nil
	end

	if SGUI.IsValid( self.AutoCompletePanel ) then
		self.AutoCompletePanel:Destroy()
	end

	self.AutoCompletePanel = nil
	self.AutoCompleteResults = nil
	self.AutoCompleteLetter = nil
	self.LastSearch = nil
	self.CurrentResult = nil
end

function Plugin:ShouldAutoComplete( Text )
	return StringFind( Text, "^[!/]" ) and StringLen( Text ) > 1
end

function Plugin:AutoCompleteCommand( Text )
	-- Only auto-complete when the text starts with ! or /, and there's a command being typed.
	if not self:ShouldAutoComplete( Text ) then
		self:DestroyAutoCompletePanel()
		return
	end

	-- Keep debouncing the timer until the user stops typing to avoid spamming completion requests.
	self.AutoCompleteTimer = self.AutoCompleteTimer or self:SimpleTimer( 0.15, function()
		self.AutoCompleteTimer = nil
		self:SubmitAutoCompleteRequest( self.TextEntry:GetText() )
	end )
	self.AutoCompleteTimer:Debounce()
end

function Plugin:CloseChat( ForcePreserveText )
	if not SGUI.IsValid( self.MainPanel ) then return end

	self.MainPanel:SetIsVisible( false )
	self.GUIChat:SetIsVisible( true )

	SGUI:EnableMouse( false )

	if not ForcePreserveText and self.Config.DeleteOnClose then
		self.TextEntry:SetText( "" )
		self.TextEntry:ResetUndoState()
		self:DestroyAutoCompletePanel()
	end

	self.TextEntry:LoseFocus()

	self.Visible = false
end

-- Close and re-open the chatbox when logging in/out of a command structure to
-- avoid the mouse disappearing and/or elements getting stuck on the screen.
function Plugin:OnCommanderLogin()
	if not self.Visible then return end

	local WasTeamChat = self.TeamChat

	-- Ensure existing text entry state is preserved.
	self:CloseChat( true )

	self:SimpleTimer( 0, function()
		-- Wait a frame to allow the commander mouse to be pushed/popped first.
		self:StartChat( WasTeamChat )
	end )
end

Plugin.OnCommanderLogout = Plugin.OnCommanderLogin

do
	local TeamStates = {
		[ kMarineTeamType ] = "Team1",
		[ kAlienTeamType ] = "Team2",
		[ kNeutralTeamType ] = "NeutralTeam"
	}

	--[[
		Opens the chatbox, and creates it first if it's not created yet.
	]]
	function Plugin:StartChat( Team )
		if MainMenu_GetIsOpened and MainMenu_GetIsOpened() then return true end
		if not self.GUIChat then return end

		self.TeamChat = Team

		if not SGUI.IsValid( self.MainPanel ) then
			if not self:CreateChatbox() then
				return
			end
		end

		local StyleState
		if Team then
			-- Change the background colour for team chat to make it more obvious
			-- which mode the chatbox is currently in.
			StyleState = TeamStates[ PlayerUI_GetTeamType() ]
		end

		self.MainPanel:SetStylingState( StyleState )
		if SGUI.IsValid( self.SettingsPanel ) then
			self.SettingsPanel:SetStylingState( StyleState )
		end

		self.TextEntry:SetPlaceholderText( self.TeamChat and self:GetPhrase( "SAY_TEAM" ) or self:GetPhrase( "SAY_ALL" ) )

		SGUI:EnableMouse( true )

		self.MainPanel:SetIsVisible( true )
		self.GUIChat:SetIsVisible( false )

		self:RefreshLayout( true )

		if self.Config.ScrollToBottomOnOpen then
			self.ChatBox:ScrollToBottom( false )
		end

		-- Get our text entry accepting input.
		self.TextEntry:RequestFocus()
		self.Visible = true

		-- Set this so we don't accept text input straight away, avoids the bind button making it in.
		self.OpenTime = Clock()

		return true
	end
end

--[[
	When the plugin is disabled, we need to cleanup the chatbox itself
	and empty out the messages table.
]]
function Plugin:Cleanup()
	Hook.Remove( "PlayerKeyPress", self )

	if not SGUI.IsValid( self.MainPanel ) then return end

	self.IgnoreRemove = true
	self.MainPanel:Destroy()
	self.IgnoreRemove = nil

	--Clear out everything.
	self.MainPanel = nil
	self.ChatBox = nil
	self.TextEntry = nil
	self.SettingsPanel = nil

	TableEmpty( self.Messages )

	if self.Visible then
		SGUI:EnableMouse( false )
		self.Visible = false
		self.GUIChat:SetIsVisible( true )
	end
end

--Enables this plugin and sets it to auto load.
local EnableCommand = Shine:RegisterClientCommand( "sh_chatbox", function( Enable )
	if Enable then
		Shine:EnableExtension( "chatbox" )
		Shine:SetPluginAutoLoad( "chatbox", true )

		Shared.Message( "[Shine] Chatbox enabled. The chatbox will now autoload on any server running Shine." )
	else
		Shine:UnloadExtension( "chatbox" )
		Shine:SetPluginAutoLoad( "chatbox", false )

		Shared.Message( "[Shine] Chatbox disabled. The chatbox will no longer autoload." )
	end
end )
EnableCommand:AddParam{ Type = "boolean", Optional = true,
	Default = function() return not Plugin.Enabled end }

Shine.Hook.Add( "OnMapLoad", "NotifyAboutChatBox", function()
	Shine.AddStartupMessage( "Shine has a chatbox that you can enable/disable by entering \"sh_chatbox\" into the "..
		"console or using the config menu." )
end )

return Plugin
