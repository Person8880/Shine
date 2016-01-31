--[[
	Shuffling logic tests.
]]

local UnitTest = Shine.UnitTest

local VoteShuffle = UnitTest:LoadExtension( "voterandom" )
if not VoteShuffle then return end

VoteShuffle.Config.IgnoreCommanders = false
VoteShuffle.Config.UseStandardDeviation = true
VoteShuffle.Config.StandardDeviationTolerance = 40

local TableSort = table.sort

UnitTest:Test( "AssignPlayers", function( Assert )
	local TeamMembers = {
		{
			1, 2, 3
		},
		{
			4, 5, 6
		}
	}

	local TeamSkills = {
		{
			Average = 1000,
			Total = 3000,
			Count = 3
		},
		{
			Average = 750,
			Total = 2250,
			Count = 3
		}
	}

	local SortTable = {
		{
			Player = {},
			Skill = 1500
		},
		{
			Player = {},
			Skill = 1000
		}
	}

	local Count, NumTargets = 2, 2

	VoteShuffle:AssignPlayers( TeamMembers, SortTable, Count, NumTargets, TeamSkills )

	-- Should place 1500 player on lower skill team.
	Assert:Equals( 3750, TeamSkills[ 2 ].Total )
	Assert:Equals( 4, TeamSkills[ 2 ].Count )
	Assert:Equals( 3750 / 4, TeamSkills[ 2 ].Average )

	Assert:Equals( 4000, TeamSkills[ 1 ].Total )
	Assert:Equals( 4, TeamSkills[ 1 ].Count )
	Assert:Equals( 4000 / 4, TeamSkills[ 1 ].Average )
end, nil, 100 )

UnitTest:Test( "PerformSwap", function( Assert )
	local TeamMembers = {
		{
			1, 2, 3
		},
		{
			4, 5, 6
		}
	}

	local TeamSkills = {
		{
			Average = 1000,
			Total = 3000,
			Count = 3
		},
		{
			Average = 750,
			Total = 2250,
			Count = 3
		}
	}

	local SwapData = {
		BestPlayers = {
			5, 1
		},
		Indices = {
			1, 2
		},
		Totals = {
			2750, 2500
		},
		BestDiff = 0
	}

	VoteShuffle:PerformSwap( TeamMembers, TeamSkills, SwapData )

	Assert:ArrayEquals( { 5, 2, 3 }, TeamMembers[ 1 ] )
	Assert:ArrayEquals( { 4, 1, 6 }, TeamMembers[ 2 ] )

	Assert:Equals( 2750, TeamSkills[ 1 ].Total )
	Assert:Equals( 2500, TeamSkills[ 2 ].Total )
end )

UnitTest:Test( "PerformSwap with uneven teams", function( Assert )
	local TeamMembers = {
		{
			1, 2, 3
		},
		{
			4, 5
		}
	}

	local TeamSkills = {
		{
			Average = 1000,
			Total = 3000,
			Count = 3
		},
		{
			Average = 750,
			Total = 1500,
			Count = 2
		}
	}

	local SwapData = {
		BestPlayers = {
			nil, 1
		},
		Indices = {
			1, 3
		},
		Totals = {
			2000, 2500
		},
		BestDiff = 0
	}

	local Changed, LargerTeam, LesserTeam = VoteShuffle:PerformSwap( TeamMembers, TeamSkills, SwapData, 1, 2 )

	Assert:Truthy( Changed )
	Assert:Equals( 2, LargerTeam )
	Assert:Equals( 1, LesserTeam )

	Assert:ArrayEquals( { 2, 3 }, TeamMembers[ 1 ] )
	Assert:ArrayEquals( { 4, 5, 1 }, TeamMembers[ 2 ] )

	Assert:Equals( 2000, TeamSkills[ 1 ].Total )
	Assert:Equals( 2, TeamSkills[ 1 ].Count )

	Assert:Equals( 2500, TeamSkills[ 2 ].Total )
	Assert:Equals( 3, TeamSkills[ 2 ].Count )
end )

UnitTest:Test( "OptimiseTeams", function( Assert )
	local Skills = {
		2000, 2000, 1000,
		1000, 1000, 1000
	}

	local function RankFunc( Player )
		return Skills[ Player ]
	end

	local TeamMembers = {
		{
			1, 2, 3
		},
		{
			4, 5, 6
		}
	}

	local TeamSkills = {
		{
			Average = 5000 / 3,
			Total = 5000,
			Count = 3
		},
		{
			Average = 1000,
			Total = 3000,
			Count = 3
		}
	}

	VoteShuffle:OptimiseTeams( TeamMembers, RankFunc, TeamSkills )

	-- Final team layout should be:
	-- 2000, 1000, 1000
	-- 2000, 1000, 1000
	Assert:Equals( 4000, TeamSkills[ 1 ].Total )
	Assert:Equals( 4000, TeamSkills[ 2 ].Total )
end, nil, 100 )

