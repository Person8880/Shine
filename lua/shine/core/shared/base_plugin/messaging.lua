--[[
	Messaging module.
]]

if Predict then return end

local ChatAPI = require "shine/core/shared/chat/chat_api"

local Shine = Shine

local rawget = rawget
local StringFormat = string.format

local MessageModule = {}

local function GetName( self )
	return rawget( self, "PrintName" ) or self.__Name
end

if Client then
	local RichTextFormat = require "shine/lib/gui/richtext/format"

	local ColourElement = require "shine/lib/gui/richtext/elements/colour"
	local TextElement = require "shine/lib/gui/richtext/elements/text"

	local OSDate = os.date
	local TableInsert = table.insert

	function MessageModule:GetPhrase( Key )
		local Phrase = Shine.Locale:GetPhrase( self.__Name, Key )

		if self.__Inherit and Phrase == Key then
			return self.__Inherit:GetPhrase( Key )
		end

		if Phrase == Key then
			return Shine.Locale:GetPhrase( "Core", Key )
		end

		return Phrase
	end

	function MessageModule:GetInterpolatedPhrase( Key, FormatArgs )
		local Phrase = Shine.Locale:GetInterpolatedPhrase( self.__Name, Key, FormatArgs )

		if self.__Inherit and Phrase == Key then
			return self.__Inherit:GetInterpolatedPhrase( Key, FormatArgs )
		end

		if Phrase == Key then
			return Shine.Locale:GetInterpolatedPhrase( "Core", Key, FormatArgs )
		end

		return Phrase
	end

	function MessageModule:GetInterpolatedRichText( Key, Options )
		local Phrase = self:GetPhrase( Key )
		return RichTextFormat.FromInterpolationString( Phrase, Options )
	end

	function MessageModule:NotifyTranslatedRichTextWithFallback( Options )
		if ChatAPI:SupportsRichText() or not Options.MakeFallbackMessage then
			self:NotifyRichText( self:GetInterpolatedRichText( Options.Key, Options ) )
		else
			Options.MakeFallbackMessage( self, Options )
		end
	end

	function MessageModule:NotifyRichText( RichText )
		ChatAPI:AddRichTextMessage( {
			Source = {
				Type = ChatAPI.SourceTypeName.PLUGIN,
				ID = self:GetName()
			},
			Message = RichText
		} )
	end

	function MessageModule:AddChatLine( RP, GP, BP, Prefix, R, G, B, Message )
		Shine.AddChatText( RP, GP, BP, Prefix, R / 255, G / 255, B / 255, Message )
	end

	function MessageModule:CommandNotify( AdminName, MessageKey, Data )
		local Message = self:GetInterpolatedPhrase( MessageKey, Data )
		if Shine.AdminMenu:GetIsVisible() then
			Message = StringFormat( "%s %s", AdminName, Message )
			Shared.Message( Message )
			Shine.GUI.NotificationManager.AddNotification( Shine.NotificationType.INFO, Message, 5 )
		else
			local Options = self.RichTextMessageOptions and self.RichTextMessageOptions[ MessageKey ]
			if ChatAPI:SupportsRichText() and Options then
				local RichTextMessage = self:GetInterpolatedRichText( MessageKey, {
					Key = MessageKey,
					Values = Data,
					Colours = Options.Colours,
					DefaultColour = Options.DefaultColour,
					LangDef = Shine.Locale:GetLanguageDefinition()
				} )

				TableInsert( RichTextMessage, 1, TextElement( AdminName.." " ) )
				TableInsert( RichTextMessage, 1, ColourElement( Colour( 1, 1, 0 ) ) )

				self:NotifyRichText( RichTextMessage )
			else
				self:AddChatLine( 255, 255, 0, AdminName,
					255, 255, 255, self:GetInterpolatedPhrase( MessageKey, Data ) )
			end
		end
	end

	function MessageModule:NotifyTranslated( Key, Data )
		local Options = self.RichTextMessageOptions and self.RichTextMessageOptions[ Key ]
		if ChatAPI:SupportsRichText() and Options then
			local RichTextMessage = self:GetInterpolatedRichText( Key, {
				Key = Key,
				Values = Data,
				Colours = Options.Colours,
				DefaultColour = Options.DefaultColour,
				LangDef = Shine.Locale:GetLanguageDefinition()
			} )

			local PrefixCol = self.NotifyPrefixColour

			TableInsert( RichTextMessage, 1, TextElement( self:GetPhrase( "NOTIFY_PREFIX" ).." " ) )
			TableInsert( RichTextMessage, 1, ColourElement(
				Colour( PrefixCol[ 1 ] / 255, PrefixCol[ 2 ] / 255, PrefixCol[ 3 ] / 255 )
			) )

			self:NotifyRichText( RichTextMessage )
		else
			self:Notify( self:GetInterpolatedPhrase( Key, Data ) )
		end
	end

	function MessageModule:Notify( Message )
		local PrefixCol = self.NotifyPrefixColour

		self:AddChatLine( PrefixCol[ 1 ], PrefixCol[ 2 ], PrefixCol[ 3 ], self:GetPhrase( "NOTIFY_PREFIX" ),
			255, 255, 255, Message )
	end

	function MessageModule:NotifySingleColour( R, G, B, Message )
		self:AddChatLine( 0, 0, 0, "", R, G, B, Message )
	end

	function MessageModule:NotifyError( Message )
		Shine:NotifyError( Message )
	end

	function MessageModule:Print( Message, Format, ... )
		local Timestamp = OSDate( "[%H:%M:%S]" )
		Print( "%s[%s] %s", Timestamp, GetName( self ), Format and StringFormat( Message, ... ) or Message )
	end

	do
		local StringExplode = string.Explode
		local StringFind = string.find
		local TimeToString = string.TimeToString
		local Transformers = string.InterpolateTransformers

		-- Transforms a boolean into one of two strings.
		Transformers.BoolToPhrase = function( FormatArg, TransformArg )
			local Args = StringExplode( TransformArg, "|", true )
			return FormatArg and Args[ 1 ] or Args[ 2 ]
		end

		-- Transforms a time value into a string duration. Optionally, a translation key for 0 can be given.
		Transformers.Duration = function( FormatArg, TransformArg )
			if FormatArg == 0 and TransformArg and TransformArg ~= "" then
				return Shine.Locale:GetPhrase( "Core", TransformArg )
			end

			return TimeToString( FormatArg )
		end

		-- Adds the argument only if the value is non-zero.
		Transformers.NonZero = function( FormatArg, TransformArg )
			return FormatArg == 0 and "" or TransformArg
		end

		-- Adds one of two values depending on if the value is negative or not.
		Transformers.Sign = function( FormatArg, TransformArg )
			local Args = StringExplode( TransformArg, "|", true )
			return FormatArg < 0 and Args[ 1 ] or Args[ 2 ]
		end

		-- Gets a translation value from a given source.
		Transformers.Translation = function( FormatArg, TransformArg )
			local Source = TransformArg or "Core"
			return Shine.Locale:GetPhrase( Source, FormatArg )
		end
	end
