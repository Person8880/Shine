--[[
	AFK kick plugin test.
]]

local UnitTest = Shine.UnitTest
local AFKKick = UnitTest:LoadExtension( "afkkick" )
if not AFKKick then return end

local StringFormat = string.format

local Validator = rawget( AFKKick, "ConfigValidator" )

AFKKick = UnitTest.MockOf( AFKKick )

AFKKick.Config.WarnActions.NoImmunity = {
	"MOVE_TO_SPECTATE"
}
AFKKick.Config.WarnActions.PartialImmunity = {
	"MOVE_TO_READY_ROOM"
}

UnitTest:Test( "ValidateConfig - All valid", function( Assert )
	local NeedsUpdate = Validator:Validate( AFKKick.Config )
	Assert:False( NeedsUpdate )
	Assert:ArrayEquals( { "MOVE_TO_SPECTATE" }, AFKKick.Config.WarnActions.NoImmunity )
	Assert:ArrayEquals( { "MOVE_TO_READY_ROOM" }, AFKKick.Config.WarnActions.PartialImmunity )
end )

AFKKick.Config.WarnActions.NoImmunity = {
	"MOVE_TO_SPECTATE", "MOVE_TO_READY_ROOM"
}
AFKKick.Config.WarnActions.PartialImmunity = {
	"MOVE_TO_SPECTATE", "MOVE_TO_READY_ROOM"
}

UnitTest:Test( "ValidateConfig - Both move to ready room and spectate", function( Assert )
	local NeedsUpdate = Validator:Validate( AFKKick.Config )
	Assert:True( NeedsUpdate )
	Assert:ArrayEquals( { "MOVE_TO_SPECTATE" }, AFKKick.Config.WarnActions.NoImmunity )
	Assert:ArrayEquals( { "MOVE_TO_SPECTATE" }, AFKKick.Config.WarnActions.PartialImmunity )

	AFKKick.Config.WarnActions.NoImmunity = {
		"MOVE_TO_READY_ROOM", "MOVE_TO_SPECTATE"
	}
	AFKKick.Config.WarnActions.PartialImmunity = {
		"MOVE_TO_READY_ROOM", "MOVE_TO_SPECTATE"
	}
	NeedsUpdate = Validator:Validate( AFKKick.Config )

	Assert:True( NeedsUpdate )
	Assert:ArrayEquals( { "MOVE_TO_READY_ROOM" }, AFKKick.Config.WarnActions.NoImmunity )
	Assert:ArrayEquals( { "MOVE_TO_READY_ROOM" }, AFKKick.Config.WarnActions.PartialImmunity )
end )

AFKKick.Config.WarnActions.NoImmunity = false
AFKKick.Config.WarnActions.PartialImmunity = false

UnitTest:Test( "ValidateConfig - Missing immunity actions", function( Assert )
	local NeedsUpdate = Validator:Validate( AFKKick.Config )

	Assert:True( NeedsUpdate )
	Assert:IsType( AFKKick.Config.WarnActions.NoImmunity, "table" )
	Assert:IsType( AFKKick.Config.WarnActions.PartialImmunity, "table" )
end )

AFKKick.Config.WarnMinPlayers = 10
AFKKick.Config.MinPlayers = 0

UnitTest:Test( "ValidateConfig - WarnMinPlayers <= MinPlayers", function( Assert )
	local NeedsUpdate = Validator:Validate( AFKKick.Config )

	Assert:True( NeedsUpdate )
	Assert:Equals( AFKKick.Config.MinPlayers, AFKKick.Config.WarnMinPlayers )
end )

local OldGetClientInfo = Shine.GetClientInfo
AFKKick.Print = function() end
Shine.GetClientInfo = function() return "" end
AFKKick.CanKickForConnectingClient = function() return true end

