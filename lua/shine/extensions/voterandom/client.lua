--[[
	Vote shuffle client.
]]

local Plugin = ...

local SGUI = Shine.GUI

Plugin.VoteButtonName = "Shuffle"
Plugin.VoteButtonCheckMarkXScale = 0.5

Plugin.TeamType = table.AsEnum{
	"MARINE", "ALIEN", "NONE"
}
Plugin.HasConfig = true
Plugin.ConfigName = "VoteShuffle.json"
Plugin.Version = "1.1"
Plugin.DefaultConfig = {
	PreferredTeam = Plugin.TeamType.NONE,
	FriendGroupJoinType = Plugin.FriendGroupJoinTypeName.ALLOW_ALL,
	FriendGroupLeaderType = Plugin.FriendGroupLeaderTypeName.ALLOW_ALL_TO_JOIN,
	AutoAcceptSteamFriendGroupInvites = true
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.1",
		Apply = Shine.Migrator()
			:RenameField( "BlockFriendGroups", "FriendGroupJoinType" )
			:MapField(
				"FriendGroupJoinType",
				function( Blocked )
					return Plugin.FriendGroupJoinTypeName[ Blocked and "BLOCK" or "ALLOW_ALL" ]
				end
			)
	}
}

local StringFormat = string.format
local StringUpper = string.upper
local TableAdd = table.Add

do
	local Validator = Shine.Validator()
	Validator:AddFieldRule( "PreferredTeam", Validator.InEnum( Plugin.TeamType, Plugin.TeamType.NONE ) )
	Validator:AddFieldRule(
		"FriendGroupJoinType",
		Validator.InEnum(
			Plugin.FriendGroupJoinTypeName, Plugin.DefaultConfig.FriendGroupJoinType
		)
	)
	Validator:AddFieldRule(
		"FriendGroupLeaderType",
		Validator.InEnum(
			Plugin.FriendGroupLeaderTypeName, Plugin.DefaultConfig.FriendGroupLeaderType
		)
	)
	Plugin.ConfigValidator = Validator
end

Plugin.ConfigGroup = {
	Icon = SGUI.Icons.Ionicons.Shuffle
}

do
	local RichTextFormat = require "shine/lib/gui/richtext/format"
	local RichTextMessageOptions = {}

	local VoteMessageOptions = {
		Colours = {
			PlayerName = function( Values )
				return RichTextFormat.GetColourForPlayer( Values.PlayerName )
			end
		}
	}

	for i = 1, #Plugin.VoteMessageKeys do
		for Key, Value in pairs( Plugin.ModeStrings.Mode ) do
			RichTextMessageOptions[ StringFormat( "%s_%s", Plugin.VoteMessageKeys[ i ], Value ) ] = VoteMessageOptions
		end
	end
	for i = 1, #Plugin.FriendGroupMessageKeys do
		RichTextMessageOptions[ Plugin.FriendGroupMessageKeys[ i ] ] = VoteMessageOptions
	end

	Plugin.RichTextMessageOptions = RichTextMessageOptions
end

local FRIEND_GROUP_HINT_NAME = "ShuffleFriendGroupHint"
local FRIEND_GROUP_INVITE_HINT_NAME = "ShuffleFriendGroupInviteHint"
local TEAM_PREFERENCE_CHANGE_HINT_NAME = "ShuffleTeamPreferenceConfigHint"
local TEAM_PREFERENCE_DEFAULT_HINT_NAME = "ShuffleTeamPreferenceDefaultHint"

