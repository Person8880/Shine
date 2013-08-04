--[[
	Shine's vote menu.
	Based upon the request menu in NS2.
]]

local Shine = Shine

local Hook = Shine.Hook
local SGUI = Shine.GUI

local Ceil = math.ceil
local Cos = math.cos
local Pi = math.pi

local VoteMenu = {}
Shine.VoteMenu = VoteMenu

local OpenSound = "sound/NS2.fev/common/checkbox_on"
Client.PrecacheLocalSound( OpenSound )

local ButtonSize = Vector( 190, 48, 0 )
local ButtonClipping = 32
local MaxButtonOffset = 32
local Padding = 0

local MenuSize = Vector( 256, 256, 0 )

local FontName = "fonts/AgencyFB_small.fnt"
local FontScale = Vector( 1, 1, 0 )
local TextCol = Colour( 1, 1, 1, 1 )

local MenuTexture =
{
	[ kMarineTeamType ] = "ui/marine_request_menu.dds",
	[ kAlienTeamType ] = "ui/alien_request_menu.dds",
	[ kNeutralTeamType ] = "ui/marine_request_menu.dds",
}

local ButtonTexture = 
{
	[ kMarineTeamType ] = "ui/marine_request_button.dds",
	[ kAlienTeamType ] = "ui/alien_request_button.dds",
	[ kNeutralTeamType ] = "ui/marine_request_button.dds",
}

local ButtonHighlightTexture = 
{
	[ kMarineTeamType ] = "ui/marine_request_button_highlighted.dds",
	[ kAlienTeamType ] = "ui/alien_request_button_highlighted.dds",
	[ kNeutralTeamType ] = "ui/marine_request_button_highlighted.dds",
}

local MaxRequestsPerSide = 5

VoteMenu.Pages = {}

local NextVoteSend = 0

local function GetCanSendVote()
	local Time = Shared.GetTime()

	if Time > NextVoteSend then
		NextVoteSend = Time + 2

		return true
	end

	return false
end
VoteMenu.GetCanSendVote = GetCanSendVote

local function GenericClick( Command )
	if GetCanSendVote() then
		Shared.ConsoleCommand( Command )

		VoteMenu:SetIsVisible( false )

		return true
	end

	return false
end
VoteMenu.GenericClick = GenericClick

local ClickFuncs = {
	Random = function()
		return GenericClick( "sh_voterandom" )
	end,
	RTV = function()
		return GenericClick( "sh_votemap" )
	end,
	Surrender = function()
		return GenericClick( "sh_votesurrender" )
	end,
	Unstuck = function()
		return GenericClick( "sh_unstuck" )
	end,
	MOTD = function()
		return GenericClick( "sh_motd" )
	end
}

function VoteMenu:Create()
	self.TeamType = PlayerUI_GetTeamType()

	local BackSize = GUIScale( MenuSize )

	local Background = SGUI:Create( "Panel" )
	Background:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Background:SetSize( BackSize )
	Background:SetPos( -BackSize * 0.5 )
	Background:SetTexture( MenuTexture[ self.TeamType ] )

	self.Background = Background

	self.Buttons = self.Buttons or {}
	self.Buttons.Side = self.Buttons.Side or {}

	self.ButtonIndex = 0

	self.TextScale = GUIScale( 1 ) * FontScale
	self.ButtonSize = GUIScale( ButtonSize )
	self.ButtonClipping = GUIScale( ButtonClipping )
	self.MaxButtonOffset = GUIScale( MaxButtonOffset )

	self:SetPage( self.ActivePage or "Main" )

	self.Visible = true
end

function VoteMenu:SetIsVisible( Bool )
	if not SGUI.IsValid( self.Background ) then 
		self:Create() 
	end

	if Bool then
		self:UpdateTeamType()

		Shared.PlaySound( nil, OpenSound )

		if not CommanderUI_IsLocalPlayerCommander() then
			MouseTracker_SetIsVisible( true )
		end

		self.Background:SetIsVisible( true )

		--Set the page to ensure only the correct buttons show after making the panel visible.
		self:SetPage( self.ActivePage or "Main" )
	else
		if not CommanderUI_IsLocalPlayerCommander() then
			MouseTracker_SetIsVisible( false )
		end

		self.Background:SetIsVisible( false )
	end

	self.Visible = Bool
end

function VoteMenu:PlayerKeyPress( Key, Down )
	if not self.Visible then return end

	local Chatbox = Shine.Plugins.chatbox
	local ChatboxEnabled = Chatbox and Chatbox.Enabled and Chatbox.Visible

	if ChatUI_EnteringChatMessage() or ChatboxEnabled then
		self:SetIsVisible( false )

		return
	end

	if Down and Key == InputKey.MouseButton0 or Key == InputKey.MouseButton1 then
		self:SetIsVisible( false )

		return
	end
end

--Call this hook after SGUI so the buttons can halt the input first.
Hook.Add( "PlayerKeyPress", "VoteMenuKeyPress", function( Key, Down )
	return VoteMenu:PlayerKeyPress( Key, Down )
end, 1 )

