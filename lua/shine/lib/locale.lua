--[[
	Localised string handling (not using the game's system, so we don't interfere).
]]

local NS2Locale = Locale
local Shine = Shine

Shine.Locale = {}
local Locale = Shine.Locale

local StringFormat = string.format
local StringInterpolate = string.Interpolate

Locale.Strings = {}
Locale.Sources = {}

Locale.DefaultLanguage = "enGB"

-- Get all available locale files now, so we don't keep trying to open them later.
local LangFiles = {}
Shared.GetMatchingFileNames( "locale/*.json", true, LangFiles )

local LangLookup = {}
for i = 1, #LangFiles do
	LangLookup[ LangFiles[ i ] ] = true
end

function Locale:RegisterSource( Source, FilePath )
	self.Sources[ Source ] = FilePath
	self.Strings[ Source ] = {}
end

do
	local loadstring = loadstring
	local DefaultDef = {
		GetPluralForm = function( Value )
			return Value == 1 and 1 or 2
		end
	}

	local pcall = pcall
	local setfenv = setfenv
	local StringGSub = string.gsub

	local PermittedKeywords = {
		[ "and" ] = true,
		[ "or" ] = true,
		[ "not" ] = true,
		[ "n" ] = true
	}

	local function SanitiseCode( Source )
		return StringGSub( StringGSub( Source, "[\"'%[%]%.:]", "" ), "%a+", function( Keyword )
			if not PermittedKeywords[ Keyword ] then return "" end
		end )
	end

	local ExpectedDefKeys = {
		GetPluralForm = function( Lang, Source )
			if not Source then return DefaultDef.GetPluralForm end

			local Code = StringFormat( "return ( function( n ) return ( %s ) end )( ... )",
				SanitiseCode( Source ) )

			local PluralFormFunc, Err = loadstring( Code )
			local function Reject( Error )
				Print( "[Shine Locale] Error in plural form for %s: %s", Lang, Error )
				PluralFormFunc = DefaultDef.GetPluralForm
			end

			if PluralFormFunc then
				setfenv( PluralFormFunc, {} )
				local Valid, Err = pcall( PluralFormFunc, 1 )
				if not Valid then
					Reject( Err )
				end
			else
				Reject( Err )
			end

			return PluralFormFunc
		end
	}

	Locale.LanguageDefinitions = {}

	function Locale:GetLanguageDefinition( Lang )
		Lang = Lang or self:GetCurrentLanguage()

		if self.LanguageDefinitions[ Lang ] then
			return self.LanguageDefinitions[ Lang ]
		end

		local Path = self:ResolveFilePath( "locale/shine", StringFormat( "def-%s", Lang ) )
		local Def = DefaultDef

		if LangLookup[ Path ] then
			local LangDefs = Shine.LoadJSONFile( Path )
			if LangDefs then
				Def = {}

				for ExpectedKey, Loader in pairs( ExpectedDefKeys ) do
					Def[ ExpectedKey ] = Loader( Lang, LangDefs[ ExpectedKey ] )
				end
			else
				Def = DefaultDef
			end
		end

		self.LanguageDefinitions[ Lang ] = Def

		return Def
	end
end

function Locale:ResolveFilePath( Folder, Lang )
	return StringFormat( "%s/%s.json", Folder, Lang )
end

function Locale:LoadStrings( Source, Lang )
	local Folder = self.Sources[ Source ]
	if not Folder then return nil end

	local Path = self:ResolveFilePath( Folder, Lang )
	if not LangLookup[ Path ] then
		return nil
	end

	local LanguageStrings = Shine.LoadJSONFile( Path )
	if LanguageStrings then
		self.Strings[ Source ][ Lang ] = LanguageStrings
	end

	return LanguageStrings
end

function Locale:GetLanguageStrings( Source, Lang )
	local LoadedStrings = self.Strings[ Source ]
	if not LoadedStrings then return nil end

	local LanguageStrings = LoadedStrings[ Lang ]
	if not LanguageStrings then
		LanguageStrings = self:LoadStrings( Source, Lang )
	end

	return LanguageStrings
end

function Locale:GetLocalisedString( Source, Lang, Key )
	local LanguageStrings = self:GetLanguageStrings( Source, Lang )
	if not LanguageStrings or not LanguageStrings[ Key ] then
		LanguageStrings = self:GetLanguageStrings( Source, self.DefaultLanguage )
	end

	return LanguageStrings and LanguageStrings[ Key ] or Key
end

function Locale:GetCurrentLanguage()
	return Client.GetOptionString( "locale", self.DefaultLanguage )
end

function Locale:GetPhrase( Source, Key )
	return self:GetLocalisedString( Source, self:GetCurrentLanguage(), Key )
end

function Locale:GetInterpolatedPhrase( Source, Key, FormatArgs )
	return StringInterpolate( self:GetPhrase( Source, Key ), FormatArgs, self:GetLanguageDefinition() )
end
