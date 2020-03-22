--[[
	Map vote client.
]]

local Plugin = ...

Plugin.VoteButtonName = "Map Vote"

local MapDataRepository = require "shine/extensions/mapvote/map_data_repository"

local Shine = Shine
local Hook = Shine.Hook
local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local IsType = Shine.IsType
local SharedTime = Shared.GetTime
local StringExplode = string.Explode
local StringFormat = string.format
local TableConcat = table.concat
local TableEmpty = table.Empty

Plugin.VoteAction = table.AsEnum{
	"USE_SERVER_SETTINGS", "OPEN_MENU", "DO_NOT_OPEN_MENU"
}
Plugin.VoteMenuType = table.AsEnum{
	"FULL", "MINIMAL"
}

Plugin.HasConfig = true
Plugin.ConfigName = "MapVote.json"
Plugin.DefaultConfig = {
	OnVoteAction = Plugin.VoteAction.USE_SERVER_SETTINGS,
	VoteMenuType = Plugin.VoteMenuType.FULL,
	LoadModPreviewsInMapGrid = true,
	CloseMenuAfterChoosingMap = true
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

do
	local Validator = Shine.Validator()
	Validator:AddFieldRule( "OnVoteAction", Validator.InEnum( Plugin.VoteAction, Plugin.DefaultConfig.OnVoteAction ) )
	Validator:AddFieldRule( "VoteMenuType", Validator.InEnum( Plugin.VoteMenuType, Plugin.DefaultConfig.VoteMenuType ) )
	Plugin.ConfigValidator = Validator
end

Plugin.ConfigGroup = {
	Icon = SGUI.Icons.Ionicons.Earth
}

Plugin.Maps = {}
Plugin.MapButtons = {}
Plugin.MapVoteCounts = {}
Plugin.EndTime = 0

do
	local RichTextFormat = require "shine/lib/gui/richtext/format"
	local RichTextMessageOptions = {}

	local DurationMessageOptions = {
		Colours = {
			Duration = RichTextFormat.Colours.LightBlue
		}
	}

	for i = 1, #Plugin.DurationMessageKeys do
		RichTextMessageOptions[ Plugin.DurationMessageKeys[ i ] ] = DurationMessageOptions
	end

	local function GetColourForName( Values )
		return RichTextFormat.GetColourForPlayer( Values.TargetName )
	end

	local VoteMessageOptions = {
		Colours = {
			TargetName = GetColourForName,
			MapName = RichTextFormat.Colours.LightBlue
		}
	}
	RichTextMessageOptions[ "NOMINATED_MAP" ] = VoteMessageOptions
	RichTextMessageOptions[ "PLAYER_VOTED" ] = VoteMessageOptions
	RichTextMessageOptions[ "PLAYER_VOTED_PRIVATE" ] = VoteMessageOptions
	RichTextMessageOptions[ "PLAYER_REVOKED_VOTE_PRIVATE" ] = VoteMessageOptions
	RichTextMessageOptions[ "RTV_VOTED" ] = VoteMessageOptions
	RichTextMessageOptions[ "VETO" ] = VoteMessageOptions

	local WinningMapOptions = {
		Colours = {
			MapName = RichTextFormat.Colours.Green
		}
	}
	RichTextMessageOptions[ "WINNER_VOTES" ] = WinningMapOptions
	RichTextMessageOptions[ "WINNER_NEXT_MAP" ] = WinningMapOptions
	RichTextMessageOptions[ "WINNER_CYCLING" ] = WinningMapOptions
	RichTextMessageOptions[ "CHOOSING_RANDOM_MAP" ] = WinningMapOptions
	RichTextMessageOptions[ "MAP_CYCLING" ] = WinningMapOptions
	RichTextMessageOptions[ "EXTENDING_TIME" ] = {
		Colours = {
			Duration = RichTextFormat.Colours.Green
		}
	}

	RichTextMessageOptions[ "VOTES_TIED" ] = {
		Colours = {
			MapNames = RichTextFormat.Colours.Yellow
		}
	}

	Plugin.RichTextMessageOptions = RichTextMessageOptions
end

local MAP_GRID_SWITCH_BACK_HINT = "MapVoteSwitchToVoteMenuHint"
local MAP_GRID_AFTER_MIGRATION_HINT = "MapVoteAfterMapGridMigrationHint"
local MULTIPLE_CHOICE_VOTE_HINT = "MapVoteMultipleChoiceVoteHint"

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	MapDataRepository.Logger = self.Logger

	return true
end

function Plugin:OnFirstThink()
	SGUI.NotificationManager.RegisterHint( MAP_GRID_SWITCH_BACK_HINT, {
		MaxTimes = 1,
		MessageSource = self:GetName(),
		MessageKey = "VOTE_MENU_MAP_GRID_SWITCH_BACK_HINT",
		HintDuration = 10
	} )

	SGUI.NotificationManager.RegisterHint( MAP_GRID_AFTER_MIGRATION_HINT, {
		MaxTimes = 1,
		MessageSource = self:GetName(),
		MessageKey = "MAP_VOTE_MENU_AFTER_MIGRATION_HINT",
		HintDuration = 10
	} )

	SGUI.NotificationManager.RegisterHint( MULTIPLE_CHOICE_VOTE_HINT, {
		MaxTimes = 1,
		MessageSource = self:GetName(),
		MessageKey = "MULTIPLE_CHOICE_VOTE_HINT",
		HintDuration = 10
	} )

	if self:HasLoadedNewConfig() then
		SGUI.NotificationManager.DisableHint( MAP_GRID_AFTER_MIGRATION_HINT )
	end
end

function Plugin:SetLoadModPreviewsInMapGrid( LoadModPreviewsInMapGrid )
	if SGUI.IsValid( self.FullVoteMenu ) then
		self.FullVoteMenu:SetLoadModPreviews( LoadModPreviewsInMapGrid )
	end
end

function Plugin:SetCloseMenuAfterChoosingMap( CloseMenuAfterChoosingMap )
	if SGUI.IsValid( self.FullVoteMenu ) then
		self.FullVoteMenu:SetCloseOnClick( CloseMenuAfterChoosingMap )
	end
end

function Plugin:TimeLeftNotify( Message )
	self:AddChatLine( 0, 0, 0, "", 255, 160, 0, Message )
end

function Plugin:ReceiveTimeLeftNotify( Data )
	self:TimeLeftNotify( self:GetInterpolatedPhrase( "TIME_LEFT_NOTIFY", Data ) )
end

function Plugin:ReceiveRoundLeftNotify( Data )
	self:TimeLeftNotify( self:GetInterpolatedPhrase( "ROUND_LEFT_NOTIFY", Data ) )
end

function Plugin:ReceiveMapCycling( Data )
	self:TimeLeftNotify(
		self:GetInterpolatedPhrase( "CYCLING_NOTIFY", self:PreProcessTranslatedMessage( "MapCycling", Data ) )
	)
end

function Plugin:ReceiveTimeLeftCommand( Data )
	if Data.Duration == 0 then
		self:AddChatLine( 0, 0, 0, "", 255, 255, 255, self:GetPhrase( "MAP_WILL_CYCLE" ) )
		return
	end

	if Data.Duration < 0 then
		self:AddChatLine( 0, 0, 0, "", 255, 255, 255, self:GetPhrase( "NO_CYCLE" ) )
		return
	end

	local Key = Data.Rounds and "ROUNDS_LEFT" or "TIME_LEFT"
	self:AddChatLine( 0, 0, 0, "", 255, 255, 255, self:GetInterpolatedPhrase( Key, Data ) )
end

function Plugin:ReceiveNextMapCommand( Data )
	self:AddChatLine(
		0, 0, 0, "", 255, 255, 255,
		self:GetInterpolatedPhrase(
			"NEXT_MAP_SET_TO", self:PreProcessTranslatedMessage( "NextMapCommand", Data )
		)
	)
end

function Plugin:ReceiveTeamSwitchFail( Data )
	local Key = Data.IsEndVote and "TEAM_CHANGE_FAIL_VOTE" or "TEAM_CHANGE_FAIL_MAP_CHANGE"
	local Phrase = self:GetPhrase( Key )
	self:TimeLeftNotify( Phrase )
end

function Plugin:OnVoteMenuOpen()
	local Time = SharedTime()
	if ( self.NextVoteOptionRequest or 0 ) < Time and not self:IsVoteInProgress() then
		self.NextVoteOptionRequest = Time + 10

		self:SendNetworkMessage( "RequestVoteOptions", {}, true )
	end
end

function Plugin:IsVoteInProgress()
	return ( self.EndTime or 0 ) > SharedTime()
end

function Plugin:HandleVoteMenuButtonClick( VoteMenu )
	if self:IsVoteInProgress() then
		-- If a vote is in progress, make the "Map Vote" button do the
		-- same thing as the "Vote" button at the top.
		VoteMenu:SetPage( "MapVote" )
		return true
	end

	-- Otherwise cast a vote to start a map vote.
	return VoteMenu.GenericClick( "sh_votemap" )
end

Shine.VoteMenu:EditPage( "Main", function( self )
	if Plugin:IsVoteInProgress() then
		self:AddTopButton( Plugin:GetPhrase( "VOTE" ), function()
			self:SetPage( "MapVote" )
		end )
	end
end, function( self )
	local TopButton = self.Buttons.Top

	if Plugin:IsVoteInProgress() then
		if not SGUI.IsValid( TopButton ) or not TopButton:GetIsVisible() then
			self:AddTopButton( Plugin:GetPhrase( "VOTE" ), function()
				self:SetPage( "MapVote" )
			end )
		end
	else
		if SGUI.IsValid( TopButton ) and TopButton:GetIsVisible() then
			TopButton:SetIsVisible( false )
		end
	end
end )

local function SendMapVote( MapName, Revoke )
	Shared.ConsoleCommand( StringFormat( "sh_vote %s%s", MapName, Revoke and " 1" or "" ) )
end

do
	local function ClosePageIfVoteFinished( self )
		if not Plugin:IsVoteInProgress() then
			self:SetPage( "Main" )
			return true
		end

		return false
	end

	local GUIScaled = Units.GUIScaled
	local UnitVector = Units.UnitVector

	local TextureLoader = require "shine/lib/gui/texture_loader"

	local function SetupMapPreview( Button, Map, MapMod )
		local Cleared = false

		function Button:OnHover()
			local ModID = MapMod and tostring( MapMod )

			Plugin.Logger:Debug( "Attempting to load texture for %s/%s", ModID, Map )

			MapDataRepository.GetOverviewImage( ModID, Map, function( MapName, TextureName, Err )
				if not TextureName then
					Plugin.Logger:Debug( "Failed to load %s/%s: %s", ModID, Map, Err )
					if not Cleared and SGUI.IsValid( Button ) then
						Button.OnHover = nil
					end
					return
				end

				if Cleared then
					-- Loaded too late.
					if MapMod then
						TextureLoader.Free( TextureName )
					end
					return
				end

				Plugin.Logger:Debug( "Loaded %s/%s into %s", ModID, Map, TextureName )

				local PreviewPanel
				local PreviewSize = 256
				function Button:OnHover()
					if not SGUI.IsValid( PreviewPanel ) then
						local Anchor = self:GetAnchor()
						local IsLeft = Anchor == GUIItem.Left

						-- The only reason it's parented to the panel is so it shows above the buttons.
						PreviewPanel = SGUI:Create( "Panel", self.Parent )
						PreviewPanel:SetAutoSize( UnitVector( GUIScaled( PreviewSize ),
							GUIScaled( PreviewSize ) ), true )
						PreviewPanel:SetAnchor( self:GetAnchor() )

						local Size = PreviewPanel:GetSize()
						PreviewPanel:SetPos( self:GetPos() + Vector2( IsLeft and -Size.x or self:GetSize().x,
							-Size.y * 0.5 + self:GetSize().y * 0.5 ) )

						local Image = SGUI:Create( "Image", PreviewPanel )
						Image:SetSize( Size )
						Image:SetTexture( TextureName )
						PreviewPanel.Image = Image

						Image:SetColour( Colour( 1, 1, 1, 0 ) )
						PreviewPanel:SetColour( Colour( 0, 0, 0, 0 ) )
					end

					PreviewPanel.Image:AlphaTo( nil, nil, 1, 0, 0.3 )
					PreviewPanel:AlphaTo( nil, nil, 0.25, 0, 0.3 )
				end

				function Button:OnLoseHover()
					if not SGUI.IsValid( PreviewPanel ) then return end

					PreviewPanel.Image:AlphaTo( nil, nil, 0, 0, 0.3 )
					PreviewPanel:AlphaTo( nil, nil, 0, 0, 0.3, function()
						PreviewPanel.Image:StopAlpha()
						PreviewPanel:Destroy()
						PreviewPanel = nil
					end )
				end

				function Button:OnClear()
					if MapMod and TextureName then
						TextureLoader.Free( TextureName )
					end

					if not SGUI.IsValid( PreviewPanel ) then return end

					PreviewPanel.Image:StopAlpha()
					PreviewPanel:Destroy()
				end

				if Button.MouseHovered then
					-- If the button's still hovered, trigger the preview to show now it's ready.
					Button:OnHover()
				end
			end )
		end

		function Button:OnClear()
			Cleared = true
		end
	end

	local MapVoteMenu = require "shine/extensions/mapvote/ui/map_vote_menu"

	function Plugin:SetScreenBlurred( Blurred )
		if not self.ScreenBlur then
			self.ScreenBlur = Client.CreateScreenEffect( "shaders/Blur.screenfx" )
		end
		self.ScreenBlur:SetActive( not not Blurred )
	end

	function Plugin:IsMultipleChoiceVote()
		return self.dt.VotingMode == self.VotingModeOrdinal.MULTIPLE_CHOICE
	end

	function Plugin:ShowFullVoteMenu()
		if not SGUI.IsValid( self.FullVoteMenu ) then
			local Maps = self.Maps
			if not Maps then return end

			local Offset = SGUI.Layout.Units.GUIScaled( 32 ):GetValue()
			self.FullVoteMenu = SGUI:CreateFromDefinition( MapVoteMenu )
			self.FullVoteMenu:SetLogger( self.Logger )
			self.FullVoteMenu:SetLoadModPreviews( self.Config.LoadModPreviewsInMapGrid )
			self.FullVoteMenu:SetMultiSelect( self:IsMultipleChoiceVote() )
			self.FullVoteMenu:SetMaxVoteChoices( self.dt.MaxVoteChoicesPerPlayer )

			local W, H = SGUI.GetScreenSize()
			self.FullVoteMenu:SetPos( Vector2( Offset, Offset ) )
			self.FullVoteMenu:SetSize( Vector2( W - Offset * 2, H - Offset * 2 ) )

			Maps = Shine.Stream.Of( Maps ):Map( function( MapName )
				return {
					MapName = MapName,
					NiceName = self:GetNiceMapName( MapName ),
					ModID = self.MapMods and self.MapMods[ MapName ] and tostring( self.MapMods[ MapName ] ),
					IsSelected = MapName == self.ChosenMap,
					NumVotes = self.MapVoteCounts[ MapName ]
				}
			end ):AsTable()

			self.FullVoteMenu:SetEndTime( self.EndTime )
			self.FullVoteMenu:SetCurrentMapName( self:GetNiceMapName( Shared.GetMapName() ) )
			self.FullVoteMenu:SetMaps( Maps )
			self.FullVoteMenu:SetIsVisible( false )
			self.FullVoteMenu:SetCloseOnClick( self.Config.CloseMenuAfterChoosingMap )
			self.FullVoteMenu:AddPropertyChangeListener( "CloseOnClick", function( FullVoteMenu, CloseOnClick )
				if CloseOnClick == nil then
					return
				end

				self:SetClientSetting( "CloseMenuAfterChoosingMap", CloseOnClick )
			end )
			self.FullVoteMenu:AddPropertyChangeListener( "UseVoteMenu", function( FullVoteMenu, UseVoteMenu )
				if not UseVoteMenu then return end

				self:SetClientSetting( "VoteMenuType", self.VoteMenuType.MINIMAL )

				self.FullVoteMenu:Close( function()
					if SGUI.IsValid( self.FullVoteMenu ) then
						self.FullVoteMenu:Destroy()
						self.FullVoteMenu = nil
					end
				end )

				Shine.VoteMenu:SetIsVisible( true )
				Shine.VoteMenu:SetPage( "MapVote" )
			end )
			self.FullVoteMenu:AddPropertyChangeListener( "LoadModPreviews", function( FullVoteMenu, LoadModPreviews )
				if LoadModPreviews == nil then
					return
				end

				self:SetClientSetting( "LoadModPreviewsInMapGrid", LoadModPreviews )
			end )

			function self.FullVoteMenu:OnMapSelected( MapName )
				SendMapVote( MapName )
			end

			function self.FullVoteMenu:OnMapDeselected( MapName )
				SendMapVote( MapName, true )
			end

			function self.FullVoteMenu.PreClose()
				self:SetScreenBlurred( false )
			end

			function self.FullVoteMenu.OnClose()
				Shine.ScreenText.SetIsVisible( true )

				if SGUI.IsValid( self.MapVoteNotification ) then
					self.MapVoteNotification:FadeIn()
				end
			end

			if self.ChosenMap then
				self.FullVoteMenu:ForceSelectedMap( self.ChosenMap )
			elseif self.ChosenMaps then
				for Map in pairs( self.ChosenMaps ) do
					self.FullVoteMenu:ForceSelectedMap( Map )
				end
			end
		end

		if not self.FullVoteMenu:GetIsVisible() then
			self.FullVoteMenu:FadeIn()

			if SGUI.IsValid( self.MapVoteNotification ) then
				self.MapVoteNotification:Hide()
			end

			self:SetScreenBlurred( true )

			Shine.ScreenText.SetIsVisible( false )

			SGUI.NotificationManager.DisplayHint( MAP_GRID_AFTER_MIGRATION_HINT )

			if self:IsMultipleChoiceVote() then
				SGUI.NotificationManager.DisplayHint( MULTIPLE_CHOICE_VOTE_HINT )
			end
		end
	end

	function Plugin:OnResolutionChanged()
		if SGUI.IsValid( self.FullVoteMenu ) then
			local WasVisible = self.FullVoteMenu:GetIsVisible()

			self.FullVoteMenu:Destroy()
			self.FullVoteMenu = nil

			if WasVisible then
				self:ShowFullVoteMenu()
			end
		end

		if SGUI.IsValid( self.MapVoteNotification ) then
			self.MapVoteNotification:Destroy()
			self.MapVoteNotification = nil

			local Notification = self:CreateMapVoteNotification( Shine.VoteButton or "M" )
			Notification:UpdateTeamVariation()

			if SGUI.IsValid( self.FullVoteMenu ) and self.FullVoteMenu:GetIsVisible() then
				Notification:SetIsVisible( false )
			end
		end
	end

	local function CleanupMapVotePage( VoteMenu )
		local DescriptionLabel = Plugin.VoteMenuDescriptionLabel
		if SGUI.IsValid( DescriptionLabel ) then
			DescriptionLabel:Destroy()
		end
		Plugin.VoteMenuDescriptionLabel = nil
	end

	Shine.VoteMenu:AddPage( "MapVote", function( self )
		if ClosePageIfVoteFinished( self ) then return end

		-- Clear any pending automatic opening if the menu is opened manually.
		Plugin.WaitingForMenuClose = nil

		if Plugin.Config.VoteMenuType == Plugin.VoteMenuType.FULL then
			-- Using the new menu, hide the vote menu and show it.
			self:SetPage( "Main" )
			self:ForceHide()

			Plugin:ShowFullVoteMenu()

			return
		end

		local Maps = Plugin.Maps
		if not Maps then
			return
		end

		local NumMaps = #Maps

		for i = 1, NumMaps do
			local Map = Maps[ i ]
			local Votes = Plugin.MapVoteCounts[ Map ]
			local NiceName = Plugin:GetNiceMapName( Map )
			local Text = StringFormat( "%s (%d)", NiceName, Votes )
			local Button = self:AddSideButton( Text, function()
				SendMapVote( Map, Plugin:IsMultipleChoiceVote() and Plugin:IsMapSelected( Map ) )

				if not Plugin:IsMultipleChoiceVote() then
					self:SetIsVisible( false )
				end
			end )

			Shine.VoteMenu:MarkAsSelected( Button, Plugin:IsMapSelected( Map ) )

			local MapMod = Plugin.MapMods and Plugin.MapMods[ Map ]
			SetupMapPreview( Button, Map, MapMod )

			Plugin.MapButtons[ Map ] = {
				Button = Button,
				NiceName = NiceName,
				OriginalTextColour = Button:GetTextColour()
			}
		end

		Plugin:RefreshVoteButtonColours()

		local IconFont, IconScale = SGUI.FontManager.GetFont( SGUI.FontFamilies.Ionicons, 32 )
		self:AddTopButton( Plugin:GetPhrase( "BACK" ), function()
			self:SetPage( "Main" )
		end ):SetIcon( SGUI.Icons.Ionicons.ArrowLeftC, IconFont, IconScale )

		local BottomButton = self:AddBottomButton( Plugin:GetPhrase( "VOTE_MENU_USE_MAP_VOTE_MENU" ), function()
			Plugin:SetClientSetting( "VoteMenuType", Plugin.VoteMenuType.FULL )

			self:SetPage( "Main" )
			self:ForceHide()

			Plugin:ShowFullVoteMenu()

			SGUI.NotificationManager.DisplayHint( MAP_GRID_SWITCH_BACK_HINT )
		end )
		BottomButton:SetIcon( SGUI.Icons.Ionicons.ArrowExpand, IconFont, IconScale )
		BottomButton:SetTooltip( Plugin:GetPhrase( "VOTE_MENU_USE_MAP_VOTE_MENU_TOOLTIP" ) )

		local DescriptionText
		if Plugin.dt.VotingMode == Plugin.VotingModeOrdinal.MULTIPLE_CHOICE then
			DescriptionText = Plugin:GetInterpolatedPhrase( "MAP_VOTE_MENU_MULTIPLE_CHOICE_DESCRIPTION", {
				MaxVoteChoices = Plugin.dt.MaxVoteChoicesPerPlayer
			} )
		else
			DescriptionText = Plugin:GetPhrase( "MAP_VOTE_MENU_SINGLE_CHOICE_DESCRIPTION" )
		end

		Plugin.VoteMenuDescriptionLabel = SGUI:BuildTree( {
			Parent = self.Background,
			{
				ID = "DescriptionLabel",
				Class = "Label",
				Props = {
					Font = BottomButton:GetFont(),
					TextScale = BottomButton:GetTextScale(),
					Colour = Colour( 1, 1, 1 ),
					IsSchemed = false,
					PositionType = SGUI.PositionType.ABSOLUTE,
					AutoWrap = true,
					AutoSize = Units.UnitVector( Units.Percentage( 50 ), Units.Auto() ),
					TopOffset = Units.Percentage( 50 ) - Units.Auto() * 0.5,
					LeftOffset = Units.Percentage( 50 ),
					Shadow = {
						Colour = Colour( 0, 0, 0, 200 / 255 ),
						Offset = Vector2( 2, 2 )
					},
					Text = DescriptionText,
					TextAlignmentX = GUIItem.Align_Center
				}
			}
		} ).DescriptionLabel

		if Plugin:IsMultipleChoiceVote() then
			SGUI.NotificationManager.DisplayHint( MULTIPLE_CHOICE_VOTE_HINT )
		end
	end, ClosePageIfVoteFinished, CleanupMapVotePage )
end

do
	local StringCapitalise = string.Capitalise
	local StringGSub = string.gsub

	function Plugin:GetNiceMapName( MapName )
		local NiceName = Hook.Call( "OnGetNiceMapName", MapName )
		if IsType( NiceName, "string" ) then
			-- Allow gamemodes to format their map names appropriately.
			return NiceName
		end

		-- Otherwise, infer the name using existing conventions.
		NiceName = StringGSub( MapName, "^ns[12]?_", "" )

		local Words = StringExplode( NiceName, "_", true )
		local KnownPrefixWords = {
			co = "Combat:",
			sws = "SWS:",
			sg = "Siege:",
			gg = "Gun Game:",
			ls = "Last Stand:",
			dmd = "DMD"
		}

		return Shine.Stream( Words ):Map( function( Word, Index )
			if Index > 1 then
				-- Gamemode words should only be used on the first word.
				return StringCapitalise( Word )
			end
			return KnownPrefixWords[ Word ] or StringCapitalise( Word )
		end ):Concat( " " )
	end

	function Plugin:PreProcessTranslatedMessage( Name, Data )
		if Data.MapName then
			Data.MapName = self:GetNiceMapName( Data.MapName )
		end

		if Data.MapNames then
			Data.MapNames = Shine.Stream( StringExplode( Data.MapNames, ",%s*" ) ):Map( function( MapName )
				return self:GetNiceMapName( MapName )
			end ):Concat( ", " )
		end

		return Data
	end
end

do
	local TiedTextColour = Colour( 1, 1, 0 )
	local WinnerTextColour = Colour( 0, 1, 0 )

	function Plugin:RefreshVoteButtonColours()
		local Max = 0
		local NumAtMax = 0

		for MapName, MapButton in pairs( self.MapButtons ) do
			local Votes = self.MapVoteCounts[ MapName ]
			if Votes > Max then
				Max = Votes
				NumAtMax = 1
			elseif Votes == Max then
				NumAtMax = NumAtMax + 1
			end
		end

		for MapName, MapButton in pairs( self.MapButtons ) do
			local Votes = self.MapVoteCounts[ MapName ]
			if Votes == Max and Max > 0 then
				MapButton.Button:SetTextColour( NumAtMax > 1 and TiedTextColour or WinnerTextColour )
			else
				MapButton.Button:SetTextColour( MapButton.OriginalTextColour )
			end
		end
	end
end

function Plugin:ReceiveVoteProgress( Data )
	local MapName = Data.Map
	local Votes = Data.Votes

	self.MapVoteCounts[ MapName ] = Votes

	if SGUI.IsValid( self.FullVoteMenu ) then
		self.FullVoteMenu:OnMapVoteCountChanged( MapName, Votes )
	end

	local MapButton = self.MapButtons[ MapName ]
	if not MapButton then return end

	local Button = MapButton.Button
	if SGUI.IsValid( Button ) then
		Button:SetText( StringFormat( "%s (%d)", MapButton.NiceName, Votes ) )
	end

	self:RefreshVoteButtonColours()
end

function Plugin:IsMapSelected( MapName )
	return self.ChosenMap == MapName or ( self.ChosenMaps and self.ChosenMaps[ MapName ] )
end

function Plugin:ReceiveChosenMap( Data )
	local MapName = Data.MapName

	if self.dt.VotingMode == self.VotingModeOrdinal.SINGLE_CHOICE then
		if self.ChosenMap then
			-- Unmark the old selected map button if it's present.
			local OldButton = self.MapButtons[ self.ChosenMap ]
			if OldButton and SGUI.IsValid( OldButton.Button ) then
				Shine.VoteMenu:MarkAsSelected( OldButton.Button, false )
			end
		end

		self.ChosenMap = MapName
	else
		self.ChosenMaps = self.ChosenMaps or {}
		self.ChosenMaps[ MapName ] = Data.IsSelected or nil
	end

	local MapButton = self.MapButtons[ MapName ]
	if Data.IsSelected then
		-- Mark the selected map button.
		if MapButton and SGUI.IsValid( MapButton.Button ) then
			Shine.VoteMenu:MarkAsSelected( MapButton.Button, true )
		end

		if SGUI.IsValid( self.FullVoteMenu ) then
			self.FullVoteMenu:ForceSelectedMap( MapName )
		end
	else
		if MapButton and SGUI.IsValid( MapButton.Button ) then
			Shine.VoteMenu:MarkAsSelected( MapButton.Button, false )
		end

		if SGUI.IsValid( self.FullVoteMenu ) then
			self.FullVoteMenu:DeselectMap( MapName )
		end
	end
end

function Plugin:EndVote()
	self.EndTime = 0
	self.ChosenMap = nil
	self.ChosenMaps = nil
	self.ScreenText = nil

	TableEmpty( self.MapVoteCounts )
	TableEmpty( self.MapButtons )
	Shine.ScreenText.End( "MapVote" )

	if SGUI.IsValid( self.FullVoteMenu ) then
		self.FullVoteMenu:Close( function()
			if SGUI.IsValid( self.FullVoteMenu ) then
				self.FullVoteMenu:Destroy()
				self.FullVoteMenu = nil
			end
		end )
	end

	if SGUI.IsValid( self.MapVoteNotification ) then
		self.MapVoteNotification:Hide( function()
			if SGUI.IsValid( self.MapVoteNotification ) then
				self.MapVoteNotification:Destroy()
				self.MapVoteNotification = nil
			end
		end )
	end

	if self.ScreenBlur then
		Client.DestroyScreenEffect( self.ScreenBlur )
		self.ScreenBlur = nil
	end
end

function Plugin:ReceiveEndVote( Data )
	self:EndVote()
end

function Plugin:ReceiveMapMod( Data )
	self.MapMods = self.MapMods or {}
	self.MapMods[ Data.MapName ] = tonumber( Data.ModID, 16 )

	self.Logger:Debug( "Received mod ID %s for map %s.", Data.ModID, Data.MapName )
end

local function GetMapVoteText( self, NextMap, VoteButton, Maps, InitialText, VoteButtonCandidates )
	local Description
	if InitialText then
		Description = NextMap and self:GetPhrase( "NEXT_MAP_DESCRIPTION" )
			or self:GetPhrase( "RTV_DESCRIPTION" )
	else
		Description = NextMap and self:GetPhrase( "NEXT_MAP_DESCRIPTION2" )
			or self:GetPhrase( "RTV_DESCRIPTION2" )
	end

	if VoteButton then
		return self:GetInterpolatedPhrase( "VOTE_BOUND_MESSAGE", {
			VoteDescription = Description,
			Button = VoteButton
		} )
	end

	local VoteMessage = self:GetInterpolatedPhrase( "VOTE_UNBOUND_MESSAGE", {
		VoteDescription = Description,
		MapList = "\n* "..TableConcat( Maps, "\n* " )
	} )

	if VoteButtonCandidates then
		-- Some menu binds are conflicting with the vote menu button.
		local Binds = {}
		for i = 1, #VoteButtonCandidates do
			local Binding = VoteButtonCandidates[ i ]
			Binds[ i ] = StringFormat( "%s (%s)", Binding.Button, Binding.Bind or "UNKNOWN BIND" )
		end
		VoteMessage = StringFormat( "%s\n%s", VoteMessage, self:GetInterpolatedPhrase( "VOTE_BUTTON_CONFLICT", {
			Buttons = "\n* "..TableConcat( Binds, "\n* " )
		} ) )
	end

	return VoteMessage
end

local MapVoteNotification = require "shine/extensions/mapvote/ui/map_vote_notification"

function Plugin:OnLocalPlayerChanged( Player )
	if not SGUI.IsValid( self.MapVoteNotification ) then return end
	self.MapVoteNotification:UpdateTeamVariation()
end

function Plugin:CreateMapVoteNotification( VoteButton )
	self.MapVoteNotification = SGUI:CreateFromDefinition( MapVoteNotification )
	self.MapVoteNotification:SetBlockEventsIfFocusedWindow( false )
	self.MapVoteNotification:SetKeybind( VoteButton )
	self.MapVoteNotification:SetEndTime( self.EndTime )
	self.MapVoteNotification:InvalidateLayout( true )
	self.MapVoteNotification:SetSize(
		Vector2(
			self.MapVoteNotification:GetContentSizeForAxis( 1 ),
			self.MapVoteNotification:GetMaxSizeAlongAxis( 2 )
		)
	)
	local W, H = SGUI.GetScreenSize()
	self.MapVoteNotification:SetPos(
		Vector2( W * 0.95 - self.MapVoteNotification:GetSize().x, H * 0.2 )
	)
	return self.MapVoteNotification
end

function Plugin:ReceiveVoteOptions( Message )
	Shine.CheckVoteMenuBind()

	local Duration = Message.Duration
	local NextMap = Message.NextMap
	local TimeLeft = Message.TimeLeft
	local ShowTimeLeft = Message.ShowTime

	local Options = Message.Options

	local Maps = StringExplode( Options, ", ", true )

	self.Maps = Maps
	self.EndTime = SharedTime() + Duration

	for i = 1, #Maps do
		local Map = Maps[ i ]

		if not self.MapVoteCounts[ Map ] then
			self.MapVoteCounts[ Map ] = 0
		end
	end

	local ButtonBound = Shine.VoteButtonBound
	local VoteButton = Shine.VoteButton or "M"
	local VoteButtonCandidates = Shine.VoteButtonCandidates

	if ButtonBound then
		self:CreateMapVoteNotification( VoteButton ):FadeIn()
	else
		local VoteMessage = GetMapVoteText( self, NextMap, ButtonBound and VoteButton or nil,
			Maps, true, VoteButtonCandidates )

		if NextMap and TimeLeft > 0 and ShowTimeLeft then
			VoteMessage = StringFormat( "%s\n%s", VoteMessage, self:GetPhrase( "TIME_LEFT" ) )
		end

		if NextMap and ShowTimeLeft then
			local ScreenText = Shine.ScreenText.Add( "MapVote", {
				X = 0.95, Y = 0.2,
				Text = VoteMessage,
				Duration = Duration,
				R = 255, G = 0, B = 0,
				Alignment = 2,
				Size = 1,
				FadeIn = 0.5,
				IgnoreFormat = true
			} )

			ScreenText.TimeLeft = TimeLeft

			ScreenText.Obj:SetText( StringFormat( ScreenText.Text,
				string.TimeToString( ScreenText.Duration ),
				string.TimeToString( ScreenText.TimeLeft ) ) )

			function ScreenText:UpdateText()
				self.Obj:SetText( StringFormat( self.Text,
					string.TimeToString( self.Duration ),
					string.TimeToString( self.TimeLeft ) ) )
			end

			function ScreenText:Think()
				self.TimeLeft = self.TimeLeft - 1

				if self.Duration <= Duration - 10 and self.Stage < 2 then
					self.Stage = 2
					self.Colour = Colour( 1, 1, 1 )
					self.Obj:SetColor( self.Colour )

					self.Text = GetMapVoteText( Plugin, NextMap, ButtonBound and VoteButton or nil,
						Maps, false, VoteButtonCandidates )

					if self.TimeLeft > 0 then
						self.Text = StringFormat( "%s\n%s", self.Text, Plugin:GetPhrase( "TIME_LEFT" ) )
					end

					self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ),
						string.TimeToString( self.TimeLeft ) ) )

					return
				end

				if self.Duration <= 10 and self.Stage < 3 then
					self.Stage = 3
					self.Colour = Colour( 1, 0, 0 )
					self.Obj:SetColor( self.Colour )
				end
			end

			ScreenText.Stage = 1

			self.ScreenText = ScreenText
		else
			local ScreenText = Shine.ScreenText.Add( "MapVote", {
				X = 0.95, Y = 0.2,
				Text = VoteMessage,
				Duration = Duration,
				R = 255, G = 0, B = 0,
				Alignment = 2,
				Size = 1,
				FadeIn = 0.5
			} )

			ScreenText.Obj:SetText( StringFormat( ScreenText.Text,
				string.TimeToString( ScreenText.Duration ) ) )

			function ScreenText:Think()
				if self.Duration <= Duration - 10 and self.Stage < 2 then
					self.Stage = 2
					self.Colour = Colour( 1, 1, 1 )
					self.Obj:SetColor( self.Colour )

					self.Text = GetMapVoteText( Plugin, NextMap, ButtonBound and VoteButton or nil,
						Maps, false, VoteButtonCandidates )
					self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ) ) )

					return
				end

				if self.Duration <= 10 and self.Stage < 3 then
					self.Stage = 3
					self.Colour = Colour( 1, 0, 0 )
					self.Obj:SetColor( self.Colour )
				end
			end

			ScreenText.Stage = 1

			self.ScreenText = ScreenText
		end
	end

	local OpenedAutomatically = self:AutoOpenVoteMenu( Message.ForceMenuOpen )
	if not OpenedAutomatically and self.Config.VoteMenuType == self.VoteMenuType.FULL then
		-- If the full vote menu will be opened, precache all the mounted map previews to avoid pop-in when the menu
		-- is opened for the first time.
		self.Logger:Debug( "Attempting to precache map previews for: %s", Options )
		MapDataRepository.PrecacheMapPreviews( Maps )
	end
