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
