--[[
	Map vote plugin unit tests.
]]

local UnitTest = Shine.UnitTest

local MapVotePlugin = UnitTest:LoadExtension( "mapvote" )
if not MapVotePlugin then return end

local MapVote = UnitTest.MockPlugin( MapVotePlugin )
do
	local MockGamerules = {}
	UnitTest.MockGlobal( "GetGamerules", function()
		return MockGamerules
	end )

	MapVote.Config.ForceChangeWhenSecondsLeft = 60

	UnitTest:Before( function()
		MapVote.VoteOnEnd = true
		MapVote.Round = 0
		MapVote.SendTranslatedNotify = UnitTest.MockFunction()
		MapVote.StartVote = UnitTest.MockFunction()
		MapVote.ForcePlayersIntoReadyRoom = UnitTest.MockFunction()
	end )

	UnitTest:Test( "SetupFromMapData - Applies time and round limits from map (upper-camel)", function( Assert )
		MapVote.VoteOnEnd = false
		MapVote.MapCycle.time = 0
		MapVote.RoundLimit = 0

		MapVote:SetupFromMapData( {
			Time = 60,
			Rounds = 5
		} )

		Assert.Equals( "Should have set the map cycle time from the map", 60, MapVote.MapCycle.time )
		Assert.Equals( "Should have applied the map's round limit", 5, MapVote.RoundLimit )
		Assert.True( "Should have set VoteOnEnd = true as the round limit is > 0", MapVote.VoteOnEnd )
	end )

	UnitTest:Test( "SetupFromMapData - Applies time and round limits from map (lower-camel)", function( Assert )
		MapVote.VoteOnEnd = false
		MapVote.MapCycle.time = 0
		MapVote.RoundLimit = 0

		MapVote:SetupFromMapData( {
			time = 60,
			rounds = 5
		} )

		Assert.Equals( "Should have set the map cycle time from the map", 60, MapVote.MapCycle.time )
		Assert.Equals( "Should have applied the map's round limit", 5, MapVote.RoundLimit )
		Assert.True( "Should have set VoteOnEnd = true as the round limit is > 0", MapVote.VoteOnEnd )
	end )

	UnitTest:Test( "SetupFromMapData - Ignores invalid time/round limits from map", function( Assert )
		MapVote.VoteOnEnd = false
		MapVote.MapCycle.time = 0
		MapVote.RoundLimit = 0

		MapVote:SetupFromMapData( {
			Time = "invalid time",
			Rounds = "invalid rounds"
		} )

		Assert.Equals( "Should have kept the existing map cycle time", 0, MapVote.MapCycle.time )
		Assert.Equals( "Should have kept the existing round limit", 0, MapVote.RoundLimit )
		Assert.False( "Should not have set VoteOnEnd = true", MapVote.VoteOnEnd )
	end )

	UnitTest:Test(
		"CheckMapLimitsAfterRoundEnd - Does nothing if map time limit not yet reached and time left is > 1 hour",
		function( Assert )
			MapVote.RoundLimit = 0
			MapVote.MapCycle.time = Shared.GetTime() / 60 + 120

			MapVote:CheckMapLimitsAfterRoundEnd()

			Assert.CalledTimes( "Should not have sent a message", MapVote.SendTranslatedNotify, 0 )
			Assert.CalledTimes( "Should not have started a vote", MapVote.StartVote, 0 )
		end
	)

	UnitTest:Test(
		"CheckMapLimitsAfterRoundEnd - Does nothing if map time limit and round limit not yet reached and rounds left > 10",
		function( Assert )
			MapVote.RoundLimit = 15
			MapVote.MapCycle.time = Shared.GetTime() / 60 + 5

			MapVote:CheckMapLimitsAfterRoundEnd()

			Assert.CalledTimes( "Should not have sent a message", MapVote.SendTranslatedNotify, 0 )
			Assert.CalledTimes( "Should not have started a vote", MapVote.StartVote, 0 )
		end
	)

	UnitTest:Test(
		"CheckMapLimitsAfterRoundEnd - Sends message if no round limit and map time limit not yet reached",
		function( Assert )
			MapVote.RoundLimit = 0
			MapVote.MapCycle.time = Shared.GetTime() / 60 + 5.1

			MapVote:CheckMapLimitsAfterRoundEnd()

			Assert.Called(
				"Should have notified that there is 5 minutes remaining on the map (rounded to 30 seconds)",
				MapVote.SendTranslatedNotify,
				MapVote,
				nil,
				"TimeLeftNotify",
				{
					Duration = 300
				}
			)
			Assert.CalledTimes( "Should not have started a vote", MapVote.StartVote, 0 )
		end
	)

	UnitTest:Test(
		"CheckMapLimitsAfterRoundEnd - Sends message if round limit exists but has not been reached",
		function( Assert )
			MapVote.RoundLimit = 2
			MapVote.MapCycle.time = Shared.GetTime() / 60 + 120

			MapVote:CheckMapLimitsAfterRoundEnd()

			Assert.Called(
				"Should have notified that there is 1 round remaining on the map",
				MapVote.SendTranslatedNotify,
				MapVote,
				nil,
				"RoundLeftNotify",
				{
					Duration = 1
				}
			)
			Assert.CalledTimes( "Should not have started a vote", MapVote.StartVote, 0 )
		end
	)

	UnitTest:Test(
		"CheckMapLimitsAfterRoundEnd - Starts a next map vote if time limit is reached with no round limit",
		function( Assert )
			MapVote.RoundLimit = 0
			-- ForceChangeWhenSecondsLeft = 60 means at <= 1 minute left the next map vote should start.
			MapVote.MapCycle.time = math.floor( Shared.GetTime() / 60 ) + 1

			MapVote:CheckMapLimitsAfterRoundEnd()

			Assert.Called( "Should have called StartVote( true )", MapVote.StartVote, MapVote, true )
			Assert.Called(
				"Should have called ForcePlayersIntoReadyRoom()",
				MapVote.ForcePlayersIntoReadyRoom,
				MapVote
			)
		end
	)

	UnitTest:Test(
		"CheckMapLimitsAfterRoundEnd - Starts a next map vote if time limit is reached with a round limit",
		function( Assert )
			MapVote.RoundLimit = 5
			MapVote.MapCycle.time = Shared.GetTime() / 60

			MapVote:CheckMapLimitsAfterRoundEnd()

			Assert.Called( "Should have called StartVote( true )", MapVote.StartVote, MapVote, true )
			Assert.Called(
				"Should have called ForcePlayersIntoReadyRoom()",
				MapVote.ForcePlayersIntoReadyRoom,
				MapVote
			)
		end
	)

	UnitTest:Test(
		"CheckMapLimitsAfterRoundEnd - Starts a next map vote if round limit is reached",
		function( Assert )
			MapVote.RoundLimit = 1
			MapVote.MapCycle.time = Shared.GetTime() / 60 + 5

			MapVote:CheckMapLimitsAfterRoundEnd()

			Assert.Called( "Should have called StartVote( true )", MapVote.StartVote, MapVote, true )
			Assert.Called(
				"Should have called ForcePlayersIntoReadyRoom()",
				MapVote.ForcePlayersIntoReadyRoom,
				MapVote
			)
		end
	)

	UnitTest:ResetState()
	MapVote = UnitTest.MockPlugin( MapVotePlugin )
