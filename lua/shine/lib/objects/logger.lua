--[[
	Logger object.

	Allows setting various levels of logging, and only writing messages at or below the set level.
]]

local CodeGen = require "shine/lib/codegen"

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

local function IsEnabled() return true end
local function IsDisabled() return false end

local function ExecuteAction( self, Action, ... )
	return Action( self, ... )
end

local function DoNothing() end

local LogMethodNames = {}
local IsEnabledMethodNames = {}
local IfEnabledMethodNames = {}

local NumLogLevels = #Logger.LogLevel
for i = 1, NumLogLevels do
	local LevelName = Logger.LogLevel[ i ]
	local NiceLevelName = LevelName:sub( 1, 1 )..LevelName:sub( 2 ):lower()

	LogMethodNames[ i ] = NiceLevelName
	IsEnabledMethodNames[ i ] = StringFormat( "Is%sEnabled", NiceLevelName )
	IfEnabledMethodNames[ i ] = StringFormat( "If%sEnabled", NiceLevelName )

	-- Generate var-arg functions for this level, this helps avoid trace aborts where logging is involved.
	local Callers = CodeGen.MakeFunctionGenerator( {
		Template = [[local NiceLevelName, StringFormat = ...
		return function( self, Message{Arguments} )
			return self.Writer( StringFormat( "[%s] %s", NiceLevelName, StringFormat( Message{Arguments} ) ) )
		end]],
		ChunkName = function( NumArguments )
			return StringFormat(
				"@lua/shine/lib/objects/logger.lua/%sWith%sArg%s",
				NiceLevelName,
				NumArguments,
				NumArguments == 1 and "" or "s"
			)
		end,
		InitialSize = 16,
		Args = { NiceLevelName, StringFormat }
	} )
	-- This is a special case, no string.format call is required on the message here.
	Callers[ 0 ] = function( self, Message )
		return self.Writer( StringFormat( "[%s] %s", NiceLevelName, Message ) )
	end

	Logger[ NiceLevelName ] = function( self, Message, ... )
		return Callers[ select( "#", ... ) ]( self, Message, ... )
	end
end

function Logger:SetLevel( Level )
	local ProvidedLevel = Level
	if Shine.IsType( Level, "string" ) then
		Level = Logger.LogLevel[ Level ]
	end

	Shine.AssertAtLevel( Logger.LogLevel[ Level ], "Unrecognised log level: %s", 3, ProvidedLevel )

	self.Level = Level

	-- For every level enabled, set the methods to log and execute actions.
	for i = 1, Level do
		self[ IsEnabledMethodNames[ i ] ] = IsEnabled
		self[ IfEnabledMethodNames[ i ] ] = ExecuteAction
		self[ LogMethodNames[ i ] ] = Logger[ LogMethodNames[ i ] ]
	end

	-- For all levels above the enabled level, set the methods to do nothing.
	for i = Level + 1, NumLogLevels do
		self[ IsEnabledMethodNames[ i ] ] = IsDisabled
		self[ IfEnabledMethodNames[ i ] ] = DoNothing
		self[ LogMethodNames[ i ] ] = DoNothing
	end

	return self
end

Shine.Objects.Logger = Logger