function Plugin:SetupClientConfig()
	local function SendTeamPreference( PreferredTeam )
		self:SendNetworkMessage( "TeamPreference", { PreferredTeam = PreferredTeam }, true )
	end

	do
		local PreferredTeam = self.Config.PreferredTeam
		for i = 1, #Plugin.TeamType do
			if PreferredTeam == Plugin.TeamType[ i ] then
				PreferredTeam = i
				break
			end
		end

		SendTeamPreference( PreferredTeam )
	end

	self:BindCommand( "sh_shuffle_teampref", function( PreferredTeam )
		local OldPref = self.Config.PreferredTeam
		local NewPref = self.TeamType[ PreferredTeam ] or self.TeamType.NONE
		if OldPref == NewPref then return end

		self:SetClientSetting( "PreferredTeam", NewPref )

		SendTeamPreference( PreferredTeam )

		self:OnTeamPreferenceChanged()

		local ResetHint = ""
		if self.Config.PreferredTeam ~= self.TeamType.NONE then
			ResetHint = " Enter this command again with no arguments to reset your preference."
		end

		Print( "Team preference saved as: %s.%s", self.Config.PreferredTeam, ResetHint )

		SGUI.NotificationManager.DisplayHint( TEAM_PREFERENCE_CHANGE_HINT_NAME )
		SGUI.NotificationManager.DisableHint( TEAM_PREFERENCE_DEFAULT_HINT_NAME )
	end ):AddParam{ Type = "team", Optional = true, Default = 3 }

	self:AddClientSetting( "PreferredTeam", "sh_shuffle_teampref", {
		Type = "Radio",
		Options = self.TeamType,
		Description = "TEAM_PREFERENCE",
		HelpText = "TEAM_PREFERENCE_HELP"
	} )

	local function SendFriendGroupConfig( Config )
		self:SendNetworkMessage( "ClientFriendGroupConfig", {
			JoinType = self.FriendGroupJoinType[ Config.FriendGroupJoinType ],
			LeaderType = self.FriendGroupLeaderType[ Config.FriendGroupLeaderType ]
		}, true )
	end

	SendFriendGroupConfig( self.Config )

	local function AddFriendGroupConfigCommand( CommandName, FieldName, EnumValues, Descriptions, ConfigDescriptionKey )
		self:BindCommand( CommandName, function( Type )
			SGUI.NotificationManager.DisableHint( FRIEND_GROUP_HINT_NAME )

			if self.Config[ FieldName ] == Type then return end

			if Type == self.FriendGroupJoinTypeName.REQUIRE_INVITE then
				SGUI.NotificationManager.DisplayHint( FRIEND_GROUP_INVITE_HINT_NAME )
			end

			self:SetClientSetting( FieldName, Type )
			SendFriendGroupConfig( self.Config )

			Print( Descriptions[ Type ] )
		end ):AddParam{ Type = "enum", Values = EnumValues }

		self:AddClientSetting( FieldName, CommandName, {
			Type = "Radio",
			Options = EnumValues,
			Description = ConfigDescriptionKey
		} )
	end

	AddFriendGroupConfigCommand( "sh_shuffle_group_join_type", "FriendGroupJoinType", self.FriendGroupJoinTypeName, {
		[ self.FriendGroupJoinTypeName.ALLOW_ALL ] = "You now allow anyone to add you to friend groups.",
		[ self.FriendGroupJoinTypeName.REQUIRE_INVITE ] = "You now must accept invitations to join friend groups.",
		[ self.FriendGroupJoinTypeName.BLOCK ] = "You now block others from adding you to friend groups."
	}, "FRIEND_GROUP_JOIN_TYPE" )

	self:AddClientSetting( "AutoAcceptSteamFriendGroupInvites", "sh_shuffle_auto_accept_steam_friend_invites", {
		Type = "Boolean",
		CommandMessage = function( Value )
			return StringFormat(
				"Friend group invites from Steam friends will %s.",
				Value and "now be automatically accepted" or "no longer be automatically accepted"
			)
		end,
		Margin = {
			nil,
			SGUI.Layout.Units.HighResScaled( 8 ),
			nil,
			SGUI.Layout.Units.HighResScaled( 16 )
		},
		Bindings = {
			{
				From = {
					Element = "FriendGroupJoinType",
					Property = "SelectedOption"
				},
				To = {
					Element = "Container",
					Property = "Enabled",
					Transformer = function( Option )
						return Option ~= nil and Option.Value == self.FriendGroupJoinTypeName.REQUIRE_INVITE
					end
				}
			}
		}
	} )

	AddFriendGroupConfigCommand( "sh_shuffle_group_leader_type", "FriendGroupLeaderType", self.FriendGroupLeaderTypeName, {
		[ self.FriendGroupLeaderTypeName.ALLOW_ALL_TO_JOIN ] = "You now allow anyone to join your friend groups.",
		[ self.FriendGroupLeaderTypeName.LEADER_ADD_ONLY ] = "You now only allow yourself to add others to your friend groups."
	}, "FRIEND_GROUP_LEADER_TYPE" )
