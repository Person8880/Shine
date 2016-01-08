--[[
	Shine chatbox.

	I can't believe the game doesn't have one.
]]

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
local type = type

local Plugin = {}

Plugin.HasConfig = true
Plugin.ConfigName = "ChatBox.json"

Plugin.DefaultConfig = {
	AutoClose = true, --Should the chatbox close after sending a message?
	DeleteOnClose = true, --Should whatever's entered be deleted if the chatbox is closed before sending?
	MessageMemory = 50, --How many messages should the chatbox store before removing old ones?
	SmoothScroll = true, --Should the scrolling be smoothed?
	Opacity = 0.4, --How opaque should the chatbox be?
	Pos = {} --Remembers the position of the chatbox when it's moved.
}

Plugin.CheckConfig = true
Plugin.SilentConfigSave = true

function Plugin:HookChat( ChatElement )
	function ChatElement:SetIsVisible( Vis )
		if self.Vis == Vis then return end

		self.Vis = Vis

		local Messages = self.messages
		if not Messages then return end

		for i = 1, #Messages do
			local Element = Messages[ i ]

			if IsType( Element, "table" ) then
				Element.Background:SetIsVisible( Vis )
			end
		end
	end

	local OldSendKey = ChatElement.SendKeyEvent

	function ChatElement:SendKeyEvent( Key, Down )
		if Plugin.Enabled then return end
		return OldSendKey( self, Key, Down )
	end

	local OldAddMessage = ChatElement.AddMessage
	local function GetTag( Element )
		return {
			Colour = Element:GetColor(),
			Text = Element:GetText()
		}
	end

	function ChatElement:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName, IsCommander, IsRookie )
		Plugin.GUIChat = self

		OldAddMessage( self, PlayerColour, PlayerName, MessageColour, MessageName, IsCommander, IsRookie )

		if not Plugin.Enabled then return end

		local JustAdded = self.messages[ #self.messages ]
		local Tags
		local Rookie = JustAdded.Rookie and JustAdded.Rookie:GetIsVisible()
		local Commander = JustAdded.Commander and JustAdded.Commander:GetIsVisible()

		if Rookie or Commander then
			Tags = {}

			if Commander then
				Tags[ 1 ] = GetTag( JustAdded.Commander )
			end

			if Rookie then
				Tags[ #Tags + 1 ] = GetTag( JustAdded.Rookie )
			end
		end

		Plugin:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName, Tags )

		if Plugin.Visible and IsType( JustAdded, "table" ) then
			JustAdded.Background:SetIsVisible( false )
		end
	end
end

--We hook the class here for certain functions before we find the actual instance of it.
Hook.Add( "Think", "ChatBoxHook", function()
	if GUIChat then
		Plugin:HookChat( GUIChat )

		Hook.Remove( "Think", "ChatBoxHook" )
	end
end )

--[[
	Suddenly, with no changes, EvaluateUIVisibility is no longer being called,
	or is being called sooner than the plugin is enabled.
	I don't even.
]]
Hook.Add( "Think", "GetGUIChat", function()
	local Manager = GetGUIManager()
	if not Manager then return end

	local Scripts = Manager.scripts

	if not Scripts then return end

	for Index, Script in pairs( Scripts ) do
		if Script._scriptName == "GUIChat" then
			Plugin.GUIChat = Script

			Hook.Remove( "Think", "GetGUIChat" )

			return
		end
	end
end )

local Hooked

function Plugin:Initialise()
	if not Hooked then
		Shine.Hook.SetupGlobalHook( "ClientUI.EvaluateUIVisibility",
			"EvaluateUIVisibility", "PassivePost" )

		Hooked = true
	end

	Script.Load( "lua/shine/extensions/chatbox/chatline.lua" )

	self.Messages = self.Messages or {}
	self.Enabled = true

	return true
end

--We need the default chat script so we can hide its messages.
function Plugin:EvaluateUIVisibility()
	local Manager = GetGUIManager()
	local Scripts = Manager.scripts

	for Index, Script in pairs( Scripts ) do
		if Script._scriptName == "GUIChat" then
			self.GUIChat = Script

			return
		end
	end
end

local Units = SGUI.Layout.Units

local Percentage = Units.Percentage
local UnitVector = Units.UnitVector
local Scaled = Units.Scaled
local Spacing = Units.Spacing

local Colours = {
	Background = Colour( 0.6, 0.6, 0.6, 0.4 ),
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
			InactiveCol = Colours.Dark
		}
	},
	Panel = {
		Default = {
			Colour = Colours.Background
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
			TextColour = Colour( 1, 1, 1, 1 )
		}
	},

}

