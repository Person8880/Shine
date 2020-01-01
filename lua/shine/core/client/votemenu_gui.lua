--[[
	Shine's vote menu.
	Based upon the request menu in NS2.
]]

local Shine = Shine

local Hook = Shine.Hook
local SGUI = Shine.GUI
local IsType = Shine.IsType
local Locale = Shine.Locale

local Ceil = math.ceil
local Cos = math.cos
local Max = math.max
local Pi = math.pi

local VoteMenu = {}
Shine.VoteMenu = VoteMenu

SGUI:AddMixin( VoteMenu, "Visibility" )

local OpenSound = "sound/NS2.fev/common/checkbox_on"
Client.PrecacheLocalSound( OpenSound )

local ButtonSize = Vector( 190, 48, 0 )
local ButtonClipping = 32
local MaxButtonOffset = 32
local Padding = 0

local MenuSize = Vector( 256, 256, 0 )

local FontName = Fonts.kAgencyFB_Small
local FontScale = Vector( 1, 1, 0 )
local TextCol = Colour( 1, 1, 1, 1 )

local MenuTexture = {
	[ kMarineTeamType ] = "ui/marine_request_menu.dds",
	[ kAlienTeamType ] = "ui/alien_request_menu.dds",
	[ kNeutralTeamType ] = "ui/marine_request_menu.dds",
}

local ButtonTexture = {
	[ kMarineTeamType ] = "ui/marine_request_button.dds",
	[ kAlienTeamType ] = "ui/alien_request_button.dds",
	[ kNeutralTeamType ] = "ui/marine_request_button.dds",
}

local ButtonHighlightTexture = {
	[ kMarineTeamType ] = "ui/marine_request_button_highlighted.dds",
	[ kAlienTeamType ] = "ui/alien_request_button_highlighted.dds",
	[ kNeutralTeamType ] = "ui/marine_request_button_highlighted.dds",
}

local MaxRequestsPerSide = 5
local EasingTime = 0.15

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

		VoteMenu:ForceHide()

		return true
	end

	return false
end
VoteMenu.GenericClick = GenericClick

