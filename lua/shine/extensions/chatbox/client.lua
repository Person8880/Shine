--[[
	Shine chatbox.

	I can't believe the game doesn't have one.
]]

local Shine = Shine

local Hook = Shine.Hook
local SGUI = Shine.GUI

local Max = math.max
local pairs = pairs
local select = select
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
	SmoothScroll = true --Should the scrolling be smoothed?
}

Plugin.CheckConfig = true
Plugin.SilentConfigSave = true

function Plugin:HookChat( ChatElement )
	function ChatElement:SetIsVisible( Vis )
		if self.Vis == Vis then return end

		self.Vis = Vis

		for Index, Element in pairs( self.messages ) do
			Element.Background:SetIsVisible( Vis )
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
			if Message and Message.Background and Plugin.Enabled and Plugin.Visible then
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

function Plugin:Initialise()
	self.Messages = self.Messages or {}

	self.Enabled = true

	return true
end

--We need the default chat script so we can hide its messages.
function Plugin:Think()
	if self.GUIChat then return end
	
	local Manager = GetGUIManager()
	local Scripts = Manager.scripts

	for Index, Script in pairs( Scripts ) do
		if Script._scriptName == "GUIChat" then
			self.GUIChat = Script

			return
		end
	end
end

local ChatBoxSize = Vector( 800, 340, 0 )
local CloseButtonSize = Vector( 16, 16, 0 )
local InnerBoxSize = Vector( 760, 280, 0 )
local TextBoxSize = Vector( 670, 30, 0 )
local SettingsButtonSize = Vector( 28, 28, 0 )
local SettingsClosedSize = Vector( 0, 300, 0 )
local SettingsSize = Vector( 350, 300, 0 )

local BorderPos = Vector( 20, 20, 0 )
local CloseButtonPos = Vector( -1, -1, 0 ) 
local ModeTextPos = Vector( 65, 320, 0 )
local ScrollbarPos = Vector( 2, 0, 0 )
local SettingsButtonPos = Vector( 752, 306, 0 )
local SettingsPos = Vector( 0, 20, 0 )
local TextBoxPos = Vector( 74, 305, 0 )

