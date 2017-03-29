--[[
	Logger object.

	Allows setting various levels of logging, and only writing messages at or below the set level.
]]

local select = select
local StringFormat = string.format

local Logger = Shine.TypeDef()

Logger.LogLevel = table.AsEnum( {
	"ERROR",
	"WARN",
	"INFO",
	"DEBUG",
	"TRACE"
}, function( Index ) return Index end )

function Logger:Init( Level, Writer )
	Shine.TypeCheck( Level, { "number", "string" }, 1, "Logger" )
	Shine.TypeCheck( Writer, "function", 2, "Logger" )

	self.Writer = Writer

	return self:SetLevel( Level )
end

function Logger:SetLevel( Level )
	if Shine.IsType( Level, "string" ) then
		Level = Logger.LogLevel[ Level ]
	end

	Shine.Assert( Logger.LogLevel[ Level ], "Unrecognised log level" )

	self.Level = Level

	return self
end

for i = 1, #Logger.LogLevel do
	local LevelName = Logger.LogLevel[ i ]
	local NiceLevelName = LevelName:sub( 1, 1 )..LevelName:sub( 2 ):lower()

	local function IsLevelEnabled( self )
		return self.Level >= i
	end

	Logger[ NiceLevelName ] = function( self, Message, ... )
		if not IsLevelEnabled( self ) then return end

		local Text = select( "#", ... ) > 0 and StringFormat( Message, ... ) or Message
		self.Writer( StringFormat( "[%s] %s", NiceLevelName, Text ) )
	end

	Logger[ "Is"..NiceLevelName.."Enabled" ] = IsLevelEnabled

	Logger[ "If"..NiceLevelName.."Enabled" ] = function( self, Action, ... )
		if not IsLevelEnabled( self ) then return end

		return Action( self, ... )
	end
end

Shine.Objects.Logger = Logger
