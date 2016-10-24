--[[
	Local stats storage and querying.
]]

local Shine = Shine

local GetOwner = Server.GetOwner
local Min = math.min
local setmetatable = setmetatable
local tostring = tostring

local StatsModule = {}

StatsModule.DefaultConfig = {
	UseLocalFileStats = false,
	StatsRecording = {
		-- How many minutes must a player be on a team to have a win/loss count?
		MinMinutesOnTeam = 5,
		-- Stat to determine rookie status.
		RookieStat = "Score",
		-- Value to be greater-equal to be considered not a rookie.
		RookieBoundary = 7500
	}
}

StatsModule.STATS_FILE_PATH = "config://shine/stats/PlayerStats.json"
StatsModule.TrackedStats = table.AsEnum{
	"Kills",
	"Deaths",
	"Assists",
	"Score",
	"PlayTime",
	"Wins",
	"Losses"
}

local function GetClientUID( Client )
	return tostring( Client:GetUserId() )
end

function StatsModule:OnFirstThink()
	if not self.Config.UseLocalFileStats then return end

	Shine.Hook.SetupClassHook( "Player", "SetRookie", "OnPlayerSetRookie", "ActivePre" )
end

function StatsModule:Initialise()
	if not self.Config.UseLocalFileStats then return end

	if not self.TrackedStats[ self.Config.StatsRecording.RookieStat ] then
		table.Mixin( self.DefaultConfig.StatsRecording, self.Config.StatsRecording, {
			"RookieStat", "RookieBoundary"
		} )
		self:Print( "Invalid value for \"RookieStat\". Valid values are: \"%s\". Resetting to default...", true,
			Shine.Stream( self.TrackedStats ):Concat( "\", \"", tostring ) )
	end

	self.StatsStorage = Shine.Storage( self.STATS_FILE_PATH )
end

do
	local function BuildIncrementer( StatValue )
		return function( self, Player, Value )
			if not self.Config.UseLocalFileStats then return end
			if not self.StatsStorage:IsInTransaction() then return end

			local Client = GetOwner( Player )
			if not Client or Client:GetIsVirtual() then return end

			self:IncrementStatValue( GetClientUID( Client ), Player, StatValue, Value or 1 )
		end
	end

	local Events = {
		"AddKill", "AddScore", "AddDeaths", "AddAssistKill"
	}
	local Stats = {
		"Kills", "Score", "Deaths", "Assists"
	}
	for i = 1, #Events do
		StatsModule[ Events[ i ] ] = BuildIncrementer( Stats[ i ] )
	end
end

StatsModule.StatKeys = {
	Kills = "totalKills",
	Deaths = "totalDeaths",
	Score = "totalScore",
	Assists = "totalAssists",
	PlayTime = "totalPlayTime"
}
-- Inherit Hive values if no value is currently stored.
function StatsModule:GetDefaultStatValue( Player, Stat )
	local Key = self.StatKeys[ Stat ]
	if not Key then
		return 0
	end

	return Player[ Key ] or 0
end

function StatsModule:GameStarting( Gamerules )
	if not self.Config.UseLocalFileStats then return end

	self.StatsStorage:BeginTransaction()
end

function StatsModule:ResetGame()
	if not self.Config.UseLocalFileStats then return end
	if not self.StatsStorage:IsInTransaction() then return end

	self.StatsStorage:Rollback()
end

function StatsModule:GetStat( ClientID, Player, Stat )
	return self.StatsStorage:GetAtPath( ClientID, Stat ) or self:GetDefaultStatValue( Player, Stat )
end

function StatsModule:IncrementStatValue( ClientID, Player, Stat, Amount )
	local CurrentValue = self:GetStat( ClientID, Player, Stat )
	self.StatsStorage:SetAtPath( CurrentValue + Amount, ClientID, Stat )
end

function StatsModule:IsRookie( ClientID, Player )
	local StatValue = self:GetStat( ClientID, Player, self.Config.StatsRecording.RookieStat )
	return StatValue < self.Config.StatsRecording.RookieBoundary
