--[[
	Shine chatbox.

	I can't believe the game doesn't have one.
]]

local Binder = require "shine/lib/gui/binding/binder"
local ChatAPI = require "shine/core/shared/chat/chat_api"
local TextElement = require "shine/lib/gui/richtext/elements/text"

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
local StringContainsNonUTF8Whitespace = string.ContainsNonUTF8Whitespace
local StringExplode = string.Explode
local StringFind = string.find
local StringFormat = string.format
local StringGSub = string.gsub
local StringMatch = string.match
local StringStartsWith = string.StartsWith
local StringSub = string.sub
local StringUTF8Length = string.UTF8Length
local StringUTF8Sub = string.UTF8Sub
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableRemove = table.remove
local TableRemoveByValue = table.RemoveByValue
local TableShallowMerge = table.ShallowMerge
local TableSlice = table.Slice
local type = type

local Plugin = Shine.Plugin( ... )

Plugin.HasConfig = true
Plugin.ConfigName = "ChatBox.json"

Plugin.Version = "1.1"

Plugin.FontSizeMode = table.AsEnum{
	"AUTO", "FIXED"
}

Plugin.DefaultConfig = {
	AutoCompleteEmoji = true, -- Should the emoji auto-completion popup be displayed?
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

function Plugin:PostGUIChatInitialised( GUIChat )
	self.GUIChat = GUIChat

	if self.Config.MoveVanillaChat then
		self:MoveVanillaChat()
	end
end

function Plugin:OnGUIChatOffsetChanged( GUIChat )
	if self.GUIChat ~= GUIChat or not self.Config.MoveVanillaChat then return end

	self:MoveVanillaChat()
end

function Plugin:OnChatMessageDisplayed( PlayerColour, PlayerName, MessageColour, MessageName, TagData )
	self:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName, TagData )
end

function Plugin:OnRichTextChatMessageDisplayed( MessageData )
	self:AddMessageFromRichText( MessageData )
end

local Units = SGUI.Layout.Units

local Percentage = Units.Percentage
local UnitVector = Units.UnitVector
local function Scaled( Value, Scale )
	return Units.Integer( Units.Scaled( Value, Scale ) )
end
local Spacing = Units.Spacing

local Colours = {
	Background = Colour( 0.6, 0.6, 0.6, 0.4 ),
	Team1Background = Colour( 104 / 255, 191 / 255, 1, 0.4 ),
	Team2Background = Colour( 0.8, 0.5, 0.1, 0.4 ),
	NeutralTeamBackground = Colour( 1, 1, 1, 0.4 ),

	Dark = Colour( 0.2, 0.2, 0.2, 0.8 ),
	Highlight = Colour( 0.5, 0.5, 0.5, 0.8 ),
	ModeText = Colour( 1, 1, 1, 1 ),
	TextShadow = Colour( 0, 0, 0, 0.8 ),
	AutoCompleteCommand = Colour( 1, 0.8, 0 ),
	AutoCompleteParams = Colour( 1, 0.5, 0 ),
	AutoCompleteArg = Colour( 0, 0.75, 1 ),

	Clear = Colour( 0, 0, 0, 0 )
}