local TitlePos = Vector( 30, 10, 0 )
local AutoClosePos = Vector( 30, 50, 0 )
local AutoDeletePos = Vector( 30, 90, 0 )
local SmoothScrollPos = Vector( 30, 130, 0 )
local MessageMemoryTextPos = Vector( 30, 170, 0 )
local MessageMemoryPos = Vector( 30, 210, 0 )

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
	local UIScale = GUIScale( 1 )

	local ChatBoxPos = self.GUIChat.inputItem:GetPosition() - Vector( 0, 100 * UIScale, 0 )

	--Invisible background.
	local DummyPanel = SGUI:Create( "Panel" )
	DummyPanel:SetAnchor( GUIItem.Left, GUIItem.Bottom )
	DummyPanel:SetSize( ChatBoxSize * UIScale )
	DummyPanel:SetPos( ChatBoxPos )
	DummyPanel:SetColour( Clear )
	DummyPanel.UseScheme = false
	--DummyPanel:SetLayer( kGUILayerChat )
	DummyPanel:SetDraggable( true )

	--Double click the title bar to return it to the default position.
	function DummyPanel:ReturnToDefaultPos()
		self:SetPos( ChatBoxPos )
	end

	self.MainPanel = DummyPanel

	local BoxSize = InnerBoxSize * UIScale

	--Panel for messages.
	local Box = SGUI:Create( "Panel", DummyPanel )
	Box:SetAnchor( GUIItem.Left, GUIItem.Top )
	Box:SetScrollbarPos( ScrollbarPos )
	Box:SetScrollbarHeightOffset( 0 )
	Box:SetScrollable()
	Box:SetAllowSmoothScroll( self.Config.SmoothScroll )
	Box:SetStickyScroll( true )
	Box:SetSize( BoxSize )
	Box:SetColour( InnerCol )
	Box:SetPos( BorderPos * UIScale )
	Box.UseScheme = false
	Box.BufferAmount = 5

	self.ChatBox = Box

	--Create, not Panel:Add as we don't want the border to scroll!
	local Border = SGUI:Create( "Panel", Box )
	Border:SetSize( ChatBoxSize * UIScale )
	Border:SetAnchor( GUIItem.Left, GUIItem.Top )
	Border:SetPos( -BorderPos * UIScale )
	Border.Background:SetInheritsParentStencilSettings( false )
	Border.Background:SetStencilFunc( GUIItem.Equal )
	Border.UseScheme = false
	Border:SetColour( BorderCol )
	Border:SetBlockMouse( true )

	--Shows either "All:"" or "Team:"
	local ModeText = Border:Add( "Label" )
	ModeText:SetPos( ModeTextPos * UIScale )
	ModeText:SetTextAlignmentX( GUIItem.Align_Max )
	ModeText:SetTextAlignmentY( GUIItem.Align_Center )
	ModeText:SetFont( "fonts/AgencyFB_small.fnt" )
	ModeText:SetTextScale( UIScale * TextScale )
	ModeText:SetColour( ModeTextCol )

	self.ModeText = ModeText

	self.Border = Border

	--Where messages are entered.
	local TextEntry = SGUI:Create( "TextEntry", DummyPanel )
	TextEntry:SetSize( TextBoxSize * UIScale )
	TextEntry:SetAnchor( GUIItem.Left, GUIItem.Top )
	TextEntry:SetLayer( kGUILayerChat )
	TextEntry:SetPos( TextBoxPos * UIScale )
	TextEntry:SetTextScale( UIScale * TextScale )
	TextEntry:SetText( "" )
	TextEntry:SetStickyFocus( true )
	TextEntry.UseScheme = false

	TextEntry:SetFocusColour( TextFocusCol )
	TextEntry:SetDarkColour( TextDarkCol )
	TextEntry:SetBorderColour( TextBorderCol )
	TextEntry:SetTextColour( TextCol )
	TextEntry:SetFont( "fonts/AgencyFB_small.fnt" )
	TextEntry:SetTextScale( UIScale * TextScale )

	TextEntry.InnerBox:SetColor( TextDarkCol )

	--Send the message when the client presses enter.
	function TextEntry:OnEnter()
		local Text = self:GetText()

		--Don't go sending blank messages.
		if #Text > 0 and Text:find( "[^%s]" ) then
			Client.SendNetworkMessage( "ChatClient", 
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
		if ( Plugin.OpenTime or 0 ) + 0.2 > Shared.GetTime() then
			return false
		end
	end

	self.TextEntry = TextEntry

	local SettingsButton = SGUI:Create( "Button", DummyPanel )
	SettingsButton:SetSize( SettingsButtonSize * UIScale )
	SettingsButton:SetPos( SettingsButtonPos * UIScale )
	SettingsButton:SetText( ">" )
	SettingsButton:SetActiveCol( ButtonActiveCol )
	SettingsButton:SetInactiveCol( ButtonInActiveCol )
	SettingsButton.UseScheme = false

	function SettingsButton:DoClick()
		if not SGUI.IsValid( Plugin.SettingsPanel ) then
			local SettingsPanel = SGUI:Create( "Panel", DummyPanel )
			SettingsPanel:SetAnchor( GUIItem.Right, GUIItem.Top )
			SettingsPanel:SetPos( SettingsPos * UIScale )
			SettingsPanel:SetScrollable()
			SettingsPanel:SetSize( SettingsClosedSize * UIScale )
			SettingsPanel:SetColour( SettingsCol )
			SettingsPanel.UseScheme = false

			Plugin.SettingsPanel = SettingsPanel

			local Title = SettingsPanel:Add( "Label" )
			Title:SetPos( TitlePos * UIScale )
			Title:SetFont( "fonts/AgencyFB_small.fnt" )
			Title:SetText( "Settings" )
			Title:SetColour( ModeTextCol )

			local AutoClose = SettingsPanel:Add( "CheckBox" )
			AutoClose:SetPos( AutoClosePos * UIScale )
			AutoClose:SetSize( SettingsButtonSize * UIScale )
			AutoClose:AddLabel( "Auto close after sending." )
			AutoClose:SetCheckedColour( CheckedCol )
			AutoClose:SetBackgroundColour( CheckBackCol )
			function AutoClose:OnChecked( Value )
				if Value == Plugin.Config.AutoClose then return end
				
				Plugin.Config.AutoClose = Value

				Plugin:SaveConfig()
			end
			AutoClose:SetChecked( Plugin.Config.AutoClose )
			AutoClose:SetFont( "fonts/AgencyFB_small.fnt" )
			AutoClose:SetTextColour( ModeTextCol )
			AutoClose:SetupStencil()

			local AutoDelete = SettingsPanel:Add( "CheckBox" )
			AutoDelete:SetPos( AutoDeletePos * UIScale )
			AutoDelete:SetSize( SettingsButtonSize * UIScale )
			AutoDelete:AddLabel( "Auto delete message on close." )
			AutoDelete:SetCheckedColour( CheckedCol )
			AutoDelete:SetBackgroundColour( CheckBackCol )
			function AutoDelete:OnChecked( Value )
				if Value == Plugin.Config.DeleteOnClose then return end
				
				Plugin.Config.DeleteOnClose = Value

				Plugin:SaveConfig()
			end
			AutoDelete:SetChecked( Plugin.Config.DeleteOnClose )
			AutoDelete:SetFont( "fonts/AgencyFB_small.fnt" )
			AutoDelete:SetTextColour( ModeTextCol )
			AutoDelete:SetupStencil()

			local SmoothScroll = SettingsPanel:Add( "CheckBox" )
			SmoothScroll:SetPos( SmoothScrollPos * UIScale )
			SmoothScroll:SetSize( SettingsButtonSize * UIScale )
			SmoothScroll:AddLabel( "Use smooth scrolling." )
			SmoothScroll:SetCheckedColour( CheckedCol )
			SmoothScroll:SetBackgroundColour( CheckBackCol )
			function SmoothScroll:OnChecked( Value )
				if Value == Plugin.Config.SmoothScroll then return end
				
				Plugin.Config.SmoothScroll = Value

				Plugin.ChatBox:SetAllowSmoothScroll( Value )

				Plugin:SaveConfig()
			end
			SmoothScroll:SetChecked( Plugin.Config.SmoothScroll )
			SmoothScroll:SetFont( "fonts/AgencyFB_small.fnt" )
			SmoothScroll:SetTextColour( ModeTextCol )
			SmoothScroll:SetupStencil()

			local MessageMemoryText = SettingsPanel:Add( "Label" )
			MessageMemoryText:SetPos( MessageMemoryTextPos * UIScale )
			MessageMemoryText:SetFont( "fonts/AgencyFB_small.fnt" )
			MessageMemoryText:SetText( "Message memory" )
			MessageMemoryText:SetColour( ModeTextCol )

			local MessageMemory = SettingsPanel:Add( "Slider" )
			MessageMemory:SetPos( MessageMemoryPos * UIScale )
			MessageMemory:SetBounds( 10, 100 )
			MessageMemory:SetValue( Plugin.Config.MessageMemory )
			MessageMemory:SetHandleColour( CheckedCol )
			MessageMemory:SetLineColour( ModeTextCol )
			MessageMemory:SetDarkLineColour( TextDarkCol )
			MessageMemory:SetFont( "fonts/AgencyFB_small.fnt" )
			MessageMemory:SetTextColour( ModeTextCol )
			function MessageMemory:OnValueChanged( Value )
				if Plugin.Config.MessageMemory == Value then return end
				
				Plugin.Config.MessageMemory = Value

				Plugin:SaveConfig()
			end
		end

		if SettingsButton.Expanding then return end

		SettingsButton.Expanding = true

		local SettingsPanel = Plugin.SettingsPanel

		if not SettingsButton.Expanded then
			local Start = SettingsClosedSize * UIScale
			local End = SettingsSize * UIScale
			local Element = SettingsPanel.Background

			SettingsPanel:SetIsVisible( true )

			SettingsPanel:SizeTo( Element, Start, End, 0, 0.5, function( Panel )
				SettingsPanel:SetSize( SettingsSize * UIScale )
				SettingsButton.Expanded = true

				Plugin.SettingsButton:SetText( "<" )

				SettingsButton.Expanding = false
			end )
		else
			local End = SettingsClosedSize * UIScale
			local Start = SettingsSize * UIScale
			local Element = SettingsPanel.Background

			SettingsPanel:SizeTo( Element, Start, End, 0, 0.5, function( Panel )
				SettingsPanel:SetSize( SettingsClosedSize * UIScale )
				SettingsButton.Expanded = false

				SettingsPanel:SetIsVisible( false )

				Plugin.SettingsButton:SetText( ">" )

				SettingsButton.Expanding = false
			end )
		end
	end

	self.SettingsButton = SettingsButton
end

--Close on pressing escape (it's not hardcoded, unlike Source!)
function Plugin:PlayerKeyPress( Key, Down )
	if Key == InputKey.Escape and self.Visible then
		self:CloseChat()

		return true
	end
end

function Plugin:OnResolutionChanged( OldX, OldY, NewX, NewY )
	local UIScale = GUIScale( 1 )

	if not SGUI.IsValid( self.MainPanel ) then return end

	local Messages = self.Messages
	local Recreate = {}

	for i = 1, #Messages do
		local Message = Messages[ i ]
		local PreText = Message.Pre:GetText()
		local PreCol = Message.Pre:GetColour()

		local MessageText = Message.Message:GetText()
		local MessageCol = Message.Message:GetColour()

		Recreate[ i ] = { PreText = PreText, PreCol = PreCol, MessageText = MessageText, MessageCol = MessageCol }
	end

	--Recreate the entire chat box, it's easier than rescaling.
	self.MainPanel:Destroy()
	self:CreateChatbox()

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
	Word wraps text, adding new lines where the text exceeds the width limit.
]]
local function WordWrap( XPos, Width, Label, LastSpace )
	local StartingChar = ( LastSpace or 0 ) + 1
	local CurWidth = XPos
	local LabelText = Label:GetText()
	local i = LastSpace or 1
	local LastLastSpace

	repeat
		local CurText = LabelText:UTF8Sub( StartingChar, i )
		local CurChar = LabelText:UTF8Sub( i, i )

		if CurChar == " " then
			LastLastSpace = LastSpace
			LastSpace = i
		end

		CurWidth = XPos + Label:GetTextWidth( CurText )
		i = i + 1
	until CurWidth >= Width or i > #LabelText

	--The last space was the last character...
	if LastSpace == i - 1 then
		LastSpace = LastLastSpace
	end

	if not LastSpace or LastSpace == StartingChar - 1 then
		LabelText = LabelText:UTF8Sub( 1, i - 2 ).."\n"..LabelText:UTF8Sub( i - 1 )

		Label:SetText( LabelText )

		return i
	end

	LabelText = LabelText:UTF8Sub( 1, LastSpace - 1 ).."\n"..LabelText:UTF8Sub( LastSpace + 1 )
	Label:SetText( LabelText )

	return LastSpace
