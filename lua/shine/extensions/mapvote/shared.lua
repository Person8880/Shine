--[[
	Shared stuff.
]]

local Plugin = {}
Plugin.NotifyPrefixColour = {
	255, 255, 0
}

local VoteOptionsMessage = {
	Options = "string (255)",
	Duration = "integer (0 to 1800)",
	NextMap = "boolean",
	ShowTime = "boolean",
	TimeLeft = "integer (0 to 32768)"
}

local MapVotesMessage = {
	Map = "string (255)",
	Votes = "integer (0 to 255)"
}

Shine:RegisterExtension( "mapvote", Plugin )

function Plugin:SetupDataTable()
	local MapNameField = "string (24)"

	local MessageTypes = {
		Duration = {
			Duration = "integer"
		},
		Empty = {},
		MapName = {
			MapName = MapNameField
		},
		MapVotes = {
			MapName = MapNameField,
			Votes = "integer (0 to 127)",
			TotalVotes = "integer (0 to 127)"
		},
		MapNames = {
			MapNames = "string (255)"
		},
		Nomination = {
			TargetName = self:GetNameNetworkField(),
			MapName = MapNameField
		},
		RTV = {
			TargetName = self:GetNameNetworkField(),
			VotesNeeded = "integer (0 to 127)"
		},
		PlayerVote = {
			TargetName = self:GetNameNetworkField(),
			Revote = "boolean",
			MapName = MapNameField,
			Votes = "integer (0 to 127)",
			TotalVotes = "integer (0 to 127)"
		},
		PlayerVotePrivate = {
			Revote = "boolean",
			MapName = MapNameField,
			Votes = "integer (0 to 127)",
			TotalVotes = "integer (0 to 127)"
		},
		Veto = {
			TargetName = self:GetNameNetworkField()
		},
		TimeLeftCommand = {
			Rounds = "boolean",
			Duration = "integer"
		},
		TeamSwitchFail = {
			IsEndVote = "boolean"
		}
	}

	self:AddNetworkMessage( "VoteOptions", VoteOptionsMessage, "Client" )
	self:AddNetworkMessage( "EndVote", MessageTypes.Empty, "Client" )
	self:AddNetworkMessage( "VoteProgress", MapVotesMessage, "Client" )

	self:AddNetworkMessage( "RequestVoteOptions", MessageTypes.Empty, "Server" )

	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ table.Copy( MessageTypes.Empty ) ] = {
			"FORCED_VOTE"
		},
		[ table.Copy( MessageTypes.Duration ) ] = {
			"MAP_EXTENDED_TIME", "SET_MAP_TIME", "MAP_EXTENDED_ROUNDS",
			"SET_MAP_ROUNDS"
		}
	} )

	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.Duration ] = {
			"TimeLeftNotify", "RoundLeftNotify", "EXTENDING_TIME",
			"MAP_CHANGING"
		},
		[ MessageTypes.MapName ] = {
			"MapCycling", "WINNER_NEXT_MAP", "WINNER_CYCLING",
			"CHOOSING_RANDOM_MAP", "NextMapCommand",
			"MAP_CYCLING"
		},
		[ MessageTypes.MapVotes ] = {
			"WINNER_VOTES"
		},
		[ MessageTypes.MapNames ] = {
			"VOTES_TIED"
		},
		[ MessageTypes.Nomination ] = {
			"NOMINATED_MAP"
		},
		[ MessageTypes.RTV ] = {
			"RTV_VOTED"
		},
		[ MessageTypes.PlayerVote ] = {
			"PLAYER_VOTED"
		},
		[ MessageTypes.PlayerVotePrivate ] = {
			"PLAYER_VOTED_PRIVATE"
		},
		[ MessageTypes.Veto ] = {
			"VETO"
		},
		[ MessageTypes.TimeLeftCommand ] = {
			"TimeLeftCommand"
		},
		[ MessageTypes.TeamSwitchFail ] = {
			"TeamSwitchFail"
		}
	} )

	self:AddNetworkMessages( "AddTranslatedError", {
		[ MessageTypes.MapName ] = {
			"VOTE_FAIL_INVALID_MAP", "VOTE_FAIL_VOTED_MAP",
			"MAP_NOT_ON_LIST", "ALREADY_NOMINATED",
			"RECENTLY_PLAYED"
		}
	} )
end

if Server then
	function Plugin:ReceiveRequestVoteOptions( Client, Message )
		self:SendVoteData( Client )
	end

	return
end

local Shine = Shine
local SGUI = Shine.GUI

local SharedTime = Shared.GetTime
local StringExplode = string.Explode
local StringFormat = string.format
local TableEmpty = table.Empty

Plugin.Maps = {}
Plugin.MapButtons = {}
Plugin.MapVoteCounts = {}
Plugin.EndTime = 0

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

	if ( self.NextVoteOptionRequest or 0 ) < Time and self.EndTime < Time then
		self.NextVoteOptionRequest = Time + 10

		self:SendNetworkMessage( "RequestVoteOptions", {}, true )
	end
end