end

function MapVote:LoadMapStats() end

UnitTest:Test( "SetupMaps - Adds all valid maps from the map cycle when GetMapsFromMapCycle = true", function( Assert )
	MapVote.Config.GetMapsFromMapCycle = true

	local Cycle = {
		maps = {
			"ns2_derelict",
			"ns2_tram",
			"ns2_veil",
			12345,
			{ map = "ns2_summit", chance = 0.5, percent = 10 },
			{ map = "ns2_biodome" },
			{}
		},
		groups = {}
	}

	MapVote:SetupMaps( Cycle )

	Assert.Equals( "Should take the map groups from the cycle", Cycle.groups, MapVote.MapGroups )

	Assert.DeepEquals( "Should have copied all valid maps into Config.Maps", {
		ns2_derelict = true,
		ns2_tram = true,
		ns2_veil = true,
		ns2_biodome = true,
		ns2_summit = true
	}, MapVote.Config.Maps )

	Assert.DeepEquals( "Should read the chance value from maps, defaulting to 1", {
		ns2_derelict = 1,
		ns2_tram = 1,
		ns2_veil = 1,
		ns2_biodome = 1,
		ns2_summit = 0.5
	}, MapVote.MapProbabilities )

	Assert.DeepEquals( "Should copy the valid maps into MapChoices", {
		"ns2_derelict",
		"ns2_tram",
		"ns2_veil",
		{ map = "ns2_summit", chance = 0.5, percent = 10 },
		{ map = "ns2_biodome" },
	}, MapVote.MapChoices )

	Assert.DeepEquals( "Should store table maps in MapOptions", {
		ns2_biodome = {
			map = "ns2_biodome"
		},
		ns2_summit = {
			map = "ns2_summit",
			chance = 0.5,
			percent = 10
		}
	}, MapVote.MapOptions )
end )

