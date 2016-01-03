--[[
	AFK kick plugin test.
]]

local UnitTest = Shine.UnitTest
local AFKKick = UnitTest:LoadExtension( "afkkick" )
if not AFKKick then return end

local OldKickClient = AFKKick.KickClient
local OldPrint = AFKKick.Print
local OldCanKickForConnectingClient = AFKKick.CanKickForConnectingClient
local OldGetClientInfo = Shine.GetClientInfo

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

AFKKick.Print = OldPrint
AFKKick.KickClient = OldKickClient
AFKKick.CanKickForConnectingClient = OldCanKickForConnectingClient
Shine.GetClientInfo = OldGetClientInfo
