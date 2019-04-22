--[[
	Base commands plugin unit test.
]]

local UnitTest = Shine.UnitTest
local Plugin = UnitTest:LoadExtension( "basecommands" )
if not Plugin then return end

Plugin = UnitTest.MockOf( Plugin )

Plugin.Config = {
	EjectVotesNeeded = {
		{ FractionOfTeamToPass = 0.25, MaxSecondsAsCommander = 10 },
		{ FractionOfTeamToPass = 0.4, MaxSecondsAsCommander = 60 },
		{ FractionOfTeamToPass = 0.75 }
	}
}

Plugin.CommanderLogins = {}

local COMMANDER
local CLIENT = {
	GetControllingPlayer = function() return COMMANDER end,
	GetUserId = function() return 0 end
}
local function MockCommander()
	return {
		GetClient = function() return CLIENT end,
		GetName = function() return "TestCommander" end
	}
end
function Plugin:GetCommanderForTeam()
	return COMMANDER
end

local function SetCommanderTime( Time, Duration )
	if not Time then
		Plugin.CommanderLogins[ CLIENT ] = nil
		return
	end
	Plugin.CommanderLogins[ CLIENT ] = {
		LoginTime = Time,
		Duration = Duration
	}
end

local function GetLoginTime()
	local Login = Plugin.CommanderLogins[ CLIENT ]
	return Login and Login.LoginTime
end

local function GetDuration()
	local Login = Plugin.CommanderLogins[ CLIENT ]
	return Login and Login.Duration
end

local VoteManager = {
	numPlayers = 1
}

UnitTest:Test( "GetEjectVotesNeeded - Should have minimum value of 2", function( Assert )
	local VotesNeeded = Plugin:GetEjectVotesNeeded( VoteManager, 1 )
	Assert.Equals( "Should always return at least 2 for GetEjectVotesNeeded", 2, VotesNeeded )
end )

VoteManager.numPlayers = 2

UnitTest:Test( "GetEjectVotesNeeded - Should return 2 when 2 players present", function( Assert )
	local VotesNeeded = Plugin:GetEjectVotesNeeded( VoteManager, 1 )
	Assert.Equals( "Should always return 2 for GetEjectVotesNeeded with 2 players present", 2, VotesNeeded )
end )

VoteManager.numPlayers = 10

UnitTest:Test( "GetEjectVotesNeeded - No commander found returns first value", function( Assert )
	local VotesNeeded = Plugin:GetEjectVotesNeeded( VoteManager, 1 )
	Assert.Equals( "Should use the first interval when no valid commander is found", 3, VotesNeeded )
end )

COMMANDER = MockCommander()

UnitTest:Test( "GetEjectVotesNeeded - Commander with no login time returns first value", function( Assert )
	local VotesNeeded = Plugin:GetEjectVotesNeeded( VoteManager, 1 )
	Assert.Equals( "Should use the first interval when no valid commander is found", 3, VotesNeeded )
end )

UnitTest:Test( "GetEjectVotesNeeded - First value chosen when time low enough", function( Assert )
	SetCommanderTime( Shared.GetTime() )

	local VotesNeeded = Plugin:GetEjectVotesNeeded( VoteManager, 1 )
	Assert.Equals( "Should use the first interval when time is low enough", 3, VotesNeeded )
end )

UnitTest:Test( "GetEjectVotesNeeded - Second value chosen when time is larger than first but smaller than last", function( Assert )
	SetCommanderTime( Shared.GetTime() - 20 )

	local VotesNeeded = Plugin:GetEjectVotesNeeded( VoteManager, 1 )
	Assert.Equals( "Should use the second interval when time is between first and third", 4, VotesNeeded )
end )

UnitTest:Test( "GetEjectVotesNeeded - Last value chosen when time is high enough", function( Assert )
	SetCommanderTime( Shared.GetTime() - 61 )

	local VotesNeeded = Plugin:GetEjectVotesNeeded( VoteManager, 1 )
	Assert.Equals( "Should use the last interval when time is after first and second", 8, VotesNeeded )
end )

UnitTest:Test( "MarkCommanderLoginTime - Marks with given time", function( Assert )
	SetCommanderTime()

	Plugin:MarkCommanderLoginTime( COMMANDER, 0 )

	Assert.Equals( "Login time should be set to given value", 0, GetLoginTime() )
	Assert.Nil( "Duration should be unchanged when not reset", GetDuration() )
end )

UnitTest:Test( "MarkCommanderLoginTime - Marks with given time and resets", function( Assert )
	SetCommanderTime()

	Plugin:MarkCommanderLoginTime( COMMANDER, 0, true )

	Assert.Equals( "Login time should be set to given value", 0, GetLoginTime() )
	Assert.Equals( "Duration should be reset", 0, GetDuration() )
end )

UnitTest:Test( "MarkCommanderExitTime - Does not mark when no login time present", function( Assert )
	SetCommanderTime()

	Plugin:MarkCommanderExitTime( COMMANDER, 0 )

	Assert.Nil( "Duration should be unchanged when no login time is set", GetDuration() )
end )

UnitTest:Test( "MarkCommanderExitTime - Sets duration when none is present", function( Assert )
	SetCommanderTime( 0 )

	Plugin:MarkCommanderExitTime( COMMANDER, 120 )

	Assert.Equals( "Duration should be set to difference between now and login time",
		120, GetDuration() )
	Assert.Nil( "Login time should be reset", GetLoginTime() )
end )

UnitTest:Test( "MarkCommanderExitTime - Updates duration when it is present", function( Assert )
	SetCommanderTime( 0, 120 )

	Plugin:MarkCommanderExitTime( COMMANDER, 120 )

	Assert.Equals( "Duration should be added to the existing duration",
		240, GetDuration() )
	Assert.Nil( "Login time should be reset", GetLoginTime() )
end )

UnitTest:Test( "GetCommanderDuration - Returns nil when no login time stored", function( Assert )
	SetCommanderTime()

	Assert.Nil( "Total time should be nil when no login time is stored",
		Plugin:GetCommanderDuration( COMMANDER ) )
end )

UnitTest:Test( "GetCommanderDuration - Uses login time only when no duration present", function( Assert )
	SetCommanderTime( Shared.GetTime() - 30 )

	Assert.Equals( "Total time should equal time since last login",
		30, Plugin:GetCommanderDuration( COMMANDER ) )
end )

UnitTest:Test( "GetCommanderDuration - Uses duration when present", function( Assert )
	SetCommanderTime( Shared.GetTime() - 30, 30 )

	Assert.Equals( "Total time should equal duration plus time since last login",
		60, Plugin:GetCommanderDuration( COMMANDER ) )
end )