end

function Plugin:NetworkUpdate( Key, Old, New )
	self:BroadcastModuleEvent( "NetworkUpdate", Key, Old, New )

	if not self.dt.IsVoteForAutoShuffle then return end

	if Key == "IsAutoShuffling" then
		local Button = Shine.VoteMenu:GetButtonByPlugin( self.VoteButtonName )
		if not Button then return end

		Button.DefaultText = self:GetVoteButtonText()
		Button:SetText( Button.DefaultText )
	end
end

function Plugin:GetVoteButtonText()
	if not self.dt.IsVoteForAutoShuffle then return end

	if self.dt.IsAutoShuffling then
		return self:GetPhrase( "DISABLE_AUTO_SHUFFLE" )
	end

	return self:GetPhrase( "ENABLE_AUTO_SHUFFLE" )
end

function Plugin:GetTeamPreference()
	return self.TemporaryTeamPreference or self.Config.PreferredTeam
end

function Plugin:ReceiveTemporaryTeamPreference( Data )
	local OldPreference = self:GetTeamPreference()

	self.TemporaryTeamPreference = self.TeamType[ Data.PreferredTeam ]

	local NewPreference = self:GetTeamPreference()
	if NewPreference ~= OldPreference then
		if not Data.Silent then
			self:Notify( self:GetPhrase( "TEAM_PREFERENCE_SET_"..NewPreference ) )
			SGUI.NotificationManager.DisplayHint( TEAM_PREFERENCE_DEFAULT_HINT_NAME )
		end

		self:OnTeamPreferenceChanged()
	end
end

function Plugin:ReceiveGroupTeamPreference( Data )
	local OldPreference = self.GroupTeamPreference
	local NewPreference = self.TeamType[ Data.PreferredTeam ] or self.TeamType.NONE

	self.GroupTeamPreference = NewPreference

	if NewPreference ~= OldPreference then
		if not Data.Silent and self.InFriendGroup and NewPreference ~= self:GetTeamPreference() then
			self:Notify( self:GetPhrase( "GROUP_TEAM_PREFERENCE_SET_"..NewPreference ) )
		end

		self:OnTeamPreferenceChanged()
	end
end

function Plugin:OnTeamPreferenceChanged()
	local Button = Shine.VoteMenu:GetButtonByPlugin( self.VoteButtonName )
	if not Button then return end

	self:OnVoteButtonCreated( Button, Shine.VoteMenu )
end

function Plugin:OnVoteButtonCreated( Button, VoteMenu )
	local TeamPreference = self:GetTeamPreference() or self.TeamType.NONE
	local GroupPreference = self.InFriendGroup and self.GroupTeamPreference or self.TeamType.NONE

	if TeamPreference ~= self.TeamType.NONE or self.InFriendGroup then
		local Colours = {
			[ self.TeamType.NONE ] = Colour( 0.85, 0.85, 0.85 ),
			[ self.TeamType.MARINE ] = Colour( 0.3, 0.69, 1 ),
			[ self.TeamType.ALIEN ] = Colour( 1, 0.79, 0.23 )
		}

		local PreferenceLabel = Button.PreferenceLabel or SGUI:Create( "ColourLabel", VoteMenu.Background )
		PreferenceLabel:MakeVertical()
		PreferenceLabel:SetAnchor( "CentreMiddle" )
		PreferenceLabel:SetFontScale( Button:GetFont(), Button:GetTextScale() )

		local Text = {}
		if TeamPreference ~= self.TeamType.NONE then
			TableAdd( Text, {
				Colour( 1, 1, 1 ),
				self:GetPhrase( "TEAM_PREFERENCE_HINT" ),
				Colours[ TeamPreference ],
				self:GetPhrase( TeamPreference )
			} )
		end

		if self.InFriendGroup then
			-- Show group preference even if it's NONE to indicate if there's a disparity between a player's own
			-- preference and their group's preference.
			TableAdd( Text, {
				Colour( 1, 1, 1 ),
				self:GetPhrase( "GROUP_TEAM_PREFERENCE_HINT" ),
				Colours[ GroupPreference ],
				self:GetPhrase( GroupPreference )
			} )
		end

		PreferenceLabel:SetText( Text )
		PreferenceLabel:SetTextAlignmentX( GUIItem.Align_Center )
		PreferenceLabel:SetShadow( {
			Colour = Colour( 0, 0, 0, 200 / 255 ),
			Offset = Vector2( 2, 2 )
		} )

		PreferenceLabel:SetPos( -Vector2( 0, PreferenceLabel:GetSize().y * 0.5 ) )

		local Units = SGUI.Layout.Units

		Button.PreferenceLabel = PreferenceLabel
		Button.OnClear = function( Button )
			if SGUI.IsValid( Button.PreferenceLabel ) then
				Button.PreferenceLabel:Destroy()
				Button.PreferenceLabel = nil
			end
		end
	else
		if SGUI.IsValid( Button.PreferenceLabel ) then
			Button.PreferenceLabel:Destroy()
			Button.PreferenceLabel = nil
		end
	end

	if self.dt.IsFriendGroupingEnabled then
		-- Show a hint about friend grouping when clicking the shuffle button.
		local OldClick = Button.DoClick
		function Button:DoClick()
			SGUI.NotificationManager.DisplayHint( FRIEND_GROUP_HINT_NAME )
			return OldClick( self )
		end
	end
