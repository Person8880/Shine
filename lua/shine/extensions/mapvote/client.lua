--[[
	Map vote client.
]]

local Plugin = ...

Plugin.VoteButtonName = "Map Vote"

local Shine = Shine
local SGUI = Shine.GUI

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
	VoteMenuType = Plugin.VoteMenuType.FULL
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
	RichTextMessageOptions[ "RTV_VOTED" ] = VoteMessageOptions
	RichTextMessageOptions[ "VETO" ] = VoteMessageOptions

	Plugin.RichTextMessageOptions = RichTextMessageOptions
end

function Plugin:Initialise()
	self:SetupClientConfig()

	return true
end

function Plugin:SetupClientConfig()
	self:BindCommand( "sh_mapvote_onvote", function( Choice )
		if not Choice then
			local Explanations = {
				[ self.VoteAction.USE_SERVER_SETTINGS ] = "respect server settings",
				[ self.VoteAction.OPEN_MENU ] = "open",
				[ self.VoteAction.DO_NOT_OPEN_MENU ] = "do nothing"
			}

			Print( "The vote menu is currently set to %s when a map vote starts.", Explanations[ self.Config.OnVoteAction ] )
			return
		end

		local VoteAction = self.VoteAction[ Choice ] or self.VoteAction.USE_SERVER_SETTINGS
		if not self:SetClientSetting( "OnVoteAction", VoteAction ) then
			return
		end

		local Explanations = {
			[ self.VoteAction.USE_SERVER_SETTINGS ] = "now respect server settings",
			[ self.VoteAction.OPEN_MENU ] = "now open",
			[ self.VoteAction.DO_NOT_OPEN_MENU ] = "no longer open"
		}

		Print( "The vote menu will %s when a map vote starts.", Explanations[ self.Config.OnVoteAction ] )
	end ):AddParam{ Type = "string", Optional = true }

	self:AddClientSetting( "OnVoteAction", "sh_mapvote_onvote", {
		Type = "Radio",
		Options = self.VoteAction,
		Description = "ON_VOTE_ACTION"
	} )
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
	self:TimeLeftNotify( self:GetInterpolatedPhrase( "CYCLING_NOTIFY", Data ) )
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
	self:AddChatLine( 0, 0, 0, "", 255, 255, 255, self:GetInterpolatedPhrase( "NEXT_MAP_SET_TO", Data ) )
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

local function SendMapVote( MapName )
	Shared.ConsoleCommand( "sh_vote "..MapName )
end

do
	local function ClosePageIfVoteFinished( self )
		if not Plugin:IsVoteInProgress() then
			self:SetPage( "Main" )
			return true
		end

		return false
	end

	local Units = SGUI.Layout.Units
	local GUIScaled = Units.GUIScaled
	local UnitVector = Units.UnitVector

	local MapDataRepository = require "shine/extensions/mapvote/map_data_repository"
	local TextureLoader = require "shine/lib/gui/texture_loader"

	local function SetupMapPreview( Button, Map, MapMod )
		local Cleared = false

		function Button:OnHover()
			local ModID = MapMod and tostring( MapMod )

			LuaPrint( "Attempting to load texture for", ModID, Map )

			MapDataRepository.GetOverviewImage( ModID, Map, function( MapName, TextureName, Err )
				if Cleared then
					-- Loaded too late.
					return
				end

				if not TextureName then
					LuaPrint( "Failed to load", ModID, Map, Err )
					if not Cleared and SGUI.IsValid( Button ) then
						Buton.OnHover = nil
					end
					return
				end

				LuaPrint( "Loaded", ModID, Map, "into", TextureName )

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
	function Plugin:ShowFullVoteMenu()
		if not SGUI.IsValid( self.FullVoteMenu ) then
			local Maps = self.Maps
			if not Maps then return end

			local Offset = SGUI.Layout.Units.HighResScaled( 64 ):GetValue()
			self.FullVoteMenu = SGUI:CreateFromDefinition( MapVoteMenu )

			local W, H = SGUI.GetScreenSize()
			self.FullVoteMenu:SetPos( Vector2( Offset, Offset ) )
			self.FullVoteMenu:SetSize( Vector2( W - Offset * 2, H - Offset * 2 ) )

			Maps = Shine.Stream.Of( Maps ):Map( function( MapName )
				return {
					MapName = MapName,
					NiceName = self:GetNiceMapName( MapName ),
					ModID = self.MapMods[ MapName ] and tostring( self.MapMods[ MapName ] ),
					IsSelected = MapName == self.ChosenMap,
					NumVotes = self.MapVoteCounts[ MapName ]
				}
			end ):AsTable()

			self.FullVoteMenu:SetEndTime( self.EndTime )
			self.FullVoteMenu:SetCurrentMapName( self:GetNiceMapName( Shared.GetMapName() ) )
			self.FullVoteMenu:SetMaps( Maps )
			self.FullVoteMenu:SetIsVisible( false )
			self.FullVoteMenu:AddPropertyChangeListener( "SelectedMap", function( MapName )
				SendMapVote( MapName )
			end )

			function self.FullVoteMenu.OnClose()
				if self.ScreenText then
					self.ScreenText:SetIsVisible( true )
				end
			end
		end

		if not self.FullVoteMenu:GetIsVisible() then
			-- TODO: Make a nice fade-in if AnimateUI == true.
			SGUI:EnableMouse( true )
			self.FullVoteMenu:SetIsVisible( true )

			if self.ScreenText then
				self.ScreenText:SetIsVisible( false )
			end
		end
	end

	Shine.VoteMenu:AddPage( "MapVote", function( self )
		if ClosePageIfVoteFinished( self ) then return end

		-- Clear any pending automatic opening if the menu is opened manually.
		Plugin.WaitingForMenuClose = nil

		if Plugin.Config.VoteMenuType == Plugin.VoteMenuType.FULL then
			-- Using the new menu, hide the vote menu and show it.
			-- TODO: Figure out why this is triggered again every time the vote menu is opened.
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
				SendMapVote( Map )
				self:SetIsVisible( false )
			end )

			Shine.VoteMenu:MarkAsSelected( Button, Plugin.ChosenMap == Map )

			local MapMod = Plugin.MapMods and Plugin.MapMods[ Map ]
			SetupMapPreview( Button, Map, MapMod )

			Plugin.MapButtons[ Map ] = {
				Button = Button,
				NiceName = NiceName
			}
		end

		self:AddTopButton( Plugin:GetPhrase( "BACK" ), function()
			self:SetPage( "Main" )
		end )
	end, ClosePageIfVoteFinished )
