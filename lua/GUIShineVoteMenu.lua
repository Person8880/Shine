--[[
	Shine's vote menu.
	Based upon the request menu in NS2.
]]

Shine = Shine or {}

class 'GUIShineVoteMenu' (GUIScript)

local Ceil = math.ceil
local Cos = math.cos
local Pi = math.pi

local OpenSound = "sound/NS2.fev/common/checkbox_on"
Client.PrecacheLocalSound( OpenSound )
local function OnOpenVoteMenu()
	Shared.PlaySound( nil, OpenSound )
end

local ClickSound = "sound/NS2.fev/common/button_enter"
Client.PrecacheLocalSound( ClickSound )
local function OnClickVoteOption()
	Shared.PlaySound( nil, ClickSound )
end

local TimeLastMessageSend = 0

local function GetCanSendVote()
	return TimeLastMessageSend + 2 < Shared.GetTime()
end

local BackgroundSize = GUIScale( Vector( 190, 48, 0 ) )
local KeyBindXOffset = GUIScale( 16 )

local Padding = GUIScale( 0 )

local FontName = "fonts/AgencyFB_small.fnt"
local FontScale = GUIScale( 1 )

local ScaleVector = Vector( 1, 1, 1 ) * FontScale

local MenuSize = GUIScale( Vector( 256, 256, 0 ) )

local ButtonClipping = GUIScale( 32 )

local ButtonMaxXOffset = GUIScale( 32 )

local MenuTexture =
{
	[ kMarineTeamType ] = "ui/marine_request_menu.dds",
	[ kAlienTeamType ] = "ui/alien_request_menu.dds",
	[ kNeutralTeamType ] = "ui/marine_request_menu.dds",
}

local BackgroundTexture = 
{
	[ kMarineTeamType ] = "ui/marine_request_button.dds",
	[ kAlienTeamType ] = "ui/alien_request_button.dds",
	[ kNeutralTeamType ] = "ui/marine_request_button.dds",
}

local BackgroundTextureHighlight = 
{
	[ kMarineTeamType ] = "ui/marine_request_button_highlighted.dds",
	[ kAlienTeamType ] = "ui/alien_request_button_highlighted.dds",
	[ kNeutralTeamType ] = "ui/marine_request_button_highlighted.dds",
}

local function CreateMenuButton( self, TeamType, Name, Align, Index, MaxIndex, DoClick )
	Index = Index + ( kMaxRequestsPerSide - MaxIndex ) *.5
	
	Align = Align or GUIItem.Left

	local Background = GetGUIManager():CreateGraphicItem()
	Background:SetSize( BackgroundSize )
	Background:SetTexture( BackgroundTexture[ TeamType ] )
	Background:SetAnchor( Align, GUIItem.Top )
	Background:SetLayer( kGUILayerPlayerHUDForeground1 )
	
	local Pos = Vector( 0, 0, 0 )
	local Direction = -1    
	if Align == GUIItem.Left then        
		Pos.x = -BackgroundSize.x
		Direction = 1
	end
	
	Pos.y = ( Index - 1 ) * ( BackgroundSize.y + Padding )
	local Offset = Cos( Clamp( ( Index - 1 ) / ( kMaxRequestsPerSide - 1 ), 0, 1 ) * Pi * 2 ) * ButtonMaxXOffset + ButtonClipping
	Pos.x = Pos.x + Direction * Offset
	
	Background:SetPosition( Pos )
	
	local Description = GetGUIManager():CreateTextItem()
	Description:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Description:SetTextAlignmentX( GUIItem.Align_Center )
	Description:SetTextAlignmentY( GUIItem.Align_Center )
	Description:SetFontName( FontName )
	Description:SetScale( ScaleVector )
	Description:SetText( Name )

	self.Background:AddChild( Background )
	Background:AddChild( Description )
	
	return { Background = Background, Description = Description, DoClick = DoClick }
end

local function SendRequest( MapName )
	if GetCanSendVote() then
		if not Shine.SentVote then
			Shared.ConsoleCommand( "sh_vote "..MapName )
			TimeLastMessageSend = Shared.GetTime()
			Shine.SentVote = true
		else
			Shared.ConsoleCommand( "sh_revote "..MapName )
			TimeLastMessageSend = Shared.GetTime()
		end
		return true
	end
	
	return false