Shine.VoteMenu:EditPage( "Main", function( self )
	local Time = SharedTime()

	if ( Plugin.EndTime or 0 ) > Time then
		self:AddTopButton( Plugin:GetPhrase( "VOTE" ), function()
			self:SetPage( "MapVote" )
		end )
	end
end, function( self )
	local TopButton = self.Buttons.Top

	local Time = SharedTime()

	if Plugin.EndTime > Time then
		if not SGUI.IsValid( TopButton ) or not TopButton:GetIsVisible() then
			self:AddTopButton( Plugin:GetPhrase( "VOTE" ), function()
				self:SetPage( "MapVote" )
			end )
		end
	elseif Plugin.EndTime < Time then
		if SGUI.IsValid( TopButton ) and TopButton:GetIsVisible() then
			TopButton:SetIsVisible( false )
		end
	end
end )

local function SendMapVote( MapName )
	if Shine.VoteMenu.GetCanSendVote() then
		Shared.ConsoleCommand( "sh_vote "..MapName )

		return true
	end

	return false
end

do
	local function ClosePageIfVoteFinished( self )
		local Time = SharedTime()

		if Plugin.EndTime < Time then
			self:SetPage( "Main" )
			return true
		end

		return false
	end

	local MapIcons = {}

	do
		local StringMatch = string.match
		Shared.GetMatchingFileNames( "maps/overviews/*.tga", false, MapIcons )

		for i = 1, #MapIcons do
			local Path = MapIcons[ i ]
			local Map = StringMatch( Path, "^maps/overviews/(.+)%.tga$" )

			MapIcons[ i ] = nil
			MapIcons[ Map ] = Path
		end
	end

	local Units = SGUI.Layout.Units
	local GUIScaled = Units.GUIScaled
	local UnitVector = Units.UnitVector

	local function SetupMapPreview( Button, Map )
		local Texture = MapIcons[ Map ]
		local PreviewSize = 256

		local PreviewPanel
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
				Image:SetTexture( Texture )
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
				PreviewPanel:Destroy( true )
				PreviewPanel = nil
			end )
		end

		function Button:OnClear()
			if not SGUI.IsValid( PreviewPanel ) then return end

			PreviewPanel.Image:StopAlpha()
			PreviewPanel:Destroy( true )
		end
	end

	Shine.VoteMenu:AddPage( "MapVote", function( self )
		if ClosePageIfVoteFinished( self ) then return end

		local Maps = Plugin.Maps
		if not Maps then
			return
		end

		local NumMaps = #Maps

		for i = 1, NumMaps do
			local Map = Maps[ i ]
			local Votes = Plugin.MapVoteCounts[ Map ]
			local Text = StringFormat( "%s (%i)", Map, Votes )
			local Button = self:AddSideButton( Text, function()
				if SendMapVote( Map ) then
					self:SetIsVisible( false )
				else
					return false
				end
			end )

			if MapIcons[ Map ] then
				SetupMapPreview( Button, Map )
			end

			Plugin.MapButtons[ Map ] = Button
		end

		self:AddTopButton( Plugin:GetPhrase( "BACK" ), function()
			self:SetPage( "Main" )
		end )
	end, ClosePageIfVoteFinished )
end

function Plugin:ReceiveVoteProgress( Data )
	local MapName = Data.Map
	local Votes = Data.Votes

	self.MapVoteCounts[ MapName ] = Votes

	local MapButton = self.MapButtons[ MapName ]

	if SGUI.IsValid( MapButton ) and MapButton:GetText():find( MapName, 1, true ) then
		MapButton:SetText( StringFormat( "%s (%i)", MapName, Votes ) )
	end
end

function Plugin:ReceiveEndVote( Data )
	self.EndTime = 0

	TableEmpty( self.MapVoteCounts )
	TableEmpty( self.MapButtons )
	Shine.ScreenText.End( "MapVote" )
end

local function GetMapVoteText( self, NextMap, VoteButton, Options, InitialText )
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

	return self:GetInterpolatedPhrase( "VOTE_UNBOUND_MESSAGE", {
		VoteDescription = Description,
		MapList = Options
	} )
end

function Plugin:ReceiveVoteOptions( Message )
	Shine.CheckVoteMenuBind()

	local Duration = Message.Duration
	local NextMap = Message.NextMap
	local TimeLeft = Message.TimeLeft
	local ShowTimeLeft = Message.ShowTime

	local Options = Message.Options

	local Maps = StringExplode( Options, ", " )

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

	local VoteMessage = GetMapVoteText( self, NextMap, ButtonBound and VoteButton or nil, Options, true )

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

				self.Text = GetMapVoteText( Plugin, NextMap, ButtonBound and VoteButton or nil, Options, false )

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

				self.Text = GetMapVoteText( Plugin, NextMap, ButtonBound and VoteButton or nil, Options, false )
				self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ) ) )

				return
			end

			if self.Duration == 10 then
				self.Colour = Color( 1, 0, 0 )
				self.Obj:SetColor( self.Colour )
			end
		end
	end
end