end

function StatsModule:IsPlayerRookie( Player )
	local Client = GetOwner( Player )
	if not Client then return false end

	return self:IsRookie( GetClientUID( Client ), Player )
end

function StatsModule:EvaluateRookieMode( ClientID, Player )
	if not self:IsRookie( ClientID, Player ) then
		Player:SetRookie( false )
	end
end

function StatsModule:OnPlayerSetRookie( Player, RookieStatus )
	if not self.Config.UseLocalFileStats then return end
	if not RookieStatus then return end
	if self:IsPlayerRookie( Player ) then return end

	return false
end

function StatsModule:GetKDRStat( ClientID, Player )
	local Kills = self:GetStat( ClientID, Player, "Kills" )
	local Deaths = self:GetStat( ClientID, Player, "Deaths" )
	local Assists = self:GetStat( ClientID, Player, "Assists" )

	Kills = Kills + Assists * 0.1

	if Deaths == 0 then return Kills end

	return Kills / Deaths
end

function StatsModule:GetPlayerKDR( Player )
	if not self.Config.UseLocalFileStats then return end

	local Client = GetOwner( Player )
	if not Client then return 0 end

	return self:GetKDRStat( GetClientUID( Client ), Player )
end

function StatsModule:GetScorePerMinuteStat( ClientID, Player )
	local PlayTime = self:GetStat( ClientID, Player, "PlayTime" ) / 60
	if PlayTime <= 0 then return 0 end

	return self:GetStat( ClientID, Player, "Score" ) / PlayTime
end

function StatsModule:GetPlayerScorePerMinute( Player )
	if not self.Config.UseLocalFileStats then return end

	local Client = GetOwner( Player )
	if not Client then return 0 end

	return self:GetScorePerMinuteStat( GetClientUID( Client ), Player )
end

function StatsModule:ClientDisconnect( Client )
	if not self.Config.UseLocalFileStats then return end
	if Client:GetIsVirtual() then return end
	if not self.StatsStorage:IsInTransaction() then return end

	local Player = Client:GetControllingPlayer()
	if not Player or not Player.GetPlayTime or not Player:GetPlayTime() then return end

	-- Store the client's playtime when they disconnect.
	self:IncrementStatValue( GetClientUID( Client ), Player, "PlayTime", Player:GetPlayTime() )
end

function StatsModule:StoreRoundEndData( ClientID, Player, WinningTeamNumber, RoundLength )
	local MinTimeOnTeam = Min( self.Config.StatsRecording.MinMinutesOnTeam * 60, RoundLength * 0.95 )
	local Team = Player:GetTeamNumber()

	-- Only add win/loss if the player was on the team for more than the minimum time.
	local TimeOnTeam = Team == 1 and Player:GetMarinePlayTime() or Player:GetAlienPlayTime() or 0
	if TimeOnTeam >= MinTimeOnTeam then
		local Stat = Team == WinningTeamNumber and "Wins" or "Losses"
		self:IncrementStatValue( ClientID, Player, Stat, 1 )
	end

	-- Re-evaluate whether the player is still a rookie based upon the recorded data.
	self:IncrementStatValue( ClientID, Player, "PlayTime", Player:GetPlayTime() )
	self:EvaluateRookieMode( ClientID, Player )
end

function StatsModule:EndGame( Gamerules, WinningTeam, Players )
	if not self.Config.UseLocalFileStats then return end

	local WinningTeamNumber = WinningTeam:GetTeamNumber()
	local RoundLength = Shared.GetTime() - Gamerules.gameStartTime

	for i = 1, #Players do
		local Player = Players[ i ]
		local Client = GetOwner( Player )
		if not Client:GetIsVirtual() and Player.client and Player.GetMarinePlayTime then
			self:StoreRoundEndData( GetClientUID( Client ), Player, WinningTeamNumber, RoundLength )
		end
	end

	self.StatsStorage:Commit()
end

Plugin:AddModule( StatsModule )
