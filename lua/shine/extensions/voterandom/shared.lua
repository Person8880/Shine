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

function Plugin:Initialise()
	self.TeamTracking = {}
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

local SharedGetTime = Shared.GetTime
local CopyColour = Shine.GUI.CopyColour
local pairs = pairs
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
	local ClientID = Row.ClientIndex
	local Entry = Scoreboard_GetPlayerRecord( ClientID )
	local MemoryEntry = self.TeamTracking[ ClientID ]

	if not MemoryEntry then
		MemoryEntry = {
			TeamNumber = TeamNumber,
			LastChange = CurTime
		}
		self.TeamTracking[ ClientID ] = MemoryEntry
		return
	end

	if MemoryEntry.TeamNumber ~= TeamNumber then
		MemoryEntry.TeamNumber = TeamNumber
		MemoryEntry.LastChange = CurTime
	end

	local TimeSinceLastChange = CurTime - MemoryEntry.LastChange
	if TimeSinceLastChange >= HighlightDuration then return end

	FadeRowIn( Row, Entry, Team, OurTeam, TeamNumber, TimeSinceLastChange )
end

function Plugin:OnGUIScoreboardUpdateTeam( Scoreboard, Team )
	if not self.dt.HighlightTeamSwaps then return end

	local PlayerList = Team.PlayerList
	local TeamNumber = Team.TeamNumber
	local OurTeam = GetLocalPlayerTeam()

	local CurTime = SharedGetTime()
	for Index, Row in pairs( PlayerList ) do
		CheckRow( self, Team, Row, OurTeam, TeamNumber, CurTime )
	end

	for ClientID in pairs( self.TeamTracking ) do
		if not Scoreboard_GetPlayerRecord( ClientID ) then
			self.TeamTracking[ ClientID ] = nil
		end
	end
end
