--[[
	Shuffle plugin shared code.
]]

local Plugin = {}
Plugin.NotifyPrefixColour = {
	100, 255, 100
}

function Plugin:SetupDataTable()
	self:AddDTVar( "boolean", "HighlightTeamSwaps", false )
	self:AddDTVar( "boolean", "DisplayStandardDeviations", false )
	self:AddDTVar( "integer", "CurrentShuffleVotes", 0 )
	self:AddDTVar( "integer", "RequiredShuffleVotes", 0 )

	local MessageTypes = {
		ShuffleType = {
			ShuffleType = "string (24)"
		},
		ShuffleDuration = {
			ShuffleType = "string (24)",
			Duration = "integer"
		},
		PlayerVote  = {
			ShuffleType = "string (24)",
			PlayerName = self:GetNameNetworkField(),
			VotesNeeded = "integer"
		},
		PrivateVote = {
			ShuffleType = "string (24)",
			VotesNeeded = "integer"
		}
	}

	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ table.Copy( MessageTypes.ShuffleType ) ] = {
			"ENABLED_TEAMS"
		}
	}, "ShuffleType" )
	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.ShuffleType ] = {
			"AUTO_SHUFFLE", "PREVIOUS_VOTE_SHUFFLE",
			"TEAM_SWITCH_DENIED", "NEXT_ROUND_SHUFFLE",
			"TEAMS_FORCED_NEXT_ROUND",
			"SHUFFLE_AND_RESTART", "SHUFFLING_TEAMS",
			"TEAM_ENFORCING_TIMELIMIT", "DISABLED_TEAMS"
		},
		[ MessageTypes.ShuffleDuration ] = {
			"TEAMS_SHUFFLED_FOR_DURATION"
		},
		[ MessageTypes.PlayerVote ] = {
			"PLAYER_VOTED"
		},
		[ MessageTypes.PrivateVote ] = {
			"PLAYER_VOTED_PRIVATE"
		}
	}, "ShuffleType" )
	self:AddNetworkMessages( "AddTranslatedError", {
		[ MessageTypes.ShuffleType ] = {
			"ERROR_CANNOT_START", "ERROR_ALREADY_ENABLED",
			"ERROR_TEAMS_FORCED", "ERROR_ALREADY_VOTED"
		}
	}, "ShuffleType" )
end

Shine:RegisterExtension( "voterandom", Plugin )

if Server then return end

local StringFormat = string.format

function Plugin:UpdateShuffleButton()
	local ShuffleButton = Shine.VoteMenu:GetButtonByPlugin( "Shuffle" )
	if not ShuffleButton then return end

	if self.dt.CurrentShuffleVotes == 0 or self.dt.RequiredShuffleVotes == 0 then
		ShuffleButton:SetText( ShuffleButton.DefaultText )
		return
	end

	-- Update the button with the current vote count.
	ShuffleButton:SetText( StringFormat( "%s (%d/%d)", ShuffleButton.DefaultText,
		self.dt.CurrentShuffleVotes,
		self.dt.RequiredShuffleVotes ) )
end

function Plugin:NetworkUpdate( Key, Old, New )
	if Key == "RequiredShuffleVotes" or Key == "CurrentShuffleVotes" then
		if not Shine.VoteMenu.Visible then return end

		self:UpdateShuffleButton()
	end
end

function Plugin:OnFirstThink()
	Shine.VoteMenu:EditPage( "Main", function( VoteMenu )
		if not self.Enabled then return end

		self:UpdateShuffleButton()
	end )

	-- Defensive check in case the scoreboard code changes.
	if not Scoreboard_GetPlayerRecord or not GUIScoreboard or not GUIScoreboard.UpdateTeam then return end

	Shine.Hook.SetupClassHook( "GUIScoreboard", "UpdateTeam", "OnGUIScoreboardUpdateTeam", "PassivePost" )
end

