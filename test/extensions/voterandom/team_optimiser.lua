--[[
	Tests for the team optimiser.
]]

local UnitTest = Shine.UnitTest

local VoteShuffle = UnitTest:LoadExtension( "voterandom" )
if not VoteShuffle then return end

UnitTest:Test( "CommitSwap", function( Assert )
	local TeamMembers = {
		{
			1, 2, 3
		},
		{
			4, 5, 6
		},
		TeamPreferences = {}
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
		Players = {
			1, 5
		},
		Indices = {
			1, 2
		},
		Totals = {
			2750, 2500
		}
	}

	local Optimiser = VoteShuffle.TeamOptimiser( TeamMembers, TeamSkills, function() end )
	local Swaps = {
		SwapData
	}
	Optimiser.CurrentPotentialState.Swaps = Swaps
	Optimiser.SwapCount = 1

	local Result = Optimiser:CommitSwap()
	Assert:Nil( Result )

	Assert:ArrayEquals( { 5, 2, 3 }, TeamMembers[ 1 ] )
	Assert:ArrayEquals( { 4, 1, 6 }, TeamMembers[ 2 ] )

	Assert:Equals( 2750, TeamSkills[ 1 ].Total )
	Assert:Equals( 2500, TeamSkills[ 2 ].Total )
end )

UnitTest:Test( "CommitSwap with uneven teams", function( Assert )
	local TeamMembers = {
		{
			1, 2, 3
		},
		{
			4, 5
		},
		TeamPreferences = {}
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
		Players = {
			1, nil
		},
		Indices = {
			1, 3
		},
		Totals = {
			2000, 2500
		}
	}

	local Optimiser = VoteShuffle.TeamOptimiser( TeamMembers, TeamSkills, function() end )
	local Swaps = {
		SwapData
	}
	Optimiser.CurrentPotentialState.Swaps = Swaps
	Optimiser.SwapCount = 1

	local Result = Optimiser:CommitSwap()

	Assert:Nil( Result )
	Assert:Equals( 2, Optimiser.LargerTeam )
	Assert:Equals( 1, Optimiser.LesserTeam )

	Assert:ArrayEquals( { 2, 3 }, TeamMembers[ 1 ] )
	Assert:ArrayEquals( { 4, 5, 1 }, TeamMembers[ 2 ] )

	Assert:Equals( 2000, TeamSkills[ 1 ].Total )
	Assert:Equals( 2, TeamSkills[ 1 ].Count )

	Assert:Equals( 2500, TeamSkills[ 2 ].Total )
	Assert:Equals( 3, TeamSkills[ 2 ].Count )
end )

UnitTest:Test( "SwapPassesRequirements", function( Assert )
	local Optimiser = VoteShuffle.TeamOptimiser( { {}, {} }, {}, function() end )
	Optimiser.CurrentPotentialState.AverageDiffBefore = 100
	Optimiser.CurrentPotentialState.StdDiffBefore = 20

	-- Fails because average is increasing.
	Assert:False( Optimiser:SwapPassesRequirements( 120, 10 ) )
	-- Fails because there is no change.
	Assert:False( Optimiser:SwapPassesRequirements( 100, 20 ) )
	-- Fails because standard deviation increases while average doesn't.
	Assert:False( Optimiser:SwapPassesRequirements( 100, 100 ) )
	-- Fails because standard deviation increases too much.
	Assert:False( Optimiser:SwapPassesRequirements( 90, 100 ) )

	-- Succeeds because it's a decrease in both.
	Assert:True( Optimiser:SwapPassesRequirements( 90, 10 ) )
	-- Succeeds because it's a decrease in standard deviation.
	Assert:True( Optimiser:SwapPassesRequirements( 100, 10 ) )
	-- Succeeds because it's a decrease in average, while the standard deviation increase is within tolerance.
	Assert:True( Optimiser:SwapPassesRequirements( 90, 30 ) )
end )

UnitTest:Test( "GetAverage", function( Assert )
	local Skills = {
		50, 80
	}
	local Optimiser = VoteShuffle.TeamOptimiser( { {}, {} }, {
		{
			Total = 1000,
			Count = 10,
			Average = 100
		},
		{
			Total = 1500,
			Count = 10,
			Average = 150
		}
	}, function( Player )
		return Skills[ Player ]
	end )

	local Average, Total = Optimiser:GetAverage( 1, Optimiser.TeamSkills, 1, 2 )
	Assert:Equals( 103, Average )
	Assert:Equals( 1030, Total )

	Average, Total = Optimiser:GetAverage( 2, Optimiser.TeamSkills, 1, 2 )
	Assert:Equals( 153, Average )
	Assert:Equals( 1530, Total )
end )