end

local IntToColour

local IsType = Shine.IsType

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
	PreLabel:SetFont( "fonts/AgencyFB_small.fnt" )
	PreLabel:SetColour( PlayerColour )
	PreLabel:SetTextScale( TextScale * UIScale )
	PreLabel:SetText( PlayerName )
	PreLabel:SetPos( PrePos )

	MessageLabel:SetAnchor( GUIItem.Left, GUIItem.Top )
	MessageLabel:SetFont( "fonts/AgencyFB_small.fnt" )
	MessageLabel:SetTextScale( TextScale * UIScale )
	MessageLabel:SetColour( MessageColour )
	MessageLabel:SetText( MessageName )

	local ChatboxSize = self.ChatBox:GetSize().x
	local LastSpace
	local XPos = PrePos.x + 5 + PreLabel:GetTextWidth()

	if MessageName:find( "[^%s]" ) then
		while XPos + MessageLabel:GetTextWidth() > ChatboxSize do
			LastSpace = WordWrap( XPos, ChatboxSize, MessageLabel, LastSpace )

			local Text = MessageLabel:GetText()

			if Text:sub( #Text, #Text ) == "\n" then
				Text = Text:sub( 1, #Text - 1 )
				break
			end
		end
	end

	local MessagePos = Vector( PrePos.x + 5 + PreLabel:GetTextWidth(), PrePos.y, 0 )
	MessageLabel:SetPos( MessagePos )

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
	if not self.GUIChat then return end
	
	self.TeamChat = Team

	if not SGUI.IsValid( self.MainPanel ) then
		self:CreateChatbox()
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
	self.OpenTime = Shared.GetTime()

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
	if not Shine.AutoLoadPlugins or not Shine.AutoLoadPlugins[ "chatbox" ] then
		Shine.AddStartupMessage( "Shine has a chatbox that you can enable by entering \"sh_chatbox 1\" into the console." )
	end
end )
