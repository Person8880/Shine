--[[
	Shuffling logic tests.
]]

local UnitTest = Shine.UnitTest

local VoteShuffle = UnitTest:LoadExtension( "voterandom" )
if not VoteShuffle or not VoteShuffle.Config then return end

local MockShuffle = UnitTest.MockOf( VoteShuffle )

VoteShuffle.Config.IgnoreCommanders = false
VoteShuffle.Config.BalanceModeConfig[ VoteShuffle.ShuffleMode.HIVE ].UseTeamSkill = false
VoteShuffle.Config.BalanceModeConfig[ VoteShuffle.ShuffleMode.HIVE ].UseCommanderSkill = false

local MathRandom = math.random
local StringFormat = string.format
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

	local SortTable = { 1, 2 }
	local Skills = { 1500, 1000 }

	local Count, NumTargets = 2, 2

	VoteShuffle:AssignPlayers( TeamMembers, SortTable, Count, NumTargets, TeamSkills, function( Player, TeamNumber )
		return Skills[ Player ]
	end )

	-- Should place 1500 player on lower skill team.
	Assert:Equals( 3750, TeamSkills[ 2 ].Total )
	Assert:Equals( 4, TeamSkills[ 2 ].Count )
	Assert:Equals( 3750 / 4, TeamSkills[ 2 ].Average )

	Assert:Equals( 4000, TeamSkills[ 1 ].Total )
	Assert:Equals( 4, TeamSkills[ 1 ].Count )
	Assert:Equals( 4000 / 4, TeamSkills[ 1 ].Average )
end, nil, 100 )