function VoteMenu:Think( DeltaTime )
	local ActivePage = self.ActivePage

	if not ActivePage then return end
	
	local Think = self.Pages[ ActivePage ].Think

	if Think then
		Think( self, DeltaTime )
	end
end

Hook.Add( "Think", "VoteMenuThink", function( DeltaTime )
	VoteMenu:Think( DeltaTime )
end )

function VoteMenu:OnResolutionChanged( OldX, OldY, NewX, NewY )
	if not SGUI.IsValid( self.Background ) then return end
	
	self.Background:Destroy()

	self:Create()

	if not self.Visible then
		self:SetIsVisible( false )
	end
end

Hook.Add( "OnResolutionChanged", "VoteMenuOnResolutionChanged", function( OldX, OldY, NewX, NewY )
	VoteMenu:OnResolutionChanged( OldX, OldY, NewX, NewY )
end )

--[[
	Adds a page to the menu that can be switched to with VoteMenu:SetPage().
]]
function VoteMenu:AddPage( Name, PopulateFunc, ThinkFunc )
	self.Pages[ Name ] = { Populate = PopulateFunc, Think = ThinkFunc }
end

--[[
	Allows you to extend a page that has already been created.
	Whatever you add will be called after the old populate function.
]]
function VoteMenu:EditPage( Name, ExtraFunc, ExtraThink )
	local Page = self.Pages[ Name ]

	if not Page then return self:AddPage( Name, ExtraFunc, ExtraThink ) end
	
	if ExtraFunc then
		local OldPopulate = Page.Populate

		Page.Populate = function( self )
			OldPopulate( self )
			ExtraFunc( self )
		end
	end
	
	if ExtraThink then
		local OldThink = Page.Think

		if OldThink then
			Page.Think = function( self )
				OldThink( self )
				ExtraThink( self )
			end
		else
			Page.Think = ExtraThink
		end
	end
end

--[[
	Clears out the votemenu, then populate with the given page.
]]
function VoteMenu:SetPage( Name )
	--if Name == self.ActivePage then return end
	
	local Page = self.Pages[ Name ]

	if not Page or not Page.Populate then return end

	self:Clear()

	Page.Populate( self )

	self:SortSideButtons()

	self.ActivePage = Name
end

--[[
	Hides all buttons from view.

	We re-use them, not remove them.
]]
function VoteMenu:Clear()
	local Buttons = self.Buttons
	local SideButtons = Buttons.Side
	local TopButton = Buttons.Top
	local BottomButton = Buttons.Bottom

	if SGUI.IsValid( TopButton ) then
		TopButton:SetIsVisible( false )
	end

	if SGUI.IsValid( BottomButton ) then
		BottomButton:SetIsVisible( false )
	end

	for i = 1, #SideButtons do
		local Button = SideButtons[ i ]

		if SGUI.IsValid( Button ) then
			Button:SetIsVisible( false )
		end
	end

	self.ButtonIndex = 0
end

--[[
	Updates the textures of all active buttons.
]]
function VoteMenu:UpdateTeamType()
	self.TeamType = PlayerUI_GetTeamType()

	self.Background:SetTexture( MenuTexture[ self.TeamType ] )

	local Buttons = self.Buttons
	local SideButtons = Buttons.Side
	local TopButton = Buttons.Top
	local BottomButton = Buttons.Bottom

	if SGUI.IsValid( TopButton ) then
		TopButton:SetTexture( ButtonTexture[ self.TeamType ] )
		TopButton:SetHighlightTexture( ButtonHighlightTexture[ self.TeamType ] )
	end

	if SGUI.IsValid( BottomButton ) then
		BottomButton:SetTexture( ButtonTexture[ self.TeamType ] )
		BottomButton:SetHighlightTexture( ButtonHighlightTexture[ self.TeamType ] )
	end

	for i = 1, #SideButtons do
		local Button = SideButtons[ i ]

		if SGUI.IsValid( Button ) then
			Button:SetTexture( ButtonTexture[ self.TeamType ] )
			Button:SetHighlightTexture( ButtonHighlightTexture[ self.TeamType ] )
		end
	end
end

--[[
	Creates or sets the text/click function of the top button.
]]
function VoteMenu:AddTopButton( Text, DoClick )
	local Buttons = self.Buttons
	local TopButton = Buttons.Top

	if SGUI.IsValid( TopButton ) then
		TopButton:SetText( Text )
		TopButton:SetDoClick( DoClick )
		TopButton:SetIsVisible( true )

		return TopButton
	end

	local Size = self.ButtonSize

	TopButton = SGUI:Create( "Button", self.Background )
	TopButton:SetAnchor( GUIItem.Middle, GUIItem.Top )
	TopButton:SetSize( Size )
	TopButton:SetPos( Vector( -Size.x * 0.5, -Size.y, 0 ) )
	TopButton:SetTexture( ButtonTexture[ self.TeamType or PlayerUI_GetTeamType() ] )
	TopButton:SetHighlightTexture( ButtonHighlightTexture[ self.TeamType or PlayerUI_GetTeamType() ] )
	TopButton:SetHighlightOnMouseOver( true, 1, true )
	TopButton:SetText( Text )
	TopButton:SetFont( FontName )
	TopButton:SetTextScale( self.TextScale )
	TopButton:SetTextColour( TextCol )
	TopButton:SetDoClick( DoClick )
	TopButton:SetLayer( kGUILayerPlayerHUDForeground1 )
	TopButton.ClickDelay = 0

	Buttons.Top = TopButton

	return TopButton