UnitTest:Test( "GetStandardDeviation", function( Assert )
	local Players = {
		1, 2, 3, 4, 5, 6
	}
	local Skills = {
		{ 1000, 1000, 1200, 1500, 1600, 2000 },
		{ 2000, 2100, 2200, 2300, 2500, 3000 }
	}

	local Optimiser = VoteShuffle.TeamOptimiser( { {}, {} }, {}, function( Player, TeamNumber )
		return Skills[ TeamNumber ][ Player ] or 5000
	end )

	-- Should respect team number.
	local StdDev = Optimiser:GetStandardDeviation( Players, table.Average( Skills[ 1 ] ), 1 )
	Assert:Equals( math.StandardDeviation( Skills[ 1 ] ), StdDev )

	StdDev = Optimiser:GetStandardDeviation( Players, table.Average( Skills[ 2 ] ), 2 )
	Assert:Equals( math.StandardDeviation( Skills[ 2 ] ), StdDev )

	-- If testing a swap, should replace the player being swapped in correctly.
	local NewTeam = table.QuickCopy( Skills[ 1 ] )
	NewTeam[ 6 ] = 5000
	StdDev = Optimiser:GetStandardDeviation( Players, table.Average( NewTeam ), 1, 7, 6 )
	Assert:Equals( math.StandardDeviation( NewTeam ), StdDev )

	-- If adding a new player, should account for them.
	NewTeam[ 6 ] = Skills[ 1 ][ 6 ]
	NewTeam[ 7 ] = 5000
	StdDev = Optimiser:GetStandardDeviation( Players, table.Average( NewTeam ), 1, 7, 7 )
	Assert:Equals( math.StandardDeviation( NewTeam ), StdDev )
end )

UnitTest:Test( "SnapshotStats", function( Assert )
	local CurrentTeamSkills = {}
	local TeamMembers = { {}, {} }

	local Optimiser = VoteShuffle.TeamOptimiser( TeamMembers, CurrentTeamSkills, function( Player, TeamNumber ) end )

	local GotAverage
	local GotStdDev
	local CurrentTeamNumber = 1
	local CurrentLosingPlayer = 1
	local CurrentGainingPlayer = 2
	local GainingIndex = 1

	function Optimiser:GetAverage( TeamNumber, TeamSkills, LosingPlayer, GainingPlayer )
		GotAverage = true
		Assert:Equals( CurrentTeamNumber, TeamNumber )
		Assert:Equals( CurrentTeamSkills, TeamSkills )
		Assert:Equals( CurrentLosingPlayer, LosingPlayer )
		Assert:Equals( CurrentGainingPlayer, GainingPlayer )

		return 1000, 10000
	end

	function Optimiser:GetStandardDeviation( Players, Average, TeamNumber, GainingPlayer, Index )
		GotStdDev = true
		Assert:Equals( TeamMembers[ TeamNumber ], Players )
		Assert:Equals( 1000, Average )
		Assert:Equals( CurrentTeamNumber, TeamNumber )
		Assert:Equals( CurrentGainingPlayer, 2 )
		Assert:Equals( GainingIndex, Index )

		return 0
	end

	local SwapContext = {
		Indices = { GainingIndex, 2 },
		Players = { CurrentLosingPlayer, CurrentGainingPlayer },
		PostData = { {}, {} }
	}

	Optimiser:SnapshotStats( 1, SwapContext )
	Assert:True( GotAverage )
	Assert:Equals( 1000, SwapContext.PostData[ 1 ].Average )
	Assert:Equals( 10000, SwapContext.PostData[ 1 ].Total )
	Assert:Equals( 0, SwapContext.PostData[ 1 ].StandardDeviation )
end )

UnitTest:Test( "GetSwap", function( Assert )
	local Optimiser = VoteShuffle.TeamOptimiser( { {}, {} }, {}, function( Player, TeamNumber ) end )
	local Swap = Optimiser:GetSwap( 1 )
	Assert:Equals( Swap, Optimiser.CurrentPotentialState.Swaps[ 1 ] )

	local SwapAgain = Optimiser:GetSwap( 1 )
	Assert:Equals( Swap, SwapAgain )
	Assert:Equals( Swap, Optimiser.CurrentPotentialState.Swaps[ 1 ] )
end )

