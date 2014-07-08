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

		if self.messages then
			for Index, Element in pairs( self.messages ) do
				--There's non-table elements in here???
				if IsType( Element, "table" ) then
					Element.Background:SetIsVisible( Vis )
				end
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
		if Plugin.Enabled then
			Plugin:AddMessage( PlayerColour, PlayerName, MessageColour, MessageName )
		end

		return OldAddMessage( self, PlayerColour, PlayerName, MessageColour, MessageName )
	end

	local OldInsert = table.insert

	--This is hilariously hacky, but it should work just fine.
	function table.insert( ... )
		local Table = select( 1, ... )

		if Plugin.GUIChat and Table == Plugin.GUIChat.messages then
			local Message = select( 2, ... )

			--This is called when the message is added to the GUIChat's message list.
			if IsType( Message, "table" ) and Message.Background and Plugin.Enabled and Plugin.Visible then
				Message.Background:SetIsVisible( false )
			end
		end

		return OldInsert( ... )
	end
end

--We hook the class here for certain functions before we find the actual instance of it.
Hook.Add( "Think", "ChatBoxHook", function()
	if GUIChat then
		Plugin:HookChat( GUIChat )

		Hook.Remove( "Think", "ChatBoxHook" )
	end
end )

local Hooked

function Plugin:Initialise()
	if not Hooked then
		Shine.Hook.SetupGlobalHook( "ClientUI.EvaluateUIVisibility", "EvaluateUIVisibility", "PassivePost" )

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

local ChatBoxSize = Vector( 800, 350, 0 )
local CloseButtonSize = Vector( 16, 16, 0 )
local InnerBoxSize = Vector( 760, 280, 0 )
local TextBoxSize = Vector( 720, 40, 0 )
local SettingsButtonSize = Vector( 36, 36, 0 )
local SettingsClosedSize = Vector( 0, 350, 0 )
local SettingsSize = Vector( 350, 350, 0 )
local SliderSize = Vector( 250, 32, 0 )

local BorderPos = Vector( 20, 20, 0 )
local CloseButtonPos = Vector( -1, -1, 0 ) 
local ModeTextPos = Vector( 65, -25, 0 )
local ScrollbarPos = Vector( 2, 0, 0 )
local SettingsButtonPos = Vector( -48, -43, 0 )
local SettingsPos = Vector( 0, 0, 0 )
local TextBoxPos = Vector( 74, -45, 0 )

local TitlePos = Vector( 30, 10, 0 )
local AutoClosePos = Vector( 30, 50, 0 )
local AutoDeletePos = Vector( 30, 90, 0 )
local SmoothScrollPos = Vector( 30, 130, 0 )
local MessageMemoryTextPos = Vector( 30, 170, 0 )
local MessageMemoryPos = Vector( 30, 210, 0 )
local OpacityTextPos = Vector( 30, 240, 0 )
local OpacityPos = Vector( 30, 280, 0 )

local SliderTextPadding = 20

local TextScale = Vector( 1, 1, 0 )

local BorderCol = Colour( 0.6, 0.6, 0.6, 0.4 )
local InnerCol = Colour( 0.2, 0.2, 0.2, 0.8 )
local SettingsCol = Colour( 0.6, 0.6, 0.6, 0.4 )

local ModeTextCol = Colour( 1, 1, 1, 1 )

local TextDarkCol = Colour( 0.2, 0.2, 0.2, 0.8 )--Colour( 0.5, 0.5, 0.5, 1 )
local TextFocusCol = Colour( 0.2, 0.2, 0.2, 0.8 )
local TextBorderCol = Colour( 0, 0, 0, 0 )
local TextCol = Colour( 1, 1, 1, 1 )

local ButtonActiveCol = Colour( 0.5, 0.5, 0.5, 0.8 )
local ButtonInActiveCol = Colour( 0.2, 0.2, 0.2, 0.8 )