end

function Plugin:OnFirstThink()
	self:CallModuleEvent( "OnFirstThink" )

	SGUI.NotificationManager.RegisterHint( FRIEND_GROUP_HINT_NAME, {
		MaxTimes = 3,
		HintIntervalInSeconds = 24 * 60 * 60,
		MessageSource = self:GetName(),
		MessageKey = "FRIEND_GROUP_HINT",
		HintDuration = 10
	} )
	SGUI.NotificationManager.RegisterHint( FRIEND_GROUP_INVITE_HINT_NAME, {
		MaxTimes = 1,
		MessageSource = self:GetName(),
		MessageKey = "FRIEND_GROUP_INVITE_HINT",
		HintDuration = 10,
		SuppressConsoleMessage = true,
		Options = {
			Buttons = {
				{
					Text = self:GetPhrase( "ACCEPT_FRIEND_GROUP_INVITE" ),
					Icon = SGUI.Icons.Ionicons.Checkmark,
					StyleName = "AcceptButton",
					DoClick = function( Button, Notification ) Notification:FadeOut() end
				},
				{
					Text = self:GetPhrase( "DECLINE_FRIEND_GROUP_INVITE" ),
					Icon = SGUI.Icons.Ionicons.Close,
					StyleName = "DeclineButton",
					DoClick = function( Button, Notification ) Notification:FadeOut() end
				}
			}
		}
	} )
	SGUI.NotificationManager.RegisterHint( TEAM_PREFERENCE_CHANGE_HINT_NAME, {
		MaxTimes = 1,
		MessageSource = self:GetName(),
		MessageKey = "TEAM_PREFERENCE_CHANGE_HINT",
		HintDuration = 10
	} )
	SGUI.NotificationManager.RegisterHint( TEAM_PREFERENCE_DEFAULT_HINT_NAME, {
		MaxTimes = 1,
		HintDuration = 10,
		MessageSupplier = function()
			local ConfigTab = self:GetPhrase( "CLIENT_CONFIG_TAB" )

			local VoteMenuButton = Shine.VoteButton
			if VoteMenuButton then
				return self:GetInterpolatedPhrase( "TEAM_PREFERENCE_DEFAULT_HINT_VOTEMENU", {
					ConfigTab = ConfigTab,
					ClientConfigButton = Shine.Locale:GetPhrase( "Core", "CLIENT_CONFIG_MENU" ),
					VoteMenuButton = VoteMenuButton
				} )
			end

			return self:GetInterpolatedPhrase( "TEAM_PREFERENCE_DEFAULT_HINT_CONSOLE", {
				ConfigTab = ConfigTab,
				ClientConfigButton = Shine.Locale:GetPhrase( "Core", "CLIENT_CONFIG_MENU" )
			} )
		end
	} )

	if self.Config.PreferredTeam ~= self.TeamType.NONE then
		-- Already set a default team preference, no need to tell them about it.
		SGUI.NotificationManager.DisableHint( TEAM_PREFERENCE_DEFAULT_HINT_NAME )
	end

	-- Defensive check in case the scoreboard code changes.
	if not Scoreboard_GetPlayerRecord or not GUIScoreboard or not GUIScoreboard.UpdateTeam then return end

	Shine.Hook.SetupClassHook( "GUIScoreboard", "UpdateTeam", "OnGUIScoreboardUpdateTeam", "PassivePost" )
	Shine.Hook.SetupClassHook( "GUIScoreboard", "SendKeyEvent", "OnGUIScoreboardSendKeyEvent", "PassivePost" )