UnitTest:Test( "SetupMaps - Sets up maps from config and cycle when GetMapsFromMapCycle = false", function( Assert )
	MapVote.Config.GetMapsFromMapCycle = false

	local Cycle = {
		maps = {
			"ns2_derelict",
			"ns2_tram",
			"ns2_veil",
			12345,
			{ map = "ns2_summit", chance = 0.5, percent = 10 },
			{ map = "ns2_biodome" },
			{}
		}
	}
	MapVote.Config.Maps = {
		ns2_descent = true,
		ns2_eclipse = {
			chance = 0.2,
			percent = 50
		}
	}

	MapVote:SetupMaps( Cycle )

	Assert.DeepEquals( "Config.Maps should be unchanged", {
		ns2_descent = true,
		ns2_eclipse = {
			map = "ns2_eclipse",
			chance = 0.2,
			percent = 50
		}
	}, MapVote.Config.Maps )

	Assert.DeepEquals( "Should read the chance value from maps, defaulting to 1", {
		ns2_derelict = 1,
		ns2_tram = 1,
		ns2_veil = 1,
		ns2_biodome = 1,
		ns2_descent = 1,
		ns2_summit = 0.5,
		ns2_eclipse = 0.2
	}, MapVote.MapProbabilities )

	Assert.DeepEquals( "Should copy the valid maps from the cycle into MapChoices", {
		"ns2_derelict",
		"ns2_tram",
		"ns2_veil",
		{ map = "ns2_summit", chance = 0.5, percent = 10 },
		{ map = "ns2_biodome" },
	}, MapVote.MapChoices )

	Assert.DeepEquals( "Should store table maps in MapOptions", {
		ns2_biodome = {
			map = "ns2_biodome"
		},
		ns2_summit = {
			map = "ns2_summit",
			chance = 0.5,
			percent = 10
		},
		ns2_eclipse = {
			map = "ns2_eclipse",
			chance = 0.2,
			percent = 50
		}
	}, MapVote.MapOptions )
end )

function MapVote:GetCurrentMap()
	return "ns2_veil"
end

UnitTest:Test( "GetNextMap - Returns next map vote winner if present", function( Assert )
	MapVote.NextMap.Winner = "ns2_tram"
	Assert.Equals( "Should return the map vote winner", "ns2_tram", MapVote:GetNextMap() )
end )

MapVote.NextMap.Winner = nil

UnitTest:Test( "GetNextMap - Returns the first valid map after the current map", function( Assert )
	MapVote.MapChoices = {
		"ns2_summit",
		"ns2_tram",
		{ map = "ns2_veil" },
		{ map = "ns2_derelict", max = 0 },
		"ns2_biodome"
	}
	MapVote.Config.IgnoreAutoCycle = {
		ns2_biodome = true,
		ns2_summit = true
	}
	-- Derelict is invalid due to player count, and biodome and summit are ignored, so tram must be next.
	Assert.Equals(
		"Should return the first valid map after ns2_veil",
		"ns2_tram",
		MapVote:GetNextMap()
	)
end )

UnitTest:Test( "GetNextMap - Returns the first map not in IgnoreAutoCycle when no maps are valid", function( Assert )
	MapVote.MapChoices = {
		{ map = "ns2_summit", max = 0 },
		{ map = "ns2_tram", max = 0 },
		{ map = "ns2_veil" },
		{ map = "ns2_derelict", max = 0 },
		{ map = "ns2_biodome", max = 0 }
	}
	MapVote.Config.IgnoreAutoCycle = {
		ns2_derelict = true,
		ns2_biodome = true
	}
	-- All maps are invalid due to player count except the current map, but only derelict and biodome are
	-- ignored, thus the next map should be summit.
	Assert.Equals(
		"Should return the first map after ns2_veil not in IgnoreAutoCycle",
		"ns2_summit",
		MapVote:GetNextMap()
	)
end )

function MapVote:GetCurrentMap()
	return "ns2_unearthed"