local CheckBackCol = Colour( 0.2, 0.2, 0.2, 1 )
local CheckedCol = Colour( 0.8, 0.6, 0.1, 1 ) 

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

	--[[if ScreenWidth < 1600 then
		ScalarScale = ScalarScale * WidthMult
	end]]

	self.UseTinyFont = ScreenWidth <= 1366

	local Opacity = self.Config.Opacity
	local ScaledOpacity = AlphaScale( Opacity )

	BorderCol.a = Opacity
	InnerCol.a = ScaledOpacity
	SettingsCol.a = Opacity
	TextDarkCol.a = ScaledOpacity
	TextFocusCol.a = ScaledOpacity
	ButtonActiveCol.a = ScaledOpacity
	ButtonInActiveCol.a = ScaledOpacity

	local ChatBoxPos = self.GUIChat.inputItem:GetPosition() - Vector( 0, 100 * ScalarScale, 0 )

	--Invisible background.
	local DummyPanel = SGUI:Create( "Panel" )
	DummyPanel:SetupFromTable{
		Anchor = "BottomLeft",
		Size = VectorMultiply( ChatBoxSize, UIScale ),
		Pos = ChatBoxPos,
		Colour = Clear,
		Draggable = true,
		IsSchemed = false
	}

	--Double click the title bar to return it to the default position.
	function DummyPanel:ReturnToDefaultPos()
		self:SetPos( ChatBoxPos )
	end

	self.MainPanel = DummyPanel

	local BoxSize = VectorMultiply( InnerBoxSize, UIScale )

	--Panel for messages.
	local Box = SGUI:Create( "Panel", DummyPanel )
	Box:SetupFromTable{
		Anchor = "TopLeft",
		ScrollbarPos = ScrollbarPos,
		ScrollbarHeightOffset = 0,
		Scrollable = true,
		AllowSmoothScroll = self.Config.SmoothScroll,
		StickyScroll = true,
		Size = BoxSize,
		Colour = InnerCol,
		Pos = VectorMultiply( BorderPos, UIScale ),
		ScrollbarWidthMult = WidthMult,
		IsSchemed = false
	}
	Box.BufferAmount = 5

	self.ChatBox = Box

	--Create, not Panel:Add as we don't want the border to scroll!
	local Border = SGUI:Create( "Panel", Box )
	Border:SetupFromTable{
		Size = VectorMultiply( ChatBoxSize, UIScale ),
		Anchor = "TopLeft",
		Pos = VectorMultiply( -BorderPos, UIScale ),
		Colour = BorderCol,
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
		Pos = VectorMultiply( ModeTextPos, UIScale ),
		TextAlignmentX = GUIItem.Align_Max,
		TextAlignmentY = GUIItem.Align_Center,
		Font = Font,
		Colour = ModeTextCol,
		IsSchemed = false
	}
	if not self.UseTinyFont then
		ModeText:SetTextScale( ScalarScale * TextScale )
	end

	self.ModeText = ModeText

	self.Border = Border

	local SettingsPos = VectorMultiply( SettingsButtonPos, UIScale )
	local TextEntrySize = VectorMultiply( TextBoxSize, UIScale )
	TextEntrySize.x = TextEntrySize.x + SettingsPos.x - 5

	--Where messages are entered.
	local TextEntry = SGUI:Create( "TextEntry", DummyPanel )
	TextEntry:SetupFromTable{
		Size = TextEntrySize,
		Anchor = "BottomLeft",
		Pos = VectorMultiply( TextBoxPos, UIScale ),
		--TextScale = ScalarScale * TextScale,
		Text = "",
		StickyFocus = true,
		FocusColour = TextFocusCol,
		DarkColour = TextDarkCol,
		BorderColour = TextBorderCol,
		TextColour = TextCol,
		Font = Font,
		IsSchemed = false
	}
	if not self.UseTinyFont then
		TextEntry:SetTextScale( ScalarScale * TextScale )
	end

	TextEntry.InnerBox:SetColor( TextDarkCol )

	--Send the message when the client presses enter.
	function TextEntry:OnEnter()
		local Text = self:GetText()

		--Don't go sending blank messages.
		if #Text > 0 and Text:find( "[^%s]" ) then
			Shine.SendNetworkMessage( "ChatClient", 
				BuildChatClientMessage( Plugin.TeamChat, Text:sub( 1, kMaxChatLength ) ), true )
		end

		self:SetText( "" )

		if Plugin.Config.AutoClose then
			Plugin:CloseChat()
		end
	end

	--We don't want to allow characters after hitting the max length message.
	function TextEntry:ShouldAllowChar( Char )
		local Text = self:GetText()

		if #Text >= kMaxChatLength then
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
		Size = VectorMultiply( SettingsButtonSize, UIScale ),
		Pos = VectorMultiply( SettingsButtonPos, UIScale ),
		Text = ">",
		ActiveCol = ButtonActiveCol,
		InactiveCol = ButtonInActiveCol,
		IsSchemed = false
	}

	function SettingsButton:DoClick()
		Plugin:OpenSettings( DummyPanel, UIScale, ScalarScale )
	end

	self.SettingsButton = SettingsButton

	return true
