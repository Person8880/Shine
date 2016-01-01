--[[
	Shuffle plugin shared code.
]]

local Plugin = {}

function Plugin:SetupDataTable()
	self:AddDTVar( "boolean", "HighlightTeamSwaps", false )
end

Shine:RegisterExtension( "voterandom", Plugin )

if Server then return end

function Plugin:OnFirstThink()
	-- Defensive check in case the scoreboard code changes.
	if not Scoreboard_GetPlayerRecord or not GUIScoreboard or not GUIScoreboard.UpdateTeam then return end

	Shine.Hook.SetupClassHook( "GUIScoreboard", "UpdateTeam", "OnGUIScoreboardUpdateTeam", "PassivePost" )
end

local pairs = pairs
local SharedGetTime = Shared.GetTime

function Plugin:UpdateTeamMemoryEntry( ClientIndex, TeamNumber, CurTime )
	local MemoryEntry = self.TeamTracking[ ClientIndex ]
	if not MemoryEntry then
		MemoryEntry = {}
		self.TeamTracking[ ClientIndex ] = MemoryEntry
	end

	if MemoryEntry.TeamNumber ~= TeamNumber then
		MemoryEntry.TeamNumber = TeamNumber
		MemoryEntry.LastChange = CurTime
	end

	return MemoryEntry
end

function Plugin:Initialise()
	self.TeamTracking = {}

	-- Track changes in a separate timer too as the scoreboard's team update
	-- only runs when the scoreboard is visible.
	self:CreateTimer( "TrackTeamChanges", 1, -1, function()
		if not self.dt.HighlightTeamSwaps then return end

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

local CopyColour = Shine.GUI.CopyColour
local FadeAlphaMin = 0.3
local FadeAlphaMult = 1 - FadeAlphaMin
local HighlightDuration = 10

local function FadeRowIn( Row, Entry, Team, OurTeam, TeamNumber, TimeSinceLastChange )
	local IsCommander = IsVisibleTeam( OurTeam, TeamNumber ) and Entry.IsCommander
	local OriginalColour = IsCommander and GUIScoreboard.kCommanderFontColor or Team.Color

	-- Fade the entry in for a short time after joining a team.
	local Mult = FadeAlphaMin + ( TimeSinceLastChange / HighlightDuration ) * FadeAlphaMult
	local HighlightColour = CopyColour( OriginalColour )
	HighlightColour.a = Mult * OriginalColour.a

	Row.Background:SetColor( HighlightColour )
end

local function CheckRow( self, Team, Row, OurTeam, TeamNumber, CurTime )
	local ClientIndex = Row.ClientIndex
	local MemoryEntry = self:UpdateTeamMemoryEntry( ClientIndex, TeamNumber, CurTime )

	local TimeSinceLastChange = CurTime - MemoryEntry.LastChange
	if TimeSinceLastChange >= HighlightDuration then return end

	FadeRowIn( Row, Scoreboard_GetPlayerRecord( ClientIndex ), Team,
		OurTeam, TeamNumber, TimeSinceLastChange )
end

function Plugin:OnGUIScoreboardUpdateTeam( Scoreboard, Team )
	if not self.dt.HighlightTeamSwaps then return end

	local TeamNumber = Team.TeamNumber
	local OurTeam = GetLocalPlayerTeam()

	local CurTime = SharedGetTime()
	for Index, Row in pairs( Team.PlayerList ) do
		CheckRow( self, Team, Row, OurTeam, TeamNumber, CurTime )
	end
end