end

UnitTest:Test( "GetNextMap - Handles current map being outside the current cycle", function( Assert )
	MapVote.MapChoices = {
		"ns2_summit",
		"ns2_tram",
		{ map = "ns2_veil" },
		{ map = "ns2_derelict", max = 0 },
		"ns2_biodome"
	}
	MapVote.Config.IgnoreAutoCycle = {
		ns2_biodome = true,
		ns2_summit = true
	}
	-- When outside the cycle, the current map index is 0, so should start from the first map.
	Assert.Equals(
		"Should return the first valid map in the cycle",
		"ns2_tram",
		MapVote:GetNextMap()
	)
end )

MapVote.MaxNominations = 5
MapVote.Config.Nominations.MaxTotalType = MapVote.MaxNominationsType.AUTO

UnitTest:Test( "GetMaxNominations - AUTO should return computed max", function( Assert )
	Assert:Equals( 5, MapVote:GetMaxNominations() )
end )

MapVote.Config.Nominations.MaxTotalType = MapVote.MaxNominationsType.ABSOLUTE
MapVote.Config.Nominations.MaxTotalValue = 2

UnitTest:Test( "GetMaxNominations - ABSOLUTE should return max value from config", function( Assert )
	Assert:Equals( 2, MapVote:GetMaxNominations() )
end )

function MapVote:GetPlayerCountForVote() return 1 end

MapVote.Config.Nominations.MaxTotalType = MapVote.MaxNominationsType.FRACTION_OF_PLAYERS
MapVote.Config.Nominations.MaxTotalValue = 0.5
MapVote.Config.Nominations.MinTotalValue = 3

UnitTest:Test( "GetMaxNominations - FRACTION_OF_PLAYERS should return min value when player count is too low", function( Assert )
	Assert:Equals( 3, MapVote:GetMaxNominations() )
end )

function MapVote:GetPlayerCountForVote() return 20 end

UnitTest:Test( "GetMaxNominations - FRACTION_OF_PLAYERS should return fraction when player count is high enough", function( Assert )
	Assert:Equals( 10, MapVote:GetMaxNominations() )
end )

MapVote.Config.Nominations.AllowExcludedMaps = false

UnitTest:Test( "CanNominateWhenExcluded - Deny when AllowExcludedMaps = false and no map override", function( Assert )
	Assert.False( "Should not allow nominating when excluded", MapVote:CanNominateWhenExcluded( "ns2_derelict" ) )
end )

MapVote.MapOptions[ "ns2_derelict" ] = {
	AllowNominationWhenExcluded = true
}

UnitTest:Test( "CanNominateWhenExcluded - Allow when AllowExcludedMaps = false but map overrides with true", function( Assert )
	Assert.True( "Should allow nominating when excluded", MapVote:CanNominateWhenExcluded( "ns2_derelict" ) )
end )

MapVote.Config.Nominations.AllowExcludedMaps = true

UnitTest:Test( "CanNominateWhenExcluded - Allow when AllowExcludedMaps = true and no map override", function( Assert )
	Assert.True( "Should allow nominating when excluded", MapVote:CanNominateWhenExcluded( "ns2_derelict" ) )
end )

MapVote.MapOptions[ "ns2_derelict" ] = {
	AllowNominationWhenExcluded = false
}

UnitTest:Test( "CanNominateWhenExcluded - Deny when AllowExcludedMaps = true but map overrides with false", function( Assert )
	Assert.False( "Should not allow nominating when excluded", MapVote:CanNominateWhenExcluded( "ns2_derelict" ) )
end )

MapVote.Config.Constraints.StartVote.MinVotesRequired = {
	Type = MapVote.ConstraintType.ABSOLUTE,
	Value = 10
}

UnitTest:Test( "GetVoteConstraint - Absolute value", function( Assert )
	Assert:Equals( 10, MapVote:GetVoteConstraint( "StartVote", "MinVotesRequired", 10 ) )
end )

MapVote.Config.Constraints.StartVote.MinVotesRequired = {
	Type = MapVote.ConstraintType.FRACTION_OF_PLAYERS,
	Value = 0.5
}

UnitTest:Test( "GetVoteConstraint - Fraction value", function( Assert )
	Assert:Equals( 5, MapVote:GetVoteConstraint( "StartVote", "MinVotesRequired", 9 ) )
end )

MapVote.Config.Constraints.StartVote.MinVotesRequired = nil