end

local SharedGetTime = Shared.GetTime

function Plugin:DismissFriendGroupInvite()
	if SGUI.IsValid( self.FriendGroupInviteNotification ) then
		self.FriendGroupInviteNotification:FadeOut()
		self.FriendGroupInviteNotification = nil
	end
end

function Plugin:ReceiveFriendGroupInvite( Data )
	if SGUI.IsValid( self.FriendGroupInviteNotification ) then
		self.FriendGroupInviteNotification:FadeOut()
		self.FriendGroupInviteNotification = nil
	end

	if self.Config.AutoAcceptSteamFriendGroupInvites and Client.GetIsSteamFriend( Data.InviterID ) then
		self:SendNetworkMessage( "FriendGroupInviteAnswer", { Accepted = true }, true )
		return
	end

	local function MakeClickFunc( Accept )
		return function( Button, Notification )
			Notification:FadeOut()
			self.FriendGroupInviteNotification = nil
			self:SendNetworkMessage( "FriendGroupInviteAnswer", { Accepted = Accept }, true )
		end
	end

	self.FriendGroupInviteNotification = SGUI.NotificationManager.AddNotification(
		Shine.NotificationType.INFO,
		self:GetInterpolatedPhrase( "INVITED_TO_FRIEND_GROUP", Data ),
		Data.ExpiryTime - SharedGetTime(),
		{
			Buttons = {
				{
					Text = self:GetPhrase( "ACCEPT_FRIEND_GROUP_INVITE" ),
					Icon = SGUI.Icons.Ionicons.Checkmark,
					StyleName = "AcceptButton",
					DoClick = MakeClickFunc( true )
				},
				{
					Text = self:GetPhrase( "DECLINE_FRIEND_GROUP_INVITE" ),
					Icon = SGUI.Icons.Ionicons.Close,
					StyleName = "DeclineButton",
					DoClick = MakeClickFunc( false )
				}
			}
		}
	)
end

function Plugin:ReceiveFriendGroupInviteCancelled( Data )
	self:DismissFriendGroupInvite()
end

function Plugin:ReceiveLeftFriendGroup( Data )
	self.FriendGroup = {}
	self.InFriendGroup = false
end

function Plugin:ReceiveFriendGroupConfig( Data )
	self.FriendGroup.LeaderID = Data.LeaderID
	self.FriendGroup.LeaderType = Data.LeaderType
end

function Plugin:ReceiveFriendGroupUpdated( Data )
	self.FriendGroup[ Data.SteamID ] = Data.Joined or nil

	for SteamID in pairs( self.FriendGroup ) do
		if SteamID ~= Client.GetSteamId() then
			self.InFriendGroup = true
			return
		end
	end

	self.InFriendGroup = false
end

local IsPlayingTeam = Shine.IsPlayingTeam
local pairs = pairs

function Plugin:UpdateTeamMemoryEntry( ClientIndex, TeamNumber, CurTime )
	local MemoryEntry = self.TeamTracking:Get( ClientIndex )
	if not MemoryEntry then
		-- Start with the team they're currently on to avoid everyone flashing on first join.
		MemoryEntry = { TeamNumber = TeamNumber }
		self.TeamTracking:Add( ClientIndex, MemoryEntry )
	end

	-- For some reason, spectators are constantly swapped between team 0 and 3.
	-- So just don't both flashing for ready room/spectator.
	if MemoryEntry.TeamNumber ~= TeamNumber then
		MemoryEntry.TeamNumber = TeamNumber
		if IsPlayingTeam( TeamNumber ) then
			MemoryEntry.LastChange = CurTime
		end
	end

	return MemoryEntry
end