end

--[[
	Creates or sets the text/click function of the bottom button.
]]
function VoteMenu:AddBottomButton( Text, DoClick )
	local Buttons = self.Buttons
	local BottomButton = Buttons.Bottom

	if SGUI.IsValid( BottomButton ) then
		BottomButton:SetText( Text )
		BottomButton:SetDoClick( DoClick )
		BottomButton:SetIsVisible( true )

		return BottomButton
	end

	local Size = self.ButtonSize
	BottomButton = SGUI:Create( "Button", self.Background )
	BottomButton:SetAnchor( GUIItem.Middle, GUIItem.Bottom )
	BottomButton:SetSize( Size )
	BottomButton:SetPos( Vector( -Size.x * 0.5, 0, 0 ) )
	BottomButton:SetTexture( ButtonTexture[ self.TeamType or PlayerUI_GetTeamType() ] )
	BottomButton:SetHighlightTexture( ButtonHighlightTexture[ self.TeamType or PlayerUI_GetTeamType() ] )
	BottomButton:SetHighlightOnMouseOver( true, 1, true )
	BottomButton:SetText( Text )
	BottomButton:SetFont( FontName )
	BottomButton:SetTextScale( self.TextScale )
	BottomButton:SetTextColour( TextCol )
	BottomButton:SetDoClick( DoClick )
	BottomButton:SetLayer( kGUILayerPlayerHUDForeground1 )
	BottomButton.ClickDelay = 0

	Buttons.Bottom = BottomButton

	return BottomButton
end

--[[
	Adds a side button, but does not position it.

	After page population, side buttons are positioned with VoteMenu:SortSideButtons().
]]
function VoteMenu:AddSideButton( Text, DoClick )
	local Buttons = self.Buttons.Side
	local Index = self.ButtonIndex + 1

	local Button = Buttons[ Index ]

	if SGUI.IsValid( Button ) then
		Button:SetText( Text )
		Button:SetDoClick( DoClick )
		Button:SetIsVisible( true )

		self.ButtonIndex = Index

		return Button
	end

	Button = SGUI:Create( "Button", self.Background )
	Button:SetSize( self.ButtonSize )
	Button:SetTexture( ButtonTexture[ self.TeamType or PlayerUI_GetTeamType() ] )
	Button:SetHighlightTexture( ButtonHighlightTexture[ self.TeamType or PlayerUI_GetTeamType() ] )
	Button:SetHighlightOnMouseOver( true, 1, true )
	Button:SetText( Text )
	Button:SetFont( FontName )
	Button:SetTextScale( self.TextScale )
	Button:SetTextColour( TextCol )
	Button:SetDoClick( DoClick )
	Button:SetLayer( kGUILayerPlayerHUDForeground1 )

	Buttons[ Index ] = Button

	self.ButtonIndex = Index

	return Button
end

--[[
	Positions a side button based on the number of buttons on the side.
]]
function VoteMenu:PositionButton( Button, Index, MaxIndex, Align )
	local Button = self.Buttons.Side[ Button ]

	if not SGUI.IsValid( Button ) then return end
	
	Index = Index + ( MaxRequestsPerSide - MaxIndex ) * 0.5

	Button:SetAnchor( Align, GUIItem.Top )

	local Pos = Vector( 0, 0, 0 )
	local Direction = -1    
	if Align == GUIItem.Left then        
		Pos.x = -self.ButtonSize.x
		Direction = 1
	end
	
	Pos.y = ( Index - 1 ) * ( self.ButtonSize.y + Padding )
	local Offset = Cos( Clamp( ( Index - 1 ) / ( MaxRequestsPerSide - 1 ), 0, 1 ) * Pi * 2 ) * self.MaxButtonOffset + self.ButtonClipping
	Pos.x = Pos.x + Direction * Offset

	Button:SetPos( Pos )
end

--[[
	This should be called after all side buttons have been added.
]]
function VoteMenu:SortSideButtons()
	local MaxIndex = Ceil( self.ButtonIndex * 0.5 )

	for i = 1, MaxIndex do
		self:PositionButton( i, i, MaxIndex, GUIItem.Left )
	end

	for i = 1, MaxIndex do
		self:PositionButton( i + MaxIndex, i, MaxIndex, GUIItem.Right )
	end
end

--[[
	Default page.
]]
VoteMenu:AddPage( "Main", function( self )
	local ActivePlugins = Shine.ActivePlugins

	for i = 1, #ActivePlugins do
		local Plugin = ActivePlugins[ i ]

		self:AddSideButton( Plugin, ClickFuncs[ Plugin ] )
	end
end )