MapVote.TrackMapStats = false
MapVote.MapStats = {}

UnitTest:Test( "IsValidMapChoice - Stats", function( Assert )
	local Map = {
		map = "ns2_veil",
		percent = 10
	}
	local MapStats = {
		ns2_veil = 11,
		ns2_derelict = 89
	}

	MapVote.TrackMapStats = true
	MapVote.MapStats = MapStats
	MapVote.TotalPlayedMaps = 100

	Assert:False( MapVote:IsValidMapChoice( Map, 16 ) )

	MapStats.ns2_veil = 10
	MapStats.ns2_derelict = 90

	Assert:False( MapVote:IsValidMapChoice( Map, 16 ) )

	MapStats.ns2_veil = 9
	MapStats.ns2_derelict = 91

	Assert:True( MapVote:IsValidMapChoice( Map, 16 ) )
end, function()
	MapVote.TrackMapStats = false
	MapVote.MapStats = {}
end )

UnitTest:Test( "IsValidMapChoice - Player count", function( Assert )
	local Map = {
		map = "ns2_veil",
		min = 5,
		max = 10
	}

	for i = 0, Map.min - 1 do
		Assert:False( MapVote:IsValidMapChoice( Map, i ) )
	end

	for i = Map.min, Map.max do
		Assert:True( MapVote:IsValidMapChoice( Map, i ) )
	end

	for i = Map.max + 1, 100 do
		Assert:False( MapVote:IsValidMapChoice( Map, i ) )
	end
end )

MapVote.Config.MaxOptions = 5
MapVote.Config.ExcludeLastMaps = {
	Min = 0,
	Max = 0,
	UseStrictMatching = true
}
MapVote.LastMapData = {
	"ns2_refinery", "ns2_veil", "ns2_summit", "ns2_kodiak"
}

UnitTest:Test( "RemoveLastMaps - Min and max == 0", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:RemoveLastMaps( PotentialMaps, FinalChoices )

	-- Should not remove anything, min and max are 0.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), PotentialMaps )
end )

MapVote.Config.ExcludeLastMaps = {
	Min = 3,
	UseStrictMatching = true
}

UnitTest:Test( "RemoveLastMaps - Min == auto and no max", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:RemoveLastMaps( PotentialMaps, FinalChoices )

	-- Should remove the last 3 maps, as min is 3 and auto would be 3 to bring it down to max options.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), PotentialMaps )
end )

UnitTest:Test( "RemoveLastMaps - Min > auto and no max", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:RemoveLastMaps( PotentialMaps, FinalChoices )

	-- Should remove the last 3 maps, as min is 3, even though it's now less than max options.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_refinery = true,
		ns2_descent = true
	} ), PotentialMaps )
end )

MapVote.Config.ExcludeLastMaps = {
	Min = 2,
	Max = 2,
	UseStrictMatching = true
}

UnitTest:Test( "RemoveLastMaps - Min and max equal", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:RemoveLastMaps( PotentialMaps, FinalChoices )

	-- Should remove the last 2 maps, as min is 2 and max is 2, even though auto would be 3.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), PotentialMaps )
end )

MapVote.Config.ExcludeLastMaps = {
	Min = 1,
	Max = 2,
	UseStrictMatching = true
}

UnitTest:Test( "RemoveLastMaps - Min and max not equal", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:RemoveLastMaps( PotentialMaps, FinalChoices )

	-- Should remove the last 2 maps, as min is 1 and max is 2, auto would be 3.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), PotentialMaps )
end )

MapVote.Config.ExcludeLastMaps = {
	Min = 2,
	Max = 4,
	UseStrictMatching = true
}

UnitTest:Test( "RemoveLastMaps - Min and max not equal, max larger than auto", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:RemoveLastMaps( PotentialMaps, FinalChoices )

	-- Should remove the last 3 maps, as min is 2 and max is 4, auto would be 3.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), PotentialMaps )
end )

MapVote.Config.ExcludeLastMaps = {
	Min = 2,
	Max = 4,
	UseStrictMatching = false
}

MapVote.LastMapData = {
	"ns2_refinery", "ns2_veil", "ns2_tram_nextstop", "ns2_kodiak"
}

