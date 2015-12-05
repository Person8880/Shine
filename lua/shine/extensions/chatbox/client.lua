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
local StringFormat = string.format
local StringGSub = string.gsub
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
		if Plugin.Enabled then
			return
		end

		return OldSendKey( self, Key, Down )
	end

	local OldAddMessage = ChatElement.AddMessage

	function ChatElement:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName, IsCommander, IsRookie )
		Plugin.GUIChat = self

		OldAddMessage( self, PlayerColour, PlayerName, MessageColour, MessageName, IsCommander, IsRookie )

		local JustAdded = self.messages[ #self.messages ]

		if Plugin.Enabled then
			local Tags
			local Rookie = JustAdded.Rookie and JustAdded.Rookie:GetIsVisible()
			local Commander = JustAdded.Commander and JustAdded.Commander:GetIsVisible()

			if Rookie or Commander then
				Tags = {}

				if Commander then
					Tags[ 1 ] = {
						Colour = JustAdded.Commander:GetColor(),
						Text = JustAdded.Commander:GetText()
					}
				end

				if Rookie then
					Tags[ #Tags + 1 ] = {
						Colour = JustAdded.Rookie:GetColor(),
						Text = JustAdded.Rookie:GetText()
					}
				end
			end

			Plugin:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName, Tags )
		end

		if Plugin.Enabled and Plugin.Visible then
			if IsType( JustAdded, "table" ) then
				JustAdded.Background:SetIsVisible( false )
			end
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
	},

	Colours = {
		StandardOpacity = {
			Border = Colour( 0.6, 0.6, 0.6, 0.4 ),
			Settings = Colour( 0.6, 0.6, 0.6, 0.4 )
		},
		HalfOpacity = {
			Inner = Colour( 0.2, 0.2, 0.2, 0.8 ),
			TextDark = Colour( 0.2, 0.2, 0.2, 0.8 ),
			TextFocus = Colour( 0.2, 0.2, 0.2, 0.8 ),
			ButtonActive = Colour( 0.5, 0.5, 0.5, 0.8 ),
			ButtonInActive = Colour( 0.2, 0.2, 0.2, 0.8 )
		},
		ModeText = Colour( 1, 1, 1, 1 ),
		TextBorder = Colour( 0, 0, 0, 0 ),
		Text = Colour( 1, 1, 1, 1 ),
		CheckBack = Colour( 0.2, 0.2, 0.2, 1 ),
		Checked = Colour( 0.8, 0.6, 0.1, 1 )
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

--UWE's vector type has no multiplication defined.
local function VectorMultiply( Vec1, Vec2 )
	return Vector( Vec1.x * Vec2.x, Vec1.y * Vec2.y, 0 )
end

function Plugin:GetFont()
	return self.Font
end

function Plugin:GetTextScale()
	return self.TextScale
end

local function UpdateOpacity( self, Opacity )
	local ScaledOpacity = AlphaScale( Opacity )

	for Name, Colour in pairs( LayoutData.Colours.StandardOpacity ) do
		Colour.a = Opacity
	end

	for Name, Colour in pairs( LayoutData.Colours.HalfOpacity ) do
		Colour.a = ScaledOpacity
	end
end

--[[
	Creates the chatbox UI elements.

	Essentially,
		1. An invisible dummy panel to contain everything.
		2. A smaller panel to contain the chat messages, scrollable.
		3. A larger panel parented to the smaller one, that provides a border.
		4. A text entry for entering chat messages.
		5. Text to show if it's all chat or team chat.
		6. A settings button that opens up the chatbox settings.
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
		Colour = LayoutData.Colours.StandardOpacity.Border,
		Draggable = true,
		IsSchemed = false
	}

	--Double click the title bar to return it to the default position.
	function Border:ReturnToDefaultPos()
		self:SetPos( ChatBoxPos )
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
		Colour = LayoutData.Colours.HalfOpacity.Inner,
		IsSchemed = false,
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
		FocusColour = LayoutData.Colours.HalfOpacity.TextFocus,
		DarkColour = LayoutData.Colours.HalfOpacity.TextDark,
		BorderColour = LayoutData.Colours.TextBorder,
		TextColour = LayoutData.Colours.Text,
		Font = Font,
		IsSchemed = false,
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

	TextEntry.InnerBox:SetColor( LayoutData.Colours.HalfOpacity.TextDark )
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

	self.TextEntry = TextEntry

	local SettingsButton = SGUI:Create( "Button", Border )
	SettingsButton:SetupFromTable{
		Text = ">",
		ActiveCol = LayoutData.Colours.HalfOpacity.ButtonActive,
		InactiveCol = LayoutData.Colours.HalfOpacity.ButtonInActive,
		Font = Font,
		IsSchemed = false,
		AutoSize = UnitVector( Scaled( SettingsButtonSize, ScalarScale ),
			Scaled( SettingsButtonSize, ScalarScale ) ),
		Margin = Spacing( PaddingUnit, 0, 0, 0 )
	}
	if self.TextScale ~= 1 then
		SettingsButton:SetTextScale( self.TextScale )
	end

	function SettingsButton:DoClick()
		Plugin:OpenSettings( Border, UIScale, ScalarScale )
	end

	SettingsButton:SetTooltip( "Opens/closes the chatbox settings." )

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
					CheckedColour = LayoutData.Colours.Checked,
					BackgroundColour = LayoutData.Colours.CheckBack,
					Checked = Checked,
					Font = self:GetFont(),
					TextColour = LayoutData.Colours.ModeText,
					IsSchemed = false,
					Margin = Spacing( 0, 0, 0, Scaled( 4, self.UIScale.y ) )
				}
				CheckBox:AddLabel( Label )

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
					Text = Text,
					Colour = LayoutData.Colours.ModeText,
					IsSchemed = false,
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
					HandleColour = LayoutData.Colours.Checked,
					LineColour = LayoutData.Colours.ModeText,
					DarkLineColour = LayoutData.Colours.HalfOpacity.TextDark,
					Font = self:GetFont(),
					TextColour = LayoutData.Colours.ModeText,
					IsSchemed = false,
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
			Values = { "Settings" }
		},
		{
			Type = "CheckBox",
			ConfigValue = "AutoClose",
			Values = function( self )
				return GetCheckBoxSize( self ), self.Config.AutoClose, "Auto close after sending."
			end
		},
		{
			Type = "CheckBox",
			ConfigValue = "DeleteOnClose",
			Values = function( self )
				return GetCheckBoxSize( self ), self.Config.DeleteOnClose, "Auto delete on close."
			end
		},
		{
			Type = "CheckBox",
			ConfigValue = function( self, Value )
				if not UpdateConfigValue( self, "SmoothScroll", Value ) then return end
				Plugin.ChatBox:SetAllowSmoothScroll( Value )
			end,
			Values = function( self )
				return GetCheckBoxSize( self ), self.Config.SmoothScroll, "Use smooth scrolling."
			end
		},
		{
			Type = "Label",
			Values = { "Message memory" }
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
			Values = { "Opacity (%)" }
		},
		{
			Type = "Slider",
			ConfigValue = function( self, Value )
				Value = Value * 0.01

				if not UpdateConfigValue( self, "Opacity", Value ) then return end

				UpdateOpacity( self, Value )

				self.SettingsPanel:SetColour( LayoutData.Colours.StandardOpacity.Settings )

				self.ChatBox:SetColour( LayoutData.Colours.HalfOpacity.Inner )
				self.MainPanel:SetColour( LayoutData.Colours.StandardOpacity.Border )

				self.TextEntry:SetFocusColour( LayoutData.Colours.HalfOpacity.TextFocus )
				self.TextEntry:SetDarkColour( LayoutData.Colours.HalfOpacity.TextDark )

				self.SettingsButton:SetActiveCol( LayoutData.Colours.HalfOpacity.ButtonActive )
				self.SettingsButton:SetInactiveCol( LayoutData.Colours.HalfOpacity.ButtonInActive )
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
			Colour = LayoutData.Colours.StandardOpacity.Settings,
			ShowScrollbar = false,
			IsSchemed = false
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
	if SettingsButton.Expanding then return end

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
	if not IsType( PlayerColour, "number" ) or not IsType( PlayerName, "string" )
	or not IsType( MessageColour, "cdata" ) or not IsType( MessageName, "string" ) then
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
end

function Plugin:CloseChat()
	if not SGUI.IsValid( self.MainPanel ) then return end

	self.MainPanel:SetIsVisible( false )
	self.GUIChat:SetIsVisible( true )

	SGUI:EnableMouse( false )

	if self.Config.DeleteOnClose then
		self.TextEntry:SetText( "" )
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

	self.TextEntry:SetPlaceholderText( self.TeamChat and "Say to team..." or "Say to all..." )

	SGUI:EnableMouse( true )

	self.MainPanel:SetIsVisible( true )
	self.GUIChat:SetIsVisible( false )

	--Get our text entry accepting input.
	self.TextEntry:RequestFocus()

	self.TextEntry:SetFocusColour( LayoutData.Colours.HalfOpacity.TextFocus )
	self.TextEntry:SetDarkColour( LayoutData.Colours.HalfOpacity.TextDark )
	self.TextEntry:SetBorderColour( LayoutData.Colours.TextBorder )
	self.TextEntry:SetTextColour( LayoutData.Colours.Text )

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

		Shared.Message( "[Shine] Chatbox enabled. The chatbox will now autoload on any server running Shine with the right version." )
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