end

do
	local StringCapitalise = string.Capitalise
	local StringGSub = string.gsub

	function Plugin:GetNiceMapName( MapName )
		local NiceName = Shine.Hook.Call( "OnGetNiceMapName", MapName )
		if NiceName ~= nil then
			-- Allow gamemodes to format their map names appropriately.
			return NiceName
		end

		-- Otherwise, infer the name using existing conventions.
		local NiceName = StringGSub( MapName, "^ns2_", "" )
		local Words = StringExplode( NiceName, "_" )

		local KnownGamemodeWords = {
			co = "Combat:",
			sws = "SWS:",
			sg = "Siege:",
			gg = "Gun Game:"
		}

		return Shine.Stream( Words ):Map( function( Word )
			return KnownGamemodeWords[ Word ] or StringCapitalise( Word )
		end ):Concat( " " )
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
end

function Plugin:ReceiveChosenMap( Data )
	local MapName = Data.MapName

	if self.ChosenMap then
		-- Unmark the old selected map button if it's present.
		local OldButton = self.MapButtons[ self.ChosenMap ]
		if OldButton and SGUI.IsValid( OldButton.Button ) then
			Shine.VoteMenu:MarkAsSelected( OldButton.Button, false )
		end
	end

	self.ChosenMap = MapName

	-- Mark the selected map button.
	local MapButton = self.MapButtons[ MapName ]
	if MapButton and SGUI.IsValid( MapButton.Button ) then
		Shine.VoteMenu:MarkAsSelected( MapButton.Button, true )
	end
end

function Plugin:ReceiveEndVote( Data )
	self.EndTime = 0
	self.ChosenMap = nil
	self.ScreenText = nil

	TableEmpty( self.MapVoteCounts )
	TableEmpty( self.MapButtons )
	Shine.ScreenText.End( "MapVote" )

	if SGUI.IsValid( self.FullVoteMenu ) then
		self.FullVoteMenu:Close()
		self.FullVoteMenu:Destroy()
		self.FullVoteMenu = nil
	end
end

function Plugin:ReceiveMapMod( Data )
	-- Note, we assume the first mod in the list in the map cycle is the map.
	-- If it's not, we won't get the right preview image.
	self.MapMods = self.MapMods or {}
	self.MapMods[ Data.MapName ] = Data.ModID

	LuaPrint( "Received mod ID", Data.ModID, "for map", Data.MapName )
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

			if self.Duration == Duration - 10 then
				self.Colour = Color( 1, 1, 1 )
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

			if self.Duration == 10 then
				self.Colour = Color( 1, 0, 0 )
				self.Obj:SetColor( self.Colour )
			end
		end

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
			if self.Duration == Duration - 10 then
				self.Colour = Color( 1, 1, 1 )
				self.Obj:SetColor( self.Colour )

				self.Text = GetMapVoteText( Plugin, NextMap, ButtonBound and VoteButton or nil,
					Maps, false, VoteButtonCandidates )
				self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ) ) )

				return
			end

			if self.Duration == 10 then
				self.Colour = Color( 1, 0, 0 )
				self.Obj:SetColor( self.Colour )
			end
		end

		self.ScreenText = ScreenText
	end

	self:AutoOpenVoteMenu( Message.ForceMenuOpen )
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
		return
	end

	-- Open the map vote menu if configured to do so.
	local ConfiguredAction = self.Config.OnVoteAction

	if ConfiguredAction ~= self.VoteAction.OPEN_MENU
	and not ( ConfiguredAction == self.VoteAction.USE_SERVER_SETTINGS and ForceOpen ) then
		return
	end

	if Client.GetMouseVisible() and not Shine.VoteMenu.Visible then
		-- Mouse is visible, and it's not for the vote menu. Assume some other UI elements are
		-- visible and thus opening the vote menu now would be disruptive.
		self.WaitingForMenuClose = true
		return
	end

	if not Shine.VoteMenu.Visible then
		Shine.OpenVoteMenu()
	end

	Shine.VoteMenu:SetPage( "MapVote" )
end