local ClickFuncs = {
	Shuffle = function()
		return GenericClick( "sh_voterandom" )
	end,
	[ "Map Vote" ] = function()
		local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
		if not Enabled then return GenericClick( "sh_votemap" ) end

		return MapVote:HandleVoteMenuButtonClick( VoteMenu )
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

	local ScreenWidth = Client.GetScreenWidth()
	local ScreenHeight = Client.GetScreenHeight()

	local WidthMult = Max( ScreenWidth / 1920, 1 )
	local HeightMult = Max( ScreenHeight / 1080, 1 )

	local function Scale( Value, ForFont )
		local Scale
		if ScreenWidth > 1920 then
			Scale = SGUI.TenEightyPScale( Value )
		else
			Scale = GUIScale( Value )
		end

		if IsType( Scale, "number" ) then
			return Scale * WidthMult
		end

		if ForFont then
			return Scale * HeightMult
		end

		Scale.x = Scale.x * WidthMult
		Scale.y = Scale.y * HeightMult

		return Scale
	end

	local BackSize = Scale( MenuSize )

	if ScreenHeight <= SGUI.ScreenHeight.Normal then
		self.Font = FontName
		self.TextScale = Scale( FontScale, true )
	elseif ScreenHeight <= SGUI.ScreenHeight.Large then
		self.Font = Fonts.kAgencyFB_Medium
		self.TextScale = FontScale
	else
		self.Font = Fonts.kAgencyFB_Huge
		self.TextScale = FontScale * 0.6
	end

	local Background = SGUI:Create( "Panel" )
	Background:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Background:SetSize( BackSize )
	Background:SetPos( -BackSize * 0.5 )
	Background:SetTexture( MenuTexture[ self.TeamType ] )
	Background:SetIsSchemed( false )
	Background.AlwaysInMouseFocus = true

	self.Background = Background

	self.Buttons = self.Buttons or {}
	self.Buttons.Side = self.Buttons.Side or {}

	self.ButtonIndex = 0

	self.ButtonSize = Scale( ButtonSize )
	self.ButtonClipping = Scale( ButtonClipping )
	self.MaxButtonOffset = Scale( MaxButtonOffset )

	self:SetPage( self.ActivePage or "Main" )

	if self.Visible == nil then
		self.Visible = true
	end
end

Hook.Add( "PostLoadScript:lua/GUICrosshair.lua", "VoteMenu", function( Reload )
	local GUICrosshair = _G.GUICrosshair
	if not GUICrosshair then return end

	local OldUpdate = GUICrosshair.Update
	function GUICrosshair:Update( DeltaTime )
		if VoteMenu.Visible then
			-- Hide the crosshair when the vote menu is visible.
			if self.crosshairs then
				self.crosshairs:SetIsVisible( false )
			end
			if self.reloadDial then
				self.reloadDial:SetIsVisible( false )
			end
			return
		end

		return OldUpdate( self, DeltaTime )
	end
end )

function VoteMenu:SetIsVisible( Bool, IgnoreAnim )
	if self.Visible == Bool then return false end

	if not SGUI.IsValid( self.Background ) then
		self:Create()
	end

	if Bool then
		self:UpdateTeamType()

		Shared.PlaySound( nil, OpenSound )

		SGUI:EnableMouse( true )

		self.Background:SetIsVisible( true )

		-- Set the page to ensure only the correct buttons show after making the panel visible.
		self:SetPage( self.ActivePage or "Main", IgnoreAnim )
	else
		SGUI:EnableMouse( false )

		self.Background:SetIsVisible( false )
	end

	self.Visible = Bool

	return true
end

function VoteMenu:GetIsVisible()
	return self.Visible or false
end

VoteMenu:BindVisibilityToEvents( "OnHelpScreenDisplay", "OnHelpScreenHide" )

function VoteMenu:PlayerKeyPress( Key, Down )
	if not self.Visible then return end

	local Enabled, Chatbox = Shine:IsExtensionEnabled( "chatbox" )
	local ChatboxEnabled = Enabled and Chatbox.Visible

	if ChatUI_EnteringChatMessage() or ChatboxEnabled then
		self:ForceHide()

		return
	end

	local IsCloseKey = Key == InputKey.MouseButton0 or Key == InputKey.MouseButton1
		or Key == InputKey.Escape or GetIsBinding( Key, "Use" )

	if Down and IsCloseKey then
		self:ForceHide()

		return
	end
end

--Call this hook after SGUI so the buttons can halt the input first.
Hook.Add( "PlayerKeyPress", "VoteMenuKeyPress", function( Key, Down )
	return VoteMenu:PlayerKeyPress( Key, Down )
end, 1 )

function VoteMenu:Think( DeltaTime )
	if not self.Visible then return end

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

-- Close when logging in/out of a command structure to avoid mouse problems.
Hook.Add( "OnCommanderLogout", "VoteMenuLogout", function()
	VoteMenu:ForceHide()
end )
Hook.Add( "OnCommanderLogin", "VoteMenuLogin", function()
	VoteMenu:ForceHide()
end )

function VoteMenu:OnResolutionChanged( OldX, OldY, NewX, NewY )
	if not SGUI.IsValid( self.Background ) then return end

	local Buttons = self.Buttons
	local SideButtons = Buttons.Side
	local TopButton = Buttons.Top
	local BottomButton = Buttons.Bottom

	if SGUI.IsValid( TopButton ) then
		TopButton:Destroy()
		Buttons.Top = nil
	end

	if SGUI.IsValid( BottomButton ) then
		BottomButton:Destroy()
		Buttons.Bottom = nil
	end

	for Key, Button in pairs( SideButtons ) do
		if SGUI.IsValid( Button ) then
			Button:Destroy()
		end

		SideButtons[ Key ] = nil
	end

	self.Background:Destroy()

	self:Create()

	if not self.Visible then
		self.Visible = true
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
function VoteMenu:SetPage( Name, IgnoreAnim )
	local Page = self.Pages[ Name ]
	if not Page or not Page.Populate then return end

	self:Clear()

	Page.Populate( self )

	self:SortSideButtons( IgnoreAnim )
	self.ActivePage = Name
end

local function ClearButton( self, Button )
	if not SGUI.IsValid( Button ) then return end

	self:MarkAsSelected( Button, false )
	Button:SetIsVisible( false )
	Button:SetTooltip( nil )
	Button.DefaultText = nil
	Button.Plugin = nil
	Button.CheckMarkXScale = nil

	if Button.OnClear then
		Button:OnClear()
		Button.OnClear = nil
	end
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

	ClearButton( self, TopButton )
	ClearButton( self, BottomButton )

	for i = 1, #SideButtons do
		ClearButton( self, SideButtons[ i ] )
	end

	self.ButtonIndex = 0
end

function VoteMenu:SetupButtonForTeam( Button, TeamType )
	Button:SetTexture( ButtonTexture[ TeamType ] )
	Button:SetHighlightTexture( ButtonHighlightTexture[ TeamType ] )
end

--[[
	Updates the textures of all active buttons.
]]
function VoteMenu:UpdateTeamType()
	local TeamType = PlayerUI_GetTeamType()
	self.TeamType = TeamType

	self.Background:SetTexture( MenuTexture[ TeamType ] )

	local Buttons = self.Buttons
	local SideButtons = Buttons.Side
	local TopButton = Buttons.Top
	local BottomButton = Buttons.Bottom

	if SGUI.IsValid( TopButton ) then
		self:SetupButtonForTeam( TopButton, TeamType )
	end

	if SGUI.IsValid( BottomButton ) then
		self:SetupButtonForTeam( BottomButton, TeamType )
	end

	for i = 1, #SideButtons do
		local Button = SideButtons[ i ]

		if SGUI.IsValid( Button ) then
			self:SetupButtonForTeam( Button, TeamType )
		end
	end
end

local White = Colour( 1, 1, 1, 1 )

local function AddButton( self, Pos, Anchor, Text, DoClick )
	local Button = SGUI:Create( "Button", self.Background )
	Button:SetupFromTable{
		Anchor = Anchor,
		Size = self.ButtonSize,
		Pos = Pos,
		ActiveCol = White,
		InactiveCol = White,
		Texture = ButtonTexture[ self.TeamType or PlayerUI_GetTeamType() ],
		HighlightTexture = ButtonHighlightTexture[ self.TeamType or PlayerUI_GetTeamType() ],
		Text = Text,
		Font = self.Font,
		TextScale = self.TextScale,
		TextColour = TextCol,
		DoClick = DoClick,
		IsSchemed = false
	}
	Button:SetHighlightOnMouseOver( true, 1, true )
	Button.ClickDelay = 0

	return Button
end

local function HandleButton( Button, Text, DoClick, StartPos, EndPos )
	Button:SetText( Text )
	Button:SetDoClick( DoClick )
	Button:SetIsVisible( true )

	if not StartPos then return end

	if Shine.Config.AnimateUI then
		Button:SetPos( StartPos )
		Button:MoveTo( nil, nil, EndPos, 0, EasingTime )
	else
		Button:SetPos( EndPos )
	end
end

--[[
	Creates or sets the text/click function of the top button.
]]
function VoteMenu:AddTopButton( Text, DoClick )
	local Buttons = self.Buttons
	local TopButton = Buttons.Top

	local Size = self.ButtonSize
	local StartPos = Vector( -Size.x * 0.5, -Size.y + self.Background:GetSize().y * 0.5, 0 )
	local EndPos = Vector( -Size.x * 0.5, -Size.y, 0 )

	if SGUI.IsValid( TopButton ) then
		HandleButton( TopButton, Text, DoClick, StartPos, EndPos )

		return TopButton
	end

	local Pos = Shine.Config.AnimateUI and StartPos or EndPos
	TopButton = AddButton( self, Pos, "TopMiddle", Text, DoClick )

	Buttons.Top = TopButton

	if Shine.Config.AnimateUI then
		TopButton:MoveTo( nil, nil, EndPos, 0, EasingTime )
	end

	return TopButton
end

--[[
	Creates or sets the text/click function of the bottom button.
]]
function VoteMenu:AddBottomButton( Text, DoClick )
	local Buttons = self.Buttons
	local BottomButton = Buttons.Bottom

	local Size = self.ButtonSize
	local StartPos = Vector( -Size.x * 0.5, -self.Background:GetSize().y * 0.5, 0 )
	local EndPos = Vector( StartPos.x, 0, 0 )

	if SGUI.IsValid( BottomButton ) then
		HandleButton( BottomButton, Text, DoClick, StartPos, EndPos )

		return BottomButton
	end

	local Pos = Shine.Config.AnimateUI and StartPos or EndPos
	BottomButton = AddButton( self, Pos, "BottomMiddle", Text, DoClick )

	Buttons.Bottom = BottomButton

	if Shine.Config.AnimateUI then
		BottomButton:MoveTo( nil, nil, EndPos, 0, EasingTime )
	end

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
		HandleButton( Button, Text, DoClick )

		self.ButtonIndex = Index

		return Button
	end

	Button = AddButton( self, nil, nil, Text, DoClick )
	Buttons[ Index ] = Button

	self.ButtonIndex = Index

	return Button
end

do
	local TickTexture = PrecacheAsset( "ui/checkmark.dds" )

	--[[
		Marks or unmarks a given button as selected.
		Selected buttons have a checkmark added to their right-hand side.
	]]
	function VoteMenu:MarkAsSelected( Button, Selected )
		local HasCheckMark = SGUI.IsValid( Button.CheckMark )

		if Selected and not HasCheckMark then
			local Height = Button:GetSize().y * 0.75

			local CheckMark = SGUI:Create( "Image", Button )
			CheckMark:SetAnchor( "CentreRight" )
			CheckMark:SetSize( Vector2( Height, Height ) )
			CheckMark:SetPos( Vector2(
				-Height * ( Button.CheckMarkXScale or 1 ),
				-Height * 0.5
			) )
			CheckMark:SetTexture( TickTexture )

			Button.CheckMark = CheckMark
		elseif not Selected and HasCheckMark then
			Button.CheckMark:Destroy()
			Button.CheckMark = nil
		end
	end
end

--[[
	Positions a side button based on the number of buttons on the side.
]]
function VoteMenu:PositionButton( Button, Index, MaxIndex, Align, IgnoreAnim )
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

	local Offset = Cos( Clamp( ( Index - 1 ) / ( MaxRequestsPerSide - 1 ),
		0, 1 ) * Pi * 2 ) * self.MaxButtonOffset + self.ButtonClipping

	Pos.x = Pos.x + Direction * Offset

	if not IgnoreAnim and Shine.Config.AnimateUI then
		local Size = self.Background:GetSize()
		Button:SetPos( Vector( Align == GUIItem.Right and -Size.x * 0.5 or 0,
			Size.y * 0.5, 0 ) )
		Button:MoveTo( nil, nil, Pos, 0, EasingTime )
	else
		Button:SetPos( Pos )
		Button:StopMoving()
	end
end

--[[
	This should be called after all side buttons have been added.
]]
function VoteMenu:SortSideButtons( IgnoreAnim )
	local MaxIndex = Ceil( self.ButtonIndex * 0.5 )

	for i = 1, MaxIndex do
		self:PositionButton( i, i, MaxIndex, GUIItem.Left, IgnoreAnim )
	end

	for i = 1, MaxIndex do
		self:PositionButton( i + MaxIndex, i, MaxIndex, GUIItem.Right, IgnoreAnim )
	end
end

function VoteMenu:AddAdminMenuButton()
	self:AddSideButton( Locale:GetPhrase( "Core", "ADMIN_MENU" ), function()
		Shared.ConsoleCommand( "sh_adminmenu" )
		self:ForceHide()
	end )
end

function VoteMenu:GetButtonByPlugin( PluginName )
	if self.ActivePage ~= "Main" then return nil end

	local SideButtons = self.Buttons.Side
	for i = 1, #SideButtons do
		if SideButtons[ i ].Plugin == PluginName then
			return SideButtons[ i ]
		end
	end

	return nil
end

local PluginNames = {
	Shuffle = "voterandom",
	[ "Map Vote" ] = "mapvote",
	Surrender = "votesurrender",
	Unstuck = "unstuck",
	MOTD = "motd"
}

--[[
	Default page.
]]
VoteMenu:AddPage( "Main", function( self )
	local ActivePlugins = Shine.ActivePlugins

	for i = 1, #ActivePlugins do
		local PluginButton = ActivePlugins[ i ]

		local Enabled, Plugin = Shine:IsExtensionEnabled( PluginNames[ PluginButton ] )
		local Text = Locale:GetPhrase( "Core", PluginButton )
		if Enabled then
			Text = Plugin.GetVoteButtonText and Plugin:GetVoteButtonText() or Text
		end

		local Button = self:AddSideButton( Text, ClickFuncs[ PluginButton ] )
		Button.Plugin = PluginButton
		Button.DefaultText = Text

		if Enabled and Plugin and Plugin.OnVoteButtonCreated then
			Plugin:OnVoteButtonCreated( Button, VoteMenu )
		end
	end

	self:AddSideButton( Locale:GetPhrase( "Core", "CLIENT_CONFIG_MENU" ), function()
		Shared.ConsoleCommand( "sh_clientconfigmenu" )
		self:ForceHide()
	end )

	if not self.CanViewAdminMenu then return end

	self:AddAdminMenuButton()
end )

Client.HookNetworkMessage( "Shine_AuthAdminMenu", function( Data )
	VoteMenu.CanViewAdminMenu = Data.CanUseAdminMenu
end )
