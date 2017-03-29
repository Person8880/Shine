--[[
	Logger object tests.
]]

local UnitTest = Shine.UnitTest

local Logger = Shine.Objects.Logger
local LogLevel = Logger.LogLevel

UnitTest:Test( "Construct with string level", function( Assert )
	local Instance = Logger( "DEBUG", LuaPrint )
	Assert:Equals( LogLevel.DEBUG, Instance.Level )
	Assert:Equals( LuaPrint, Instance.Writer )
end )

UnitTest:Test( "Construct with number level", function( Assert )
	local Instance = Logger( LogLevel.DEBUG, LuaPrint )
	Assert:Equals( LogLevel.DEBUG, Instance.Level )
	Assert:Equals( LuaPrint, Instance.Writer )
end )

UnitTest:Test( "Message is logged when level is higher", function( Assert )
	local Text = {}
	local function Writer( Message )
		Text[ #Text + 1 ] = Message
	end

	local Instance = Logger( LogLevel.INFO, Writer )
	Instance:Error( "Error" )
	Instance:Warn( "Warn" )
	Instance:Info( "Info" )
	Instance:Debug( "Debug" )
	Instance:Trace( "Trace" )

	Assert:ArrayEquals( { "[Error] Error", "[Warn] Warn", "[Info] Info" }, Text )
end )

UnitTest:Test( "Is<X>Enabled", function( Assert )
	local Instance = Logger( LogLevel.INFO, LuaPrint )
	Assert:True( Instance:IsErrorEnabled() )
	Assert:True( Instance:IsWarnEnabled() )
	Assert:True( Instance:IsInfoEnabled() )
	Assert:False( Instance:IsDebugEnabled() )
	Assert:False( Instance:IsTraceEnabled() )
end )

UnitTest:Test( "If<X>Enabled", function( Assert )
	local Instance = Logger( LogLevel.INFO, LuaPrint )

	local Called = false
	Instance:IfDebugEnabled( function()
		Called = true
	end )
	Assert:False( Called )

	Instance:IfInfoEnabled( function( self )
		Assert:Equals( Instance, self )
		Called = true
	end )
	Assert:True( Called )
end )