end

function Plugin:CreateSettings( DummyPanel, UIScale, ScalarScale )
	local Font = self:GetFont()

	local SettingsPanel = SGUI:Create( "Panel", DummyPanel )
	SettingsPanel:SetupFromTable{
		Anchor = "TopRight",
		Pos = VectorMultiply( SettingsPos, UIScale ),
		Scrollable = true,
		Size = VectorMultiply( SettingsClosedSize, UIScale ),
		Colour = SettingsCol,
		ShowScrollbar = false,
		IsSchemed = false
	}

	self.SettingsPanel = SettingsPanel

	local Title = SettingsPanel:Add( "Label" )
	Title:SetupFromTable{
		Pos = VectorMultiply( TitlePos, UIScale ),
		Font = Font,
		Text = "Settings",
		Colour = ModeTextCol,
		--TextScale = ScalarScale * TextScale,
		IsSchemed = false
	}
	if not self.UseTinyFont then
		Title:SetTextScale( ScalarScale * TextScale )
	end

	local AutoClose = SettingsPanel:Add( "CheckBox" )
	AutoClose:SetupFromTable{
		Pos = VectorMultiply( AutoClosePos, UIScale ),
		Size = VectorMultiply( SettingsButtonSize, UIScale ),
		CheckedColour = CheckedCol,
		BackgroundColour = CheckBackCol,
		Checked = self.Config.AutoClose,
		Font = Font,
		TextColour = ModeTextCol,
		--TextScale = ScalarScale * TextScale,
		IsSchemed = false
	}
	AutoClose:AddLabel( "Auto close after sending." )
	if not self.UseTinyFont then
		AutoClose:SetTextScale( ScalarScale * TextScale )
	end

	function AutoClose:OnChecked( Value )
		if Value == Plugin.Config.AutoClose then return end
		
		Plugin.Config.AutoClose = Value

		Plugin:SaveConfig()
	end

	local AutoDelete = SettingsPanel:Add( "CheckBox" )
	AutoDelete:SetupFromTable{
		Pos = VectorMultiply( AutoDeletePos, UIScale ),
		Size = VectorMultiply( SettingsButtonSize, UIScale ),
		CheckedColour = CheckedCol,
		BackgroundColour = CheckBackCol,
		Checked = self.Config.DeleteOnClose,
		Font = Font,
		TextColour = ModeTextCol,
		--TextScale = ScalarScale * TextScale,
		IsSchemed = false
	}
	AutoDelete:AddLabel( "Auto delete on close." )
	if not self.UseTinyFont then
		AutoDelete:SetTextScale( ScalarScale * TextScale )
	end

	function AutoDelete:OnChecked( Value )
		if Value == Plugin.Config.DeleteOnClose then return end
		
		Plugin.Config.DeleteOnClose = Value

		Plugin:SaveConfig()
	end

	local SmoothScroll = SettingsPanel:Add( "CheckBox" )
	SmoothScroll:SetupFromTable{
		Pos = VectorMultiply( SmoothScrollPos, UIScale ),
		Size = VectorMultiply( SettingsButtonSize, UIScale ),
		CheckedColour = CheckedCol,
		BackgroundColour = CheckBackCol,
		Checked = self.Config.SmoothScroll,
		Font = Font,
		TextColour = ModeTextCol,
		--TextScale = ScalarScale * TextScale,
		IsSchemed = false
	}
	SmoothScroll:AddLabel( "Use smooth scrolling." )
	if not self.UseTinyFont then
		SmoothScroll:SetTextScale( ScalarScale * TextScale )
	end

	function SmoothScroll:OnChecked( Value )
		if Value == Plugin.Config.SmoothScroll then return end
		
		Plugin.Config.SmoothScroll = Value

		Plugin.ChatBox:SetAllowSmoothScroll( Value )

		Plugin:SaveConfig()
	end

	local MessageMemoryText = SettingsPanel:Add( "Label" )
	MessageMemoryText:SetupFromTable{
		Pos = VectorMultiply( MessageMemoryTextPos, UIScale ),
		Font = Font,
		Text = "Message memory",
		Colour = ModeTextCol,
		--TextScale = ScalarScale * TextScale,
		IsSchemed = false
	}
	if not self.UseTinyFont then
		MessageMemoryText:SetTextScale( ScalarScale * TextScale )
	end

	local MessageMemory = SettingsPanel:Add( "Slider" )
	MessageMemory:SetupFromTable{
		Pos = VectorMultiply( MessageMemoryPos, UIScale ),
		Value = self.Config.MessageMemory,
		HandleColour = CheckedCol,
		LineColour = ModeTextCol,
		DarkLineColour = TextDarkCol,
		Font = Font,
		TextColour = ModeTextCol,
		Size = VectorMultiply( SliderSize, UIScale ),
		--TextScale = ScalarScale * TextScale,
		IsSchemed = false,
		Padding = SliderTextPadding * ScalarScale
	}
	MessageMemory:SetBounds( 10, 100 )
	if not self.UseTinyFont then
		MessageMemory:SetTextScale( ScalarScale * TextScale )
	end

	function MessageMemory:OnValueChanged( Value )
		if Plugin.Config.MessageMemory == Value then return end
		
		Plugin.Config.MessageMemory = Value

		Plugin:SaveConfig()
	end

	local OpacityText = SettingsPanel:Add( "Label" )
	OpacityText:SetupFromTable{
		Pos = VectorMultiply( OpacityTextPos, UIScale ),
		Font = Font,
		Text = "Opacity (%)",
		Colour = ModeTextCol,
		--TextScale = ScalarScale * TextScale,
		IsSchemed = false
	}
	if not self.UseTinyFont then
		OpacityText:SetTextScale( ScalarScale * TextScale )
	end

	local Opacity = SettingsPanel:Add( "Slider" )
	Opacity:SetupFromTable{
		Pos = VectorMultiply( OpacityPos, UIScale ),
		Value = self.Config.Opacity * 100,
		HandleColour = CheckedCol,
		LineColour = ModeTextCol,
		DarkLineColour = TextDarkCol,
		Font = Font,
		TextColour = ModeTextCol,
		Size = VectorMultiply( SliderSize, UIScale ),
		--TextScale = ScalarScale * TextScale,
		IsSchemed = false,
		Padding = SliderTextPadding * ScalarScale
	}
	Opacity:SetBounds( 0, 100 )
	if not self.UseTinyFont then
		Opacity:SetTextScale( ScalarScale * TextScale )
	end

	function Opacity:OnValueChanged( Value )
		Value = Value * 0.01

		if Plugin.Config.Opacity == Value then return end
		
		Plugin.Config.Opacity = Value

		Plugin:SaveConfig()

		local ScaledOpacity = AlphaScale( Value )

		BorderCol.a = Value
		InnerCol.a = ScaledOpacity
		SettingsCol.a = Value
		TextDarkCol.a = ScaledOpacity
		TextFocusCol.a = ScaledOpacity
		ButtonActiveCol.a = ScaledOpacity
		ButtonInActiveCol.a = ScaledOpacity

		SettingsPanel:SetColour( SettingsCol )

		Plugin.ChatBox:SetColour( InnerCol )
		Plugin.Border:SetColour( BorderCol )

		Plugin.TextEntry:SetFocusColour( TextFocusCol )
		Plugin.TextEntry:SetDarkColour( TextDarkCol )

		Plugin.SettingsButton:SetActiveCol( ButtonActiveCol )
		Plugin.SettingsButton:SetInactiveCol( ButtonInActiveCol )
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

	if not SettingsButton.Expanded then
		local Start = VectorMultiply( SettingsClosedSize, UIScale )
		local End = VectorMultiply( SettingsSize, UIScale )
		local Element = SettingsPanel.Background

		SettingsPanel:SetIsVisible( true )

		SettingsPanel:SizeTo( Element, Start, End, 0, 0.5, function( Panel )
			SettingsPanel:SetSize( End )
			SettingsButton.Expanded = true

			Plugin.SettingsButton:SetText( "<" )

			SettingsButton.Expanding = false
		end )
	else
		local End = VectorMultiply( SettingsClosedSize, UIScale )
		local Start = VectorMultiply( SettingsSize, UIScale )
		local Element = SettingsPanel.Background

		SettingsPanel:SizeTo( Element, Start, End, 0, 0.5, function( Panel )
			SettingsPanel:SetSize( End )
			SettingsButton.Expanded = false

			SettingsPanel:SetIsVisible( false )

			Plugin.SettingsButton:SetText( ">" )

			SettingsButton.Expanding = false
		end )
	end
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
		local MessageText = Message.Message:GetText():gsub( "\n", " " )
		local MessageCol = Message.Message:GetColour()

		Recreate[ i ] = { PreText = PreText, PreCol = PreCol, MessageText = MessageText, MessageCol = MessageCol }
	end

	--Recreate the entire chat box, it's easier than rescaling.
	self.MainPanel:Destroy()
	if not self:CreateChatbox() then return end

	TableEmpty( Messages )

	if not self.Visible then
		self.MainPanel:SetIsVisible( false )
	end

	for i = 1, #Recreate do
		local Message = Recreate[ i ]
		self:AddMessage( Message.PreCol, Message.PreText, Message.MessageCol, Message.MessageText )
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

	--Character by character, extend the text until it exceeds the width limit.
	repeat
		local CurText = Text:UTF8Sub( 1, i )

		--Once it reaches the limit, we go back a character, and set our first and second line results.
		if XPos + Label:GetTextWidth( CurText ) > MaxWidth then
			FirstLine = Text:UTF8Sub( 1, i - 1 )
			SecondLine = Text:UTF8Sub( i )

			break
		end

		i = i + 1
	until i >= Text:UTF8Length()

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

		local ChatboxSize = self.ChatBox:GetSize().x
		local XPos = PrePos.x + 5 + PreLabel:GetTextWidth()

		if XPos + MessageLabel:GetTextWidth( MessageName ) > ChatboxSize then
			WordWrap( MessageLabel, MessageName, XPos, ChatboxSize )
		end
	end

	local MessagePos = Vector( PrePos.x + 5 + PreLabel:GetTextWidth(), PrePos.y, 0 )
	MessageLabel:SetPos( MessagePos )

	if SGUI.IsValid( ChatBox.Scrollbar ) then
		ChatBox:SetMaxHeight( MessageLabel:GetPos().y + MessageLabel:GetSize().y + ChatBox.BufferAmount )
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
			self.MainPanel:Destroy()
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

	self.TextEntry:SetFocusColour( TextFocusCol )
	self.TextEntry:SetDarkColour( TextDarkCol )
	self.TextEntry:SetBorderColour( TextBorderCol )
	self.TextEntry:SetTextColour( TextCol )

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
	
	self.MainPanel:Destroy()

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
EnableCommand:AddParam{ Type = "boolean", Optional = true, Default = function() return not Plugin.Enabled end }

Shine.Hook.Add( "OnMapLoad", "NotifyAboutChatBox", function()
	Shine.AddStartupMessage( "Shine has a chatbox that you can enable/disable by entering \"sh_chatbox\" into the console." )
end )