local IsPlayingTeam = Shine.IsPlayingTeam
local pairs = pairs
local SharedGetTime = Shared.GetTime

function Plugin:UpdateTeamMemoryEntry( ClientIndex, TeamNumber, CurTime )
	local MemoryEntry = self.TeamTracking[ ClientIndex ]
	if not MemoryEntry then
		MemoryEntry = {}
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

	self.Enabled = true

	return true
end

local function IsVisibleTeam( OurTeam, TeamNumber )
	return OurTeam == TeamNumber or OurTeam == kTeamReadyRoom or OurTeam == kSpectatorIndex
end

local ClientGetLocalPlayer = Client.GetLocalPlayer

local function GetLocalPlayerTeam()
	local Player = ClientGetLocalPlayer()
	if not Player then return nil end

	return Player:GetTeamNumber()
end

local Abs = math.abs
local CopyColour = Shine.GUI.CopyColour
local Cos = math.cos

local FadeAlphaMin = 0.3
local FadeAlphaMult = 1 - FadeAlphaMin
local HighlightDuration = 10
local OscillationMultiplier = HighlightDuration * math.pi * 0.5

local function FadeRowIn( Row, Entry, Team, OurTeam, TeamNumber, TimeSinceLastChange )
	if not Entry then return end

	local IsCommander = IsVisibleTeam( OurTeam, TeamNumber ) and Entry.IsCommander
	local OriginalColour = IsCommander and GUIScoreboard.kCommanderFontColor or Team.Color

	-- Fade the entry in for a short time after joining a team.
	local Mult = FadeAlphaMin + Abs( Cos( TimeSinceLastChange / HighlightDuration * OscillationMultiplier ) ) * FadeAlphaMult
	local HighlightColour = CopyColour( OriginalColour )
	HighlightColour.a = Mult * OriginalColour.a

	Row.Background:SetColor( HighlightColour )
end

local function CheckRow( self, Team, Row, OurTeam, TeamNumber, CurTime )
	local ClientIndex = Row.ClientIndex
	if not ClientIndex then return end

	local Entry = Scoreboard_GetPlayerRecord( ClientIndex )
	if not self.dt.HighlightTeamSwaps then return Entry end

	local MemoryEntry = self:UpdateTeamMemoryEntry( ClientIndex, TeamNumber, CurTime )
	if not MemoryEntry.LastChange then return Entry end

	local TimeSinceLastChange = CurTime - MemoryEntry.LastChange
	if TimeSinceLastChange >= HighlightDuration then return Entry end

	FadeRowIn( Row, Entry, Team, OurTeam, TeamNumber, TimeSinceLastChange )

	return Entry
end

local MathStandardDeviation = math.StandardDeviation
local StringFormat = string.format

function Plugin:OnGUIScoreboardUpdateTeam( Scoreboard, Team )
	local TeamNumber = Team.TeamNumber

	local ShouldTrackStdDev = self.dt.DisplayStandardDeviations and IsPlayingTeam( TeamNumber )
	if not ShouldTrackStdDev and not self.dt.HighlightTeamSwaps then return end

	local OurTeam = GetLocalPlayerTeam()

	local SkillValues = ShouldTrackStdDev and {}
	local CurTime = SharedGetTime()
	for Index, Row in pairs( Team.PlayerList ) do
		local Entry = CheckRow( self, Team, Row, OurTeam, TeamNumber, CurTime )
		if ShouldTrackStdDev and Entry and Entry.SteamId > 0 then
			SkillValues[ #SkillValues + 1 ] = Entry.Skill
		end
	end

	if not ShouldTrackStdDev then return end

	local TeamNameItem = Team.GUIs.TeamName
	local StandardDeviation = MathStandardDeviation( SkillValues )

	TeamNameItem:SetText( StringFormat( "%s - Skill SD: %.2f",
		TeamNameItem:GetText(), StandardDeviation ) )
end