end

function Plugin:OnMouseVisibilityChange( Visible )
	if Visible or not self.WaitingForMenuClose or not self:IsVoteInProgress() then
		return
	end

	-- Mouse has been hidden by other UI elements, show the vote menu.
	self.WaitingForMenuClose = nil
	self:AutoOpenVoteMenu( true )
end

function Plugin:AutoOpenVoteMenu( ForceOpen )
	-- Do not open the map vote menu if a game is in-progress.
	local GameInfo = GetGameInfoEntity()
	if GameInfo and ( GameInfo:GetCountdownActive() or GameInfo:GetGameStarted() ) then
		return false
	end

	-- Open the map vote menu if configured to do so.
	local ConfiguredAction = self.Config.OnVoteAction

	if ConfiguredAction ~= self.VoteAction.OPEN_MENU
	and not ( ConfiguredAction == self.VoteAction.USE_SERVER_SETTINGS and ForceOpen ) then
		return false
	end

	if Client.GetMouseVisible() and not Shine.VoteMenu.Visible then
		-- Mouse is visible, and it's not for the vote menu. Assume some other UI elements are
		-- visible and thus opening the vote menu now would be disruptive.
		self.WaitingForMenuClose = true
		return false
	end

	if not Shine.VoteMenu.Visible then
		Shine.OpenVoteMenu()
	end

	Shine.VoteMenu:SetPage( "MapVote" )

	return true
