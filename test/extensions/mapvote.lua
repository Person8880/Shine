--[[
	Map vote plugin unit tests.
]]

local UnitTest = Shine.UnitTest

local MapVote = UnitTest:LoadExtension( "mapvote" )
if not MapVote then return end

MapVote.TrackMapStats = nil
MapVote.MapStats = nil

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
	MapVote.TrackMapStats = nil
	MapVote.MapStats = nil
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

local OldMaxOptions = MapVote.Config.MaxOptions
local OldExcludeLastMaps = MapVote.Config.ExcludeLastMaps
local OldLastMaps = MapVote.LastMapData

MapVote.Config.MaxOptions = 5
MapVote.Config.ExcludeLastMaps = {
	Min = 0,
	Max = 0
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
	Min = 3
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
	Max = 2
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
	Max = 2
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
	Max = 4
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

local OldMaps = MapVote.Config.Maps
local OldGetMapGroup = MapVote.GetMapGroup
local OldIsValidMapChoice = MapVote.IsValidMapChoice

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

function MapVote:GetMapGroup() return nil end
function MapVote:IsValidMapChoice( Map, PlayerCount ) return true end

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

UnitTest:Test( "BuildPotentialMapChoices - Nominations", function( Assert )
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

MapVote.Vote.Nominated = { "ns2_tram", "ns2_summit", "ns2_veil", "ns2_biodome", "ns2_eclipse" }
MapVote.Config.ExcludeLastMaps = {
	Min = 0,
	Max = 0
}

local OldForcedMaps = MapVote.Config.ForcedMaps
MapVote.Config.ForcedMaps = {}

UnitTest:Test( "BuildMapChoices - Respect nominations", function( Assert )
	-- Nominated 5 maps, with 5 max options, so all nominations should be the choices.
	Assert:ArrayEquals( MapVote.Vote.Nominated, MapVote:BuildMapChoices() )
end )

function MapVote:IsValidMapChoice( Map, PlayerCount ) return Map ~= "ns2_eclipse" end

UnitTest:Test( "BuildMapChoices - Deny nominations", function( Assert )
	-- Should use all nominations except the denied one.
	local Choices = MapVote:BuildMapChoices()
	for i = 1, 4 do
		Assert:Equals( MapVote.Vote.Nominated[ i ], Choices[ i ] )
	end
	Assert:NotEquals( "ns2_eclipse", Choices[ 5 ] )
end )

MapVote.Config.MaxOptions = OldMaxOptions
MapVote.Config.ExcludeLastMaps = OldExcludeLastMaps
MapVote.LastMapData = OldLastMaps
MapVote.Config.Maps = OldMaps
MapVote.IsValidMapChoice = OldIsValidMapChoice
MapVote.GetMapGroup = OldGetMapGroup
MapVote.Vote.Nominated = {}
MapVote.Config.ForcedMaps = OldForcedMaps
