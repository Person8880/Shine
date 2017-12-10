--[[
	Local stats functionality tests.
]]

local UnitTest = Shine.UnitTest

local VoteShuffle = UnitTest:LoadExtension( "voterandom" )
if not VoteShuffle or not VoteShuffle.Config then return end

VoteShuffle.Config.UseLocalFileStats = true
VoteShuffle.Config.StatsRecording = {
	MinMinutesOnTeam = 5,
	RookieStat = "Score",
	RookieBoundary = 7500
}
VoteShuffle:BroadcastModuleEvent( "Initialise" )

local TestID = "123456"
local function GetStat( Player, Stat )
	return VoteShuffle:GetStat( TestID, Player, Stat )
end

UnitTest:Before( function()
	VoteShuffle.StatsStorage.Data[ TestID ] = nil
end )

UnitTest:Test( "GetStat", function( Assert )
	local Player = {
		totalKills = 10,
		totalDeaths = 2,
		totalScore = 100,
		totalAssists = 20,
		totalPlayTime = 300
	}

	-- Should inherit from Hive data correctly as a starting point.
	for Key, StatKey in pairs( VoteShuffle.StatKeys ) do
		Assert:Equals( Player[ StatKey ], GetStat( Player, Key ) )
	end
	Assert:Equals( 0, GetStat( Player, "Wins" ) )
end )

UnitTest:Test( "IncrementStatValue", function( Assert )
	local Player = {}

	VoteShuffle:IncrementStatValue( TestID, Player, "Kills", 1 )
	Assert:Equals( 1, GetStat( Player, "Kills" ) )

	VoteShuffle:IncrementStatValue( TestID, Player, "Deaths", 20 )
	Assert:Equals( 20, GetStat( Player, "Deaths" ) )
end )

UnitTest:Test( "EvaluateRookieMode", function( Assert )
	local Player = {
		IsRookie = true,
		SetRookie = function( self, Value ) self.IsRookie = Value end
	}

	local StatsRecording = VoteShuffle.Config.StatsRecording

	-- Start as a rookie.
	Assert:Equals( 0, GetStat( Player, StatsRecording.RookieStat ) )
	Assert:True( VoteShuffle:IsRookie( TestID, Player ) )

	-- Evaluating rookie mode now should not result in a change.
	VoteShuffle:EvaluateRookieMode( TestID, Player )
	Assert:True( Player.IsRookie )

	-- Increment the rookie stat to the boundary.
	VoteShuffle:IncrementStatValue( TestID, Player, StatsRecording.RookieStat,
		StatsRecording.RookieBoundary )
	Assert:Equals( StatsRecording.RookieBoundary,
		GetStat( Player, StatsRecording.RookieStat ) )

	-- Should now be considered a non-rookie.
	Assert:False( VoteShuffle:IsRookie( TestID, Player ) )

	-- Evaluating the rookie mode should call Player:SetRookie( false ) now.
	VoteShuffle:EvaluateRookieMode( TestID, Player )
	Assert:False( Player.IsRookie )
end )

UnitTest:Test( "GetKDRStat", function( Assert )
	local Player = {}
	-- 0 deaths = 0 KDR, not NaN.
	local KDR = VoteShuffle:GetKDRStat( TestID, Player )
	Assert:Equals( 0, KDR )

	VoteShuffle:IncrementStatValue( TestID, Player, "Kills", 10 )
	KDR = VoteShuffle:GetKDRStat( TestID, Player )
	Assert:Equals( 10, KDR )

	VoteShuffle:IncrementStatValue( TestID, Player, "Deaths", 2 )
	KDR = VoteShuffle:GetKDRStat( TestID, Player )
	Assert:Equals( 5, KDR )
end )

UnitTest:Test( "GetScorePerMinuteStat", function( Assert )
	local Player = {}
	-- 0 playtime = 0 score/minute, not NaN.
	local ScorePerMinute = VoteShuffle:GetScorePerMinuteStat( TestID, Player )
	Assert:Equals( 0, ScorePerMinute )

	VoteShuffle:IncrementStatValue( TestID, Player, "PlayTime", 120 )
	ScorePerMinute = VoteShuffle:GetScorePerMinuteStat( TestID, Player )
	Assert:Equals( 0, ScorePerMinute )

	VoteShuffle:IncrementStatValue( TestID, Player, "Score", 20 )
	ScorePerMinute = VoteShuffle:GetScorePerMinuteStat( TestID, Player )
	Assert:Equals( 10, ScorePerMinute )
end )