else
	function MessageModule:Print( Message, Format, ... )
		Shine:Print( "[%s] %s", true, GetName( self ),
			Format and StringFormat( Message, ... ) or Message )
	end

	function MessageModule:Notify( Player, Message, Format, ... )
		Shine.TypeCheck( Message, "string", 2, "Notify" )

		local NotifyColour = self.NotifyPrefixColour

		Shine:NotifyDualColour( Player, NotifyColour[ 1 ], NotifyColour[ 2 ], NotifyColour[ 3 ],
			StringFormat( "[%s]", GetName( self ) ), 255, 255, 255, Message, Format, ... )
	end

	function MessageModule:NotifyTranslated( Player, Message )
		local NotifyColour = self.NotifyPrefixColour

		Shine:TranslatedNotifyDualColour( Player, NotifyColour[ 1 ], NotifyColour[ 2 ], NotifyColour[ 3 ],
			"NOTIFY_PREFIX", 255, 255, 255, Message, self.__Name )
	end

	function MessageModule:NotifyTranslatedError( Player, Message )
		Shine:TranslatedNotifyError( Player, Message, self.__Name )
	end

	function MessageModule:NotifyTranslatedCommandError( Player, Message )
		Shine:TranslatedNotifyCommandError( Player, Message, self.__Name )
	end

	function MessageModule:NotifyRichText( Player, RichText )
		ChatAPI:AddRichTextMessage( {
			Source = {
				Type = ChatAPI.SourceTypeName.PLUGIN,
				ID = self:GetName()
			},
			Message = RichText,
			Targets = Player
		} )
	end
end

Shine.BasePlugin:AddModule( MessageModule )