UnitTest:Test( "OptimiseLargeTeams", function( Assert )
	local Skills = {
		2000, 2000, 2000, 1800, 1700, 1500, 1200, 1000,
		1000, 1000, 1000, 700, 600, 500, 0, 0
	}

	local function RankFunc( Player )
		return Skills[ Player ]
	end

	local TeamMembers = {
		{
			1, 2, 3, 4, 5, 6, 7, 8
		},
		{
			9, 10, 11, 12, 13, 14, 15, 16
		}
	}

	local TeamSkills = {}
	local Team = 1
	local PerTeam = #Skills * 0.5
	for i = 1, #Skills, PerTeam do
		local Data = {}
		local Sum = 0

		for j = i, i + PerTeam - 1 do
			Sum = Sum + Skills[ j ]
		end

		Data.Total = Sum
		Data.Average = Sum / PerTeam
		Data.Count = PerTeam

		TeamSkills[ Team ] = Data
		Team = Team + 1
	end

	VoteShuffle:OptimiseTeams( TeamMembers, RankFunc, TeamSkills )

	local FinalTeams = {
		{ 2000, 2000, 1500, 1200, 1000, 700, 600, 0 },
		{ 2000, 1800, 1700, 1000, 1000, 1000, 500, 0 }
	}

	for i = 1, 2 do
		local TeamTable = TeamMembers[ i ]
		TableSort( TeamTable, function( A, B )
			return Skills[ A ] > Skills[ B ]
		end )

		local AsSkillArray = {}
		for j = 1, #TeamTable do
			AsSkillArray[ j ] = Skills[ TeamTable[ j ] ]
		end

		Assert:ArrayEquals( FinalTeams[ i ], AsSkillArray )
	end
end, nil, 100 )

UnitTest:Test( "OptimiseTeams with uneven teams", function( Assert )
	local Skills = {
		2000, 2000, 1000,
		1000, 1000
	}

	local function RankFunc( Player )
		return Skills[ Player ]
	end

	local TeamMembers = {
		{
			1, 2, 3
		},
		{
			4, 5
		}
	}

	local TeamSkills = {
		{
			Average = 5000 / 3,
			Total = 5000,
			Count = 3
		},
		{
			Average = 1000,
			Total = 2000,
			Count = 2
		}
	}

	VoteShuffle:OptimiseTeams( TeamMembers, RankFunc, TeamSkills )

	-- Final team layout should be:
	-- 2000, 1000, 1000
	-- 2000, 1000
	Assert:Equals( 4000, TeamSkills[ 1 ].Total )
	Assert:Equals( 3, TeamSkills[ 1 ].Count )
	Assert:Equals( 3000, TeamSkills[ 2 ].Total )
	Assert:Equals( 2, TeamSkills[ 2 ].Count )
end, nil, 100 )

UnitTest:Test( "NormaliseSkills", function( Assert )
	local ScoreTable = {
		{
			Player = {}, Skill = 1.5
		},
		{
			Player = {}, Skill = 3
		},
		{
			Player = {}, Skill = 2
		}
	}

	VoteShuffle:NormaliseSkills( ScoreTable, 3 )

	local NormalisedScoreFactor = VoteShuffle.NormalisedScoreFactor

	Assert:Equals( NormalisedScoreFactor * 0.5, ScoreTable[ 1 ].Skill )
	Assert:Equals( NormalisedScoreFactor, ScoreTable[ 2 ].Skill )
	Assert:Equals( NormalisedScoreFactor / 3 * 2, ScoreTable[ 3 ].Skill )
end )

UnitTest:Test( "OptimiseTeams with preference", function( Assert )
	local Skills = {
		2000, 2000, 1000,
		1000, 1000, 1000
	}

	local function RankFunc( Player )
		return Skills[ Player ]
	end

	local TeamMembers = {
		{
			1, 2, 3
		},
		{
			4, 5, 6
		},
		TeamPreferences = {
			[ 4 ] = true,
			[ 5 ] = true
		}
	}

	local TeamSkills = {
		{
			Average = 5000 / 3,
			Total = 5000,
			Count = 3
		},
		{
			Average = 1000,
			Total = 3000,
			Count = 3
		}
	}

	VoteShuffle:OptimiseTeams( TeamMembers, RankFunc, TeamSkills )

	-- It should always swap 1 and 6, as 4 and 5 have chosen team 2 specifically.
	Assert:ArrayEquals( { 6, 2, 3 }, TeamMembers[ 1 ] )
	Assert:ArrayEquals( { 4, 5, 1 }, TeamMembers[ 2 ] )
end, nil, 100 )

UnitTest:Test( "AddPlayersRandomly", function( Assert )
	local TeamMembers = {
		{
			1
		},
		{
			2, 3, 4
		}
	}
	local Targets = { 5, 6, 7, 8 }

	VoteShuffle:AddPlayersRandomly( Targets, #Targets, TeamMembers )
	Assert:Equals( 4, #TeamMembers[ 1 ] )
	Assert:Equals( 4, #TeamMembers[ 2 ] )

	TeamMembers = {
		{
			1
		},
		{
			2, 3, 4
		}
	}
	Targets = { 5, 6 }

	VoteShuffle:AddPlayersRandomly( Targets, #Targets, TeamMembers )
	Assert:Equals( 3, #TeamMembers[ 1 ] )
	Assert:Equals( 3, #TeamMembers[ 2 ] )
end )

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