end

function Plugin:Cleanup()
	self:EndVote()

	return self.BaseClass.Cleanup( self )
end

Shine.LoadPluginModule( "logger.lua", Plugin )

Plugin.ClientConfigSettings = {
	{
		ConfigKey = "LoadModPreviewsInMapGrid",
		Command = "sh_mapvote_loadmodpreviews",
		Type = "Boolean",
		CommandMessage = function( Value )
			local Explanations = {
				[ true ] = "now show previews for mods",
				[ false ] = "no longer show previews for mods"
			}
			return StringFormat( "The map grid will %s.", Explanations[ Value ] )
		end,
		OnChange = Plugin.SetLoadModPreviewsInMapGrid
	},
	{
		ConfigKey = "CloseMenuAfterChoosingMap",
		Command = "sh_mapvote_closeaftervote",
		Type = "Boolean",
		CommandMessage = function( Value )
			local Explanations = {
				[ true ] = "now close after casting a vote",
				[ false ] = "no longer close after casting a vote"
			}
			return StringFormat( "The map grid will %s.", Explanations[ Value ] )
		end,
		OnChange = Plugin.SetCloseMenuAfterChoosingMap
	},
	{
		ConfigKey = "OnVoteAction",
		Command = "sh_mapvote_onvote",
		Type = "Radio",
		Options = Plugin.VoteAction,
		CommandMessage = function( Value )
			local Explanations = {
				[ Plugin.VoteAction.USE_SERVER_SETTINGS ] = "respect server settings",
				[ Plugin.VoteAction.OPEN_MENU ] = "open",
				[ Plugin.VoteAction.DO_NOT_OPEN_MENU ] = "do nothing"
			}
			return StringFormat( "The vote menu will %s when a map vote starts.", Explanations[ Value ] )
		end,
		Description = "ON_VOTE_ACTION"
	},
	{
		ConfigKey = "VoteMenuType",
		Command = "sh_mapvote_menutype",
		Type = "Radio",
		Options = Plugin.VoteMenuType,
		CommandMessage = function( Value )
			local Explanations = {
				[ Plugin.VoteMenuType.FULL ] = "in full screen",
				[ Plugin.VoteMenuType.MINIMAL ] = "in the vote menu",
			}
			return StringFormat( "Map voting will now open %s.", Explanations[ Value ] )
		end
	}
}