local LayoutData = {
	Sizes = {
		ChatBox = Vector2( 800, 350 ),
		SettingsClosed = Vector2( 0, 350 ),
		Settings = Vector2( 350, 350 ),
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

--Scales alpha value for elements that default to 0.8 rather than 0.4 alpha.
local function AlphaScale( Alpha )
	if Alpha <= 0.4 then
		return Alpha * 2
	end

	return 0.8 + ( ( Alpha - 0.4 ) / 3 )
end

--UWE's vector type has no Hadamard product defined.
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

--[[
	Creates the chatbox UI elements.

	Essentially,
		1. An outer panel to contain everything.
		2. A smaller panel to contain the chat messages, scrollable.
		3. A text entry for entering chat messages (with placeholder text indicating team/all mode).
		4. A settings button that opens up the chatbox settings.
]]
function Plugin:CreateChatbox()
	local UIScale = GUIScale( Vector( 1, 1, 1 ) )
	local ScalarScale = GUIScale( 1 )

	local ScreenWidth, ScreenHeight = SGUI.GetScreenSize()

	local WidthMult = Max( ScreenWidth / 1920, 0.7 )
	local HeightMult = Max( ScreenHeight / 1080, 0.7 )

	if ScreenWidth > 1920 then
		UIScale = SGUI.TenEightyPScale( Vector( 1, 1, 1 ) )
		ScalarScale = SGUI.TenEightyPScale( 1 )
	end

	local FourToThreeHeight = ( ScreenWidth / 4 ) * 3
	--Use a more boxy box for 4:3 monitors.
	if FourToThreeHeight == ScreenHeight then
		WidthMult = WidthMult * 0.72
	end

	UIScale.x = UIScale.x * WidthMult
	UIScale.y = UIScale.y * HeightMult

	ScalarScale = ScalarScale * ( WidthMult + HeightMult ) * 0.5

	self.UIScale = UIScale
	self.ScalarScale = ScalarScale
	self.TextScale = TextScale * ScalarScale
	self.MessageTextScale = TextScale

	if ScreenWidth <= 1366 then
		self.Font = Fonts.kAgencyFB_Tiny
		self.TextScale = TextScale
	elseif ScreenWidth <= 1920 then
		self.Font = Fonts.kAgencyFB_Small
	elseif ScreenWidth <= 2880 then --1440p probably.
		self.Font = Fonts.kAgencyFB_Medium
		self.TextScale = TextScale
	else --Assumming 4K here. "Large" font is too small, so we need huge at a scale.
		self.Font = Fonts.kAgencyFB_Huge
		self.TextScale = TextScale * 0.6
		self.MessageTextScale = self.TextScale
	end

	local Opacity = self.Config.Opacity
	UpdateOpacity( self, Opacity )

	local Pos = self.Config.Pos
	local ChatBoxPos
	local PanelSize = VectorMultiply( LayoutData.Sizes.ChatBox, UIScale )

	if not Pos.x or not Pos.y then
		ChatBoxPos = self.GUIChat.inputItem:GetPosition() - Vector( 0, 100 * ScalarScale, 0 )
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

	--Double click the title bar to return it to the default position.
	function Border:ReturnToDefaultPos()
		self:SetPos( ChatBoxPos )
		self:OnDragFinished( ChatBoxPos )
	end

	--Update our saved position on drag finish.
	function Border.OnDragFinished( Panel, Pos )
		self.Config.Pos.x = Pos.x
		self.Config.Pos.y = Pos.y

		self:SaveConfig()
	end

	--If, for some reason, there's an error in a panel hook, then this is removed.
	--We don't want to leave the mouse showing if that happens.
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

	--Panel for messages.
	local Box = SGUI:Create( "Panel", Border )
	local ScrollbarPos = LayoutData.Positions.Scrollbar * WidthMult
	ScrollbarPos.x = Ceil( ScrollbarPos.x )
	Box:SetupFromTable{
		ScrollbarPos = ScrollbarPos,
		ScrollbarWidth = Ceil( 8 * WidthMult ),
		ScrollbarHeightOffset = 0,
		Scrollable = true,
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
	Box.BufferAmount = 5
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
		Fill = true
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

	--We don't want to allow characters after hitting the max length message.
	function TextEntry:ShouldAllowChar( Char )
		local Text = self:GetText()

		if StringUTF8Length( Text ) >= kMaxChatLength then
			return false
		end

		--We also don't want the player's chat button bind making it into the text entry.
		if ( Plugin.OpenTime or 0 ) + 0.05 > Clock() then
			return false
		end
	end

	function TextEntry.OnUnhandledKey( TextEntry, Key, Down )
		if Key == InputKey.Down or Key == InputKey.Up then
			self:ScrollAutoComplete( Key == InputKey.Down and 1 or -1 )
		end
	end

	function TextEntry.OnTextChanged( TextEntry, OldText, NewText )
		self:AutoCompleteCommand( NewText )
	end

	self.TextEntry = TextEntry

	local SettingsButton = SGUI:Create( "Button", Border )
	SettingsButton:SetupFromTable{
		Text = ">",
		Skin = Skin,
		Font = Font,
		AutoSize = UnitVector( Scaled( SettingsButtonSize, ScalarScale ),
			Scaled( SettingsButtonSize, ScalarScale ) ),
		Margin = Spacing( PaddingUnit, 0, 0, 0 )
	}
	if self.TextScale ~= 1 then
		SettingsButton:SetTextScale( self.TextScale )
	end

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
	local unpack = unpack

	local function UpdateConfigValue( self, Key, Value )
		if self.Config[ Key ] == Value then return false end

		self.Config[ Key ] = Value
		self:SaveConfig()

		return true
	end

	local ElementCreators = {
		CheckBox = {
			Create = function( self, SettingsPanel, Layout, Size, Checked, Label )
				local CheckBox = SettingsPanel:Add( "CheckBox" )
				CheckBox:SetupFromTable{
					AutoSize = Size,
					Font = self:GetFont(),
					Margin = Spacing( 0, 0, 0, Scaled( 4, self.UIScale.y ) )
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
			end
		},
		Label = {
			Create = function( self, SettingsPanel, Layout, Text )
				local Label = SettingsPanel:Add( "Label" )
				Label:SetupFromTable{
					Font = self:GetFont(),
					Text = self:GetPhrase( Text ),
					Margin = Spacing( 0, 0, 0, Scaled( 4, self.UIScale.y ) )
				}

				if self.TextScale ~= 1 then
					Label:SetTextScale( self.TextScale )
				end

				Layout:AddElement( Label )

				return Label
			end
		},
		Slider = {
			Create = function( self, SettingsPanel, Layout, Size, Value )
				local Slider = SettingsPanel:Add( "Slider" )
				Slider:SetupFromTable{
					AutoSize = Size,
					Value = Value,
					Font = self:GetFont(),
					Padding = SliderTextPadding * self.ScalarScale,
					Margin = Spacing( 0, 0, 0, Scaled( 4, self.UIScale.y ) )
				}

				if self.TextScale ~= 1 then
					Slider:SetTextScale( self.TextScale )
				end

				Layout:AddElement( Slider )

				return Slider
			end,
			Setup = function( self, Object, Data )
				Object:SetBounds( unpack( Data.Bounds ) )

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
		}
	}

	local function GetCheckBoxSize( self )
		return UnitVector( Scaled( 36, self.ScalarScale ),
			Scaled( 36, self.ScalarScale ) )
	end

	local function GetSliderSize( self )
		return UnitVector( Percentage( 80 ), Scaled( 32, self.UIScale.y ) )
	end

	local Elements = {
		{
			Type = "Label",
			Values = { "SETTINGS_TITLE" }
		},
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
			Bounds = { 0, 100 },
			Values = function( self )
				return GetSliderSize( self ), self.Config.Opacity * 100
			end
		}
	}

	function Plugin:CreateSettings( MainPanel, UIScale, ScalarScale )
		local Padding = Spacing( Scaled( 30, UIScale.x ),
			Scaled( 15, UIScale.y ), Scaled( 30, UIScale.x ), 0 )

		local Layout = SGUI.Layout:CreateLayout( "Vertical", {
			Padding = Padding
		} )

		local SettingsPanel = SGUI:Create( "Panel", MainPanel )
		SettingsPanel:SetupFromTable{
			Anchor = "TopRight",
			Pos = VectorMultiply( LayoutData.Positions.Settings, UIScale ),
			Scrollable = true,
			Size = VectorMultiply( LayoutData.Sizes.SettingsClosed, UIScale ),
			Skin = Skin,
			ShowScrollbar = false
		}

		self.SettingsPanel = SettingsPanel

		for i = 1, #Elements do
			local Data = Elements[ i ]
			local Values = IsType( Data.Values, "table" ) and Data.Values or { Data.Values( self ) }

			local Creator = ElementCreators[ Data.Type ]

			local Object = Creator.Create( self, SettingsPanel, Layout, unpack( Values ) )
			if Creator.Setup then
				Creator.Setup( self, Object, Data )
			end
		end

		Layout:SetSize( VectorMultiply( LayoutData.Sizes.Settings, UIScale ) )
		Layout:InvalidateLayout( true )
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

	if not SettingsButton.Expanded then
		Start = VectorMultiply( LayoutData.Sizes.SettingsClosed, UIScale )
		End = VectorMultiply( LayoutData.Sizes.Settings, UIScale )
		Expanded = true

		SettingsPanel:SetIsVisible( true )
	else
		Start = VectorMultiply( LayoutData.Sizes.Settings, UIScale )
		End = VectorMultiply( LayoutData.Sizes.SettingsClosed, UIScale )
		Expanded = false
	end

	SettingsPanel:SizeTo( SettingsPanel.Background, Start, End, 0, 0.5, function( Panel )
		SettingsButton.Expanded = Expanded

		self.SettingsButton:SetText( Expanded and "<" or ">" )
		if not Expanded then
			SettingsPanel:SetIsVisible( false )
		end

		SettingsButton.Expanding = false
	end )

	return true
end

--Close on pressing escape (it's not hardcoded, unlike Source!)
function Plugin:PlayerKeyPress( Key, Down )
	if Key == InputKey.Escape and self.Visible then
		self:CloseChat()

		return true
	end
end

function Plugin:OnResolutionChanged( OldX, OldY, NewX, NewY )
	if not SGUI.IsValid( self.MainPanel ) then return end

	local Messages = self.Messages
	local Recreate = {}

	for i = 1, #Messages do
		local Message = Messages[ i ]
		local PreText = Message.PreLabel:GetText()
		local PreCol = Message.PreLabel:GetColour()

		local MessageText = Message.MessageText
		local MessageCol = Message.MessageLabel:GetColour()

		local TagData
		local Tags = Message.Tags
		if Tags then
			TagData = {}

			for j = 1, #Tags do
				TagData[ j ] = {
					Colour = Tags[ j ]:GetColour(),
					Text = Tags[ j ]:GetText()
				}
			end
		end

		Recreate[ i ] = {
			TagData = TagData,
			PreText = PreText, PreCol = PreCol,
			MessageText = MessageText, MessageCol = MessageCol
		}
	end

	--Recreate the entire chat box, it's easier than rescaling.
	self.IgnoreRemove = true
	self.MainPanel:Destroy()
	self.IgnoreRemove = nil

	TableEmpty( Messages )

	if not self:CreateChatbox() then return end

	if not self.Visible then
		self.MainPanel:SetIsVisible( false )
	end

	for i = 1, #Recreate do
		local Message = Recreate[ i ]
		self:AddMessage( Message.PreCol, Message.PreText,
			Message.MessageCol, Message.MessageText, Message.TagData )
	end
end

local IntToColour

--[[
	Adds a message to the chatbox.

	Inputs are derived from the GUIChat inputs as we want to maintain compatability.

	Theoretically, we can make messages with any number of colours, but for now this will do.
]]
function Plugin:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName, TagData )
	if not SGUI.IsValid( self.MainPanel ) then
		self:CreateChatbox()

		if not self.Visible then
			self.MainPanel:SetIsVisible( false )
		end
	end

	--Don't add anything if one of the elements is the wrong type. Default chat will error instead.
	if not ( IsType( PlayerColour, "number" ) or IsType( PlayerColour, "cdata" ) )
	or not IsType( PlayerName, "string" ) or not IsType( MessageColour, "cdata" )
	or not IsType( MessageName, "string" ) then
		return
	end

	IntToColour = IntToColour or ColorIntToColor

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

	-- Why did they use int for the first colour, then colour object for the second?
	if IsType( PlayerColour, "number" ) then
		PlayerColour = IntToColour( PlayerColour )
	end

	local Units = SGUI.Layout.Units

	local ChatLine = ReUse or self.ChatBox:Add( "ChatLine" )
	ChatLine:SetFont( self:GetFont() )
	ChatLine:SetTextScale( self.MessageTextScale )
	ChatLine:SetTags( TagData )
	ChatLine:SetMessage( PlayerColour, PlayerName, MessageColour, MessageName )
	ChatLine:SetPreMargin( PrefixMargin )
	ChatLine:SetLineSpacing( LineMargin )

	self.ChatBox.Layout:AddElement( ChatLine )
	-- Force layout refresh now so we can update the scrollbar.
	self.ChatBox:InvalidateLayout( true )

	if SGUI.IsValid( self.ChatBox.Scrollbar ) then
		local NewMaxHeight = ChatLine:GetPos().y + ChatLine:GetSize().y + self.ChatBox.BufferAmount
		if NewMaxHeight < self.ChatBox:GetMaxHeight() then
			self.ChatBox:SetMaxHeight( NewMaxHeight )
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

		self.AutoCompleteResults = Results

		local ResultPanel = self.AutoCompletePanel
		if not ResultPanel then
			ResultPanel = SGUI:Create( "Panel", self.MainPanel )
			self.AutoCompletePanel = ResultPanel

			ResultPanel:SetAnchor( "BottomLeft" )

			local Padding = self.MainPanel.Layout:GetComputedPadding()
			ResultPanel:SetPos( Vector2( Padding[ 1 ], 0 ) )
			ResultPanel:SetColour( Colour( 0, 0, 0, 0 ) )
			ResultPanel:SetLayout( SGUI.Layout:CreateLayout( "Vertical", {} ) )
		end

		local Layout = ResultPanel.Layout
		local Elements = Layout.Elements

		for i = 1, Max( #Results, #Elements ) do
			local Label = Elements[ i ]
			if not Results[ i ] then
				if Label then
					Label:AlphaTo( nil, nil, 0, 0, 0.3, function()
						if not Label then return end

						Label:Destroy( true )
						Label = nil
						Elements[ i ] = nil
					end )
				end
			else
				local ShouldFade
				if not Label then
					ShouldFade = true
					Label = SGUI:Create( "ColourLabel", ResultPanel )
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
			end
		end

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
		self.AutoCompletePanel:Destroy( true )
	end
	self.AutoCompletePanel = nil

	self.AutoCompleteResults = nil
	self.AutoCompleteLetter = nil
	self.LastSearch = nil
	self.CurrentResult = nil
end

function Plugin:AutoCompleteCommand( Text )
	-- Only auto-complete when the text starts with ! or /, and there's a command being typed.
	if not StringFind( Text, "^[!/]" ) or StringLen( Text ) <= 1 then
		self:DestroyAutoCompletePanel()

		return
	end

	-- Keep debouncing the timer until the user stops typing to avoid spamming completion requests.
	self.AutoCompleteTimer = self.AutoCompleteTimer or self:SimpleTimer( 0.3, function()
		self.AutoCompleteTimer = nil
		self:SubmitAutoCompleteRequest( self.TextEntry:GetText() )
	end )
	self.AutoCompleteTimer:Debounce()
end

function Plugin:CloseChat()
	if not SGUI.IsValid( self.MainPanel ) then return end

	self.MainPanel:SetIsVisible( false )
	self.GUIChat:SetIsVisible( true )

	SGUI:EnableMouse( false )

	if self.Config.DeleteOnClose then
		self.TextEntry:SetText( "" )
		self.TextEntry:ResetUndoState()
		self:DestroyAutoCompletePanel()
	end

	self.TextEntry:LoseFocus()

	self.Visible = false
end

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

	--This is somehow gone for some people?
	if not SGUI.IsValid( self.TextEntry ) then
		if SGUI.IsValid( self.MainPanel ) then
			self.IgnoreRemove = true
			self.MainPanel:Destroy()
			self.IgnoreRemove = nil
		end

		if not self:CreateChatbox() then
			return
		end
	end

	self.TextEntry:SetPlaceholderText( self.TeamChat and self:GetPhrase( "SAY_TEAM" ) or self:GetPhrase( "SAY_ALL" ) )

	SGUI:EnableMouse( true )

	self.MainPanel:SetIsVisible( true )
	self.GUIChat:SetIsVisible( false )

	--Get our text entry accepting input.
	self.TextEntry:RequestFocus()
	self.Visible = true

	--Set this so we don't accept text input straight away, avoids the bind button making it in.
	self.OpenTime = Clock()

	return true
end

--[[
	When the plugin is disabled, we need to cleanup the chatbox itself
	and empty out the messages table.
]]
function Plugin:Cleanup()
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

Shine:RegisterExtension( "chatbox", Plugin )

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
	Shine.AddStartupMessage( "Shine has a chatbox that you can enable/disable by entering \"sh_chatbox\" into the console." )
end )