UnitTest:Test( "KickOnConnect", function( Assert )
	AFKKick.Config.PlayerCountRules = {}
	AFKKick.Config.KickOnConnect = true
	AFKKick.Config.KickTimeInMinutes = 2
	AFKKick:OnPlayerCountChanged()

	AFKKick.Users = Shine.Map( {
		[ 1 ] = {
			AFKAmount = 2.5 * 60
		},
		[ 2 ] = {
			AFKAmount = 0.5
		},
		[ 3 ] = {
			AFKAmount = 5 * 60
		}
	} )

	-- Should kick client 3
	local Kicked
	AFKKick.KickClient = function( self, Client )
		Assert:Equals( 3, Client )
		Kicked = true
	end

	Assert.Nil( "Should return nil from event", AFKKick:CheckConnectionAllowed( 123456 ) )
	Assert.True( "Should kick AFK player to make room", Kicked )

	-- Should now not kick anyone.
	AFKKick.Config.KickTimeInMinutes = 10
	AFKKick:OnPlayerCountChanged()
	Kicked = false

	Assert.Nil( "Should return nil from event", AFKKick:CheckConnectionAllowed( 123456 ) )
	Assert.False( "Should not kick anyone as none are AFK longer than the kick time", Kicked )
end, function()
	AFKKick.Config.KickOnConnect = false
end )

Shine.GetClientInfo = OldGetClientInfo

UnitTest:Test( "EnsurePlayerNameIsValid - Does nothing if MarkPlayersAFK = false", function( Assert )
	AFKKick.Config.MarkPlayersAFK = false

	Assert.Nil(
		"Should return nil when MarkPlayersAFK = false",
		AFKKick:EnsurePlayerNameIsValid( nil, AFKKick.AFK_PREFIX.."SomePlayer" )
	)
end )

UnitTest:Test( "EnsurePlayerNameIsValid - Does nothing if the player's name is valid", function( Assert )
	AFKKick.Config.MarkPlayersAFK = true

	Assert.Nil(
		"Should return nil when the player name is valid",
		AFKKick:EnsurePlayerNameIsValid( nil, "SomePlayer" )
	)
end )

UnitTest:Test( "EnsurePlayerNameIsValid - Removes the prefix when present in a name with non-whitespace after it", function( Assert )
	AFKKick.Config.MarkPlayersAFK = true

	Assert.Equals(
		"Should return the name without the prefix",
		"SomePlayer",
		AFKKick:EnsurePlayerNameIsValid( nil, AFKKick.AFK_PREFIX.."SomePlayer" )
	)
end )

UnitTest:Test( "EnsurePlayerNameIsValid - Renames the player to 'AFK' if their name is purely the prefix with whitespace after", function( Assert )
	AFKKick.Config.MarkPlayersAFK = true

	Assert.Equals(
		"Should return 'AFK' for the name due to only having whitespace after the prefix",
		"AFK",
		AFKKick:EnsurePlayerNameIsValid( nil, AFKKick.AFK_PREFIX.."   " )
	)
end )

UnitTest:Test( "EnsurePlayerNameIsValid - Renames the player to 'AFK' if their name is purely the prefix", function( Assert )
	AFKKick.Config.MarkPlayersAFK = true

	Assert.Equals(
		"Should return 'AFK' for the name due to being the prefix only",
		"AFK",
		AFKKick:EnsurePlayerNameIsValid( nil, AFKKick.AFK_PREFIX )
	)
end )

AFKKick.Config.WarnTimeInMinutes = 1
AFKKick.Config.MarkPlayersAFK = true
AFKKick.Config.PlayerCountRules = {
	{
		MinPlayers = 4,
		MaxPlayers = 8,
		WarnTimeInMinutes = 2,
		MarkPlayersAFK = false
	},
	{
		MinPlayers = 9,
		MaxPlayers = 15,
		WarnTimeInMinutes = 1.5
	}
}

local PlayerCount = 0
function AFKKick:GetPlayerCount()
	return PlayerCount
end