function Plugin:Initialise()
	self.TeamTracking = Shine.UnorderedMap()
	self.FriendGroup = {}
	self.InFriendGroup = false

	-- Track changes in a separate timer too as the scoreboard's team update
	-- only runs when the scoreboard is visible.
	self:CreateTimer( "TrackTeamChanges", 1, -1, function()
		if not self.dt.HighlightTeamSwaps then return end
		if not ScoreboardUI_GetAllScores then return end

		local Scores = ScoreboardUI_GetAllScores()
		local CurTime = SharedGetTime()
		local Clients = {}

		for i = 1, #Scores do
			local Entry = Scores[ i ]

			local ClientIndex = Entry.ClientIndex
			Clients[ ClientIndex ] = true

			self:UpdateTeamMemoryEntry( ClientIndex, Entry.EntityTeamNumber, CurTime )
		end

		for ClientIndex in self.TeamTracking:Iterate() do
			if not Clients[ ClientIndex ] then
				self.TeamTracking:Remove( ClientIndex )
			end
		end
	end )

	self:SetupClientConfig()

	self.Enabled = true

	return true
end

local function IsGameInProgress()
	local GameInfo = GetGameInfoEntity()
	if GameInfo and ( GameInfo:GetCountdownActive() or GameInfo:GetGameStarted() ) then
		return true
	end
	return false
end

