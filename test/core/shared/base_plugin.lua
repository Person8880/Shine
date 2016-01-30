--[[
	Base plugin tests.
]]

local UnitTest = Shine.UnitTest

local function GetDummyPlugin()
	return setmetatable( {}, Shine.BasePlugin )
end

UnitTest:Test( "WrapCallback", function( Assert )
	local Plugin = GetDummyPlugin()
	local Executions = 0
	local Callback = Plugin:WrapCallback( function( Cake )
		Assert:True( Cake )
		Executions = Executions + 1
	end )

	Callback( true )
	Assert:Equals( 0, Executions )

	Plugin.Enabled = true
	Callback( true )
	Assert:Equals( 1, Executions )

	Plugin.Enabled = false
	Callback( true )
	Assert:Equals( 1, Executions )
end )