UnitTest:Test( "RemoveLastMaps - Non-strict matching removes similar maps", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil_five = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:RemoveLastMaps( PotentialMaps, FinalChoices )

	-- Should remove the last 3 maps, matching ns2_veil vs. ns2_veil_five
	-- and ns2_tram vs. ns2_tram_nextstop.
	Assert:Equals( Shine.Set( {
		ns2_summit = true,
		ns2_derelict = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), PotentialMaps )
end )

MapVote.Config.ExcludeLastMaps = {
	Min = 2,
	Max = 4,
	UseStrictMatching = true
}

UnitTest:Test( "RemoveLastMaps - Strict matching removes only exactly matching maps", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil_five = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:RemoveLastMaps( PotentialMaps, FinalChoices )

	-- Should remove only ns2_kodiak as it's the only one with an exact match in the
	-- last 3 maps.
	Assert:Equals( Shine.Set( {
		ns2_summit = true,
		ns2_derelict = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true,
		ns2_tram = true,
		ns2_veil_five = true
	} ), PotentialMaps )
end )

function MapVote:GetCurrentMap()
	return "ns2_derelict"
end

MapVote.Config.ConsiderSimilarMapsAsExtension = true
function MapVote:CanExtend() return false end

UnitTest:Test( "AddCurrentMap - ConsiderSimilarMapsAsExtension excludes similar maps when enabled", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_derelict_awesomeedition = true,
		ns2_veil_five = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:AddCurrentMap( PotentialMaps, FinalChoices )

	-- Should remove both maps that are akin to ns2_derelict.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_veil_five = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), PotentialMaps )
end )

MapVote.Config.ConsiderSimilarMapsAsExtension = false

UnitTest:Test( "AddCurrentMap - ConsiderSimilarMapsAsExtension includes similar maps when disabled", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_derelict_awesomeedition = true,
		ns2_veil_five = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:AddCurrentMap( PotentialMaps, FinalChoices )

	-- Should remove only ns2_derelict.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict_awesomeedition = true,
		ns2_veil_five = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), PotentialMaps )
end )

function MapVote:CanExtend() return true end
MapVote.Config.AlwaysExtend = true

UnitTest:Test( "AddCurrentMap - AlwaysExtend adds map to final choices", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_derelict_awesomeedition = true,
		ns2_veil_five = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} )
	local FinalChoices = Shine.Set()

	MapVote:AddCurrentMap( PotentialMaps, FinalChoices )

	-- Should remove the current map from the potential set, and add it to the final choices.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict_awesomeedition = true,
		ns2_veil_five = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), PotentialMaps )
	Assert.Equals( "Set of final choices does not include current map!", Shine.Set( {
		ns2_derelict = true
	} ), FinalChoices )
end )

MapVote.CanExtend = nil
MapVote.Config.AlwaysExtend = false

MapVote.Config.Maps = {
	ns2_tram = true,
	ns2_derelict = true,
	ns2_veil = true,
	ns2_summit = true,
	ns2_kodiak = true,
	ns2_refinery = true,
	ns2_descent = true,
	ns2_biodome = true
}
MapVote.Config.Nominations.MaxOptionsExceededAction = MapVote.MaxOptionsExceededAction.ADD_MAP