UnitTest:Test( "SimulateSwap", function( Assert )
	local Optimiser = VoteShuffle.TeamOptimiser( { { 4 }, { 2, 3 } }, {}, function( Player, TeamNumber ) end )

	local TimesSimulated = 0
	local CurrentTeam = 1
	function Optimiser:SnapshotStats( TeamNumber, SwapContext )
		TimesSimulated = TimesSimulated + 1

		Assert:Equals( CurrentTeam, TeamNumber )
		Assert:Equals( self.SwapContext, SwapContext )

		CurrentTeam = CurrentTeam + 1
	end

	local SwapContext = Optimiser.SwapContext
	SwapContext.PreData = {
		{
			Average = 1500,
			Total = 11500,
			StandardDeviation = 10
		},
		{
			Average = 1500,
			Total = 18500,
			StandardDeviation = 30
		}
	}
	SwapContext.PostData = {
		{
			Average = 1000,
			Total = 10000,
			StandardDeviation = 0
		},
		{
			Average = 2000,
			Total = 20000,
			StandardDeviation = 20
		}
	}

	Optimiser.SwapCount = 0

	function Optimiser:SwapPassesRequirements( AverageDiff, StdDiff )
		Assert:Equals( 1000, AverageDiff )
		Assert:Equals( 20, StdDiff )
		return true
	end

	Optimiser:SimulateSwap( 1, 2 )

	Assert:Equals( 2, TimesSimulated )
	Assert:Equals( 1, Optimiser.SwapCount )
	Assert:NotNil( Optimiser.CurrentPotentialState.Swaps[ 1 ] )

	local Swap = Optimiser.CurrentPotentialState.Swaps[ 1 ]
	Assert:ArrayEquals( { 1, 2 }, Swap.Indices )
	Assert:ArrayEquals( { 4, 3 }, Swap.Players )
	Assert:ArrayEquals( { 10000, 20000 }, Swap.Totals )
	Assert:Equals( 1000, Swap.AverageDiff )
	Assert:Equals( 20, Swap.StdDiff )
end )

UnitTest:Test( "TrySwaps", function( Assert )
	local Optimiser = VoteShuffle.TeamOptimiser( { { 2, 3 }, { 1 } }, {}, function( Player, TeamNumber ) end )

	-- Teams are not equal, this should have been seen.
	Assert:Equals( 1, Optimiser.LargerTeam )
	Assert:Equals( 2, Optimiser.LesserTeam )
	Assert:False( Optimiser.TeamsAreEqual )

	local CheckedPlayers = {}
	local CurrentPass = 1
	function Optimiser:IsValidForSwap( Player, Pass )
		Assert:Equals( CurrentPass, Pass )
		CheckedPlayers[ Player ] = true

		return true
	end

	local CurrentMainPlayerIndex = 1
	local ComparedTo = {}

	function Optimiser:SimulateSwap( PlayerIndex, OtherPlayerIndex )
		Assert:Equals( CurrentMainPlayerIndex, PlayerIndex )
		ComparedTo[ OtherPlayerIndex ] = true
	end

	Optimiser:TrySwaps( CurrentMainPlayerIndex, CurrentPass )
	-- Should have made sure all players were valid to swap, and simulated
	-- player 2 on team 1 vs player 1 and adding to slot 2 on team 2.
	for i = 1, 2 do
		Assert:True( CheckedPlayers[ i ] )
		Assert:True( ComparedTo[ i ] )
	end
end )

UnitTest:Test( "PerformOptimisationPass", function( Assert )
	local Optimiser = VoteShuffle.TeamOptimiser( { { 2, 3 }, { 1, 4 } },
		{ { Average = 1000 }, { Average = 2000 } }, function( Player, TeamNumber ) end )

	function Optimiser:CacheStandardDeviations()
		self.StandardDeviationCache = self.StandardDeviationCache or {}
		for i = 1, 2 do
			self.StandardDeviationCache[ i ] = i * 10
		end
	end

	local CurrentPlayerIndex = 1
	local CurrentPass = 1
	local SwapsTried = 0
	function Optimiser:TrySwaps( PlayerIndex, Pass )
		Assert:Equals( 1000, self.CurrentPotentialState.AverageDiffBefore )
		Assert:Equals( 10, self.CurrentPotentialState.StdDiffBefore )
		Assert:Equals( CurrentPlayerIndex, PlayerIndex )
		Assert:Equals( CurrentPass, Pass )

		CurrentPlayerIndex = CurrentPlayerIndex + 1
		SwapsTried = SwapsTried + 1
	end

	local Iterations = 0
	local ReturnCode = 1
	function Optimiser:CommitSwap()
		CurrentPlayerIndex = 1
		Iterations = Iterations + 1
		if Iterations == 2 then
			return ReturnCode
		end
	end

	-- CommitSwap says to terminate on iteration 2, so should return true.
	Assert:True( Optimiser:PerformOptimisationPass( CurrentPass ) )
	Assert:Equals( 2, Iterations )
	Assert:Equals( 4, SwapsTried )

	Iterations = 0
	ReturnCode = 2
	SwapsTried = 0

	-- CommitSwap says to end the pass on iteration 2, so should return nil.
	Assert:Nil( Optimiser:PerformOptimisationPass( CurrentPass ) )
	Assert:Equals( 2, Iterations )
	Assert:Equals( 4, SwapsTried )
end )