UnitTest:Test( "GetConfigValueWithRules - Returns default when no rule matches", function( Assert )
	for i = 1, 3 do
		PlayerCount = i

		Assert.Equals(
			StringFormat( "Warn time should be the default when no time rule matches (with %d player(s))", i ),
			1,
			AFKKick:GetConfigValueWithRules( "WarnTimeInMinutes" )
		)
	end

	for i = 16, 24 do
		PlayerCount = i

		Assert.Equals(
			StringFormat( "Warn time should be the default when no time rule matches (with %d player(s))", i ),
			1,
			AFKKick:GetConfigValueWithRules( "WarnTimeInMinutes" )
		)
	end
end )

UnitTest:Test( "GetConfigValueWithRules - Returns first matching rule value", function( Assert )
	for i = 4, 8 do
		PlayerCount = i

		Assert.Equals(
			StringFormat( "Warn time should be taken from the first matching rule (with %d player(s))", i ),
			2,
			AFKKick:GetConfigValueWithRules( "WarnTimeInMinutes" )
		)
	end

	for i = 9, 15 do
		PlayerCount = i

		Assert.Equals(
			StringFormat( "Warn time should be taken from the first matching rule (with %d player(s))", i ),
			1.5,
			AFKKick:GetConfigValueWithRules( "WarnTimeInMinutes" )
		)
	end
end )

UnitTest:Test( "GetConfigValueWithRules - Maintains false values from rules", function( Assert )
	for i = 4, 8 do
		PlayerCount = i

		Assert.False(
			StringFormat( "MarkPlayersAFK should be taken from the first matching rule (with %d player(s))", i ),
			AFKKick:GetConfigValueWithRules( "MarkPlayersAFK" )
		)
	end
end )

UnitTest:Test( "CanCheckInCurrentGameState - Returns true if OnlyCheckOnStarted = false", function( Assert )
	local GameStarted = false
	local Gamerules = {
		GetGameStarted = function() return GameStarted end
	}

	AFKKick.Config.OnlyCheckOnStarted = false
	Assert.True( "Should check when round has not started", AFKKick:CanCheckInCurrentGameState( Gamerules ) )

	GameStarted = true
	Assert.True( "Should check when round has started", AFKKick:CanCheckInCurrentGameState( Gamerules ) )
end )

UnitTest:Test( "CanCheckInCurrentGameState - Returns false if OnlyCheckOnStarted = true and a round has not started", function( Assert )
	local Gamerules = {
		GetGameStarted = function() return false end
	}

	AFKKick.Config.OnlyCheckOnStarted = true
	Assert.False( "Should not check when round has not started", AFKKick:CanCheckInCurrentGameState( Gamerules ) )
end )

UnitTest:Test( "CanCheckInCurrentGameState - Returns true if OnlyCheckOnStarted = true and a round has started", function( Assert )
	local Gamerules = {
		GetGameStarted = function() return true end
	}

	AFKKick.Config.OnlyCheckOnStarted = true
	Assert.True( "Should check when round has started", AFKKick:CanCheckInCurrentGameState( Gamerules ) )
end )

UnitTest:Test( "GetMinPlayersToKickOnConnect - Clamps to MaxPlayers, MaxPlayers + MaxSpectators", function( Assert )
	AFKKick.Config.MinPlayers = 10
	Assert.Equals(
		"Should clamp MinPlayers when below the minimum effective value",
		20,
		AFKKick:GetMinPlayersToKickOnConnect( 20, 6 )
	)

	for i = 21, 26 do
		AFKKick.Config.MinPlayers = i
		Assert.Equals(
			"Should use MinPlayers when within the valid range",
			i,
			AFKKick:GetMinPlayersToKickOnConnect( 20, 6 )
		)
	end

	AFKKick.Config.MinPlayers = 27
	Assert.Equals(
		"Should clamp MinPlayers when above the maximum effective value",
		26,
		AFKKick:GetMinPlayersToKickOnConnect( 20, 6 )
	)
end )