UnitTest:Test( "AddNomination - Should add when number of choices is lower than max options size", function( Assert )
	Assert.True( "Expected max options exceeded actions to exist", #MapVotePlugin.MaxOptionsExceededAction > 0 )
	for i = 1, #MapVotePlugin.MaxOptionsExceededAction do
		local Action = MapVotePlugin.MaxOptionsExceededAction[ i ]
		local FinalChoices = Shine.Set()
		local Added = MapVote:AddNomination( "ns2_derelict", FinalChoices, Action, Shine.Set() )
		Assert.True( "Should have added nomination to choices set", Added )
		Assert:Equals( 1, FinalChoices:GetCount() )
		Assert.True( "Set should contain nominated map", FinalChoices:Contains( "ns2_derelict" ) )
	end
end )

UnitTest:Test( "AddNomination - ADD_MAP should add map even when number of choices is >= max", function( Assert )
	local FinalChoices = Shine.Set.FromList( { "ns2_tram", "ns2_summit", "ns2_biodome", "ns2_kodiak", "ns2_descent" } )
	local Added = MapVote:AddNomination( "ns2_derelict", FinalChoices, MapVotePlugin.MaxOptionsExceededAction.ADD_MAP, Shine.Set() )
	Assert.True( "Should have added nomination to choices set", Added )
	Assert:Equals( 6, FinalChoices:GetCount() )
	Assert.True( "Set should contain nominated map", FinalChoices:Contains( "ns2_derelict" ) )
end )

UnitTest:Test( "AddNomination - REPLACE_MAP should replace map when number of choices is >= max", function( Assert )
	local FinalChoices = Shine.Set.FromList( { "ns2_tram", "ns2_summit", "ns2_biodome", "ns2_kodiak", "ns2_descent" } )
	local Added = MapVote:AddNomination( "ns2_derelict", FinalChoices, MapVotePlugin.MaxOptionsExceededAction.REPLACE_MAP, Shine.Set() )
	Assert.True( "Should have added nomination to choices set", Added )
	Assert:Equals( 5, FinalChoices:GetCount() )
	Assert.True( "Set should contain nominated map", FinalChoices:Contains( "ns2_derelict" ) )
	Assert.False( "Set should not contain first replaceable map", FinalChoices:Contains( "ns2_tram" ) )
end )

UnitTest:Test( "AddNomination - REPLACE_MAP should not replace map when number of choices is >= max but all other maps are nominations", function( Assert )
	local FinalChoices = Shine.Set.FromList( { "ns2_tram", "ns2_summit", "ns2_biodome", "ns2_kodiak", "ns2_descent" } )
	local Added = MapVote:AddNomination( "ns2_derelict", FinalChoices, MapVotePlugin.MaxOptionsExceededAction.REPLACE_MAP, FinalChoices )
	Assert.False( "Should not have added nomination to choices set", Added )
	Assert:Equals( 5, FinalChoices:GetCount() )
	Assert.False( "Set should not contain nominated map", FinalChoices:Contains( "ns2_derelict" ) )
end )

UnitTest:Test( "AddNomination - SKIP should not add map when number of choices is >= max", function( Assert )
	local FinalChoices = Shine.Set.FromList( { "ns2_tram", "ns2_summit", "ns2_biodome", "ns2_kodiak", "ns2_descent" } )
	local Added = MapVote:AddNomination( "ns2_derelict", FinalChoices, MapVotePlugin.MaxOptionsExceededAction.SKIP, Shine.Set() )
	Assert.False( "Should not have added nomination to choices set", Added )
	Assert.False( "Set should not contain nominated map", FinalChoices:Contains( "ns2_derelict" ) )
end )

function MapVote:GetMapGroup() return nil end
function MapVote:IsValidMapChoice( Map, PlayerCount ) return true end
function MapVote:GetMaxNominations() return 2 end

MapVote.Vote.Nominated = {}

UnitTest:Test( "BuildPotentialMapChoices - No nominations or map group", function( Assert )
	-- Should just select all maps.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_refinery = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), MapVote:BuildPotentialMapChoices() )
end )

function MapVote:IsValidMapChoice( Map, PlayerCount ) return Map ~= "ns2_refinery" end

UnitTest:Test( "BuildPotentialMapChoices - No nominations or map group with invalid map", function( Assert )
	-- Should select everything except refinery.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_descent = true,
		ns2_biodome = true
	} ), MapVote:BuildPotentialMapChoices() )
end )

MapVote.Vote.Nominated = { "ns2_eclipse" }

UnitTest:Test( "BuildPotentialMapChoices - Nominations below limit", function( Assert )
	-- Should select everything except refinery and including eclipse.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_descent = true,
		ns2_biodome = true,
		ns2_eclipse = true
	} ), MapVote:BuildPotentialMapChoices() )
end )

MapVote.Vote.Nominated = { "ns2_eclipse", "ns2_kodiak", "ns2_caged" }

UnitTest:Test( "BuildPotentialMapChoices - Nominations above limit", function( Assert )
	-- Should select everything except refinery and including eclipse, but not caged as it's past the limit.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_derelict = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_kodiak = true,
		ns2_descent = true,
		ns2_biodome = true,
		ns2_eclipse = true
	} ), MapVote:BuildPotentialMapChoices() )
end )

function MapVote:GetMapGroup()
	return { maps = { "ns2_tram", "ns2_veil", "ns2_summit" } }
end

MapVote.Vote.Nominated = { "ns2_eclipse" }

UnitTest:Test( "BuildPotentialMapChoices - Map group", function( Assert )
	-- Should select everything in the map group, plus the nomination.
	Assert:Equals( Shine.Set( {
		ns2_tram = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_eclipse = true
	} ), MapVote:BuildPotentialMapChoices() )
end )

