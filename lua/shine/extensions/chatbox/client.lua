--[[
	Shine chatbox.

	I can't believe the game doesn't have one.
]]

local Shine = Shine

local Hook = Shine.Hook
local SGUI = Shine.GUI
local IsType = Shine.IsType

local Clamp = math.Clamp
local Clock = os.clock
local Floor = math.floor
local Max = math.max
local pairs = pairs
local select = select
local StringExplode = string.Explode
local StringFormat = string.format
local StringGSub = string.gsub
local StringUTF8Length = string.UTF8Length
local StringUTF8Sub = string.UTF8Sub
local TableConcat = table.concat
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
	Opacity = 0.4 --How opaque should the chatbox be?
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

	function ChatElement:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName )
		Plugin.GUIChat = self

		if Plugin.Enabled then
			Plugin:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName )
		end

		OldAddMessage( self, PlayerColour, PlayerName, MessageColour, MessageName )

		if Plugin.Enabled and Plugin.Visible then
			local JustAdded = self.messages[ #self.messages ]
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

local LayoutData = {
	Sizes = {
		ChatBox = Vector( 800, 350, 0 ),
		InnerBox = Vector( 760, 280, 0 ),
		TextBox = Vector( 720, 40, 0 ),
		SettingsButton = Vector( 36, 36, 0 ),
		SettingsClosed = Vector( 0, 350, 0 ),
		Settings = Vector( 350, 350, 0 ),
		Slider = Vector( 250, 32, 0 )
	},

	Positions = {
		Border = Vector( 20, 20, 0 ),
		ModeText = Vector( 70, -25, 0 ),
		Scrollbar = Vector( 2, 0, 0 ),
		SettingsButton = Vector( -56, -43, 0 ),
		Settings = Vector( 0, 0, 0 ),
		TextBox = Vector( 74, -45, 0 ),
		Title = Vector( 30, 10, 0 ),
		AutoClose = Vector( 30, 50, 0 ),
		AutoDelete = Vector( 30, 90, 0 ),
		SmoothScroll = Vector( 30, 130, 0 ),
		MessageMemoryText = Vector( 30, 170, 0 ),
		MessageMemory = Vector( 30, 210, 0 ),
		OpacityText = Vector( 30, 240, 0 ),
		Opacity = Vector( 30, 280, 0 )
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
local TextScale = Vector( 1, 1, 0 )
local Clear = Colour( 0, 0, 0, 0 )

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
	return self.UseTinyFont and Fonts.kAgencyFB_Tiny or Fonts.kAgencyFB_Small
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
	--For some reason, some people don't have this. Without it, we can't do anything...
	if not self.GUIChat.inputItem then
		Shine:AddErrorReport( "GUIChat is missing its inputItem!",
			"Type: %s. inputItem: %s. messages: %s.", true, type( self.GUIChat ),
			tostring( self.GUIChat.inputItem ), tostring( self.GUIChat.messages ) )

		Shine:UnloadExtension( "chatbox" )

		return
	end

	local UIScale = GUIScale( Vector( 1, 1, 1 ) )
	local ScalarScale = GUIScale( 1 )

	local ScreenWidth = Client.GetScreenWidth()
	local ScreenHeight = Client.GetScreenHeight()

	local WidthMult = Clamp( ScreenWidth / 1920, 0.7, 1 )
	local HeightMult = Clamp( ScreenHeight / 1080, 0.7, 1 )

	local FourToThreeHeight = ( ScreenWidth / 4 ) * 3
	--Use a more boxy box for 4:3 monitors.
	if FourToThreeHeight == ScreenHeight then
		WidthMult = WidthMult * 0.72
	end

	UIScale.x = UIScale.x * WidthMult
	UIScale.y = UIScale.y * HeightMult

	self.UseTinyFont = ScreenWidth <= 1366

	local Opacity = self.Config.Opacity
	UpdateOpacity( self, Opacity )

	local ChatBoxPos = self.GUIChat.inputItem:GetPosition() - Vector( 0, 100 * ScalarScale, 0 )

	--Invisible background.
	local DummyPanel = SGUI:Create( "Panel" )
	DummyPanel:SetupFromTable{
		Anchor = "BottomLeft",
		Size = VectorMultiply( LayoutData.Sizes.ChatBox, UIScale ),
		Pos = ChatBoxPos,
		Colour = Clear,
		Draggable = true,
		IsSchemed = false
	}

	--Double click the title bar to return it to the default position.
	function DummyPanel:ReturnToDefaultPos()
		self:SetPos( ChatBoxPos )
	end

	--If, for some reason, there's an error in a panel hook, then this is removed.
	--We don't want to leave the mouse showing if that happens.
	DummyPanel:CallOnRemove( function()
		if self.IgnoreRemove then return end

		if self.Visible then
			SGUI:EnableMouse( false )
			self.Visible = false
			self.GUIChat:SetIsVisible( true )
		end

		TableEmpty( self.Messages )
	end )

	self.MainPanel = DummyPanel

	local BoxSize = VectorMultiply( LayoutData.Sizes.InnerBox, UIScale )

	--Panel for messages.
	local Box = SGUI:Create( "Panel", DummyPanel )
	Box:SetupFromTable{
		Anchor = "TopLeft",
		ScrollbarPos = LayoutData.Positions.Scrollbar,
		ScrollbarHeightOffset = 0,
		Scrollable = true,
		AllowSmoothScroll = self.Config.SmoothScroll,
		StickyScroll = true,
		Size = BoxSize,
		Colour = LayoutData.Colours.HalfOpacity.Inner,
		Pos = VectorMultiply( LayoutData.Positions.Border, UIScale ),
		ScrollbarWidthMult = WidthMult,
		IsSchemed = false
	}
	Box.BufferAmount = 5

	self.ChatBox = Box

	--Create, not Panel:Add as we don't want the border to scroll!
	local Border = SGUI:Create( "Panel", Box )
	Border:SetupFromTable{
		Size = VectorMultiply( LayoutData.Sizes.ChatBox, UIScale ),
		Anchor = "TopLeft",
		Pos = VectorMultiply( -LayoutData.Positions.Border, UIScale ),
		Colour = LayoutData.Colours.StandardOpacity.Border,
		BlockMouse = true,
		IsSchemed = false
	}
	Border.Background:SetInheritsParentStencilSettings( false )
	Border.Background:SetStencilFunc( GUIItem.Equal )

	local Font = self:GetFont()

	--Shows either "All:"" or "Team:"
	local ModeText = Border:Add( "Label" )
	ModeText:SetupFromTable{
		Anchor = "BottomLeft",
		Pos = VectorMultiply( LayoutData.Positions.ModeText, UIScale ),
		TextAlignmentX = GUIItem.Align_Max,
		TextAlignmentY = GUIItem.Align_Center,
		Font = Font,
		Colour = LayoutData.Colours.ModeText,
		IsSchemed = false
	}
	if not self.UseTinyFont then
		ModeText:SetTextScale( ScalarScale * TextScale )
	end

	self.ModeText = ModeText

	self.Border = Border

	local SettingsPos = VectorMultiply( LayoutData.Positions.SettingsButton, UIScale )
	local TextEntrySize = VectorMultiply( LayoutData.Sizes.TextBox, UIScale )
	TextEntrySize.x = TextEntrySize.x + SettingsPos.x - 5

	--Where messages are entered.
	local TextEntry = SGUI:Create( "TextEntry", DummyPanel )
	TextEntry:SetupFromTable{
		Size = TextEntrySize,
		Anchor = "BottomLeft",
		Pos = VectorMultiply( LayoutData.Positions.TextBox, UIScale ),
		Text = "",
		StickyFocus = true,
		FocusColour = LayoutData.Colours.HalfOpacity.TextFocus,
		DarkColour = LayoutData.Colours.HalfOpacity.TextDark,
		BorderColour = LayoutData.Colours.TextBorder,
		TextColour = LayoutData.Colours.Text,
		Font = Font,
		IsSchemed = false
	}
	if not self.UseTinyFont then
		TextEntry:SetTextScale( ScalarScale * TextScale )
	end

	TextEntry.InnerBox:SetColor( LayoutData.Colours.HalfOpacity.TextDark )

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

	local SettingsButton = SGUI:Create( "Button", DummyPanel )
	SettingsButton:SetupFromTable{
		Anchor = "BottomRight",
		Size = VectorMultiply( LayoutData.Sizes.SettingsButton, UIScale ),
		Pos = VectorMultiply( LayoutData.Positions.SettingsButton, UIScale ),
		Text = ">",
		ActiveCol = LayoutData.Colours.HalfOpacity.ButtonActive,
		InactiveCol = LayoutData.Colours.HalfOpacity.ButtonInActive,
		IsSchemed = false
	}

	function SettingsButton:DoClick()
		Plugin:OpenSettings( DummyPanel, UIScale, ScalarScale )
	end

	SettingsButton:SetTooltip( "Opens/closes the chatbox settings." )

	self.SettingsButton = SettingsButton

	return true
end

local function CreateCheckBox( self, SettingsPanel, UIScale, ScalarScale, Pos, Size, Checked, Label )
	local CheckBox = SettingsPanel:Add( "CheckBox" )
	CheckBox:SetupFromTable{
		Pos = VectorMultiply( Pos, UIScale ),
		Size = VectorMultiply( Size, UIScale ),
		CheckedColour = LayoutData.Colours.Checked,
		BackgroundColour = LayoutData.Colours.CheckBack,
		Checked = Checked,
		Font = self:GetFont(),
		TextColour = LayoutData.Colours.ModeText,
		IsSchemed = false
	}
	CheckBox:AddLabel( Label )

	if not self.UseTinyFont then
		CheckBox:SetTextScale( ScalarScale * TextScale )
	end

	return CheckBox
end

local function CreateLabel( self, SettingsPanel, UIScale, ScalarScale, Pos, Text )
	local Label = SettingsPanel:Add( "Label" )
	Label:SetupFromTable{
		Pos = VectorMultiply( Pos, UIScale ),
		Font = self:GetFont(),
		Text = Text,
		Colour = LayoutData.Colours.ModeText,
		IsSchemed = false
	}

	if not self.UseTinyFont then
		Label:SetTextScale( ScalarScale * TextScale )
	end

	return Label
end

local function CreateSlider( self, SettingsPanel, UIScale, ScalarScale, Pos, Value )
	local Slider = SettingsPanel:Add( "Slider" )
	Slider:SetupFromTable{
		Pos = VectorMultiply( Pos, UIScale ),
		Value = Value,
		HandleColour = LayoutData.Colours.Checked,
		LineColour = LayoutData.Colours.ModeText,
		DarkLineColour = LayoutData.Colours.HalfOpacity.TextDark,
		Font = self:GetFont(),
		TextColour = LayoutData.Colours.ModeText,
		Size = VectorMultiply( LayoutData.Sizes.Slider, UIScale ),
		IsSchemed = false,
		Padding = SliderTextPadding * ScalarScale
	}

	if not self.UseTinyFont then
		Slider:SetTextScale( ScalarScale * TextScale )
	end

	return Slider
end

function Plugin:CreateSettings( DummyPanel, UIScale, ScalarScale )
	local Font = self:GetFont()

	local SettingsPanel = SGUI:Create( "Panel", DummyPanel )
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

	CreateLabel( self, SettingsPanel, UIScale, ScalarScale,
		LayoutData.Positions.Title, "Settings" )

	local AutoClose = CreateCheckBox( self, SettingsPanel, UIScale, ScalarScale,
		LayoutData.Positions.AutoClose, LayoutData.Sizes.SettingsButton,
		self.Config.AutoClose, "Auto close after sending." )

	local function UpdateConfigValue( Key, Value )
		if self.Config[ Key ] == Value then return false end

		self.Config[ Key ] = Value
		self:SaveConfig()

		return true
	end

	function AutoClose:OnChecked( Value )
		UpdateConfigValue( "AutoClose", Value )
	end

	local AutoDelete = CreateCheckBox( self, SettingsPanel, UIScale, ScalarScale,
		LayoutData.Positions.AutoDelete, LayoutData.Sizes.SettingsButton,
		self.Config.DeleteOnClose, "Auto delete on close." )

	function AutoDelete:OnChecked( Value )
		UpdateConfigValue( "DeleteOnClose", Value )
	end

	local SmoothScroll = CreateCheckBox( self, SettingsPanel, UIScale, ScalarScale,
		LayoutData.Positions.SmoothScroll, LayoutData.Sizes.SettingsButton,
		self.Config.SmoothScroll, "Use smooth scrolling." )

	function SmoothScroll:OnChecked( Value )
		if not UpdateConfigValue( "SmoothScroll", Value ) then return end
		Plugin.ChatBox:SetAllowSmoothScroll( Value )
	end

	CreateLabel( self, SettingsPanel, UIScale, ScalarScale,
		LayoutData.Positions.MessageMemoryText, "Message memory" )

	local MessageMemory = CreateSlider( self, SettingsPanel, UIScale, ScalarScale,
		LayoutData.Positions.MessageMemory, self.Config.MessageMemory )
	MessageMemory:SetBounds( 10, 100 )

	function MessageMemory:OnValueChanged( Value )
		UpdateConfigValue( "MessageMemory", Value )
	end

	CreateLabel( self, SettingsPanel, UIScale, ScalarScale,
		LayoutData.Positions.OpacityText, "Opacity (%)" )

	local Opacity = CreateSlider( self, SettingsPanel, UIScale, ScalarScale,
		LayoutData.Positions.Opacity, self.Config.Opacity * 100 )
	Opacity:SetBounds( 0, 100 )

	function Opacity:OnValueChanged( Value )
		Value = Value * 0.01

		if not UpdateConfigValue( "Opacity", Value ) then return end

		UpdateOpacity( self, Value )

		SettingsPanel:SetColour( LayoutData.Colours.StandardOpacity.Settings )

		Plugin.ChatBox:SetColour( LayoutData.Colours.HalfOpacity.Inner )
		Plugin.Border:SetColour( LayoutData.Colours.StandardOpacity.Border )

		Plugin.TextEntry:SetFocusColour( LayoutData.Colours.HalfOpacity.TextFocus )
		Plugin.TextEntry:SetDarkColour( LayoutData.Colours.HalfOpacity.TextDark )

		Plugin.SettingsButton:SetActiveCol( LayoutData.Colours.HalfOpacity.ButtonActive )
		Plugin.SettingsButton:SetInactiveCol( LayoutData.Colours.HalfOpacity.ButtonInActive )
	end
end

function Plugin:OpenSettings( DummyPanel, UIScale, ScalarScale )
	if not SGUI.IsValid( Plugin.SettingsPanel ) then
		self:CreateSettings( DummyPanel, UIScale, ScalarScale )
	end

	local SettingsButton = self.SettingsButton
	if SettingsButton.Expanding then return end

	SettingsButton.Expanding = true

	local SettingsPanel = Plugin.SettingsPanel
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

		Plugin.SettingsButton:SetText( Expanded and "<" or ">" )
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
		local PreText = Message.Pre:GetText()
		local PreCol = Message.Pre:GetColour()

		--Take out any new line characters, we'll re-wrap the text for the new size when we add the message back.
		local MessageText = StringGSub( Message.Message:GetText(), "\n", " " )
		local MessageCol = Message.Message:GetColour()

		Recreate[ i ] = { PreText = PreText, PreCol = PreCol,
			MessageText = MessageText, MessageCol = MessageCol }
	end

	--Recreate the entire chat box, it's easier than rescaling.
	self.IgnoreRemove = true
	self.MainPanel:Destroy()
	self.IgnoreRemove = nil
	if not self:CreateChatbox() then return end

	TableEmpty( Messages )

	if not self.Visible then
		self.MainPanel:SetIsVisible( false )
	end

	for i = 1, #Recreate do
		local Message = Recreate[ i ]
		self:AddMessage( Message.PreCol, Message.PreText,
			Message.MessageCol, Message.MessageText )
	end
end

--[[
	Wraps text to fit the size limit. Used for long words...

	Returns two strings, first one fits entirely on one line, the other may not, and should be
	added to the next word.
]]
local function TextWrap( Label, Text, XPos, MaxWidth )
	local i = 1
	local FirstLine = Text
	local SecondLine = ""
	local Length = StringUTF8Length( Text )

	--Character by character, extend the text until it exceeds the width limit.
	repeat
		local CurText = StringUTF8Sub( Text, 1, i )

		--Once it reaches the limit, we go back a character, and set our first and second line results.
		if XPos + Label:GetTextWidth( CurText ) > MaxWidth then
			FirstLine = StringUTF8Sub( Text, 1, i - 1 )
			SecondLine = StringUTF8Sub( Text, i )

			break
		end

		i = i + 1
	until i >= Length

	return FirstLine, SecondLine
end

--[[
	Word wraps text, adding new lines where the text exceeds the width limit.

	This time, it shouldn't freeze the game...
]]
local function WordWrap( Label, Text, XPos, MaxWidth )
	local Words = StringExplode( Text, " " )
	local StartIndex = 1
	local Lines = {}
	local i = 1

	--While loop, as the size of the Words table may increase.
	while i <= #Words do
		local CurText = TableConcat( Words, " ", StartIndex, i )

		if XPos + Label:GetTextWidth( CurText ) > MaxWidth then
			--This means one word is wider than the whole chatbox, so we need to cut it part way through.
			if StartIndex == i then
				local FirstLine, SecondLine = TextWrap( Label, CurText, XPos, MaxWidth )

				Lines[ #Lines + 1 ] = FirstLine

				--Add the second line to the next word, or as a new next word if none exists.
				if Words[ i + 1 ] then
					Words[ i + 1 ] = StringFormat( "%s %s", SecondLine, Words[ i + 1 ] )
				else
					Words[ i + 1 ] = SecondLine
				end

				StartIndex = i + 1
			else
				Lines[ #Lines + 1 ] = TableConcat( Words, " ", StartIndex, i - 1 )

				--We need to jump back a step, as we've still got another word to check.
				StartIndex = i
				i = i - 1
			end
		elseif i == #Words then --We're at the end!
			Lines[ #Lines + 1 ] = CurText
		end

		i = i + 1
	end

	Label:SetText( TableConcat( Lines, "\n" ) )
end

local IntToColour

--[[
	Adds a message to the chatbox.

	Inputs are derived from the GUIChat inputs as we want to maintain compatability.

	Theoretically, we can make messages with any number of colours, but for now this will do.
]]
function Plugin:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName )
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

	--I've decided not to scale this text, scaling blurs or pixelates and it's very hard to read.
	local UIScale = 1

	IntToColour = IntToColour or ColorIntToColor

	local Messages = self.Messages
	local LastMessage = Messages[ #Messages ]

	local PreLabel, MessageLabel, ReUse

	local NextIndex = #Messages + 1

	--We've gone past the message memory limit.
	if NextIndex > self.Config.MessageMemory then
		local FirstMessage = TableRemove( Messages, 1 )
		ReUse = FirstMessage

		PreLabel = FirstMessage.Pre
		MessageLabel = FirstMessage.Message

		--local Height = Max( PreLabel:GetTextHeight(), MessageLabel:GetTextHeight() )
		local Height = Messages[ 1 ].Pre:GetPos().y

		--Move all messages up to compensate for the removal.
		for i = 1, #Messages do
			local MessageTable = Messages[ i ]

			local PrePos = MessageTable.Pre:GetPos()
			local MessagePos = MessageTable.Message:GetPos()

			MessageTable.Pre:SetPos( Vector( PrePos.x, PrePos.y - Height, 0 ) )
			MessageTable.Message:SetPos( Vector( MessagePos.x, MessagePos.y - Height, 0 ) )
		end
	else
		PreLabel = self.ChatBox:Add( "Label" )
		MessageLabel = self.ChatBox:Add( "Label" )
	end

	local PrePos, PostPos

	--Now calculate the next message's position, it's important to do this after moving old ones up.
	--Otherwise the scrollbar would increase its size thinking there's text further down.
	if not LastMessage then
		PrePos = Vector( 5, 5, 0 )
	else
		local LastPre = LastMessage.Pre
		PrePos = Vector( 5, LastPre:GetPos().y + LastMessage.Message:GetTextHeight() + 2, 0 )
	end

	--Why did they use int for the first colour, then colour object for the second?
	if IsType( PlayerColour, "number" ) then
		PlayerColour = IntToColour( PlayerColour )
	end

	PreLabel:SetAnchor( GUIItem.Left, GUIItem.Top )
	PreLabel:SetFont( self.UseTinyFont and Fonts.kAgencyFB_Tiny or Fonts.kAgencyFB_Small )
	PreLabel:SetColour( PlayerColour )
	PreLabel:SetTextScale( TextScale * UIScale )
	PreLabel:SetText( PlayerName )
	PreLabel:SetPos( PrePos )

	MessageLabel:SetAnchor( GUIItem.Left, GUIItem.Top )
	MessageLabel:SetFont( self.UseTinyFont and Fonts.kAgencyFB_Tiny or Fonts.kAgencyFB_Small )
	MessageLabel:SetTextScale( TextScale * UIScale )
	MessageLabel:SetColour( MessageColour )
	MessageLabel:SetText( MessageName )

	local ChatBox = self.ChatBox

	if MessageName:find( "[^%s]" ) then
		MessageName = StringTrim( MessageName )

		MessageLabel:SetText( MessageName )

		local ChatBoxSize = self.ChatBox:GetSize().x
		local XPos = PrePos.x + 5 + PreLabel:GetTextWidth()

		if XPos + MessageLabel:GetTextWidth( MessageName ) > ChatBoxSize then
			WordWrap( MessageLabel, MessageName, XPos, ChatBoxSize )
		end
	end

	local MessagePos = Vector( PrePos.x + 5 + PreLabel:GetTextWidth(), PrePos.y, 0 )
	MessageLabel:SetPos( MessagePos )

	if SGUI.IsValid( ChatBox.Scrollbar ) then
		ChatBox:SetMaxHeight( MessageLabel:GetPos().y + MessageLabel:GetSize().y
			+ ChatBox.BufferAmount )
	end

	--Reuse the removed message table if there was one.
	Messages[ #Messages + 1 ] = ReUse or { Pre = PreLabel, Message = MessageLabel }
end

--[[
	Closes the chat box. Basically sets the invisible main panel to invisible.

	Yep, that's right.
]]
function Plugin:CloseChat()
	if not SGUI.IsValid( self.MainPanel ) then return end

	self.MainPanel:SetIsVisible( false )
	self.GUIChat:SetIsVisible( true ) --Allow the GUIChat messages to show.

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
	if not SGUI.IsValid( self.TextEntry ) or not SGUI.IsValid( self.ModeText ) then
		if SGUI.IsValid( self.MainPanel ) then
			self.IgnoreRemove = true
			self.MainPanel:Destroy()
			self.IgnoreRemove = nil
		end

		if not self:CreateChatbox() then
			return
		end
	end

	--The little text to the left of the text entry.
	self.ModeText:SetText( self.TeamChat and "Team:" or "All:" )

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
	self.ModeText = nil
	self.Border = nil
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