UnitTest:Test( "AssignPlayers - Keeps player counts even", function( Assert )
	local TeamMembers = { {}, {} }
	for i = 1, 17 do
		local Team = TeamMembers[ ( i % 2 ) + 1 ]
		Team[ #Team + 1 ] = i + 3
	end

	local Skills = {}
	for i = 1, 20 do
		Skills[ i ] = MathRandom( 500, 5000 )
	end

	local TeamSkills = {
		{
			Count = #TeamMembers[ 1 ]
		},
		{
			Count = #TeamMembers[ 2 ]
		}
	}
	for i = 1, 2 do
		local Team = TeamMembers[ i ]
		local Total = 0
		for j = 1, #Team do
			local Skill = Skills[ j ]
			Total = Total + Skill
		end
		TeamSkills[ i ].Total = Total
		TeamSkills[ i ].Average = Total / #Team
	end

	local SortTable = { 1, 2, 3 }
	local Count, NumTargets = 3, 3

	local Sorted = VoteShuffle:AssignPlayers(
		TeamMembers,
		SortTable,
		Count,
		NumTargets,
		TeamSkills,
		function( Player, TeamNumber )
			return Skills[ Player ]
		end
	)
	Assert.DeepEquals( "Should have sorted all players", { true, true, true }, Sorted )
	Assert.Equals( "Should have 10 players on team 1", 10, #TeamMembers[ 1 ] )
	Assert.Equals( "Should have 10 players on team 2", 10, #TeamMembers[ 2 ] )
end, nil, 100 )

UnitTest:Test( "NormaliseSkills", function( Assert )
	local ScoreTable = {
		{
			Player = 4, Skill = 1.5
		},
		{
			Player = 5, Skill = 3
		},
		{
			Player = 6, Skill = 2
		}
	}

	VoteShuffle:NormaliseSkills( ScoreTable, 3 )

	local NormalisedScoreFactor = VoteShuffle.NormalisedScoreFactor

	Assert:Equals( NormalisedScoreFactor * 0.5, ScoreTable[ 4 ] )
	Assert:Equals( NormalisedScoreFactor, ScoreTable[ 5 ] )
	Assert:Equals( NormalisedScoreFactor / 3 * 2, ScoreTable[ 6 ] )
end )

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

UnitTest:Test( "GetOptimalTeamForPlayer - Uneven teams", function( Assert )
	local Team1Players = { 1000, 1000, 1000, 1000, 1500 }
	local Team2Players = { 1000, 1000, 1000, 1000, 1000 }

	local function SkillGetter( Player ) return Player end

	local TeamToJoin = VoteShuffle:GetOptimalTeamForPlayer( 2000, Team1Players, Team2Players, SkillGetter )
	Assert.Equals( "Should pick team 2 as the optimal team", 2, TeamToJoin )
end )

UnitTest:Test( "GetOptimalTeamForPlayer - Even teams", function( Assert )
	local Team1Players = { 1000, 1000, 1000, 1000, 1000 }
	local Team2Players = { 1000, 1000, 1000, 1000, 1000 }

	local function SkillGetter( Player ) return Player end

	local TeamToJoin = VoteShuffle:GetOptimalTeamForPlayer( 2000, Team1Players, Team2Players, SkillGetter )
	Assert.Nil( "Should not pick an optimal team, both are equivalent", TeamToJoin )
end )

UnitTest:Test( "GetOptimalTeamForPlayer - Empty teams", function( Assert )
	local Team1Players = {}
	local Team2Players = {}

	local function SkillGetter( Player ) return Player end

	local TeamToJoin = VoteShuffle:GetOptimalTeamForPlayer( 2000, Team1Players, Team2Players, SkillGetter )
	Assert.Nil( "Should not pick an optimal team, both are empty", TeamToJoin )
end )

local function FakePlayer( SteamID, TeamNumber, IsCommander )
	local Client = UnitTest.MakeMockClient( SteamID )
	return {
		GetClient = function()
			return Client
		end,
		GetTeamNumber = function() return TeamNumber end,
		isa = function( self, Type )
			if Type == "Commander" and IsCommander then
				return true
			end
			return false
		end
	}
end

VoteShuffle.HappinessHistory = {}
VoteShuffle.SaveHappinessHistory = function() end
VoteShuffle.HasShuffledThisRound = false

local FakeGamerules = {}
local BalanceModule = VoteShuffle.Modules[ #VoteShuffle.Modules - 3 ]

UnitTest:Test( "BalanceModule:EndGame - Does nothing if not shuffled", function( Assert )
	BalanceModule.EndGame( VoteShuffle, FakeGamerules, nil, { FakePlayer( 1 ) } )
	Assert:Equals( 0, #VoteShuffle.HappinessHistory )
end )

VoteShuffle.HasShuffledThisRound = true
VoteShuffle.LastShufflePreferences = nil

UnitTest:Test( "BalanceModule:EndGame - Does nothing if no preference stored", function( Assert )
	BalanceModule.EndGame( VoteShuffle, FakeGamerules, nil, { FakePlayer( 1 ) } )
	Assert:Equals( 0, #VoteShuffle.HappinessHistory )
end )

FakeGamerules.gameStartTime = Shared.GetTime()
UnitTest:Test( "BalanceModule:EndGame - Does nothing if round is too short", function( Assert )
	BalanceModule.EndGame( VoteShuffle, FakeGamerules, nil, { FakePlayer( 1 ) } )
	Assert:Equals( 0, #VoteShuffle.HappinessHistory )
end )

FakeGamerules.gameStartTime = -math.huge

VoteShuffle.LastShufflePreferences = {
	[ 1 ] = 1,
	[ 2 ] = 2
}
VoteShuffle.LastShuffleTeamLookup = {
	[ 1 ] = 1,
	[ 2 ] = 1,
	[ 3 ] = 2
}
UnitTest:Test( "BalanceModule:EndGame - Remembers team preferences", function( Assert )
	BalanceModule.EndGame( VoteShuffle, FakeGamerules, nil, { FakePlayer( 1, 1 ), FakePlayer( 2, 1 ), FakePlayer( 3, 2 ) } )
	-- Should store the round.
	Assert:Equals( 1, #VoteShuffle.HappinessHistory )
	-- Should remember that player 1 was on the team they wanted, while player 2 was not.
	-- Player 3 has no preference so they should not be stored.
	Assert:TableEquals( {
		[ "1" ] = true,
		[ "2" ] = false
	}, VoteShuffle.HappinessHistory[ 1 ] )
end )

VoteShuffle.HappinessHistory = {
	{
		[ "1" ] = true,
		[ "2" ] = false
	},
	{
		[ "1" ] = true,
		[ "2" ] = false,
		[ "3" ] = true
	},
	{
		[ "3" ] = false
	}
}

UnitTest:Test( "GetHistoricHappinessWeight", function( Assert )
	-- Two rounds, both on the preferred team, so should be a low weight.
	Assert:Equals( 0.25, VoteShuffle:GetHistoricHappinessWeight( FakePlayer( 1 ) ) )
	-- Two rounds, both on the non-preferred team, so should be a high weight.
	Assert:Equals( 4, VoteShuffle:GetHistoricHappinessWeight( FakePlayer( 2 ) ) )
	-- Two rounds, one on the preferred team and the other not, so should be weight 1.
	Assert:Equals( 1, VoteShuffle:GetHistoricHappinessWeight( FakePlayer( 3 ) ) )
end )

VoteShuffle.GetHistoricHappinessWeight = function( self, Player )
	return 1
end

UnitTest:Test( "OptimiseHappiness - More unhappiness swaps teams", function( Assert )
	local TeamMembers = {
		{ FakePlayer( 1 ), FakePlayer( 2 ) },
		{ FakePlayer( 3 ), FakePlayer( 4 ) },
	}
	local Team1 = TeamMembers[ 1 ]
	local Team2 = TeamMembers[ 2 ]
	TeamMembers.TeamPreferences = {
		-- Player 1 is unhappy
		[ Team1[ 1 ] ] = 2,
		-- Player 2 is happy
		[ Team1[ 2 ] ] = 1,
		-- Player 3 is unhappy
		[ Team2[ 1 ] ] = 1
		-- Player 4 is neutral
	}

	local Swapped, TotalHappiness = VoteShuffle:OptimiseHappiness( TeamMembers )
	Assert:True( Swapped )
	Assert:Equals( -1, TotalHappiness )
	Assert:Equals( Team2, TeamMembers[ 1 ] )
	Assert:Equals( Team1, TeamMembers[ 2 ] )
	Assert:TableEquals( {
		[ 1 ] = 2,
		[ 2 ] = 1,
		[ 3 ] = 1
	}, VoteShuffle.LastShufflePreferences )
end )

VoteShuffle.Config.BalanceModeConfig[ VoteShuffle.ShuffleMode.HIVE ].UseTeamSkill = true

UnitTest:Test( "OptimiseHappiness - More unhappiness with per-team skills does not swap teams but does record preferences", function( Assert )
	local TeamMembers = {
		{ FakePlayer( 1 ), FakePlayer( 2 ) },
		{ FakePlayer( 3 ), FakePlayer( 4 ) },
	}
	local Team1 = TeamMembers[ 1 ]
	local Team2 = TeamMembers[ 2 ]
	TeamMembers.TeamPreferences = {
		-- Player 1 is unhappy
		[ Team1[ 1 ] ] = 2,
		-- Player 2 is happy
		[ Team1[ 2 ] ] = 1,
		-- Player 3 is unhappy
		[ Team2[ 1 ] ] = 1
		-- Player 4 is neutral
	}

	local Swapped, TotalHappiness = VoteShuffle:OptimiseHappiness( TeamMembers )
	Assert:False( Swapped )
	Assert:Equals( -1, TotalHappiness )
	Assert:Equals( Team1, TeamMembers[ 1 ] )
	Assert:Equals( Team2, TeamMembers[ 2 ] )
	Assert:TableEquals( {
		[ 1 ] = 2,
		[ 2 ] = 1,
		[ 3 ] = 1
	}, VoteShuffle.LastShufflePreferences )
end )

VoteShuffle.Config.BalanceModeConfig[ VoteShuffle.ShuffleMode.HIVE ].UseTeamSkill = false

UnitTest:Test( "OptimiseHappiness - Less unhappiness does nothing", function( Assert )
	local TeamMembers = {
		{ FakePlayer( 1 ), FakePlayer( 2 ) },
		{ FakePlayer( 3 ), FakePlayer( 4 ) },
	}
	local Team1 = TeamMembers[ 1 ]
	local Team2 = TeamMembers[ 2 ]
	TeamMembers.TeamPreferences = {
		-- Player 1 is happy
		[ Team1[ 1 ] ] = 1,
		-- Player 2 is happy
		[ Team1[ 2 ] ] = 1,
		-- Player 3 is unhappy
		[ Team2[ 1 ] ] = 1
		-- Player 4 is neutral
	}

	local Swapped, TotalHappiness = VoteShuffle:OptimiseHappiness( TeamMembers )
	Assert:False( Swapped )
	Assert:Equals( 1, TotalHappiness )
	Assert:Equals( Team1, TeamMembers[ 1 ] )
	Assert:Equals( Team2, TeamMembers[ 2 ] )
	Assert:TableEquals( {
		[ 1 ] = 1,
		[ 2 ] = 1,
		[ 3 ] = 1
	}, VoteShuffle.LastShufflePreferences )
end )

UnitTest:Test( "ShouldOptimiseHappiness - Not ignoring commanders accepts optimisation", function( Assert )
	local TeamMembers = {
		{ FakePlayer( 1 ), FakePlayer( 2 ) },
		{ FakePlayer( 3 ), FakePlayer( 4, 2, true ) }
	}
	-- Can optimise with commanders
	Assert:True( VoteShuffle:ShouldOptimiseHappiness( TeamMembers ) )
	TeamMembers = {
		{ FakePlayer( 1 ), FakePlayer( 2 ) },
		{ FakePlayer( 3 ), FakePlayer( 4 ) }
	}
	-- Can optimise without commanders
	Assert:True( VoteShuffle:ShouldOptimiseHappiness( TeamMembers ) )
end )

VoteShuffle.Config.IgnoreCommanders = true

UnitTest:Test( "ShouldOptimiseHappiness - Ignoring commanders and having commanders rejects optimisation",
function( Assert )
	local TeamMembers = {
		{ FakePlayer( 1 ), FakePlayer( 2 ) },
		{ FakePlayer( 3 ), FakePlayer( 4, 2, true ) }
	}
	-- Cannot optimise when asked to ignore commanders and there are commanders present
	Assert:False( VoteShuffle:ShouldOptimiseHappiness( TeamMembers ) )
end )

UnitTest:Test( "ShouldOptimiseHappiness - Ignoring commanders and not having commanders accepts optimisation",
function( Assert )
	local TeamMembers = {
		{ FakePlayer( 1 ), FakePlayer( 2 ) },
		{ FakePlayer( 3 ), FakePlayer( 4 ) }
	}
	-- Can optimise when asked to ignore commanders but there are no commanders present
	Assert:True( VoteShuffle:ShouldOptimiseHappiness( TeamMembers ) )
end )

local VoteConstraints = {
	MinPlayers = 10,
	FractionNeededToPass = 0.75,
	MinPlayerFractionToConstrainSkillDiff = 0.9,
	MinAverageDiffToAllowShuffle = 100,
	MinStandardDeviationDiffToAllowShuffle = 0
}
function MockShuffle:GetCurrentVoteConstraints()
	return VoteConstraints
end

local HasEligiblePlayersInReadyRoom = true
function MockShuffle:HasEligiblePlayersInReadyRoom()
	return HasEligiblePlayersInReadyRoom
end

function MockShuffle:GetPlayerCountForVote()
	return 20
end

UnitTest:Test( "GetVotesNeeded - Returns current constraint fraction * number of players", function( Assert )
	Assert.Equals( "Should return player count * fraction", 15, MockShuffle:GetVotesNeeded() )
end )

UnitTest:Test( "IsRoundActive - Returns true if the game state is for an active round with no grace time", function( Assert )
	MockShuffle.InGameStateChangeTime = false

	local States = { "Countdown", "Started" }
	for i = 1, #States do
		Assert.True(
			StringFormat( "Should return true for the %s state", States[ i ] ),
			MockShuffle:IsRoundActive( kGameState[ States[ i ] ] )
		)
	end
end )

UnitTest:Test( "IsRoundActive - Returns true if the game state is for an active round and grace time has expired", function( Assert )
	MockShuffle.InGameStateChangeTime = Shared.GetTime() - 60

	local States = { "Countdown", "Started" }
	for i = 1, #States do
		Assert.True(
			StringFormat( "Should return true for the %s state", States[ i ] ),
			MockShuffle:IsRoundActive( kGameState[ States[ i ] ] )
		)
	end
end )

UnitTest:Test( "IsRoundActive - Returns true if the game state is for an active round and grace time has not expired but is ignored", function( Assert )
	MockShuffle.InGameStateChangeTime = Shared.GetTime() + 60

	local States = { "Countdown", "Started" }
	for i = 1, #States do
		Assert.True(
			StringFormat( "Should return true for the %s state", States[ i ] ),
			MockShuffle:IsRoundActive( kGameState[ States[ i ] ], true )
		)
	end
end )

UnitTest:Test( "IsRoundActive - Returns false if the game state is for an active round but grace time has not expired", function( Assert )
	MockShuffle.InGameStateChangeTime = Shared.GetTime() + 60

	local States = { "Countdown", "Started" }
	for i = 1, #States do
		Assert.False(
			StringFormat( "Should return false for the %s state", States[ i ] ),
			MockShuffle:IsRoundActive( kGameState[ States[ i ] ] )
		)
	end
end )

UnitTest:Test( "IsRoundActive - Returns false if the game state is for an inactive round", function( Assert )
	local States = { "NotStarted", "PreGame", "WarmUp", "Team1Won", "Team2Won", "Draw" }
	for i = 1, #States do
		Assert.False(
			StringFormat( "Should return false for the %s state", States[ i ] ),
			MockShuffle:IsRoundActive( kGameState[ States[ i ] ] )
		)
	end
end )

UnitTest:Test( "EvaluateConstraints - Number of players too low", function( Assert )
	Assert.True( "Should allow voting as only 2/10 players are on teams",
		MockShuffle:EvaluateConstraints( 10, {
			{ Skills = { 1000 } },
			{ Skills = { 1000 } }
		} )
	)
end )

UnitTest:Test( "EvaluateConstraints - Teams imbalanced by > 1 player", function( Assert )
	Assert.True( "Should allow voting as teams are imbalanced",
		MockShuffle:EvaluateConstraints( 4, {
			{ Skills = { 1000, 2000, 2000 } },
			{ Skills = { 1000 } }
		} )
	)
end )

UnitTest:Test( "EvaluateConstraints - Average diff is high enough", function( Assert )
	Assert.True( "Should allow voting as averages are too far apart",
		MockShuffle:EvaluateConstraints( 4, {
			{ Skills = { 1000, 2000 }, Average = 1500 },
			{ Skills = { 1000, 4000 }, Average = 2500 }
		} )
	)
end )

UnitTest:Test( "EvaluateConstraints - Min standard deviation difference = 0 is ignored", function( Assert )
	Assert.False( "Should ignore standard deviation as min is 0",
		MockShuffle:EvaluateConstraints( 4, {
			{ Skills = { 1500, 1500 }, Average = 1500, StandardDeviation = 0 },
			{ Skills = { 1000, 2000 }, Average = 1500, StandardDeviation = 500 }
		} )
	)
end )

UnitTest:Test( "EvaluateConstraints - Standard deviation diff is high enough", function( Assert )
	VoteConstraints.MinStandardDeviationDiffToAllowShuffle = 200

	Assert.True( "Should allow voting as standard deviations are too far apart",
		MockShuffle:EvaluateConstraints( 4, {
			{ Skills = { 1500, 1500 }, Average = 1500, StandardDeviation = 0 },
			{ Skills = { 1000, 2000 }, Average = 1500, StandardDeviation = 500 }
		} )
	)
end )

UnitTest:Test( "EvaluateConstraints - Teams are balanced", function( Assert )
	VoteConstraints.MinStandardDeviationDiffToAllowShuffle = 200

	Assert.False( "Should deny voting when teams are sufficiently balanced",
		MockShuffle:EvaluateConstraints( 4, {
			{ Skills = { 1500, 1500 }, Average = 1500, StandardDeviation = 0 },
			{ Skills = { 1500, 1500 }, Average = 1500, StandardDeviation = 0 }
		} )
	)
end )

VoteConstraints.MinPlayerFractionToConstrainSkillDiff = 0.5

UnitTest:Test( "EvaluateConstraints - Teams imbalanced by 1 player and eligible players in ready room", function( Assert )
	HasEligiblePlayersInReadyRoom = true

	Assert.True( "Should allow voting as teams are imbalanced",
		MockShuffle:EvaluateConstraints( 4, {
			{ Skills = { 1500, 1500 }, Average = 1500, StandardDeviation = 0 },
			{ Skills = { 1500 }, Average = 1500, StandardDeviation = 0 }
		} )
	)
end )

UnitTest:Test( "EvaluateConstraints - Teams imbalanced by 1 player but no eligible players in ready room", function( Assert )
	HasEligiblePlayersInReadyRoom = false

	Assert.False( "Should deny voting when teams are sufficiently balanced",
		MockShuffle:EvaluateConstraints( 4, {
			{ Skills = { 1500, 1500 }, Average = 1500, StandardDeviation = 0 },
			{ Skills = { 1500 }, Average = 1500, StandardDeviation = 0 }
		} )
	)
end )

UnitTest:Test( "GetTeamStats - Uses cached data if available", function( Assert )
	local RankFunc = function() end
	local Stats = {}

	MockShuffle.TeamStatsCache[ RankFunc ] = Stats
	local ComputedStats = MockShuffle:GetTeamStats( RankFunc )

	Assert.Equals( "Expected GetTeamStats to return cached data when available",
		Stats, ComputedStats )
end )

VoteShuffle.Config.IgnoreCommanders = false

UnitTest:Test( "RandomisePlayers - Keeps commanders on the same team", function( Assert )
	local Players = {}
	for i = 1, 5 do
		Players[ i ] = FakePlayer( i )
	end
	local Commanders = { FakePlayer( 6 ), FakePlayer( 7 ) }

	local TeamMembers = VoteShuffle:RandomisePlayers( Players, Commanders )
	Assert.Equals( "Should make team 1 have size 3", 3, #TeamMembers[ 1 ] )
	Assert.Equals( "Should make team 2 have size 4", 4, #TeamMembers[ 2 ] )
	Assert.Equals( "Should keep commander for team 1 on team 1", Commanders[ 1 ], TeamMembers[ 1 ][ 1 ] )
	Assert.Equals( "Should keep commander for team 2 on team 2", Commanders[ 2 ], TeamMembers[ 2 ][ 1 ] )
end )

UnitTest:Test( "RandomisePlayers - Keeps team sizes correct with only team 1 commander", function( Assert )
	local Players = {}
	for i = 1, 5 do
		Players[ i ] = FakePlayer( i )
	end
	local Commanders = { FakePlayer( 6 ) }

	local TeamMembers = VoteShuffle:RandomisePlayers( Players, Commanders )
	Assert.Equals( "Should make team 1 have size 3", 3, #TeamMembers[ 1 ] )
	Assert.Equals( "Should make team 2 have size 3", 3, #TeamMembers[ 2 ] )
	Assert.Equals( "Should keep commander for team 1 on team 1", Commanders[ 1 ], TeamMembers[ 1 ][ 1 ] )
end )

UnitTest:Test( "RandomisePlayers - Keeps team sizes correct with only team 1 commander and even number of non-commanders", function( Assert )
	local Players = {}
	for i = 1, 6 do
		Players[ i ] = FakePlayer( i )
	end
	local Commanders = { FakePlayer( 6 ) }

	local TeamMembers = VoteShuffle:RandomisePlayers( Players, Commanders )
	Assert.Equals( "Should make team 1 have size 4", 4, #TeamMembers[ 1 ] )
	Assert.Equals( "Should make team 2 have size 3", 3, #TeamMembers[ 2 ] )
	Assert.Equals( "Should keep commander for team 1 on team 1", Commanders[ 1 ], TeamMembers[ 1 ][ 1 ] )
end )

UnitTest:Test( "RandomisePlayers - Keeps team sizes correct with only team 2 commander", function( Assert )
	local Players = {}
	for i = 1, 5 do
		Players[ i ] = FakePlayer( i )
	end
	local Commanders = { nil, FakePlayer( 6 ) }

	local TeamMembers = VoteShuffle:RandomisePlayers( Players, Commanders )
	Assert.Equals( "Should make team 1 have size 3", 3, #TeamMembers[ 1 ] )
	Assert.Equals( "Should make team 2 have size 3", 3, #TeamMembers[ 2 ] )
	Assert.Equals( "Should keep commander for team 2 on team 2", Commanders[ 2 ], TeamMembers[ 2 ][ 1 ] )
end )

UnitTest:Test( "RandomisePlayers - Keeps team sizes correct with only team 2 commander and even number of non-commanders", function( Assert )
	local Players = {}
	for i = 1, 6 do
		Players[ i ] = FakePlayer( i )
	end
	local Commanders = { nil, FakePlayer( 6 ) }

	local TeamMembers = VoteShuffle:RandomisePlayers( Players, Commanders )
	Assert.Equals( "Should make team 1 have size 3", 3, #TeamMembers[ 1 ] )
	Assert.Equals( "Should make team 2 have size 4", 4, #TeamMembers[ 2 ] )
	Assert.Equals( "Should keep commander for team 2 on team 2", Commanders[ 2 ], TeamMembers[ 2 ][ 1 ] )
end )

UnitTest:Test( "RandomisePlayers - Keeps team sizes correct with no commanders", function( Assert )
	local Players = {}
	for i = 1, 5 do
		Players[ i ] = FakePlayer( i )
	end
	local Commanders = {}

	local TeamMembers = VoteShuffle:RandomisePlayers( Players, Commanders )
	Assert.Equals( "Should make team 1 have size 2", 2, #TeamMembers[ 1 ] )
	Assert.Equals( "Should make team 2 have size 3", 3, #TeamMembers[ 2 ] )
end )

UnitTest:Test( "RandomisePlayers - Keeps team sizes correct with even number of non-commanders", function( Assert )
	local Players = {}
	for i = 1, 6 do
		Players[ i ] = FakePlayer( i )
	end
	local Commanders = {}

	local TeamMembers = VoteShuffle:RandomisePlayers( Players, Commanders )
	Assert.Equals( "Should make team 1 have size 3", 3, #TeamMembers[ 1 ] )
	Assert.Equals( "Should make team 2 have size 3", 3, #TeamMembers[ 2 ] )
end )

UnitTest:Test( "FilterPlayerGroupsToTeamMembers - Removes players not in the team members only", function( Assert )
	local TeamMembers = {
		{
			FakePlayer( 1 ),
			FakePlayer( 2 )
		},
		{
			FakePlayer( 3 ),
			FakePlayer( 4 ),
			FakePlayer( 5 )
		}
	}
	local PlayerGroups = {
		{
			Players = {
				TeamMembers[ 2 ][ 3 ],
				FakePlayer( 6 )
			}
		},
		{
			Players = {
				TeamMembers[ 1 ][ 1 ],
				TeamMembers[ 1 ][ 2 ],
				FakePlayer( 7 )
			}
		}
	}

	local FilteredGroups = VoteShuffle:FilterPlayerGroupsToTeamMembers( PlayerGroups, TeamMembers )
	Assert.DeepEquals( "Should remove the first group and remove the 3rd player of the second group", {
		{
			Players = {
				TeamMembers[ 1 ][ 1 ],
				TeamMembers[ 1 ][ 2 ]
			}
		}
	}, FilteredGroups )
end )

VoteShuffle.SaveHappinessHistory = BalanceModule.SaveHappinessHistory
VoteShuffle.GetHistoricHappinessWeight = BalanceModule.GetHistoricHappinessWeight

UnitTest:Test( "ConsolidateGroupTeamPreferences", function( Assert )
	local Players = {}
	for i = 1, 10 do
		Players[ i ] = FakePlayer()
	end
	local TeamMembers = {
		TeamPreferences = {
			1,
			1,
			2,

			2,
			2,

			1,
			2,

			2,
			2,
			1
		}
	}
	for i = 1, #TeamMembers.TeamPreferences do
		TeamMembers.TeamPreferences[ Players[ i ] ] = TeamMembers.TeamPreferences[ i ]
		TeamMembers.TeamPreferences[ i ] = nil
	end

	local PlayerGroups = {
		{
			Players = {
				Players[ 1 ], Players[ 2 ], Players[ 3 ]
			}
		},
		{
			Players = {
				Players[ 4 ], Players[ 5 ]
			}
		},
		{
			Players = {
				Players[ 6 ], Players[ 7 ]
			}
		},
		{
			Players = {
				Players[ 8 ], Players[ 9 ], Players[ 10 ]
			}
		}
	}

	local TeamPrefs = {}
	VoteShuffle:ConsolidateGroupTeamPreferences( TeamMembers, PlayerGroups, function( Player, Client, Preference )
		TeamPrefs[ Player ] = Preference
	end )

	for i = 1, 3 do
		Assert.Equals( "First group should prefer team 1", 1, TeamPrefs[ Players[ i ] ] )
	end

	for i = 4, 5 do
		Assert.Equals( "Second group should prefer team 2", 2, TeamPrefs[ Players[ i ] ] )
	end

	Assert.Nil( "Third group should remove preferences", TeamPrefs[ Players[ 6 ] ] )
	Assert.Nil( "Third group should remove preferences", TeamPrefs[ Players[ 7 ] ] )

	for i = 8, 10 do
		Assert.Equals( "Fourth group should prefer team 2", 2, TeamPrefs[ Players[ i ] ] )
	end
end )

do
	local Clients = {}
	local function MockClient( SteamID )
		local Client = Clients[ SteamID ]
		if not Client then
			Client = UnitTest.MakeMockClient( SteamID )
			Clients[ SteamID ] = Client
		end
		return Client
	end

	local MockPlugin
	local function MakeMockPlugin()
		local ExistingFriendGroup = {
			Clients = {
				MockClient( 12345 ),
				MockClient( 54321 ),
				MockClient( 67890 )
			},
			Leader = MockClient( 12345 )
		}
		return setmetatable( {
			SendNetworkMessage = function() end,
			SendTranslatedError = function() end,
			SendTranslatedNotify = function() end,
			SendTranslatedNotification = function() end,
			FriendGroupsBySteamID = {
				[ 12345 ] = ExistingFriendGroup,
				[ 54321 ] = ExistingFriendGroup,
				[ 67890 ] = ExistingFriendGroup
			},
			FriendGroupInvitesBySteamID = {},
			FriendGroupInviteDelaysBySteamID = {},
			FriendGroupConfigBySteamID = setmetatable( {
				[ 789 ] = {
					LeaderType = VoteShuffle.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN,
					JoinType = VoteShuffle.FriendGroupJoinType.BLOCK
				}
			}, {
				__index = function( self, Key )
					return {
						LeaderType = VoteShuffle.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN,
						JoinType = VoteShuffle.FriendGroupJoinType.ALLOW_ALL
					}
				end
			} ),
			FriendGroups = {
				ExistingFriendGroup
			},
			Logger = {
				IsDebugEnabled = function() return false end,
				Debug = function() end,
				Warn = function() end
			},
			Config = {
				TeamPreferences = {
					MaxFriendGroupSize = 4,
					FriendGroupInviteDurationInSeconds = 30,
					FriendGroupInviteCooldownInSeconds = 30
				}
			}
		}, { __index = VoteShuffle } )
	end

	UnitTest:Before( function()
		Clients = {}
		MockPlugin = MakeMockPlugin()
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Client that's opted out is not added", function( Assert )
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 123 ), MockClient( 789 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert:Equals( MockPlugin.FriendGroups[ 1 ], MockPlugin.FriendGroupsBySteamID[ 12345 ] )
		Assert:Equals( MockPlugin.FriendGroups[ 1 ], MockPlugin.FriendGroupsBySteamID[ 54321 ] )
		Assert.Nil( "Should not have added the target to a group", MockPlugin.FriendGroupsBySteamID[ 789 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Client that requires an invite is invited", function( Assert )
		MockPlugin.FriendGroupConfigBySteamID[ 789 ] = {
			LeaderType = VoteShuffle.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN,
			JoinType = VoteShuffle.FriendGroupJoinType.REQUIRE_INVITE
		}
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 123 ), MockClient( 789 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Nil( "Should not have added the target to a group", MockPlugin.FriendGroupsBySteamID[ 789 ] )

		local Invite = MockPlugin.FriendGroupInvitesBySteamID[ 789 ]
		Assert.NotNil( "Should have added an invite for the target player", Invite )
		Assert.Equals( "Should be invited by the calling client", 123, Invite.InviterID )

		local Delay = MockPlugin.FriendGroupInviteDelaysBySteamID[ 789 ]
		Assert.NotNil( "Should have added a delay for the next invite from the calling player to the target",
			Delay and Delay[ 123 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Client that requires an invite is rejected if already invited to another group", function( Assert )
		MockPlugin.FriendGroupConfigBySteamID[ 789 ] = {
			LeaderType = VoteShuffle.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN,
			JoinType = VoteShuffle.FriendGroupJoinType.REQUIRE_INVITE
		}
		MockPlugin.FriendGroupInvitesBySteamID[ 789 ] = {
			InviterID = 12345,
			ExpiryTime = math.huge
		}
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 123 ), MockClient( 789 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Nil( "Should not have added the target to a group", MockPlugin.FriendGroupsBySteamID[ 789 ] )

		local Invite = MockPlugin.FriendGroupInvitesBySteamID[ 789 ]
		Assert.Equals( "Should not have added an invite for the target player", 12345, Invite.InviterID )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Client that requires an invite is rejected if the caller's group is full", function( Assert )
		MockPlugin.FriendGroupConfigBySteamID[ 789 ] = {
			LeaderType = VoteShuffle.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN,
			JoinType = VoteShuffle.FriendGroupJoinType.REQUIRE_INVITE
		}
		MockPlugin.Config = {
			TeamPreferences = {
				MaxFriendGroupSize = 3
			}
		}
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 12345 ), MockClient( 789 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Nil( "Should not have added the target to a group", MockPlugin.FriendGroupsBySteamID[ 789 ] )

		local Invite = MockPlugin.FriendGroupInvitesBySteamID[ 789 ]
		Assert.Nil( "Should not have added an invite for the target player", Invite )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Client that requires an invite is rejected if the caller has recently invited the target", function( Assert )
		MockPlugin.FriendGroupConfigBySteamID[ 789 ] = {
			LeaderType = VoteShuffle.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN,
			JoinType = VoteShuffle.FriendGroupJoinType.REQUIRE_INVITE
		}
		MockPlugin.FriendGroupInviteDelaysBySteamID = {
			[ 789 ] = {
				[ 123 ] = math.huge
			}
		}
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 123 ), MockClient( 789 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Nil( "Should not have added the target to a group", MockPlugin.FriendGroupsBySteamID[ 789 ] )

		local Invite = MockPlugin.FriendGroupInvitesBySteamID[ 789 ]
		Assert.Nil( "Should not have added an invite for the target player", Invite )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - No groups for either client creates new group", function( Assert )
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 123 ), MockClient( 456 ) )

		Assert:Equals( 2, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly( { MockClient( 123 ), MockClient( 456 ) }, MockPlugin.FriendGroups[ 2 ].Clients )
		Assert:Equals( MockPlugin.FriendGroups[ 2 ], MockPlugin.FriendGroupsBySteamID[ 123 ] )
		Assert:Equals( MockPlugin.FriendGroups[ 2 ], MockPlugin.FriendGroupsBySteamID[ 456 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Both in same group does nothing", function( Assert )
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 12345 ), MockClient( 54321 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert:Equals( MockPlugin.FriendGroups[ 1 ], MockPlugin.FriendGroupsBySteamID[ 12345 ] )
		Assert:Equals( MockPlugin.FriendGroups[ 1 ], MockPlugin.FriendGroupsBySteamID[ 54321 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Both in different groups does nothing", function( Assert )
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 123 ), MockClient( 456 ) )
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 12345 ), MockClient( 456 ) )

		Assert:Equals( 2, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert:ArrayContainsExactly( { MockClient( 123 ), MockClient( 456 ) }, MockPlugin.FriendGroups[ 2 ].Clients )
		Assert:Equals( MockPlugin.FriendGroups[ 1 ], MockPlugin.FriendGroupsBySteamID[ 12345 ] )
		Assert:Equals( MockPlugin.FriendGroups[ 1 ], MockPlugin.FriendGroupsBySteamID[ 54321 ] )
		Assert:Equals( MockPlugin.FriendGroups[ 2 ], MockPlugin.FriendGroupsBySteamID[ 123 ] )
		Assert:Equals( MockPlugin.FriendGroups[ 2 ], MockPlugin.FriendGroupsBySteamID[ 456 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - No target group adds the target to the caller's group", function( Assert )
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 12345 ), MockClient( 456 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ), MockClient( 456 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert:Equals( MockPlugin.FriendGroups[ 1 ], MockPlugin.FriendGroupsBySteamID[ 456 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Adding to caller group fails if only the group's leader can invite", function( Assert )
		MockPlugin.FriendGroupConfigBySteamID[ 12345 ] = {
			LeaderType = VoteShuffle.FriendGroupLeaderType.LEADER_ADD_ONLY,
			JoinType = VoteShuffle.FriendGroupJoinType.ALLOW_ALL
		}
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 54321 ), MockClient( 456 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Nil( "Target should not have been added to the group", MockPlugin.FriendGroupsBySteamID[ 456 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Adding to caller group fails if full", function( Assert )
		MockPlugin.Config.TeamPreferences.MaxFriendGroupSize = 3

		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 12345 ), MockClient( 456 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Nil( "Target should not have been added to the group", MockPlugin.FriendGroupsBySteamID[ 456 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - No caller group adds the caller to the target's group", function( Assert )
		-- Simulate invites sent from the player that's joining the group.
		MockPlugin.FriendGroupInvitesBySteamID[ 789 ] = {
			InviterID = 456,
			ExpiryTime = math.huge
		}

		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 456 ), MockClient( 12345 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ), MockClient( 456 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert:Equals( MockPlugin.FriendGroups[ 1 ], MockPlugin.FriendGroupsBySteamID[ 456 ] )

		Assert.NotNil( "Should not cancel any pending invites as the group is open to all",
			MockPlugin.FriendGroupInvitesBySteamID[ 789 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Adding to target group succeeds if only the group's leader can invite and the player is invited", function( Assert )
		MockPlugin.FriendGroupConfigBySteamID[ 12345 ] = {
			LeaderType = VoteShuffle.FriendGroupLeaderType.LEADER_ADD_ONLY,
			JoinType = VoteShuffle.FriendGroupJoinType.ALLOW_ALL
		}
		MockPlugin.FriendGroupInvitesBySteamID[ 456 ] = {
			InviterID = 12345,
			ExpiryTime = math.huge
		}

		-- Simulate invites sent from the player that's joining the group.
		MockPlugin.FriendGroupInvitesBySteamID[ 789 ] = {
			InviterID = 456,
			ExpiryTime = math.huge
		}
		MockPlugin.FriendGroupInvitesBySteamID[ 987 ] = {
			InviterID = 456,
			ExpiryTime = math.huge
		}

		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 456 ), MockClient( 12345 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ), MockClient( 456 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert:Equals( MockPlugin.FriendGroups[ 1 ], MockPlugin.FriendGroupsBySteamID[ 456 ] )

		Assert.Nil( "Should remove the consumed invite for the caller",
			MockPlugin.FriendGroupInvitesBySteamID[ 456 ] )
		Assert.Nil( "Should cancel any pending invites as the group is leader invite only",
			MockPlugin.FriendGroupInvitesBySteamID[ 789 ] )
		Assert.Nil( "Should cancel any pending invites as the group is leader invite only",
			MockPlugin.FriendGroupInvitesBySteamID[ 987 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Adding to target group fails if only the group's leader can invite", function( Assert )
		MockPlugin.FriendGroupConfigBySteamID[ 12345 ] = {
			LeaderType = VoteShuffle.FriendGroupLeaderType.LEADER_ADD_ONLY,
			JoinType = VoteShuffle.FriendGroupJoinType.ALLOW_ALL
		}
		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 456 ), MockClient( 12345 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Nil( "Target should not have been added to the group", MockPlugin.FriendGroupsBySteamID[ 456 ] )
	end )

	UnitTest:Test( "HandleFriendGroupJoinRequest - Adding to target group fails if full", function( Assert )
		MockPlugin.Config.TeamPreferences.MaxFriendGroupSize = 3

		VoteShuffle.HandleFriendGroupJoinRequest( MockPlugin, MockClient( 456 ), MockClient( 12345 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Nil( "Caller should not have been added to the group", MockPlugin.FriendGroupsBySteamID[ 456 ] )
	end )

	local OldIsValidClient = Shine.IsValidClient
	function Shine:IsValidClient() return true end

	UnitTest:Test( "RemoveClientFromFriendGroup - Leaves group in place when enough members remain", function( Assert )
		MockPlugin.FriendGroupInvitesBySteamID[ 456 ] = {
			InviterID = 12345,
			ExpiryTime = math.huge
		}

		VoteShuffle.RemoveClientFromFriendGroup( MockPlugin, MockPlugin.FriendGroups[ 1 ], MockClient( 12345 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 54321 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Equals( "Should have updated the group leader", MockClient( 54321 ), MockPlugin.FriendGroups[ 1 ].Leader )
		Assert.Nil( "Removed client should no longer be mapped to the group", MockPlugin.FriendGroupsBySteamID[ 12345 ] )
		Assert.Nil( "Should have cancelled invites from the client being removed",
			MockPlugin.FriendGroupInvitesBySteamID[ 456 ] )
	end )

	UnitTest:Test( "RemoveClientFromFriendGroup - Does not change leader when leader is still present", function( Assert )
		VoteShuffle.RemoveClientFromFriendGroup( MockPlugin, MockPlugin.FriendGroups[ 1 ], MockClient( 54321 ) )

		Assert:Equals( 1, #MockPlugin.FriendGroups )
		Assert:ArrayContainsExactly(
			{ MockClient( 12345 ), MockClient( 67890 ) },
			MockPlugin.FriendGroups[ 1 ].Clients
		)
		Assert.Equals( "Should not have changed the group leader", MockClient( 12345 ), MockPlugin.FriendGroups[ 1 ].Leader )
		Assert.Nil( "Removed client should no longer be mapped to the group", MockPlugin.FriendGroupsBySteamID[ 54321 ] )
	end )

	UnitTest:Test( "RemoveClientFromFriendGroup - Removes group when only 1 member remains", function( Assert )
		VoteShuffle.RemoveClientFromFriendGroup( MockPlugin, MockPlugin.FriendGroups[ 1 ], MockClient( 12345 ) )
		VoteShuffle.RemoveClientFromFriendGroup( MockPlugin, MockPlugin.FriendGroups[ 1 ], MockClient( 54321 ) )

		Assert:Equals( 0, #MockPlugin.FriendGroups )
		Assert.DeepEquals( "All clients should be removed from the group", {}, MockPlugin.FriendGroupsBySteamID )
	end )

	Shine.IsValidClient = OldIsValidClient

	UnitTest:Test( "SerialiseFriendGroups - Saves friend groups with human members", function( Assert )
		local SerialisedGroups = VoteShuffle.SerialiseFriendGroups( MockPlugin )
		Assert:DeepEquals( {
			{
				Members = {
					12345,
					54321,
					67890
				},
				Leader = 12345
			}
		}, SerialisedGroups )
	end )

	UnitTest:Test( "SerialiseFriendGroups - Omits bots from the serialised groups", function( Assert )
		MockPlugin.FriendGroups = {
			{
				Leader = MockClient( 0 ),
				Clients = {
					MockClient( 0 ),
					MockClient( 12345 ),
					MockClient( 54321 )
				}
			}
		}

		local SerialisedGroups = VoteShuffle.SerialiseFriendGroups( MockPlugin )
		Assert:DeepEquals( {
			{
				Members = {
					12345,
					54321
				},
				-- Should make the leader the first human player.
				Leader = 12345
			}
		}, SerialisedGroups )
	end )

	UnitTest:Test( "SerialiseFriendGroups - Omits groups containing only a single human and a bot", function( Assert )
		MockPlugin.FriendGroups = {
			{
				Leader = MockClient( 12345 ),
				Clients = {
					MockClient( 0 ),
					MockClient( 12345 )
				}
			}
		}

		local SerialisedGroups = VoteShuffle.SerialiseFriendGroups( MockPlugin )
		Assert:DeepEquals( {}, SerialisedGroups )
	end )

	UnitTest:Test( "SerialiseFriendGroups - Omits groups containing only bots", function( Assert )
		MockPlugin.FriendGroups = {
			{
				Leader = MockClient( 0 ),
				Clients = {
					MockClient( 0 ),
					MockClient( 0 )
				}
			}
		}

		local SerialisedGroups = VoteShuffle.SerialiseFriendGroups( MockPlugin )
		Assert:DeepEquals( {}, SerialisedGroups )
	end )

	local OldGetClientByNS2ID = Shine.GetClientByNS2ID

	function Shine.GetClientByNS2ID( ID )
		return Clients[ ID ]
	end

	UnitTest:Test( "RestoreClientToFriendGroup - Does nothing if no persisted group exists for the client", function( Assert )
		local Client = MockClient( 123 )

		local Restored = VoteShuffle.RestoreClientToFriendGroup( MockPlugin, Client, {} )
		Assert.False( "Should not have restored the client", Restored )
		Assert:Equals( 1, #MockPlugin.FriendGroups )
	end )

	UnitTest:Test( "RestoreClientToFriendGroup - Does nothing if the group contains only a single member", function( Assert )
		local Client = MockClient( 123 )

		local Restored = VoteShuffle.RestoreClientToFriendGroup( MockPlugin, Client, {
			[ 123 ] = {
				Leader = 123,
				Members = { 123 }
			}
		} )
		Assert.False( "Should not have restored the client", Restored )
		Assert:Equals( 1, #MockPlugin.FriendGroups )
	end )

	UnitTest:Test( "RestoreClientToFriendGroup - Does nothing if no other members are connected", function( Assert )
		local Client = MockClient( 123 )

		local Restored = VoteShuffle.RestoreClientToFriendGroup( MockPlugin, Client, {
			[ 123 ] = {
				Leader = 123,
				Members = { 123, 456 }
			}
		} )
		Assert.False( "Should not have restored the client", Restored )
		Assert:Equals( 1, #MockPlugin.FriendGroups )
	end )

	UnitTest:Test( "RestoreClientToFriendGroup - Does nothing if the other member is a bot", function( Assert )
		local Client = MockClient( 123 )
		local Bot = MockClient( 0 )

		local Restored = VoteShuffle.RestoreClientToFriendGroup( MockPlugin, Client, {
			[ 123 ] = {
				Leader = 123,
				Members = { 123, 0 }
			}
		} )
		Assert.False( "Should not have restored the client", Restored )
		Assert:Equals( 1, #MockPlugin.FriendGroups )
	end )

	UnitTest:Test( "RestoreClientToFriendGroup - Does nothing if all other members are in a full group", function( Assert )
		local Client = MockClient( 123 )

		local ExistingGroup = {
			Leader = MockClient( 456 ),
			Clients = { MockClient( 456 ), MockClient( 789 ), MockClient( 100 ), MockClient( 101 ) }
		}
		MockPlugin.FriendGroupsBySteamID[ 456 ] = ExistingGroup
		MockPlugin.FriendGroupsBySteamID[ 789 ] = ExistingGroup
		MockPlugin.FriendGroupsBySteamID[ 100 ] = ExistingGroup

		local Restored = VoteShuffle.RestoreClientToFriendGroup( MockPlugin, Client, {
			[ 123 ] = {
				Leader = 123,
				Members = { 123, 456, 789, 100 }
			}
		} )
		Assert.False( "Should not have restored the client", Restored )
		Assert:Equals( 1, #MockPlugin.FriendGroups )
	end )

	UnitTest:Test( "RestoreClientToFriendGroup - Adds the client to an existing group if it's not full", function( Assert )
		local Client = MockClient( 123 )

		MockPlugin.FriendGroupsBySteamID[ 456 ] = {
			Leader = MockClient( 456 ),
			Clients = { MockClient( 456 ), MockClient( 789 ), MockClient( 100 ) }
		}

		local Restored = VoteShuffle.RestoreClientToFriendGroup( MockPlugin, Client, {
			[ 123 ] = {
				Leader = 123,
				Members = { 123, 456, 789, 100 }
			}
		} )
		Assert.True( "Should have restored the client", Restored )
		Assert.Equals(
			"Should have assigned the group to the client",
			MockPlugin.FriendGroupsBySteamID[ 456 ], MockPlugin.FriendGroupsBySteamID[ 123 ]
		)
		Assert.DeepEquals(
			"Should have added the client to the group and changed the leader",
			{
				Leader = MockClient( 123 ),
				Clients = { MockClient( 456 ), MockClient( 789 ), MockClient( 100 ), MockClient( 123 ) }
			},
			MockPlugin.FriendGroupsBySteamID[ 456 ]
		)
	end )

	UnitTest:Test( "RestoreClientToFriendGroup - Adds the client to an existing group without altering the leader if they were not the original leader", function( Assert )
		local Client = MockClient( 123 )

		MockPlugin.FriendGroupsBySteamID[ 456 ] = {
			Leader = MockClient( 456 ),
			Clients = { MockClient( 456 ), MockClient( 789 ), MockClient( 100 ) }
		}

		local Restored = VoteShuffle.RestoreClientToFriendGroup( MockPlugin, Client, {
			[ 123 ] = {
				Leader = 456,
				Members = { 123, 456, 789, 100 }
			}
		} )
		Assert.True( "Should have restored the client", Restored )
		Assert.Equals(
			"Should have assigned the group to the client",
			MockPlugin.FriendGroupsBySteamID[ 456 ], MockPlugin.FriendGroupsBySteamID[ 123 ]
		)
		Assert.DeepEquals(
			"Should have added the client to the group without changing the leader",
			{
				Leader = MockClient( 456 ),
				Clients = { MockClient( 456 ), MockClient( 789 ), MockClient( 100 ), MockClient( 123 ) }
			},
			MockPlugin.FriendGroupsBySteamID[ 456 ]
		)
	end )

	UnitTest:Test( "RestoreClientToFriendGroup - Adds the client and members to a new group if none are in a group", function( Assert )
		local Client = MockClient( 123 )
		local Members = { MockClient( 456 ), MockClient( 789 ), MockClient( 100 ) }

		local Restored = VoteShuffle.RestoreClientToFriendGroup( MockPlugin, Client, {
			[ 123 ] = {
				Leader = 456,
				Members = { 123, 456, 789, 100 }
			}
		} )
		Assert.True( "Should have restored the client", Restored )
		Assert.DeepEquals(
			"Should have restored the group with all members and its original leader",
			{
				Leader = MockClient( 456 ),
				Clients = { MockClient( 456 ), MockClient( 789 ), MockClient( 100 ), MockClient( 123 ) }
			},
			MockPlugin.FriendGroupsBySteamID[ 456 ]
		)
	end )

	Shine.GetClientByNS2ID = OldGetClientByNS2ID

	UnitTest:ResetState()
end

UnitTest:Test( "BuildEnforcementPolicy - Returns NoOpEnforcement if no policies are specified", function( Assert )
	local Enforcement = VoteShuffle:BuildEnforcementPolicy( {
		EnforcementPolicy = {}
	} )

	Assert.Nil( "Should have no policies to enforce", Enforcement.Policies )
end )

UnitTest:Test( "BuildEnforcementPolicy - Returns NoOpEnforcement if EnforcementDurationType == 'NONE'", function( Assert )
	local Enforcement = VoteShuffle:BuildEnforcementPolicy( {
		EnforcementPolicy = {
			{
				Type = VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS,
				MinPlayers = 0,
				MaxPlayers = 0
			}
		},
		EnforcementDurationType = VoteShuffle.EnforcementDurationType.NONE
	} )

	Assert.Nil( "Should have no policies to enforce", Enforcement.Policies )
end )

UnitTest:Test( "BuildEnforcementPolicy - Returns NoOpEnforcement if duration is too small", function( Assert )
	local Enforcement = VoteShuffle:BuildEnforcementPolicy( {
		EnforcementPolicy = {
			{
				Type = VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS,
				MinPlayers = 0,
				MaxPlayers = 0
			}
		},
		DurationInMinutes = 0,
		EnforcementDurationType = VoteShuffle.EnforcementDurationType.TIME
	} )

	Assert.Nil( "Should have no policies to enforce", Enforcement.Policies )
end )

UnitTest:Test( "BuildEnforcementPolicy - Returns DurationBasedEnforcement if duration is large enough", function( Assert )
	local Enforcement = VoteShuffle:BuildEnforcementPolicy( {
		EnforcementPolicy = {
			{
				Type = VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS,
				MinPlayers = 10,
				MaxPlayers = 15
			}
		},
		DurationInMinutes = 10,
		EnforcementDurationType = VoteShuffle.EnforcementDurationType.TIME
	} )

	Assert.DeepEquals( "Should have policies to enforce", {
		[ VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS ] = {
			Type = VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS,
			MinPlayers = 10,
			MaxPlayers = 15
		}
	}, Enforcement.Policies )

	Assert.False(
		"Should not enforce policy that is not specified",
		Enforcement:IsPolicyEnforced( VoteShuffle.EnforcementPolicyType.ASSIGN_PLAYERS, 10 )
	)
	Assert.False(
		"Should not enforce policy when player count is too low",
		Enforcement:IsPolicyEnforced( VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS, 9 )
	)
	Assert.False(
		"Should not enforce policy when player count is too high",
		Enforcement:IsPolicyEnforced( VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS, 16 )
	)
	for i = 10, 15 do
		Assert.True(
			"Should enforce policy when player count ("..i..") is within bounds",
			Enforcement:IsPolicyEnforced( VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS, i )
		)
	end
end )

UnitTest:Test( "BuildEnforcementPolicy - Returns PeriodBasedEnforcement if configured to do so", function( Assert )
	local Enforcement = VoteShuffle:BuildEnforcementPolicy( {
		EnforcementPolicy = {
			{
				Type = VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS,
				MinPlayers = 0,
				MaxPlayers = 0
			}
		},
		DurationInMinutes = 10,
		EnforcementDurationType = VoteShuffle.EnforcementDurationType.PERIOD
	} )

	Assert.DeepEquals( "Should have policies to enforce", {
		[ VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS ] = {
			Type = VoteShuffle.EnforcementPolicyType.BLOCK_TEAMS,
			MinPlayers = 0,
			MaxPlayers = 0
		}
	}, Enforcement.Policies )
	Assert.NotNil( "Should return period based enforcement", Enforcement.InitialStage )
end )

do
	local OldApplyToBots = VoteShuffle.Config.ApplyToBots
	local OldGetMaxPlayers = VoteShuffle.GetMaxPlayers

	local MaxPlayers = 2
	function VoteShuffle:GetMaxPlayers()
		return MaxPlayers
	end

	local Targets = {
		FakePlayer( 0, 0, false ),
		FakePlayer( 123, 0, false ),
		FakePlayer( 456, 0, false ),
	}
	local OriginalTargets = table.ShallowCopy( Targets )
	local TeamMembers = {
		{
			FakePlayer( 0, 1, true ),
			FakePlayer( 0, 1, false )
		},
		{
			FakePlayer( 1234, 2, true ),
			FakePlayer( 0, 2, false )
		}
	}
	local OriginalTeamMembers = {
		table.ShallowCopy( TeamMembers[ 1 ] ),
		table.ShallowCopy( TeamMembers[ 2 ] )
	}

	VoteShuffle.Config.ApplyToBots = false
	UnitTest:Test( "RemoveBotsIfNeeded - Does nothing if max players exceeded but ApplyToBots is false", function( Assert )
		VoteShuffle:RemoveBotsIfNeeded( Targets, TeamMembers )

		Assert.ArrayEquals( "Should not have changed the target list", OriginalTargets, Targets )
		Assert.DeepEquals( "Should not have changed the team members", OriginalTeamMembers, TeamMembers )
	end )

	MaxPlayers = 20
	VoteShuffle.Config.ApplyToBots = true
	UnitTest:Test( "RemoveBotsIfNeeded - Does nothing if max players not reached", function( Assert )
		VoteShuffle:RemoveBotsIfNeeded( Targets, TeamMembers )

		Assert.ArrayEquals( "Should not have changed the target list", OriginalTargets, Targets )
		Assert.DeepEquals( "Should not have changed the team members", OriginalTeamMembers, TeamMembers )
	end )

	MaxPlayers = 3
	UnitTest:Test( "RemoveBotsIfNeeded - Removes non-commander bots if exceeding the max player count and ApplyToBots is enabled", function( Assert )
		VoteShuffle:RemoveBotsIfNeeded( Targets, TeamMembers )

		Assert.ArrayEquals( "Should have removed the bot from the target list", {
			OriginalTargets[ 2 ],
			OriginalTargets[ 3 ]
		}, Targets )
		Assert.DeepEquals( "Should have removed the non-commander bots from the team members", {
			{
				OriginalTeamMembers[ 1 ][ 1 ]
			},
			{
				OriginalTeamMembers[ 2 ][ 1 ]
			}
		}, TeamMembers )

		Assert.CalledTimes(
			"Should have disconnected the bot in the targets list",
			OriginalTargets[ 1 ]:GetClient().bot.Disconnect, 1
		)
		Assert.CalledTimes(
			"Should not have disconnected the commander bot on team 1",
			OriginalTeamMembers[ 1 ][ 1 ]:GetClient().bot.Disconnect, 0
		)
		Assert.CalledTimes(
			"Should have disconnected the player bot on team 1",
			OriginalTeamMembers[ 1 ][ 2 ]:GetClient().bot.Disconnect, 1
		)
		Assert.CalledTimes(
			"Should have disconnected the player bot on team 2",
			OriginalTeamMembers[ 2 ][ 2 ]:GetClient().bot.Disconnect, 1
		)
	end )

	VoteShuffle.GetMaxPlayers = OldGetMaxPlayers
	VoteShuffle.Config.ApplyToBots = OldApplyToBots
end

----- Integration tests for team optimisation -----

-- Turn off happiness optimisation for integration tests.
VoteShuffle.OptimiseHappiness = function() end
VoteShuffle.HappinessHistory = {}

local SteamID = 0
local function PlayerWithSkill( Skill, Commander )
	SteamID = SteamID + 1
	local Client = UnitTest.MakeMockClient( SteamID )
	return {
		__SteamID = SteamID,
		GetClient = function()
			return Client
		end,
		Skill = Skill,
		isa = function() return Commander end,
		Commander = Commander
	}
end
local function RankPlayerWithSkill( Player )
	return Player.Skill
end

UnitTest:Before( function()
	SteamID = 0
end )

UnitTest:Test( "OptimiseTeams", function( Assert )
	local TeamMembers = {
		{
			PlayerWithSkill( 2000 ), PlayerWithSkill( 2000 ), PlayerWithSkill( 1000 )
		},
		{
			PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 )
		},
		TeamPreferences = {}
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

	VoteShuffle:OptimiseTeams( TeamMembers, RankPlayerWithSkill, TeamSkills )

	-- Final team layout should be:
	-- 2000, 1000, 1000
	-- 2000, 1000, 1000
	Assert:Equals( 4000, TeamSkills[ 1 ].Total )
	Assert:Equals( 4000, TeamSkills[ 2 ].Total )
end, nil, 5 )

UnitTest:Test( "OptimiseLargeTeams", function( Assert )
	local TeamMembers = {
		{
			PlayerWithSkill( 2000 ), PlayerWithSkill( 2000 ), PlayerWithSkill( 2000 ), PlayerWithSkill( 1800 ),
			PlayerWithSkill( 1700 ), PlayerWithSkill( 1500 ), PlayerWithSkill( 1200 ), PlayerWithSkill( 1000 )
		},
		{
			PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 ), PlayerWithSkill( 700 ),
			PlayerWithSkill( 600 ), PlayerWithSkill( 500 ), PlayerWithSkill( 0 ), PlayerWithSkill( 0 )
		},
		TeamPreferences = {}
	}

	local TeamSkills = {}
	local Team = 1
	for i = 1, 2 do
		local Data = {}
		local Sum = 0

		for j = 1, #TeamMembers[ i ] do
			Sum = Sum + RankPlayerWithSkill( TeamMembers[ i ][ j ] )
		end

		Data.Total = Sum
		Data.Average = Sum / #TeamMembers[ i ]
		Data.Count = #TeamMembers[ i ]

		TeamSkills[ Team ] = Data
		Team = Team + 1
	end

	VoteShuffle:OptimiseTeams( TeamMembers, RankPlayerWithSkill, TeamSkills )

	local FinalTeams = {
		{ 2000, 1800, 1700, 1200, 1000, 700, 600, 0 },
		{ 2000, 2000, 1500, 1000, 1000, 1000, 500, 0 }
	}

	for i = 1, 2 do
		local TeamTable = TeamMembers[ i ]
		TableSort( TeamTable, function( A, B )
			return RankPlayerWithSkill( A ) > RankPlayerWithSkill( B )
		end )

		local AsSkillArray = {}
		for j = 1, #TeamTable do
			AsSkillArray[ j ] = RankPlayerWithSkill( TeamTable[ j ] )
		end

		Assert:ArrayEquals( FinalTeams[ i ], AsSkillArray )
	end
end, nil, 5 )

UnitTest:Test( "OptimiseTeams with uneven teams", function( Assert )
	local TeamMembers = {
		{
			PlayerWithSkill( 2000 ), PlayerWithSkill( 2000 ), PlayerWithSkill( 1000 )
		},
		{
			PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 )
		},
		TeamPreferences = {}
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

	VoteShuffle:OptimiseTeams( TeamMembers, RankPlayerWithSkill, TeamSkills )

	-- Final team layout should be:
	-- 2000, 1000
	-- 2000, 1000, 1000
	Assert:Equals( 3000, TeamSkills[ 1 ].Total )
	Assert:Equals( 2, TeamSkills[ 1 ].Count )
	Assert:Equals( 4000, TeamSkills[ 2 ].Total )
	Assert:Equals( 3, TeamSkills[ 2 ].Count )
end, nil, 5 )

UnitTest:Test( "OptimiseTeams with preference", function( Assert )
	local Players = {
		PlayerWithSkill( 2000 ), PlayerWithSkill( 2000 ), PlayerWithSkill( 1000 ),
		PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 )
	}
	local TeamMembers = {
		{
			Players[ 1 ], Players[ 2 ], Players[ 3 ]
		},
		{
			Players[ 4 ], Players[ 5 ], Players[ 6 ]
		},
		TeamPreferences = {
			[ 4 ] = 2,
			[ 5 ] = 2
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

	VoteShuffle:OptimiseTeams( TeamMembers, RankPlayerWithSkill, TeamSkills )

	-- It should always swap 2 and 6, as 4 and 5 have chosen team 2 specifically.
	Assert:ArrayContainsExactly( { Players[ 1 ], Players[ 6 ], Players[ 3 ] }, TeamMembers[ 1 ] )
	Assert:ArrayContainsExactly( { Players[ 4 ], Players[ 5 ], Players[ 2 ] }, TeamMembers[ 2 ] )
end, nil, 5 )

VoteShuffle.HappinessHistory = {
	{
		[ "1" ] = false
	},
	{
		[ "1" ] = false,
		[ "2" ] = false
	},
	{
		[ "4" ] = true
	}
}

UnitTest:Test( "OptimiseTeams with weighted preference", function( Assert )
	SteamID = 0

	local Players = {
		PlayerWithSkill( 2000 ), PlayerWithSkill( 2000 ), PlayerWithSkill( 1000 ),
		PlayerWithSkill( 2000 ), PlayerWithSkill( 2000 ), PlayerWithSkill( 1000 )
	}
	local TeamMembers = {
		{
			Players[ 1 ], Players[ 2 ], Players[ 3 ]
		},
		{
			Players[ 4 ], Players[ 5 ], Players[ 6 ]
		},
		TeamPreferences = {
			-- Unsatisfiable preferences, only two players can be swapped out of the four that want to.
			[ Players[ 1 ] ] = 2,
			[ Players[ 2 ] ] = 2,
			[ Players[ 4 ] ] = 2,
			[ Players[ 5 ] ] = 2
		}
	}

	local TeamSkills = {
		{
			Average = 5000 / 3,
			Total = 5000,
			Count = 3
		},
		{
			Average = 5000 / 3,
			Total = 5000,
			Count = 3
		}
	}

	VoteShuffle:OptimiseTeams( TeamMembers, RankPlayerWithSkill, TeamSkills )

	-- It should always move players 1 and 2 to team 2, as they have the highest preference weightings.
	Assert:Contains( TeamMembers[ 2 ], Players[ 1 ] )
	Assert:Contains( TeamMembers[ 2 ], Players[ 2 ] )

	Assert:Equals( 3, #TeamMembers[ 1 ] )
	Assert:Equals( 3, #TeamMembers[ 2 ] )

	for i = 1, 3 do
		local Player = TeamMembers[ 2 ][ i ]
		if Player ~= Players[ 1 ] and Player ~= Players[ 2 ] then
			Assert:Equals( 1000, Player.Skill )
			break
		end
	end
end, nil, 5 )

VoteShuffle.HappinessHistory = {}
VoteShuffle.Config.IgnoreCommanders = true

UnitTest:Test( "OptimiseTeams with commanders", function( Assert )
	local Index = 0
	local Players = {
		PlayerWithSkill( 2000, true ), PlayerWithSkill( 2000 ), PlayerWithSkill( 1000 ),
		PlayerWithSkill( 1000, true ), PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 )
	}

	local Marines = {
		Players[ 1 ], Players[ 2 ], Players[ 3 ]
	}
	local Aliens = {
		Players[ 4 ], Players[ 5 ], Players[ 6 ]
	}

	local TeamMembers = {
		Marines,
		Aliens,
		TeamPreferences = {
			[ Marines[ 1 ] ] = true,
			[ Aliens[ 1 ] ] = true
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

	VoteShuffle:OptimiseTeams( TeamMembers, RankPlayerWithSkill, TeamSkills )

	-- It should never swap the commanders.
	Assert:ArrayContainsExactly( { Players[ 1 ], Players[ 6 ], Players[ 3 ] }, TeamMembers[ 1 ] )
	Assert:ArrayContainsExactly( { Players[ 4 ], Players[ 5 ], Players[ 2 ] }, TeamMembers[ 2 ] )
end, nil, 5 )

UnitTest:Test( "OptimiseTeams with friend groups", function( Assert )
	local Index = 0
	local Players = {
		PlayerWithSkill( 2000, true ), PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 ),
		PlayerWithSkill( 2000, true ), PlayerWithSkill( 1000 ), PlayerWithSkill( 1000 )
	}

	local Marines = {
		Players[ 1 ], Players[ 2 ], Players[ 3 ]
	}
	local Aliens = {
		Players[ 4 ], Players[ 5 ], Players[ 6 ]
	}

	local TeamMembers = {
		Marines,
		Aliens,
		TeamPreferences = {},
		PlayerGroups = {
			{
				Players = {
					Marines[ 2 ], Aliens[ 3 ]
				}
			}
		}
	}

	local TeamSkills = {
		{
			Average = 4000 / 3,
			Total = 4000,
			Count = 3
		},
		{
			Average = 4000 / 3,
			Total = 4000,
			Count = 3
		}
	}

	VoteShuffle:OptimiseTeams( TeamMembers, RankPlayerWithSkill, TeamSkills )

	-- It should swap the players that are grouped as it will not harm the balance.
	Assert:ArrayContainsExactly( { Players[ 1 ], Players[ 2 ], Players[ 6 ] }, TeamMembers[ 1 ] )
	Assert:ArrayContainsExactly( { Players[ 4 ], Players[ 5 ], Players[ 3 ] }, TeamMembers[ 2 ] )
end )

UnitTest:Test( "OptimiseTeams with per-team and role skill values", function( Assert )
	local Index = 0
	local Players = {
		PlayerWithSkill( { Commander = { 2000, 1000 } }, true ),
		PlayerWithSkill( { 2000, 2000 } ),
		PlayerWithSkill( { 1000, 1000 } ),

		PlayerWithSkill( { Commander = { 1000, 2000 } }, true ),
		PlayerWithSkill( { 2000, 1000 } ),
		PlayerWithSkill( { 1000, 1000 } )
	}

	-- The middle players here can be swapped to make the teams even based on team skill.
	local Marines = {
		Players[ 1 ], Players[ 2 ], Players[ 3 ]
	}
	local Aliens = {
		Players[ 4 ], Players[ 5 ], Players[ 6 ]
	}

	local function RankFunc( Player, TeamNumber )
		if Player.Commander then
			return Player.Skill.Commander[ TeamNumber ]
		end
		return Player.Skill[ TeamNumber ]
	end

	local TeamMembers = {
		Marines,
		Aliens,
		TeamPreferences = {},
		PlayerGroups = {}
	}

	local TeamSkills = {
		{
			Average = 5000 / 3,
			Total = 5000,
			Count = 3
		},
		{
			Average = 4000 / 3,
			Total = 4000,
			Count = 3
		}
	}

	VoteShuffle:OptimiseTeams( TeamMembers, RankFunc, TeamSkills )

	local TeamSkill = { 0, 0 }
	for i = 1, 3 do
		for j = 1, 2 do
			local Player = TeamMembers[ j ][ i ]
			local Skill = RankFunc( Player, j )
			TeamSkill[ j ] = TeamSkill[ j ] + Skill
		end
	end

	Assert.Equals( "Team skills should be equal after balancing", TeamSkill[ 1 ], TeamSkill[ 2 ] )
end )

VoteShuffle.OptimiseHappiness = BalanceModule.OptimiseHappiness