end

function GUIShineVoteMenu:Initialize()
	self.TeamType = PlayerUI_GetTeamType()
	self.PlayerClass = PlayerUI_GetPlayerClassName()

	if self.Background then GUI.DestroyItem( self.Background ) end

	self.Background = GetGUIManager():CreateGraphicItem()
	self.Background:SetAnchor( GUIItem.Middle, GUIItem.Center )
	self.Background:SetSize( MenuSize )
	self.Background:SetPosition( -MenuSize * .5 )
	self.Background:SetTexture( MenuTexture[ self.TeamType ] )
	self.Background:SetIsVisible( false )
	
	self.MenuButtons = {}
end

function GUIShineVoteMenu:ClearOptions()
	local MenuButtons = self.MenuButtons

	for i = 1, #MenuButtons do
		GUI.DestroyItem( MenuButtons[ i ].Background )
		MenuButtons[ i ] = nil
	end
end

local function GenericClick( Command )
	if GetCanSendVote() then
		Shared.ConsoleCommand( Command )
		TimeLastMessageSend = Shared.GetTime()

		return true
	end

	return false
end

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
	Scramble = function()
		return GenericClick( "sh_votescramble" )
	end,
	Unstuck = function()
		return GenericClick( "sh_unstuck" )
	end,
	MOTD = function()
		return GenericClick( "sh_motd" )
	end
}

function GUIShineVoteMenu:Populate( ActivePlugins )
	local NumPlugins = #ActivePlugins
	local HalfNum = Ceil( NumPlugins * 0.5 )

	local MenuButtons = self.MenuButtons

	for i = 1, HalfNum do
		if not ActivePlugins[ i ] then break end
		if i > kMaxRequestsPerSide then break end
		
		MenuButtons[ #MenuButtons + 1 ] = CreateMenuButton( self, self.TeamType, ActivePlugins[ i ], 
			GUIItem.Left, i, HalfNum, ClickFuncs[ ActivePlugins[ i ] ] )
	end

	for i = 1, HalfNum do
		if not ActivePlugins[ i + HalfNum ] then break end
		if i > kMaxRequestsPerSide then break end
		
		MenuButtons[ #MenuButtons + 1 ] = CreateMenuButton( self, self.TeamType, ActivePlugins[ i + HalfNum ], 
			GUIItem.Right, i, HalfNum, ClickFuncs[ ActivePlugins[ i + HalfNum ] ] )
	end

	self.MainMenu = true
end

