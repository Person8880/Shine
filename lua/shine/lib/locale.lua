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

function Locale:GetPhrase( Source, Key )
	return self:GetLocalisedString( Source, NS2Locale.GetLocale(), Key )
end

function Locale:GetInterpolatedPhrase( Source, Key, FormatArgs )
	return StringInterpolate( self:GetPhrase( Source, Key ), FormatArgs )
end
