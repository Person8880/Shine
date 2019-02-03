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
Plugin.DefaultConfig = {
	PreferredTeam = Plugin.TeamType.NONE,
	BlockFriendGroups = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

local StringFormat = string.format
local StringUpper = string.upper

do
	local Validator = Shine.Validator()
	Validator:AddFieldRule( "PreferredTeam", Validator.InEnum( Plugin.TeamType, Plugin.TeamType.NONE ) )
	Plugin.ConfigValidator = Validator
end

function Plugin:SetupClientConfig()
	Shine.AddStartupMessage( "You can choose a preferred team for shuffling by entering sh_shuffle_teampref <team> into the console." )

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

	local HasWarnedAboutPref = false
	self:BindCommand( "sh_shuffle_teampref", function( PreferredTeam )
		local OldPref = self.Config.PreferredTeam
		local NewPref = self.TeamType[ PreferredTeam ] or self.TeamType.NONE
		if OldPref == NewPref then return end

		self.Config.PreferredTeam = NewPref
		self:SaveConfig( true )
		SendTeamPreference( PreferredTeam )

		self:OnTeamPreferenceChanged()

		local ResetHint = ""
		if self.Config.PreferredTeam ~= self.TeamType.NONE then
			ResetHint = " Enter this command again with no arguments to reset your preference."
		end

		Print( "Team preference saved as: %s.%s", self.Config.PreferredTeam, ResetHint )

		if not HasWarnedAboutPref then
			-- Inform the player that this can be overridden by joining a team.
			HasWarnedAboutPref = true
			Shine.GUI.NotificationManager.AddNotification( Shine.NotificationType.INFO,
				self:GetPhrase( "TEAM_PREFERENCE_CHANGE_HINT" ), 10 )
		end
	end ):AddParam{ Type = "team", Optional = true, Default = 3 }

	Shine:RegisterClientSetting( {
		Type = "Radio",
		Command = "sh_shuffle_teampref",
		ConfigOption = function() return self.Config.PreferredTeam end,
		Options = self.TeamType,
		Description = "TEAM_PREFERENCE",
		TranslationSource = self.__Name
	} )

	local function SendFriendGroupOptOut( OptOut )
		self:SendNetworkMessage( "FriendGroupOptOut", { OptOut = OptOut }, true )
	end

	if self.Config.BlockFriendGroups then
		SendFriendGroupOptOut( self.Config.BlockFriendGroups )
	end

	self:BindCommand( "sh_shuffle_block_friend_groups", function( OptOut )
		if self.Config.BlockFriendGroups == OptOut then return end

		self.Config.BlockFriendGroups = OptOut
		self:SaveConfig( true )
		SendFriendGroupOptOut( OptOut )

		Print( "You are now %s friend groups.", OptOut and "blocking" or "allowing" )
	end ):AddParam{ Type = "boolean", Option = true, Default = function() return not self.Config.BlockFriendGroups end }

	Shine:RegisterClientSetting( {
		Type = "Boolean",
		Command = "sh_shuffle_block_friend_groups",
		ConfigOption = function() return self.Config.BlockFriendGroups end,
		Description = "FRIEND_GROUPS_OPT_OUT",
		TranslationSource = self.__Name
	} )
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

	if TeamPreference ~= self.TeamType.NONE then
		local IsMarines = TeamPreference == self.TeamType.MARINE
		local PreferenceLabel = Button.PreferenceLabel or SGUI:Create( "ColourLabel", VoteMenu.Background )
		PreferenceLabel:MakeVertical()
		PreferenceLabel:SetAnchor( "CentreMiddle" )
		PreferenceLabel:SetFontScale( Button:GetFont(), Button:GetTextScale() )
		PreferenceLabel:SetDefaultLabelType( "ShadowLabel" )
		PreferenceLabel:SetText( {
			Colour( 1, 1, 1 ),
			self:GetPhrase( "TEAM_PREFERENCE_HINT" ),
			IsMarines and Colour( 0.3, 0.69, 1 ) or Colour( 1, 0.79, 0.23 ),
			self:GetPhrase( TeamPreference )
		} )
		PreferenceLabel:SetTextAlignmentX( GUIItem.Align_Center )
		PreferenceLabel:SetTextAlignmentY( GUIItem.Align_Max )
		PreferenceLabel:SetShadow( {
			Colour = Colour( 0, 0, 0, 200 / 255 ),
			Offset = Vector2( 2, 2 )
		} )

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
			SGUI.NotificationManager.DisplayHint( "ShuffleFriendGroupHint" )
			return OldClick( self )
		end
	end
end

function Plugin:OnFirstThink()
	self:CallModuleEvent( "OnFirstThink" )

	SGUI.NotificationManager.RegisterHint( "ShuffleFriendGroupHint", {
		MaxTimes = 3,
		HintIntervalInSeconds = 60 * 60,
		MessageSource = self:GetName(),
		MessageKey = "FRIEND_GROUP_HINT",
		HintDuration = 10
	} )

	-- Defensive check in case the scoreboard code changes.
	if not Scoreboard_GetPlayerRecord or not GUIScoreboard or not GUIScoreboard.UpdateTeam then return end

	Shine.Hook.SetupClassHook( "GUIScoreboard", "UpdateTeam", "OnGUIScoreboardUpdateTeam", "PassivePost" )
	Shine.Hook.SetupClassHook( "GUIScoreboard", "SendKeyEvent", "OnGUIScoreboardSendKeyEvent", "PassivePost" )
end

function Plugin:ReceiveLeftFriendGroup( Data )
	self.FriendGroup = {}
	self.InFriendGroup = false
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
local SharedGetTime = Shared.GetTime

function Plugin:UpdateTeamMemoryEntry( ClientIndex, TeamNumber, CurTime )
	local MemoryEntry = self.TeamTracking[ ClientIndex ]
	if not MemoryEntry then
		-- Start with the team they're currently on to avoid everyone flashing on first join.
		MemoryEntry = { TeamNumber = TeamNumber }
		self.TeamTracking[ ClientIndex ] = MemoryEntry
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
	self.TeamTracking = {}
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

		for ClientIndex in pairs( self.TeamTracking ) do
			if not Clients[ ClientIndex ] then
				self.TeamTracking[ ClientIndex ] = nil
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

	local SteamID = GetSteamIdForClientIndex( Scoreboard.hoverPlayerClientIndex ) or 0
	local HoveringSelf = Client.GetSteamId() == SteamID

	if ( HoveringSelf and not self.InFriendGroup ) or ( not HoveringSelf and self.FriendGroup[ SteamID ] ) then
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

	local Text
	if HoveringSelf then
		Text = self:GetPhrase( "LEAVE_FRIEND_GROUP" )
	elseif self.InFriendGroup then
		Text = self:GetPhrase( "ADD_TO_FRIEND_GROUP" )
	else
		Text = self:GetPhrase( "JOIN_FRIEND_GROUP" )
	end

	if not FriendGroupButton then
		-- Button not added yet, add it.
		HoverMenu:AddSeparator( "ShuffleFriendGroupActions" )
		HoverMenu:AddButton( Text, BackgroundColour, HighlightColour, TextColour, function()
			-- Disable the hint as they've used the feature.
			SGUI.NotificationManager.DisableHint( "ShuffleFriendGroupHint" )

			if HoveringSelf then
				self:SendNetworkMessage( "LeaveFriendGroup", {}, true )
			else
				self:SendNetworkMessage( "JoinFriendGroup", { SteamID = SteamID }, true )
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

local FriendColour = Colour( 0, 1, 0.2 )

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
		Row.Background:SetColor( FriendColour )
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
local StringFormat = string.format

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