function GUIShineVoteMenu:PopulateMaps()
	local Maps = Shine.Maps
	if not Maps then 
		return 
	end
	
	local NumMaps = #Maps
	local HalfMaps = Ceil( NumMaps * 0.5 )

	local MenuButtons = self.MenuButtons

	for i = 1, HalfMaps do
		local Map = Maps[ i ]
		if not Map then break end
		if i > kMaxRequestsPerSide then break end
		
		MenuButtons[ #MenuButtons + 1 ] = CreateMenuButton( self, self.TeamType, Map, GUIItem.Left, i, HalfMaps, function() return SendRequest( Map ) end )
	end

	for i = 1, HalfMaps do
		local Map = Maps[ i + HalfMaps ]
		if not Map then break end
		if i > kMaxRequestsPerSide then break end

		MenuButtons[ #MenuButtons + 1 ] = CreateMenuButton( self, self.TeamType, Map, GUIItem.Right, i, HalfMaps, function() return SendRequest( Map ) end )
	end

	self.EndTime = Shine.EndTime

	self.MainMenu = false
end

function GUIShineVoteMenu:CreateVoteButton()
	local Background = GetGUIManager():CreateGraphicItem()
	Background:SetSize( BackgroundSize )
	Background:SetTexture( BackgroundTexture[ self.TeamType or PlayerUI_GetTeamType() ] )
	Background:SetAnchor( GUIItem.Middle, GUIItem.Top )
	Background:SetPosition( Vector( -BackgroundSize.x * .5, -BackgroundSize.y - Padding, 0 ) )
	
	local Text = GetGUIManager():CreateTextItem()
	Text:SetTextAlignmentX( GUIItem.Align_Center )
	Text:SetTextAlignmentY( GUIItem.Align_Center )
	Text:SetFontName( FontName )
	Text:SetScale( ScaleVector )
	Text:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Text:SetText( "Vote" )
	
	self.Background:AddChild( Background )
	Background:AddChild( Text )
	
	self.VoteButton = { Background = Background, Text = Text, 
		DoClick = function() 
			if self.MainMenu then
				self:ClearOptions()
				self:PopulateMaps()
				Text:SetText( "Back" )

				return true
			else
				self:ClearOptions()
				self:Populate( Shine.ActivePlugins )
				Text:SetText( "Vote" )

				return true
			end
		end
	}
end

function GUIShineVoteMenu:SetIsVisible( Visible )
	if not self.Background then return end

	local WasVisible = self.Background:GetIsVisible()
	if WasVisible == Visible then return end
	
	if Visible then
		OnOpenVoteMenu()
		MouseTracker_SetIsVisible( true )
		self.Background:SetIsVisible( true )
	else
		MouseTracker_SetIsVisible( false )
		self.Background:SetIsVisible( false )
	end    
end

function GUIShineVoteMenu:Uninitialize()
	self:SetIsVisible( false )

	if self.Background then    
		GUI.DestroyItem( self.Background )        
	end
	
	self.Background = nil
	self.MenuButtons = {}
end

function GUIShineVoteMenu:Update( DeltaTime )
	if not self.Background:GetIsVisible() then return end

	if Shine.EndTime < Shared.GetTime() then
		if self.VoteButton then
			if not self.MainMenu then
				self:ClearOptions()
				self:Populate( Shine.ActivePlugins )

				GUI.DestroyItem( self.VoteButton.Background )

				self.VoteButton = nil
			else
				GUI.DestroyItem( self.VoteButton.Background )

				self.VoteButton = nil
			end
		end
	end
	
	local MouseX, MouseY = Client.GetCursorPosScreen()
	
	if self.VoteButton then
		if GUIItemContainsPoint( self.VoteButton.Background, MouseX, MouseY ) then
			self.VoteButton.Background:SetTexture( BackgroundTextureHighlight[ self.TeamType ] )
		else
			self.VoteButton.Background:SetTexture( BackgroundTexture[ self.TeamType ] )
		end
	end

	for i = 1, #self.MenuButtons do
		local Button = self.MenuButtons[ i ]
		
		if GUIItemContainsPoint( Button.Background, MouseX, MouseY ) then
			Button.Background:SetTexture( BackgroundTextureHighlight[ self.TeamType ] )
		else
			Button.Background:SetTexture( BackgroundTexture[ self.TeamType ] )
		end
	end
end

function GUIShineVoteMenu:SendKeyEvent( Key, Down )
	if self.NextClick and self.NextClick > Shared.GetTime() then
		return false
	end

	local HitButton = false
	
	if ChatUI_EnteringChatMessage() then
		self:SetIsVisible( false )
		return false
	end
	
	local MouseX, MouseY = Client.GetCursorPosScreen()

	if self.Background:GetIsVisible() then
		if Key == InputKey.MouseButton0 then
			if self.VoteButton and GUIItemContainsPoint( self.VoteButton.Background, MouseX, MouseY ) then
				if self.VoteButton.DoClick() then
					OnClickVoteOption()

					self.NextClick = Shared.GetTime() + 1

					return true
				end
			else
				for i = 1, #self.MenuButtons do
					local Button = self.MenuButtons[ i ]

					if GUIItemContainsPoint( Button.Background, MouseX, MouseY ) then
						if Button.DoClick() then
							OnClickVoteOption()
						end

						HitButton = true

						break
					end
				end
			end
		end
		
		if ( not HitButton and Key == InputKey.MouseButton0 ) or Key == InputKey.MouseButton1 then
			self:SetIsVisible( false )

			return false
		end
	end

	local Success = false
	
	if HitButton then
		if Down then
			if not self.Background:GetIsVisible() then
				self:SetIsVisible( true )
			else
				self:SetIsVisible( false )
			end
		end

		self.NextClick = Shared.GetTime() + 1

		Success = true
	end
	
	return Success
end