function Plugin:OnGUIScoreboardSendKeyEvent( Scoreboard, Key, Down )
	if not self.dt.IsFriendGroupingEnabled or IsGameInProgress() then
		return
	end

	local HoverMenu = Scoreboard.hoverMenu
	if not Scoreboard.visible or not HoverMenu or not HoverMenu.background
	or not HoverMenu.background:GetIsVisible() then
		return
	end

	-- Hover menu is open, add a button to group with players.
	local Buttons = HoverMenu.links
	if not Buttons then return end

	local SelfSteamID = Client.GetSteamId()
	local SteamID = GetSteamIdForClientIndex( Scoreboard.hoverPlayerClientIndex ) or 0
	local HoveringSelf = SelfSteamID == SteamID

	if ( HoveringSelf and not self.InFriendGroup )
	or ( not HoveringSelf and self.FriendGroup[ SteamID ] and self.FriendGroup.LeaderID ~= SelfSteamID ) then
		-- No action possible if hovering self when not in a group, or hovering a group member and not the group leader.
		return
	end

	if not HoveringSelf and self.InFriendGroup and self.FriendGroup.LeaderID ~= SelfSteamID
	and self.FriendGroup.LeaderType == self.FriendGroupLeaderType.LEADER_ADD_ONLY then
		-- Only the group leader can add more players to the group.
		return
	end

	local BackgroundColour, HighlightColour, TextColour
	local FriendGroupButton
	for i = #Buttons, 1, -1 do
		local Button = Buttons[ i ]
		if Button.IsShuffleFriendGroupButton then
			FriendGroupButton = Button.link
			break
		end

		if not BackgroundColour and not Button.isSeparator then
			BackgroundColour = Button.bgColor
			HighlightColour = Button.bgHighlightColor
			TextColour = Button.link:GetColor()
		end
	end

	local IsTargetInGroup = self.FriendGroup[ SteamID ]
	local Text
	if HoveringSelf then
		Text = self:GetPhrase( "LEAVE_FRIEND_GROUP" )
	elseif self.InFriendGroup then
		if IsTargetInGroup then
			Text = self:GetPhrase( "REMOVE_FROM_FRIEND_GROUP" )
		else
			Text = self:GetPhrase( "ADD_TO_FRIEND_GROUP" )
		end
	else
		Text = self:GetPhrase( "JOIN_FRIEND_GROUP" )
	end

	if not FriendGroupButton then
		-- Button not added yet, add it.
		HoverMenu:AddSeparator( "ShuffleFriendGroupActions" )
		HoverMenu:AddButton( Text, BackgroundColour, HighlightColour, TextColour, function()
			-- Disable the hint as they've used the feature.
			SGUI.NotificationManager.DisableHint( FRIEND_GROUP_HINT_NAME )

			if HoveringSelf then
				self:SendNetworkMessage( "LeaveFriendGroup", {}, true )
			else
				if IsTargetInGroup then
					self:SendNetworkMessage( "RemoveFromFriendGroup", { SteamID = SteamID }, true )
				else
					self:SendNetworkMessage( "JoinFriendGroup", { SteamID = SteamID }, true )
				end
			end
		end )
		FriendGroupButton = HoverMenu.links[ #HoverMenu.links ]
		FriendGroupButton.IsShuffleFriendGroupButton = true

		HoverMenu:AdjustMenuSize()
	elseif FriendGroupButton:GetText() ~= Text then
		FriendGroupButton:SetText( Text )

		HoverMenu:AdjustMenuSize()
	end
end

local Abs = math.abs
local Cos = math.cos

local FadeAlphaMin = 0.3
local FadeAlphaMult = 1 - FadeAlphaMin
local HighlightDuration = 10
local OscillationMultiplier = HighlightDuration * math.pi * 0.5

local FriendColour = Colour( 0, 0.75, 0.15 )
local FriendLeaderColour = Colour( 0, 1, 0.2 )

local function FadeRowIn( Row, Entry, TimeSinceLastChange )
	if not Entry then return end

	local OriginalColour = Row.Background:GetColor()

	-- Oscillate the entry in for a short time after joining a team.
	local Oscillation = Abs( Cos( TimeSinceLastChange / HighlightDuration * OscillationMultiplier ) )
	local Mult = FadeAlphaMin + Oscillation * FadeAlphaMult
	OriginalColour.a = Mult * OriginalColour.a

	Row.Background:SetColor( OriginalColour )
end

local function CheckRow( self, Row, TeamNumber, CurTime, ShouldShowFriendGroup )
	local ClientIndex = Row and Row.ClientIndex
	if not ClientIndex then return end

	local Entry = Scoreboard_GetPlayerRecord( ClientIndex )
	if Entry and ShouldShowFriendGroup and self.FriendGroup[ Entry.SteamId ] then
		Row.Background:SetColor( Entry.SteamId == self.FriendGroup.LeaderID and FriendLeaderColour or FriendColour )
	end

	if not self.dt.HighlightTeamSwaps then return Entry end

	local MemoryEntry = self:UpdateTeamMemoryEntry( ClientIndex, TeamNumber, CurTime )
	if not MemoryEntry.LastChange then return Entry end

	local TimeSinceLastChange = CurTime - MemoryEntry.LastChange
	if TimeSinceLastChange >= HighlightDuration then return Entry end

	FadeRowIn( Row, Entry, TimeSinceLastChange )

	return Entry
end

local MathStandardDeviation = math.StandardDeviation

function Plugin:OnGUIScoreboardUpdateTeam( Scoreboard, Team )
	local TeamNumber = Team.TeamNumber

	local ShouldTrackStdDev = self.dt.DisplayStandardDeviations and IsPlayingTeam( TeamNumber )
	if not ShouldTrackStdDev and not self.dt.HighlightTeamSwaps and not self.InFriendGroup then return end

	local SkillValues = ShouldTrackStdDev and {}
	local CurTime = SharedGetTime()
	local ShouldShowFriendGroup = self.InFriendGroup and not IsGameInProgress()
	for i = 1, #Team.PlayerList do
		local Row = Team.PlayerList[ i ]
		local Entry = CheckRow( self, Row, TeamNumber, CurTime, ShouldShowFriendGroup )
		if ShouldTrackStdDev and Entry and Entry.SteamId > 0 then
			SkillValues[ #SkillValues + 1 ] = Entry.Skill
		end
	end

	if not ShouldTrackStdDev then return end

	local TeamNameItem = Team.GUIs.TeamName
	local StandardDeviation = MathStandardDeviation( SkillValues )

	TeamNameItem:SetText( StringFormat( "%s - Skill SD: %.2f",
		TeamNameItem:GetText(), StandardDeviation ) )

	-- Move the skill icon along otherwise it will overlap the added text.
	local TeamSkillIcon = Team.GUIs.TeamSkill
	if TeamSkillIcon and TeamSkillIcon:GetIsVisible() then
		local ScaleFactor = Scoreboard.kScalingFactor or 1
		local CurrentPosition = TeamSkillIcon:GetPosition()
		CurrentPosition.x = ( TeamNameItem:GetTextWidth( TeamNameItem:GetText() ) + 20 ) * ScaleFactor
		TeamSkillIcon:SetPosition( CurrentPosition )
	end
end