UnitTest:Test( "ChooseRandomMaps", function( Assert )
	local PotentialMaps = Shine.Set( {
		ns2_tram = true,
		ns2_veil = true,
		ns2_summit = true,
		ns2_eclipse = true
	} )
	local FinalChoices = Shine.Set( {
		ns2_biodome = true,
		ns2_eclipse = true
	} )

	MapVote:ChooseRandomMaps( PotentialMaps, FinalChoices, 5 )

	-- Should fill the choices up.
	Assert:Equals( 5, FinalChoices:GetCount() )
end )

function MapVote:GetMapGroup() return nil end
function MapVote:IsValidMapChoice( Map, PlayerCount ) return true end
function MapVote:GetMaxNominations() return 5 end

MapVote.Vote.Nominated = { "ns2_tram", "ns2_summit", "ns2_veil", "ns2_biodome", "ns2_eclipse" }
MapVote.Config.ExcludeLastMaps = {
	Min = 0,
	Max = 0
}

MapVote.Config.ForcedMaps = {}

UnitTest:Test( "BuildMapChoices - Respect nominations", function( Assert )
	-- Nominated 5 maps, with 5 max options, so all nominations should be the choices.
	Assert:ArrayEquals( MapVote.Vote.Nominated, MapVote:BuildMapChoices() )
end )

MapVote.Vote.Nominated = { "ns2_tram", "ns2_summit", "ns2_veil", "ns2_biodome", "ns2_eclipse", "ns2_kodiak" }
UnitTest:Test( "BuildMapChoices - Respect nominations", function( Assert )
	-- Nominated 6 maps, with 5 max nominations and 5 max options, so the first 5 nominations should be the choices.
	Assert:ArrayEquals( {
		"ns2_tram", "ns2_summit", "ns2_veil", "ns2_biodome", "ns2_eclipse"
	}, MapVote:BuildMapChoices() )
end )

MapVote.Config.ForcedMaps = {
	ns2_kodiak = true,
	ns2_derelict = true
}
MapVote.ForcedMapCount = 2
MapVote.Vote.Nominated = { "ns2_tram", "ns2_summit", "ns2_veil", "ns2_biodome" }
UnitTest:Test( "BuildMapChoices - ADD_MAP should allow max options to be exceeded", function( Assert )
	-- Nominated 4 maps, with 5 max nominations and 5 max options, with exceed action ADD_MAP, so should just add the nominations.
	Assert:ArrayEquals( {
		"ns2_derelict", "ns2_kodiak", "ns2_tram", "ns2_summit", "ns2_veil", "ns2_biodome"
	}, MapVote:BuildMapChoices() )
end )

MapVote.Config.Nominations.MaxOptionsExceededAction = MapVote.MaxOptionsExceededAction.REPLACE_MAP
UnitTest:Test( "BuildMapChoices - REPLACE_MAP should ensure max options is not exceeded", function( Assert )
	Assert:ArrayEquals( {
		"ns2_biodome", "ns2_kodiak", "ns2_tram", "ns2_summit", "ns2_veil"
	}, MapVote:BuildMapChoices() )
end )

MapVote.Config.Nominations.MaxOptionsExceededAction = MapVote.MaxOptionsExceededAction.SKIP
UnitTest:Test( "BuildMapChoices - SKIP should ensure max options is not exceeded", function( Assert )
	Assert:ArrayEquals( {
		"ns2_derelict", "ns2_kodiak", "ns2_tram", "ns2_summit", "ns2_veil"
	}, MapVote:BuildMapChoices() )
end )

MapVote.ForcedMapCount = 0
MapVote.Config.ForcedMaps = {}
MapVote.MapOptions = {}

MapVote.Vote.Nominated = { "ns2_tram", "ns2_summit", "ns2_veil", "ns2_biodome", "ns2_eclipse" }
function MapVote:IsValidMapChoice( Map, PlayerCount ) return Map ~= "ns2_eclipse" end

UnitTest:Test( "BuildMapChoices - Deny nominations", function( Assert )
	-- Should use all nominations except the denied one.
	local Choices = MapVote:BuildMapChoices()
	for i = 1, 4 do
		Assert:Equals( MapVote.Vote.Nominated[ i ], Choices[ i ] )
	end
	Assert:NotEquals( "ns2_eclipse", Choices[ 5 ] )
end )