local Skin = {
	Button = {
		Default = {
			ActiveCol = Colours.Highlight,
			InactiveCol = Colours.Dark,
			TextColour = Colours.ModeText,
			IconShadow = false,
			TextShadow = false,
			States = {
				Open = {
					InactiveCol = Colours.Highlight
				}
			}
		},
		SettingsButton = {
			ActiveCol = SGUI.ColourWithAlpha( Colours.Highlight, 1 ),
			InactiveCol = SGUI.ColourWithAlpha( Colours.Dark, 1 ),
			TextColour = Colours.ModeText,
			IconShadow = false,
			TextShadow = false
		},
		EmojiButton = {
			ActiveCol = Colours.Dark,
			InactiveCol = Colours.Highlight
		}
	},
	CheckBoxWithLabel = {
		Default = {
			TextShadow = {
				Colour = Colours.TextShadow
			}
		}
	},
	Dropdown = {
		Default = {
			IconAutoFont = {
				Family = SGUI.FontFamilies.Ionicons,
				Size = Units.GUIScaled( 32 )
			},
			Padding = Units.Spacing( Units.GUIScaled( 4 ), 0, Units.GUIScaled( 4 ), 0 )
		}
	},
	Label = {
		Default = {
			Shadow = {
				Colour = Colours.TextShadow
			},
			States = {
				AllChat = {
					Colour = Colours.ModeText,
					Text = SGUI.Icons.Ionicons.Chatbubble
				},
				Team1 = {
					Colour = SGUI.ColourWithAlpha( Colours.Team1Background, 1 ),
					Text = SGUI.Icons.Ionicons.AndroidPeople
				},
				Team2 = {
					Colour = SGUI.ColourWithAlpha( Colours.Team2Background, 1 ),
					Text = SGUI.Icons.Ionicons.AndroidPeople
				},
				NeutralTeam = {
					Colour = Colours.ModeText,
					Text = SGUI.Icons.Ionicons.AndroidPeople
				}
			}
		},
		EmojiCategoryHeader = {
			Shadow = false
		}
	},
	EmojiAutoComplete = {
		Default = {
			Colour = SGUI.ColourWithAlpha( Colours.Dark, 1 )
		}
	},
	EmojiAutoCompleteEntry = {
		Default = {
			ActiveCol = SGUI.ColourWithAlpha( Colours.Highlight, 1 ),
			InactiveCol = SGUI.ColourWithAlpha( Colours.Dark, 1 ),
			TextColour = Colours.ModeText,
			AutoFont = {
				Family = "kAgencyFB",
				Size = Units.GUIScaled( 27 )
			}
		}
	},
	EmojiPicker = {
		Default = {
			Colour = SGUI.ColourWithAlpha( Colours.Highlight, 1 )
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
	Row = {
		TextEntryIconBackground = {
			Colour = Colours.Dark
		}
	},
	Slider = {
		Default = {
			TextShadow = {
				Colour = Colours.TextShadow
			}
		}
	},
	TabPanel = {
		Default = {
			TabBackgroundColour = Colours.Clear,
			PanelColour = Colours.Clear,
			Colour = Colours.Clear
		},
		Horizontal = {
			TabBackgroundColour = Colours.Clear,
			PanelColour = Colours.Clear,
			Colour = Colours.Clear
		}
	},
	TabPanelButton = {
		Default = {
			ActiveCol = Colours.Clear,
			InactiveCol = Colours.Dark,
			TextColour = SGUI.ColourWithAlpha( Colours.ModeText, 0.75 ),
			TextInheritsParentAlpha = false,
			States = {
				Selected = {
					TextColour = Colours.ModeText
				},
				Highlighted = {
					TextColour = Colours.ModeText
				}
			}
		},
		Horizontal = {
			ActiveCol = Colours.Clear,
			InactiveCol = Colours.Dark,
			TextColour = SGUI.ColourWithAlpha( Colours.ModeText, 0.75 ),
			TextInheritsParentAlpha = false,
			States = {
				Selected = {
					TextColour = Colours.ModeText
				},
				Highlighted = {
					TextColour = Colours.ModeText
				}
			}
		}
	},
	TextEntry = {
		Default = {
			FocusColour = Colours.Clear,
			DarkColour = Colours.Clear,
			BorderColour = Colours.Dark,
			BorderSize = Vector2( 0, 0 ),
			TextColour = Colour( 1, 1, 1, 1 ),
			PlaceholderTextColour = Colour( 1, 1, 1, 0.5 ),
			BorderRadii = false
		}
	}
}

function Plugin:OnFirstThink()
	-- Copy over default skin values to ensure they are applied regardless of the chosen
	-- default skin.
	local DefaultSkin = SGUI.SkinManager:GetSkinsByName().Default
	TableShallowMerge( DefaultSkin, Skin )

	TableShallowMerge( DefaultSkin.TextEntry, Skin.TextEntry )

	Skin.TextEntry.Default.HighlightColour = DefaultSkin.TextEntry.Default.HighlightColour
	Skin.RichTextEntry = {
		Default = Skin.TextEntry.Default
	}

	TableShallowMerge( DefaultSkin.Button, Skin.Button )

	Skin.TextEntry.EmojiPickerSearch = DefaultSkin.TextEntry.Default

	TableShallowMerge( DefaultSkin.CheckBox, Skin.CheckBox )
	TableShallowMerge( DefaultSkin.CheckBox.Default, Skin.CheckBox.Default )

	TableShallowMerge( DefaultSkin.Dropdown.Default, Skin.Dropdown.Default )

	TableShallowMerge( DefaultSkin.Label, Skin.Label )
	TableShallowMerge( DefaultSkin.Label.Default, Skin.Label.Default )

	TableShallowMerge( DefaultSkin.Slider, Skin.Slider )
	TableShallowMerge( DefaultSkin.Slider.Default, Skin.Slider.Default )
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
	return Vector2( Ceil( Vec1.x * Vec2.x ), Ceil( Vec1.y * Vec2.y ) )
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
	"TextEntryIconBackground",
	"SettingsButton",
	"SettingsPanel",
	"SettingsPanelTabs"
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
			Control:RefreshStyling()
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

	if SGUI.IsValid( self.ChatBox ) then
		self.ChatBox:InvalidateLayout( true )
	end
end

local EmojiAutoComplete = require "shine/extensions/chatbox/ui/emoji_autocomplete"
local EmojiPicker = require "shine/extensions/chatbox/ui/emoji_picker"

--[[
	Creates the chatbox UI elements.

	Essentially,
		1. An outer panel to contain everything.
		2. A smaller panel to contain the chat messages, scrollable.
		3. A text entry for entering chat messages (with placeholder text indicating team/all mode).
		4. A settings button that opens up the chatbox settings.
]]
function Plugin:CreateChatbox()
	local UIScale = SGUI.LinearScale( Vector( 1, 1, 1 ) ) * self.Config.Scale
	local ScalarScale = SGUI.LinearScale( 1 ) * self.Config.Scale

	local ScreenWidth, ScreenHeight = SGUI.GetScreenSize()
	ScreenWidth = ScreenWidth * self.Config.Scale
	ScreenHeight = ScreenHeight * self.Config.Scale

	local FourToThreeHeight = ( ScreenWidth / 4 ) * 3
	-- Use a more boxy box for 4:3 monitors.
	if FourToThreeHeight == ScreenHeight then
		local WidthMult = 0.72
		UIScale.x = UIScale.x * WidthMult
		ScalarScale = ScalarScale * ( WidthMult + 1 ) * 0.5
	end

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
	-- Keep the default position fixed as the GUIChat position can move depending on the team.
	local DefaultPos = SGUI.LinearScale( Vector2( 100, -430 ) ) - Vector2( 0, 100 * UIScale.y )

	if not Pos.x or not Pos.y then
		ChatBoxPos = DefaultPos
	else
		ChatBoxPos = Vector( Pos.x, Pos.y, 0 )
	end

	ChatBoxPos.x = Clamp( ChatBoxPos.x, 0, ScreenWidth - PanelSize.x )
	ChatBoxPos.y = Clamp( ChatBoxPos.y, -ScreenHeight + PanelSize.y, -PanelSize.y )

	local Border = SGUI:Create( "Panel" )
	Border:SetupFromTable{
		DebugName = "ChatBoxWindow",
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

	function Border.GetMouseBounds( Border )
		local Size = Border:GetSize()
		if SGUI.IsValid( self.SettingsPanel ) and self.SettingsPanel:GetIsVisible() then
			-- If the settings is visible, the mouse bounds need to include it (as it's outside the window bounds).
			Size.x = Size.x + self.SettingsPanel:GetSize().x
			return Size
		end
		return Size
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

	-- Panel for messages.
	local Box = SGUI:Create( "Panel", Border )
	local ScrollbarPos = LayoutData.Positions.Scrollbar * UIScale.x
	ScrollbarPos.x = Ceil( ScrollbarPos.x )
	Box:SetupFromTable{
		DebugName = "ChatBoxContainer",
		ScrollbarPos = ScrollbarPos,
		ScrollbarWidth = Ceil( 8 * UIScale.x ),
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

	local EmojiAutoCompletePattern = ":([^:%s]-)$"
	local function InsertEmojiFromCompletion( EmojiName )
		local CaretPos = self.TextEntry:GetCaretPos()
		local TextBehindCaret = self.TextEntry:GetTextBetween( 1, CaretPos )

		local EmojiMatch = StringMatch( TextBehindCaret, EmojiAutoCompletePattern )
		if not EmojiMatch or not StringStartsWith( EmojiName, EmojiMatch ) then return end

		local TextToInsert = StringSub( EmojiName, #EmojiMatch + 1 )..":"

		-- Avoid inserting a second space if there's one in front of the caret already.
		local TextAfterCaret = self.TextEntry:GetTextBetween( CaretPos + 1, CaretPos + 1 )
		if StringSub( TextAfterCaret, 1, 1 ) ~= " " then
			TextToInsert = TextToInsert.." "
		end

		self.TextEntry:InsertTextAtCaret( TextToInsert )

		Hook.Broadcast( "OnChatBoxEmojiSelected", self, EmojiName )
	end

	do
		local AutoCompleteSize = Units.Integer( Units.GUIScaled( 40 ) )
		local PaddingSize = Units.Integer( Units.GUIScaled( 4 ) )

		local EmojiAutoCompletePanel = SGUI:Create( EmojiAutoComplete, Box )
		EmojiAutoCompletePanel:SetupFromTable{
			PositionType = SGUI.PositionType.ABSOLUTE,
			TopOffset = Units.Percentage.ONE_HUNDRED - AutoCompleteSize,
			AutoSize = Units.UnitVector( Units.Percentage.ONE_HUNDRED, AutoCompleteSize ),
			IsVisible = false,
			Padding = Units.Spacing( PaddingSize, 0, PaddingSize, 0 )
		}
		EmojiAutoCompletePanel:AddPropertyChangeListener( "SelectedEmojiName", function( Panel, EmojiName )
			if not EmojiName then return end

			Panel:SetIsVisible( false )

			InsertEmojiFromCompletion( EmojiName )
		end )

		self.EmojiAutoComplete = EmojiAutoCompletePanel
	end

	self.ChatBox = Box

	local SettingsButtonSize = LayoutData.Sizes.SettingsButton
	local TextEntryRowHeight = Scaled( SettingsButtonSize, ScalarScale )
	local TextEntryLayout = SGUI.Layout:CreateLayout( "Horizontal", {
		AutoSize = UnitVector( Percentage.ONE_HUNDRED, TextEntryRowHeight ),
		Fill = false
	} )
	ChatBoxLayout:AddElement( TextEntryLayout )

	local Font = self:GetFont()
	local IconFont, IconScale = SGUI.FontManager.GetFontForAbsoluteSize(
		SGUI.FontFamilies.Ionicons,
		Scaled( 32, self.UIScale.y ):GetValue()
	)

	do
		local Elements = SGUI:BuildTree( {
			Parent = Border,
			{
				ID = "TextEntryIconBackground",
				Class = "Row",
				Props = {
					DebugName = "ChatBoxTextEntryIconBackground",
					AutoSize = UnitVector(
						TextEntryRowHeight + PaddingUnit,
						Percentage.ONE_HUNDRED
					),
					Padding = Spacing( 0, 0, PaddingUnit, 0 ),
					StyleName = "TextEntryIconBackground"
				},
				Children = {
					{
						ID = "TextEntryIcon",
						Class = "Label",
						Props = {
							DebugName = "ChatBoxTextEntryIcon",
							Text = SGUI.Icons.Ionicons.Speakerphone,
							Font = IconFont,
							TextScale = IconScale,
							TextInheritsParentAlpha = false,
							Alignment = SGUI.LayoutAlignment.CENTRE,
							CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE
						}
					}
				}
			}
		} )

		TextEntryLayout:AddElement( Elements.TextEntryIconBackground )

		self.TextEntryIconBackground = Elements.TextEntryIconBackground
		self.TextEntryIcon = Elements.TextEntryIcon
	end

	-- Where messages are entered.
	local TextEntry = SGUI:Create( "RichTextEntry", Border )
	TextEntry:SetupFromTable{
		DebugName = "ChatBoxTextEntry",
		Text = "",
		StickyFocus = true,
		Skin = Skin,
		Font = Font,
		Fill = true,
		MaxLength = kMaxChatLength,
		TextParser = function( Text )
			local ParsedText = Hook.Call( "ParseChatBoxText", self, Text )
			if IsType( ParsedText, "table" ) then return ParsedText end

			return { TextElement( Text ) }
		end
	}
	if self.TextScale ~= 1 then
		TextEntry:SetTextScale( self.TextScale )
	end

	TextEntryLayout:AddElement( TextEntry )

	-- Send the message when the client presses enter.
	function TextEntry:OnEnter()
		local Text = self:GetText()
		if SGUI.IsValid( Plugin.EmojiAutoComplete ) and Plugin.EmojiAutoComplete:GetIsVisible() then
			local EmojiName = Plugin.EmojiAutoComplete:ResolveSelectedEmojiName()
			if EmojiName then
				InsertEmojiFromCompletion( EmojiName )
			end

			Plugin.EmojiAutoComplete:SetIsVisible( false )

			return
		end

		-- Don't go sending blank messages.
		if #Text > 0 and StringContainsNonUTF8Whitespace( Text ) then
			Shine.SendNetworkMessage(
				"ChatClient",
				BuildChatClientMessage( Plugin.TeamChat, StringUTF8Sub( Text, 1, kMaxChatLength ) ),
				true
			)
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

	-- We don't want to allow characters after hitting the max length message.
	function TextEntry:ShouldAllowChar( Char )
		local Text = self:GetText()

		if self:IsAtMaxLength() then
			return false
		end

		-- We also don't want the player's chat button bind making it into the text entry.
		if ( Plugin.OpenTime or 0 ) + 0.05 > Clock() then
			return false
		end
	end

	local OldOnTab = TextEntry.OnTab
	function TextEntry.OnTab( TextEntry )
		if SGUI.IsValid( self.EmojiAutoComplete ) and self.EmojiAutoComplete:GetIsVisible() then
			self.EmojiAutoComplete:MoveSelection( SGUI:IsShiftDown() and -1 or 1 )
			return
		end

		return OldOnTab( TextEntry )
	end

	function TextEntry.OnUnhandledKey( TextEntry, Key, Down )
		if Down and ( Key == InputKey.Down or Key == InputKey.Up ) then
			self:ScrollAutoComplete( Key == InputKey.Down and 1 or -1 )
		end
	end

	local function UpdateEmojiAutoComplete( TextEntry )
		if not SGUI.IsValid( self.EmojiAutoComplete ) then return end

		if not self.Config.AutoCompleteEmoji then
			self.EmojiAutoComplete:SetIsVisible( false )
			return
		end

		local TextBehindCaret = TextEntry:GetTextBetween( 1, TextEntry:GetCaretPos() )
		local Emoji = StringMatch( TextBehindCaret, EmojiAutoCompletePattern )
		if not Emoji or #Emoji < 2 then
			self.EmojiAutoComplete:SetIsVisible( false )
			return
		end

		local Results = Hook.Call( "OnChatBoxEmojiAutoComplete", self, Emoji )
		if not IsType( Results, "table" ) or #Results == 0 then
			self.EmojiAutoComplete:SetIsVisible( false )
			return
		end

		self.EmojiAutoComplete:SetIsVisible( true )
		self.EmojiAutoComplete:SetEmoji( TableSlice( Results, 1, 5 ) )
		self.EmojiAutoComplete:SetSelectedIndex( 1 )
		self.EmojiAutoComplete:SetSelectedEmojiName( nil )
	end

	self.UpdateEmojiAutoComplete = UpdateEmojiAutoComplete

	-- Watch all text changes for emoji auto-complete to ensure it's hidden if the text is wiped.
	TextEntry:AddPropertyChangeListener( "Text", UpdateEmojiAutoComplete )

	function TextEntry.OnTextChanged( TextEntry, OldText, NewText )
		self:AutoCompleteCommand( NewText )
	end

	self:SetupAutoComplete( TextEntry )

	self.TextEntry = TextEntry

	do
		local EmojiButton = SGUI:Create( "Button", Border )
		EmojiButton:SetupFromTable{
			DebugName = "ChatBoxEmojiButton",
			Text = SGUI.Icons.Ionicons.HappyOutline,
			Skin = Skin,
			Font = IconFont,
			AutoSize = UnitVector(
				TextEntryRowHeight,
				Percentage.ONE_HUNDRED
			),
			Margin = Spacing( PaddingUnit, 0, 0, 0 ),
			TextInheritsParentAlpha = false,
			Tooltip = self:GetPhrase( "EMOJI_PICKER_TOOLTIP" ),
			IsVisible = false
		}
		EmojiButton:SetTextScale( IconScale )
		TextEntryLayout:AddElement( EmojiButton )

		self.EmojiButton = EmojiButton

		local function OnEmojiPicked( Picker, EmojiName )
			if not EmojiName then return end

			local FormatString = ":%s:"
			local TextAfterCaret = self.TextEntry:GetTextBetween( self.TextEntry:GetCaretPos() + 1 )
			if StringSub( TextAfterCaret, 1, 1 ) ~= " " then
				FormatString = ":%s: "
			end

			self.TextEntry:InsertTextAtCaret( StringFormat( FormatString, EmojiName ), {
				-- Only insert full emoji, if there's no more room, don't insert anything.
				SkipIfAnyCharBlocked = true
			} )

			Hook.Broadcast( "OnChatBoxEmojiSelected", self, EmojiName )
		end

		local RemovalFrameNumber
		local function OnPickerRemoved()
			RemovalFrameNumber = SGUI.FrameNumber()

			self.TextEntry:RequestFocus()

			if not SGUI.IsValid( EmojiButton ) then return end

			EmojiButton:RemoveStylingState( "Open" )
		end

		self.OpenEmojiPicker = function( self, SkipAnim )
			if SGUI.IsValid( self.EmojiPicker ) then return end

			local EmojiList = Hook.Call( "OnChatBoxEmojiPickerOpen", self )
			if not IsType( EmojiList, "table" ) or #EmojiList == 0 then return end

			EmojiButton:AddStylingState( "Open" )

			local Picker = SGUI:Create( EmojiPicker )
			Picker:SetPadding( Spacing.Uniform( Units.GUIScaled( 4 ) ) )

			local PickerSize = Vector2(
				Units.GUIScaled( 8 + 48 * 6 ):GetValue(),
				Units.GUIScaled( 8 + 48 * 6 + 4 + 32 ):GetValue()
			)
			Picker:SetSize( PickerSize )

			local ScreenWidth, ScreenHeight = SGUI.GetScreenSize()
			local Pos = EmojiButton:GetScreenPos() + Vector2( EmojiButton:GetSize().x, 0 )
			if Pos.x + PickerSize.x > ScreenWidth then
				Pos.x = ScreenWidth - PickerSize.x
			end
			if Pos.y + PickerSize.y > ScreenHeight then
				Pos.y = ScreenHeight - PickerSize.y
			end
			Picker:SetPos( Pos )
			Picker:SetSkin( Skin )
			Picker:InvalidateLayout( true )
			Picker:SetSearchPlaceholderText( self:GetPhrase( "EMOJI_SEARCH_PLACEHOLDER_TEXT" ) )
			Picker:SetEmojiList( EmojiList )
			Picker.Elements.SearchInput:RequestFocus()
			Picker:CallOnRemove( OnPickerRemoved )

			if not SkipAnim then
				Picker:ApplyTransition( {
					Type = "Move",
					StartValue = Pos - Vector2( EmojiButton:GetSize().x, 0 ),
					EndValue = Pos,
					Duration = 0.15
				} )
				Picker:ApplyTransition( {
					Type = "AlphaMultiplier",
					StartValue = 0,
					EndValue = 1,
					Duration = 0.15
				} )
			end

			Picker.OnEmojiSelected = OnEmojiPicked

			self.EmojiPicker = Picker
		end

		function EmojiButton.DoClick()
			-- Don't re-open if the button was the cause of the old picker's removal.
			if RemovalFrameNumber == EmojiButton:GetLastMouseDownFrameNumber() then return end

			self:OpenEmojiPicker()
		end
	end

	local SettingsButton = SGUI:Create( "Button", Border )
	SettingsButton:SetupFromTable{
		DebugName = "ChatBoxSettingsButton",
		Text = SGUI.Icons.Ionicons.GearB,
		Skin = Skin,
		Font = IconFont,
		AutoSize = UnitVector(
			TextEntryRowHeight,
			Percentage.ONE_HUNDRED
		),
		Margin = Spacing( PaddingUnit, 0, 0, 0 ),
		TextInheritsParentAlpha = false
	}
	SettingsButton:SetTextScale( IconScale )

	function SettingsButton:DoClick()
		return Plugin:OpenSettings( Border, UIScale, ScalarScale )
	end

	SettingsButton:SetTooltip( self:GetPhrase( "SETTINGS_TOOLTIP" ) )

	TextEntryLayout:AddElement( SettingsButton )

	self.SettingsButton = SettingsButton

	Border:SetLayout( ChatBoxLayout )
	Border:InvalidateLayout( true )
	Border:InvalidateMouseState( true )

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

	local SETTINGS_PADDING_AMOUNT = 5
	local function GetPaddingOffset( self )
		-- This is summed in this manner to match the rounding applied to the two padding values used on the panel.
		-- Using just one scaled unit here wouldn't necessarily match, as each padding direction is rounded separately.
		return Scaled( SETTINGS_PADDING_AMOUNT, self.UIScale.x ) + Scaled( SETTINGS_PADDING_AMOUNT * 4, self.UIScale.x )
	end

	local function GetCheckBoxSize( self )
		return UnitVector( Scaled( 28, self.ScalarScale ), Scaled( 28, self.ScalarScale ) )
	end

	-- These use a fixed scaled size as Percentage units would end up resizing with the panel as it animates.
	local function GetSliderSize( self )
		return UnitVector( Scaled( 0.8 * LayoutData.Sizes.Settings.x, self.UIScale.x ), Scaled( 24, self.UIScale.y ) )
	end

	local function GetDropdownSize( self )
		return UnitVector(
			Scaled( LayoutData.Sizes.Settings.x, self.UIScale.x ) - GetPaddingOffset( self ),
			Scaled( 28, self.UIScale.y )
		)
	end

	local function GetButtonSize( self )
		return UnitVector(
			Scaled( LayoutData.Sizes.Settings.x, self.UIScale.x ) - GetPaddingOffset( self ),
			Scaled( 32, self.UIScale.y )
		)
	end

	local ElementCreators = {
		CheckBox = {
			Create = function( self, SettingsPanel, Layout, Checked, Label )
				local CheckBox = SettingsPanel:Add( "CheckBoxWithLabel" )
				CheckBox:SetupFromTable{
					CheckBoxAutoSize = GetCheckBoxSize( self ),
					AutoSize = GetDropdownSize( self ),
					Font = self:GetFont(),
					AutoEllipsis = true
				}
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
			end,
			Update = function( Object, Value )
				Object:SetChecked( not not Value )
			end
		},
		Label = {
			Create = function( self, SettingsPanel, Layout, Text )
				local Label = SettingsPanel:Add( "Label" )
				Label:SetupFromTable{
					Font = self:GetFont(),
					Text = self:GetPhrase( Text )
				}

				if self.TextScale ~= 1 then
					Label:SetTextScale( self.TextScale )
				end

				Layout:AddElement( Label )

				return Label
			end
		},
		Slider = {
			Create = function( self, SettingsPanel, Layout, Value )
				local Slider = SettingsPanel:Add( "Slider" )
				Slider:SetupFromTable{
					AutoSize = GetSliderSize( self ),
					Value = Value,
					Font = self:GetFont(),
					Padding = SliderTextPadding * self.ScalarScale,
					HandleWidth = 10 * self.ScalarScale
				}

				if self.TextScale ~= 1 then
					Slider:SetTextScale( self.TextScale )
				end

				Layout:AddElement( Slider )

				return Slider
			end,
			Setup = function( self, Object, Data, Value )
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
			end,
			Update = function( Object, Value )
				Object:SetValue( Value, true )
			end
		},
		Dropdown = {
			Create = function( self, SettingsPanel, Layout, Options, SelectedOption )
				local Dropdown = SettingsPanel:Add( "Dropdown" )
				Dropdown:SetupFromTable{
					AutoSize = GetDropdownSize( self ),
					Options = Options,
					Font = self:GetFont()
				}
				Dropdown:SetSelectedOption( SelectedOption )

				if self.TextScale ~= 1 then
					Dropdown:SetTextScale( self.TextScale )
				end

				Layout:AddElement( Dropdown )

				return Dropdown
			end,
			Setup = function( self, Object, Data )
				if IsType( Data.ConfigValue, "string" ) then
					Object:AddPropertyChangeListener( "SelectedOption", function( Object, Option )
						UpdateConfigValue( self, Data.ConfigValue, Option.Value )
					end )
				else
					Object:AddPropertyChangeListener( "SelectedOption", function( Object, Option )
						Data.ConfigValue( self, Option.Value )
					end )
				end
			end,
			Update = function( Object, Value )
				Object:SelectOption( Value )
			end
		},
		Button = {
			Create = function( self, SettingsPanel, Layout, Text, IsVisible )
				local Button = SettingsPanel:Add( "Button" )
				Button:SetupFromTable{
					AutoSize = GetButtonSize( self ),
					Font = self:GetFont(),
					Text = self:GetPhrase( Text ),
					IsVisible = IsVisible,
					TextInheritsParentAlpha = false,
					StyleName = "SettingsButton"
				}

				if self.TextScale ~= 1 then
					Button:SetTextScale( self.TextScale )
				end

				Layout:AddElement( Button )

				return Button
			end,
			Setup = function( self, Object, Data )
				Object.DoClick = Data.DoClick

				if Data.Icon then
					Object:SetIcon( Data.Icon )
					Object:SetIconAutoFont( {
						Family = SGUI.FontFamilies.Ionicons,
						Size = Scaled( 32, self.UIScale.y )
					} )
				end
			end
		}
	}

	local ChatBoxElements = {
		{
			ID = "AutoCloseCheckBox",
			Type = "CheckBox",
			ConfigValue = "AutoClose",
			Values = function( self )
				return self.Config.AutoClose, "AUTO_CLOSE"
			end
		},
		{
			ID = "DeleteOnCloseCheckBox",
			Type = "CheckBox",
			ConfigValue = "DeleteOnClose",
			Values = function( self )
				return self.Config.DeleteOnClose, "AUTO_DELETE"
			end
		},
		{
			ID = "SmoothScrollCheckBox",
			Type = "CheckBox",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "SmoothScroll", Value ) then return end
				Plugin.ChatBox:SetAllowSmoothScroll( Value )
			end,
			Values = function( self )
				return self.Config.SmoothScroll, "SMOOTH_SCROLL"
			end
		},
		{
			ID = "ScrollToBottomOnOpenCheckBox",
			Type = "CheckBox",
			ConfigValue = "ScrollToBottomOnOpen",
			Values = function( self )
				return self.Config.ScrollToBottomOnOpen, "SCROLL_TO_BOTTOM"
			end
		},
		{
			ID = "MoveVanillaChatCheckBox",
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
				return self.Config.MoveVanillaChat, "MOVE_VANILLA_CHAT"
			end
		},
		{
			ID = "ShowTimestampsCheckBox",
			Type = "CheckBox",
			ConfigValue = "ShowTimestamps",
			Values = function( self )
				return self.Config.ShowTimestamps, "SHOW_TIMESTAMPS"
			end
		},
		{
			ID = "AutoCompleteEmojiCheckBox",
			Type = "CheckBox",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "AutoCompleteEmoji", Value ) then return end
				if not SGUI.IsValid( self.EmojiAutoComplete ) then return end

				if Value then
					self.UpdateEmojiAutoComplete( self.TextEntry )
				else
					self.EmojiAutoComplete:SetIsVisible( false )
				end
			end,
			Values = function( self )
				return self.Config.AutoCompleteEmoji, "AUTO_COMPLETE_EMOJI"
			end,
			Bindings = {
				{
					From = {
						Element = "EmojiButton",
						Property = "IsVisible"
					},
					To = {
						Property = "IsVisible"
					}
				}
			}
		},
		{
			ID = "MessageMemoryLabel",
			Type = "Label",
			Values = { "MESSAGE_MEMORY" }
		},
		{
			ID = "MessageMemorySlider",
			Type = "Slider",
			ConfigValue = "MessageMemory",
			Bounds = { 10, 100 },
			Values = function( self )
				return self.Config.MessageMemory
			end
		},
		{
			ID = "OpacityLabel",
			Type = "Label",
			Values = { "OPACITY" }
		},
		{
			ID = "OpacitySlider",
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
				return self.Config.Opacity * 100
			end
		},
		{
			ID = "ScaleLabel",
			Type = "Label",
			Values = { "SCALE" }
		},
		{
			ID = "ScaleSlider",
			Type = "Slider",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "Scale", Value ) then return end
				-- Re-create it after a scale change.
				self:OnResolutionChanged()
			end,
			Bounds = { 0.75, 1.25 },
			Decimals = 2,
			Values = function( self )
				return self.Config.Scale
			end
		},
		{
			ID = "FontSizeModeLabel",
			Type = "Label",
			Values = { "FONT_SIZE_MODE" }
		},
		{
			ID = "FontSizeModeDropdown",
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
				return Options, SelectedOption
			end
		},
		{
			ID = "FontSizeInPixelsSlider",
			Type = "Slider",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "FontSizeInPixels", Value ) then return end

				self:SetFontSizeInPixels( Value )
			end,
			Bounds = { 8, 64 },
			Decimals = 0,
			Values = function( self )
				return self.Config.FontSizeInPixels
			end,
			Bindings = {
				{
					From = {
						Element = "FontSizeModeDropdown",
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

	local function PopulateSettings( self, ParentPanel, Layout, Elements )
		local ElementsByID = {}
		local CreatedElements = {}
		local ElementsByCommand = {}
		local HasCommands = false

		for i = 1, #Elements do
			local Data = Elements[ i ]
			local Values = IsType( Data.Values, "table" ) and Data.Values or { Data.Values( self ) }

			local PreviousElement = CreatedElements[ i - 1 ]
			if PreviousElement then
				PreviousElement:SetMargin( Spacing( 0, 0, 0, Scaled( 4, self.UIScale.y ) ) )
			end

			local Creator = ElementCreators[ Data.Type ]

			local Object = Creator.Create( self, ParentPanel, Layout, unpack( Values ) )
			Object:SetDebugName( "ChatBox"..Data.ID )

			CreatedElements[ i ] = Object

			if Creator.Setup then
				Creator.Setup( self, Object, Data, unpack( Values ) )
			end

			if Data.Tooltip then
				if IsType( Data.Tooltip, "function" ) then
					Object:SetTooltip( Data.Tooltip() )
				else
					Object:SetTooltip( Data.Tooltip )
				end
			end

			if Data.MarginTop then
				Object:SetMargin( Spacing( 0, Scaled( Data.MarginTop, self.UIScale.y ), 0, 0 ) )
			end

			ElementsByID[ Data.ID ] = Object
			if Data.Command and Creator.Update then
				HasCommands = true
				ElementsByCommand[ Data.Command ] = {
					Update = Creator.Update,
					Object = Object
				}
			end
		end

		for i = 1, #Elements do
			local Data = Elements[ i ]
			local Bindings = Data.Bindings
			if Bindings then
				for j = 1, #Bindings do
					local Binding = Bindings[ j ]
					local FromElement = ElementsByID[ Binding.From.Element ] or self[ Binding.From.Element ]
					if FromElement then
						Binder():FromElement( FromElement, Binding.From.Property )
							:ToElement( ElementsByID[ Data.ID ], Binding.To.Property, Binding.To )
							:BindProperty()
					end
				end
			end
		end

		if HasCommands then
			Hook.Add( "OnPluginClientSettingChanged", self, function( Plugin, Setting, NewValue )
				local Element = ElementsByCommand[ Setting.Command ]
				if not Element or not SGUI.IsValid( Element.Object ) then
					return
				end

				if Setting.Inverted then
					NewValue = not NewValue
				end

				Element.Update( Element.Object, NewValue )
			end )
		else
			Hook.Remove( "OnPluginClientSettingChanged", self )
		end
	end

	function Plugin:CreateSettings( MainPanel, UIScale, ScalarScale )
		local PaddingAmountY = Scaled( SETTINGS_PADDING_AMOUNT, UIScale.y )
		local Padding = Spacing(
			Scaled( SETTINGS_PADDING_AMOUNT, UIScale.x ),
			PaddingAmountY,
			-- Right hand side needs double padding to mirror the padding correctly.
			Scaled( SETTINGS_PADDING_AMOUNT * 4, UIScale.x ),
			PaddingAmountY
		)

		local Layout = SGUI.Layout:CreateLayout( "Vertical", {
			Padding = Padding
		} )

		local SettingsPanel = self.SettingsPanel
		local ScrollbarWidth = SETTINGS_PADDING_AMOUNT * 2 * UIScale.x

		if not SGUI.IsValid( SettingsPanel ) then
			SettingsPanel = SGUI:Create( "Panel", MainPanel )
			SettingsPanel:SetupFromTable{
				DebugName = "ChatBoxSettingsPanel",
				Anchor = "TopRight",
				Pos = VectorMultiply( LayoutData.Positions.Settings, UIScale ),
				Scrollable = true,
				ScrollbarHeightOffset = 0,
				ScrollbarWidth = ScrollbarWidth,
				ScrollbarPos = Vector2( -ScrollbarWidth, 0 ),
				HorizontalScrollingEnabled = false,
				Size = VectorMultiply( LayoutData.Sizes.SettingsClosed, UIScale ),
				Skin = Skin,
				StylingState = MainPanel:GetStylingState()
			}

			self.SettingsPanel = SettingsPanel
		end

		local SettingsTabs = Shine.Multimap()
		SettingsTabs:AddAll( {
			Label = self:GetPhrase( "SETTINGS_TAB_LABEL" ),
			Icon = SGUI.Icons.Ionicons.Chatbox
		}, ChatBoxElements )

		Hook.Call( "PopulateChatBoxSettings", self, SettingsTabs )

		if SettingsTabs:GetKeyCount() == 1 then
			PopulateSettings( self, SettingsPanel, Layout, ChatBoxElements )
		else
			Layout:SetPadding( nil )

			local TabWidth = Units.Max()

			local Tabs = SettingsPanel:Add( "TabPanel" )
			Tabs:SetDebugName( "ChatBoxSettingsTabs" )
			Tabs:SetFill( false )
			-- Use a fixed size to ensure no horizontal scrolling shows during expansion.
			Tabs:SetAutoSize(
				UnitVector(
					Scaled( LayoutData.Sizes.Settings.x, self.UIScale.x ),
					Percentage.ONE_HUNDRED
				)
			)
			Tabs:SetTabWidth( TabWidth )
			Tabs:SetTabHeight( Scaled( 32, UIScale.y ):GetValue() )
			Tabs:SetFont( self:GetFont() )
			if self.TextScale ~= 1 then
				Tabs:SetTextScale( self.TextScale )
			end
			Tabs:SetHorizontal( true )

			-- Make sure opacity updates on all tab buttons.
			local OldRefreshStyling = Tabs.RefreshStyling
			function Tabs:RefreshStyling()
				OldRefreshStyling( self )
				for i = 1, #self.Tabs do
					self.Tabs[ i ].TabButton:RefreshStyling()
				end
			end

			self.SettingsPanelTabs = Tabs

			local function SetupTabPanel( TabPanel )
				TabPanel:SetScrollable()
				TabPanel:SetScrollbarWidth( ScrollbarWidth )
				TabPanel:SetScrollbarPos( Vector2( -ScrollbarWidth, 0 ) )
				TabPanel:SetScrollbarHeightOffset( 0 )
				TabPanel:SetResizeLayoutForScrollbar( true )

				return SGUI.Layout:CreateLayout( "Vertical", {
					Padding = Padding
				} )
			end

			local IconFont, IconFontScale = SGUI.FontManager.GetFontForAbsoluteSize(
				SGUI.FontFamilies.Ionicons,
				Scaled( 32, self.UIScale.y ):GetValue()
			)
			for TabDef, Elements in SettingsTabs:Iterate() do
				local Tab = Tabs:AddTab( TabDef.Label, function( TabPanel )
					local TabLayout = SetupTabPanel( TabPanel )

					PopulateSettings( self, TabPanel, TabLayout, Elements )

					TabPanel:SetLayout( TabLayout, true )
				end, TabDef.Icon, IconFont, IconFontScale )

				TabWidth:AddValue( Units.Auto( Tab.TabButton ) + Scaled( 16, UIScale.x ) )
			end

			-- Add a dummy tab to fill the rest of the tab bar background, otherwise it looks odd.
			local BackgroundTab = Tabs:AddTab( "" )
			BackgroundTab.TabButton.DoClick = function() return false end
			BackgroundTab.TabButton:SetFill( true )
			BackgroundTab.TabButton:SetAutoSize( nil )

			Layout:AddElement( Tabs )
		end

		SettingsPanel:SetLayout( Layout )
	end

	local function RefreshSettings( self )
		if not SGUI.IsValid( self.SettingsPanel ) then return end

		local SettingsButton = self.SettingsButton
		if SettingsButton.Expanding or SettingsButton.Expanded then
			self.SettingsPanel:Clear()
			self:CreateSettings( self.MainPanel, self.UIScale, self.ScalarScale )
		else
			self.SettingsPanel:Destroy()
			self.SettingsPanel = nil
		end
	end

	function Plugin:OnPluginLoad( Name, Plugin, IsShared )
		RefreshSettings( self )
	end

	function Plugin:OnPluginUnload( Name, Plugin, IsShared )
		RefreshSettings( self )
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

	SettingsPanel:SizeTo( SettingsPanel.Background, Start, End, 0, 0.25, function()
		SettingsButton.Expanded = Expanded

		if Expanded then
			SettingsButton:AddStylingState( "Open" )
		else
			SettingsButton:RemoveStylingState( "Open" )
			SettingsPanel:SetIsVisible( false )
		end

		SettingsPanel:SetAutoHideScrollbar( false )
		if SGUI.IsValid( SettingsPanel.Scrollbar ) then
			SettingsPanel.Scrollbar:SetIsVisible( true )
		end

		SettingsButton.Expanding = false
	end )
	SettingsPanel:SetAutoHideScrollbar( true )

	if SGUI.IsValid( SettingsPanel.Scrollbar ) then
		SettingsPanel.Scrollbar:SetIsVisible( false )
	end

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

function Plugin:AddMessageFromPopulator( Populator, Context )
	if not SGUI.IsValid( self.MainPanel ) then
		self:CreateChatbox()

		if not self.Visible then
			self.MainPanel:SetIsVisible( false )
		end
	end

	local Messages = self.Messages
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
	ChatLine:SetLineSpacing( LineMargin )

	Populator( ChatLine, Context )

	self.ChatBox.Layout:AddElement( ChatLine )

	if not self.Visible then return end

	self:RefreshLayout()
end

do
	local function AddMessageFromRichText( ChatLine, Contents )
		ChatLine:SetContent( Contents, Plugin.Config.ShowTimestamps )
	end

	function Plugin:AddMessageFromRichText( MessageData )
		return self:AddMessageFromPopulator( AddMessageFromRichText, MessageData.Message )
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
	local BasicMessageContext = {}
	local function AddSimpleChatMessage( ChatLine, Context )
		ChatLine:SetMessage(
			Context.TagData,
			Context.PlayerColour,
			Context.PlayerName,
			Context.MessageColour,
			Context.MessageText,
			Plugin.Config.ShowTimestamps
		)
	end

	--[[
		Adds a message to the chatbox.

		Inputs are derived from the GUIChat inputs as we want to maintain compatability.

		Messages with multiple colours can be added through the chat API.
	]]
	function Plugin:AddMessage( PlayerColour, PlayerName, MessageColour, MessageText, TagData )
		-- Don't add anything if one of the elements is the wrong type. Default chat will error instead.
		if not ( IsType( PlayerColour, "number" ) or IsType( PlayerColour, "cdata" ) )
		or not IsType( PlayerName, "string" ) or not IsType( MessageColour, "cdata" )
		or not IsType( MessageText, "string" ) then
			return
		end

		IntToColour = IntToColour or ColorIntToColor

		-- Why did they use int for the first colour, then colour object for the second?
		if IsType( PlayerColour, "number" ) then
			PlayerColour = IntToColour( PlayerColour )
		end

		BasicMessageContext.PlayerColour = PlayerColour
		BasicMessageContext.PlayerName = PlayerName
		BasicMessageContext.MessageColour = MessageColour
		BasicMessageContext.MessageText = MessageText
		BasicMessageContext.TagData = TagData

		self:AddMessageFromPopulator( AddSimpleChatMessage, BasicMessageContext )
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

do
	local MaxAutoCompleteResult = 3
	local function GetChatCommand( Text )
		local FirstSpace = StringFind( Text, " " )
		return StringSub( Text, 2, FirstSpace and ( FirstSpace - 1 ) or #Text )
	end

	local function GetCommandAndArguments( Text )
		local ChatCommand = GetChatCommand( Text )
		local ArgumentsText = StringSub( Text, #ChatCommand + 3 )
		local Arguments
		if StringFind( ArgumentsText, "[^%s]" ) then
			-- Completing a specific parameter, request completions for it.
			Arguments = Shine.CommandUtil.AdjustArguments( StringExplode( ArgumentsText, " ", true ) )
		end

		return ChatCommand, Arguments
	end

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

		local Result = Results[ self.CurrentResult ]
		local Text
		if Result.ParameterIndex then
			local Command, Arguments = GetCommandAndArguments( self.TextEntry:GetText() )
			if Command == Result.ChatCommand and Arguments and #Arguments >= Result.ParameterIndex then
				Arguments[ Result.ParameterIndex ] = Result.Parameter
				Text = StringFormat(
					"%s%s %s",
					self.AutoCompleteLetter,
					Command,
					Shine.CommandUtil.SerialiseArguments( Arguments )
				)
			end
		end

		if not Text then
			Text = StringFormat( "%s%s ", self.AutoCompleteLetter, Result.ChatCommand )
		end

		self.TextEntry:SetText( Text )
	end

	local BackgroundAlpha = 0.65
	local Easing = require "shine/lib/gui/util/easing"
	local FadeOutTransition = {
		Type = "Alpha",
		EndValue = 0,
		Duration = 0.2,
		EasingFunction = Easing.GetEaser( "OutExpo" )
	}
	local FadeInTransition = {
		Type = "Alpha",
		StartValue = 0,
		EndValue = BackgroundAlpha,
		Duration = 0.2,
		EasingFunction = Easing.GetEaser( "InSine" )
	}

	local function ApplyAutoCompletionResults( self, Results )
		if not self.Visible then return end

		local Text = self.TextEntry:GetText()
		if not self:ShouldAutoComplete( Text ) then return end

		self.AutoCompleteLetter = StringSub( Text, 1, 1 )

		local ChatCommand, Arguments = GetCommandAndArguments( Text )
		local ResultsAreForCorrectArgument = Results.Command == ChatCommand and Arguments
			and Results.ParameterIndex == #Arguments

		self.AutoCompleteResults = Results

		local ResultPanel = self.AutoCompletePanel
		if not ResultPanel then
			ResultPanel = SGUI:Create( "Column", self.MainPanel )
			ResultPanel:SetDebugName( "ChatBoxChatCommandCompletionContainer" )
			ResultPanel:SetIsSchemed( false )
			ResultPanel:SetShader( SGUI.Shaders.Invisible )
			self.AutoCompletePanel = ResultPanel

			ResultPanel:SetAnchor( "BottomLeft" )
			ResultPanel:SetColour( Colour( 0, 0, 0, 1 ) )
		end

		local Layout = ResultPanel.Layout
		local Elements = Layout.Elements

		local ResultPanelPadding = self.MainPanel.Layout:GetComputedPadding()
		local XPadding = ResultPanelPadding[ 5 ]
		local YPadding = ResultPanelPadding[ 6 ]
		local Size = Vector2( self.MainPanel:GetSize().x, YPadding )

		for i = 1, Max( #Results, #Elements ) do
			local LabelRow = Elements[ i ]
			if not Results[ i ] or ( i > 1 and Results.ParameterIndex and not ResultsAreForCorrectArgument ) then
				if LabelRow then
					FadeOutTransition.Callback = LabelRow.Destroy
					LabelRow:ApplyTransition( FadeOutTransition )
				end
			else
				local ShouldFade
				if not LabelRow then
					ShouldFade = true

					local Tree = SGUI:BuildTree( {
						Parent = ResultPanel,
						{
							ID = "Container",
							Class = "Row",
							Props = {
								DebugName = "ChatBoxChatCommandCompletionRow"..i,
								IsSchemed = false,
								Padding = Spacing(
									ResultPanelPadding[ 1 ],
									i == 1 and ResultPanelPadding[ 2 ] or 0,
									ResultPanelPadding[ 3 ],
									ResultPanelPadding[ 4 ]
								),
								Colour = Colour( 0, 0, 0, BackgroundAlpha ),
								AutoSize = UnitVector( Percentage.ONE_HUNDRED, Units.Auto.INSTANCE )
							},
							Children = {
								{
									ID = "Label",
									Class = "ColourLabel",
									Props = {
										DebugName = "ChatBoxChatCommandCompletionLabel"..i,
										IsSchemed = false,
										Alpha = 1 / BackgroundAlpha,
										InheritsParentAlpha = true
									}
								}
							}
						}
					} )

					LabelRow = Tree.Container
					LabelRow.Label = Tree.Label
				elseif LabelRow:GetAlpha() + 0.001 < BackgroundAlpha then
					ShouldFade = true
				end

				local Label = LabelRow.Label
				local Result = Results[ i ]
				Result.ParameterIndex = Results.ParameterIndex

				Label:SetFont( self:GetFont() )
				Label:SetTextScale( self.MessageTextScale )

				-- Completion of the form: !command <param> Help text.
				local TextContent = {
					Colours.ModeText, self.AutoCompleteLetter,
					Colours.AutoCompleteCommand, Result.ChatCommand.." "
				}
				if Result.Parameters ~= "" then
					if ResultsAreForCorrectArgument and Result.Parameter and Result.Parameter ~= "" then
						-- Results are for a specific parameter, show the help for the other parameters and use the
						-- completion value for this parameter.
						local Params = Shine.CommandUtil.SplitParameterHelp( Result.Parameters )
						local ParamsBefore = TableConcat( Params, " ", 1, Results.ParameterIndex - 1 )
						if #ParamsBefore > 0 then
							TextContent[ #TextContent + 1 ] = Colours.AutoCompleteParams
							TextContent[ #TextContent + 1 ] = ParamsBefore.." "
						end

						TextContent[ #TextContent + 1 ] = Colours.AutoCompleteArg
						TextContent[ #TextContent + 1 ] = Result.Parameter.." "

						if i == 1 then
							local ParamsAfter = TableConcat( Params, " ", Results.ParameterIndex + 1 )
							if #ParamsAfter > 0 then
								TextContent[ #TextContent + 1 ] = Colours.AutoCompleteParams
								TextContent[ #TextContent + 1 ] = ParamsAfter.." "
							end
						end
					else
						TextContent[ #TextContent + 1 ] = Colours.AutoCompleteParams
						TextContent[ #TextContent + 1 ] = Result.Parameters.." "
					end
				end

				if i == 1 or not ResultsAreForCorrectArgument then
					TextContent[ #TextContent + 1 ] = Colours.ModeText
					TextContent[ #TextContent + 1 ] = Result.Description
				end

				Label:SetText( TextContent )
				LabelRow:InvalidateLayout( true )

				if ShouldFade then
					LabelRow:ApplyTransition( FadeInTransition )
				else
					LabelRow:StopAlpha()
				end

				local LabelSize = Label:GetSize()
				Size.x = Max( Size.x, LabelSize.x + XPadding )
				Size.y = Size.y + LabelSize.y

				-- Display only one line if the auto-completion was for a specific command that's no longer correct.
				if Results.ParameterIndex and not ResultsAreForCorrectArgument then
					break
				end
			end
		end

		if #Results == 0 then
			Size.x = 0
			Size.y = 0
		end

		ResultPanel:SetSize( Size )
		ResultPanel:InvalidateLayout( true )
	end

	function Plugin:SubmitParameterAutoCompleteRequest( ChatCommand, ParameterIndex, SearchText )
		if self.LastSearchedChatCommand == ChatCommand and self.LastSearchedParameterIndex == ParameterIndex
		and self.LastSearchedParameter == SearchText then
			return
		end

		self.LastSearch = nil
		self.LastSearchedChatCommand = ChatCommand
		self.LastSearchedParameterIndex = ParameterIndex
		self.LastSearchedParameter = SearchText

		Shine.AutoComplete.RequestParameter(
			ChatCommand,
			ParameterIndex,
			SearchText,
			Shine.AutoComplete.CHAT_COMMAND,
			MaxAutoCompleteResult,
			function( Results ) ApplyAutoCompletionResults( self, Results ) end
		)
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
		local SearchText, Arguments = GetCommandAndArguments( Text )
		if Arguments and StringFind( Arguments[ #Arguments ], "[^%s]" ) then
			-- Completing a specific parameter, request completions for it.
			self:SubmitParameterAutoCompleteRequest( SearchText, #Arguments, Arguments[ #Arguments ] )
			return
		end

		if self.LastSearch == SearchText then return end

		self.LastSearch = SearchText
		self.LastSearchedChatCommand = nil
		self.LastSearchedParameterIndex = nil
		self.LastSearchedParameter = nil

		-- On receiving the results, add labels beneath the chatbox showing the completed command(s).
		Shine.AutoComplete.Request( SearchText, Shine.AutoComplete.CHAT_COMMAND, MaxAutoCompleteResult, function( Results )
			ApplyAutoCompletionResults( self, Results )
		end )
	end
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
	self.LastSearchedChatCommand = nil
	self.LastSearchedParameterIndex = nil
	self.LastSearchedParameter = nil
	self.CurrentResult = nil
end

function Plugin:ShouldAutoComplete( Text )
	return StringFind( Text, "^[!/]" ) and #Text > 1
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

	if SGUI.IsValid( self.EmojiPicker ) then
		self.EmojiPicker:Close()
		self.EmojiPicker = nil
	end

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
	local EmojiPickerState = SGUI.IsValid( self.EmojiPicker ) and self.EmojiPicker:GetState()

	-- Ensure existing text entry state is preserved.
	self:CloseChat( true )

	self:SimpleTimer( 0, function()
		-- Wait a frame to allow the commander mouse to be pushed/popped first.
		self:StartChat( WasTeamChat )

		if EmojiPickerState then
			self:OpenEmojiPicker( true )

			if SGUI.IsValid( self.EmojiPicker ) then
				self.EmojiPicker:RestoreFromState( EmojiPickerState )
			end
		end
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
		self.TextEntryIcon:SetStylingState( StyleState or "AllChat" )

		self.TextEntry:SetPlaceholderText( self.TeamChat and self:GetPhrase( "SAY_TEAM" ) or self:GetPhrase( "SAY_ALL" ) )
		self.EmojiButton:SetIsVisible( Hook.Call( "IsChatEmojiAvailable" ) == true )

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
	Hook.Remove( "OnPluginClientSettingChanged", self )

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

	if self.Config.MoveVanillaChat then
		self:ResetVanillaChatPos()
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
