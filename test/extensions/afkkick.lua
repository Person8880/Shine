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