UnitTest:Test( "StoreRoundEndData", function( Assert )
	local Player = {
		PlayTime = 0,
		MarineTime = 0,
		TeamNumber = 1,
		AlienTime = 0,
		GetTeamNumber = function( self ) return self.TeamNumber end,
		GetPlayTime = function( self ) return self.PlayTime end,
		GetMarinePlayTime = function( self ) return self.MarineTime end,
		GetAlienPlayTime = function( self ) return self.AlienTime end
	}

	local MinTeamTime = VoteShuffle.Config.StatsRecording.MinMinutesOnTeam * 60

	-- No win increase, as didn't play for long enough.
	VoteShuffle:StoreRoundEndData( TestID, Player, 1, MinTeamTime )
	Assert:Equals( 0, GetStat( Player, "Wins" ) )
	Assert:Equals( 0, GetStat( Player, "Losses" ) )
	Assert:Equals( 0, GetStat( Player, "PlayTime" ) )

	Player.MarineTime = MinTeamTime * 0.5

	-- Win increase, as despite the playtime being below the config min, they were in for the entire round.
	VoteShuffle:StoreRoundEndData( TestID, Player, 1, MinTeamTime * 0.5 )
	Assert:Equals( 1, GetStat( Player, "Wins" ) )
	Assert:Equals( 0, GetStat( Player, "Losses" ) )
	Assert:Equals( 0, GetStat( Player, "PlayTime" ) )

	Player.MarineTime = MinTeamTime

	-- Should now have a win, as they did play for long enough.
	VoteShuffle:StoreRoundEndData( TestID, Player, 1, MinTeamTime )
	Assert:Equals( 2, GetStat( Player, "Wins" ) )
	Assert:Equals( 0, GetStat( Player, "Losses" ) )
	Assert:Equals( 0, GetStat( Player, "PlayTime" ) )

	-- If Aliens win, should add a loss.
	VoteShuffle:StoreRoundEndData( TestID, Player, 2, MinTeamTime )
	Assert:Equals( 2, GetStat( Player, "Wins" ) )
	Assert:Equals( 1, GetStat( Player, "Losses" ) )
	Assert:Equals( 0, GetStat( Player, "PlayTime" ) )

	-- Alien playtime not enough, no change to win/loss.
	Player.TeamNumber = 2
	VoteShuffle:StoreRoundEndData( TestID, Player, 2, MinTeamTime )
	Assert:Equals( 2, GetStat( Player, "Wins" ) )
	Assert:Equals( 1, GetStat( Player, "Losses" ) )
	Assert:Equals( 0, GetStat( Player, "PlayTime" ) )

	-- Alien playtime now enough, should add a win.
	Player.AlienTime = Player.MarineTime
	VoteShuffle:StoreRoundEndData( TestID, Player, 2, MinTeamTime )
	Assert:Equals( 3, GetStat( Player, "Wins" ) )
	Assert:Equals( 1, GetStat( Player, "Losses" ) )
	Assert:Equals( 0, GetStat( Player, "PlayTime" ) )

	-- If Marines win, should add a loss.
	VoteShuffle:StoreRoundEndData( TestID, Player, 1, MinTeamTime )
	Assert:Equals( 3, GetStat( Player, "Wins" ) )
	Assert:Equals( 2, GetStat( Player, "Losses" ) )
	Assert:Equals( 0, GetStat( Player, "PlayTime" ) )

	-- Should increment the global playtime value.
	Player.PlayTime = Player.MarineTime + Player.AlienTime
	VoteShuffle:StoreRoundEndData( TestID, Player, 2, MinTeamTime )
	Assert:Equals( 4, GetStat( Player, "Wins" ) )
	Assert:Equals( 2, GetStat( Player, "Losses" ) )
	Assert:Equals( Player.MarineTime + Player.AlienTime, GetStat( Player, "PlayTime" ) )
end )
