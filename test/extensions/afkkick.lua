--[[
	AFK kick plugin test.
]]

local UnitTest = Shine.UnitTest
local AFKKick = UnitTest:LoadExtension( "afkkick" )
if not AFKKick then return end

AFKKick = UnitTest.MockOf( AFKKick )

AFKKick.Config.WarnActions.NoImmunity = {
	"MoveToSpectate"
}
AFKKick.Config.WarnActions.PartialImmunity = {
	"MoveToReadyRoom"
}
UnitTest:Test( "ValidateConfig - All valid", function( Assert )
	local Saved = false
	AFKKick.SaveConfig = function()
		Saved = true
	end

	AFKKick:ValidateConfig()
	Assert:False( Saved )
	Assert:ArrayEquals( { "MoveToSpectate" }, AFKKick.Config.WarnActions.NoImmunity )
	Assert:ArrayEquals( { "MoveToReadyRoom" }, AFKKick.Config.WarnActions.PartialImmunity )
end )

AFKKick.Config.WarnActions.NoImmunity = {
	"MoveToSpectate", "MoveToReadyRoom"
}
AFKKick.Config.WarnActions.PartialImmunity = {
	"MoveToSpectate", "MoveToReadyRoom"
}

UnitTest:Test( "ValidateConfig - Both move to ready room and spectate", function( Assert )
	local Saved
	AFKKick.SaveConfig = function()
		Saved = true
	end

	AFKKick:ValidateConfig()

	Assert:True( Saved )
	Assert:ArrayEquals( { "MoveToSpectate" }, AFKKick.Config.WarnActions.NoImmunity )
	Assert:ArrayEquals( { "MoveToSpectate" }, AFKKick.Config.WarnActions.PartialImmunity )

	Saved = false
	AFKKick.Config.WarnActions.NoImmunity = {
		"MoveToReadyRoom", "MoveToSpectate"
	}
	AFKKick.Config.WarnActions.PartialImmunity = {
		"MoveToReadyRoom", "MoveToSpectate"
	}
	AFKKick:ValidateConfig()

	Assert:True( Saved )
	Assert:ArrayEquals( { "MoveToReadyRoom" }, AFKKick.Config.WarnActions.NoImmunity )
	Assert:ArrayEquals( { "MoveToReadyRoom" }, AFKKick.Config.WarnActions.PartialImmunity )
end )

AFKKick.Config.WarnActions.NoImmunity = false
AFKKick.Config.WarnActions.PartialImmunity = false

UnitTest:Test( "ValidateConfig - Missing immunity actions", function( Assert )
	local Saved
	AFKKick.SaveConfig = function()
		Saved = true
	end

	AFKKick:ValidateConfig()

	Assert:True( Saved )
	Assert:IsType( AFKKick.Config.WarnActions.NoImmunity, "table" )
	Assert:IsType( AFKKick.Config.WarnActions.PartialImmunity, "table" )
end )

AFKKick.Config.WarnMinPlayers = 10
AFKKick.Config.MinPlayers = 0

UnitTest:Test( "ValidateConfig - WarnMinPlayers <= MinPlayers", function( Assert )
	local Saved
	AFKKick.SaveConfig = function()
		Saved = true
	end

	AFKKick:ValidateConfig()

	Assert:True( Saved )
	Assert:Equals( AFKKick.Config.MinPlayers, AFKKick.Config.WarnMinPlayers )
end )

AFKKick.Print = function() end
Shine.GetClientInfo = function() return "" end
AFKKick.CanKickForConnectingClient = function() return true end

UnitTest:Test( "KickOnConnect", function( Assert )
	AFKKick.Config.KickOnConnect = true
	AFKKick.Config.KickTime = 2

	AFKKick.Users = {
		[ 1 ] = {
			AFKAmount = 2.5 * 60
		},
		[ 2 ] = {
			AFKAmount = 0.5
		},
		[ 3 ] = {
			AFKAmount = 5 * 60
		}
	}

	-- Should kick client 3
	local Kicked
	AFKKick.KickClient = function( self, Client )
		Assert:Equals( 3, Client )
		Kicked = true
	end

	Assert:Nil( AFKKick:CheckConnectionAllowed( 123456 ) )
	Assert:True( Kicked )

	-- Should now not kick anyone.
	AFKKick.Config.KickTime = 10
	Kicked = false

	Assert:Nil( AFKKick:CheckConnectionAllowed( 123456 ) )
	Assert:False( Kicked )
end, function()
	AFKKick.Config.KickOnConnect = false
end )
