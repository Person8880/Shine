--[[
	A simple API to add messages to the chat.

	Depending on the provider, this may support rich-text messages, allowing an arbitrary number
	of colours (and possibly enriched functionality on the client).
]]

local DefaultProvider = require "shine/core/shared/chat/default_provider"

local ChatAPI = {}

do
	local SourceTypes = { "PLAYER", "PLUGIN", "SYSTEM" }
	ChatAPI.SourceType = table.AsEnum( SourceTypes, function( Index ) return Index end )
	ChatAPI.SourceTypeName = table.AsEnum( SourceTypes )
end

ChatAPI.CurrentProvider = DefaultProvider

function ChatAPI:SupportsRichText()
	return self.CurrentProvider:SupportsRichText()
end

function ChatAPI:AddDualColourMessage( PrefixColour, Prefix, MessageColour, Message )
	return self.CurrentProvider:AddDualColourMessage( PrefixColour, Prefix, MessageColour, Message )
end

function ChatAPI:AddMessage( MessageColour, Message )
	return self.CurrentProvider:AddMessage( MessageColour, Message )
end

--[[
	Adds a rich text message to the chat.

	Rich text messages must conform to the following structure:
	{
		Source = {
			-- Source allows filtering/extra information about the message to be known.
			-- For example, player messages may provide a right click menu to view the player's Steam/Hive profiles.
			Type = SourceType.PLAYER,
			ID = SteamID
		},
		Message = {
			-- Table of colours/text/textures.
		},
		-- Optional table that contains a single (no prefix keys specified) or dual colour message to use if rich text
		-- is not supported. This is a convenient alternative to checking ChatAPI:SupportsRichText().
		FallbackMessage = {
			PrefixColour = Colour( 1, 1, 1 ),
			Prefix = "[Some Prefix]",
			MessageColour = Colour( 1, 1, 1 ),
			Message = "Some message..."
		},
		-- Optionally, the chat sound may be suppressed.
		SuppressSound = true,
		-- On the server, an optional table of target players/clients to restrict the message to.
		-- When omitted, the message will be sent to all clients.
		Targets = {}
	}

	By default, rich text messages are converted into 2-colour messages (or the fallback is used), and the source data
	is unused.

	However, a rich text aware provider may be able to make use of the extra data.
]]
function ChatAPI:AddRichTextMessage( Message )
	return self.CurrentProvider:AddRichTextMessage( Message )
end

function ChatAPI:SetProvider( Provider )
	Shine.TypeCheck( Provider, "table", 1, "SetProvider" )

	Shine.AssertAtLevel(
		Shine.IsCallable( Provider.AddMessage ),
		"Provider must have an AddMessage method!", 3
	)
	Shine.AssertAtLevel(
		Shine.IsCallable( Provider.AddDualColourMessage ),
		"Provider must have an AddDualColourMessage method!", 3
	)
	Shine.AssertAtLevel(
		Shine.IsCallable( Provider.AddRichTextMessage ),
		"Provider must have an AddRichTextMessage method!", 3
	)
	Shine.AssertAtLevel(
		Shine.IsCallable( Provider.SupportsRichText ),
		"Provider must have a SupportsRichText method!", 3
	)

	self.CurrentProvider = Provider
end

function ChatAPI:ResetProvider( Provider )
	if self.CurrentProvider == Provider then
		self.CurrentProvider = DefaultProvider
	end
end

if Client then
	local NoScale = Vector( 1, 1, 0 )
	function ChatAPI.GetOptimalFontScale( ScreenHeight )
		ScreenHeight = ScreenHeight or Client.GetScreenHeight()

		local SGUI = Shine.GUI
		local Font
		local Scale = NoScale

		if ScreenHeight <= SGUI.ScreenHeight.Small then
			Font = Fonts.kAgencyFB_Tiny
		elseif ScreenHeight <= SGUI.ScreenHeight.Normal then
			Font = Fonts.kAgencyFB_Small
		else
			Font, Scale = SGUI.FontManager.GetFont( "kAgencyFB", 27 )
		end

		return Font, Scale
	end
else
	local tonumber = tonumber
	local type = type

	local function ToColour( Element )
		if not Element then
			return Colour( 1, 1, 1 )
		end

		return Colour(
			( tonumber( Element[ 1 ] ) or 255 ) / 255,
			( tonumber( Element[ 2 ] ) or 255 ) / 255,
			( tonumber( Element[ 3 ] ) or 255 ) / 255
		)
	end

	--[[
		Converts rich text from a configuration file into a table ready to be passed to ChatAPI:AddRichTextMessage().
	]]
	function ChatAPI.ToRichTextMessage( ConfiguredMessage, TextTransformer, Context )
		local RichTextMessage = {}
		for i = 1, #ConfiguredMessage do
			local Element = ConfiguredMessage[ i ]
			if type( Element ) == "string" then
				RichTextMessage[ i ] = TextTransformer and TextTransformer( Element, Context ) or Element
			else
				RichTextMessage[ i ] = ToColour( Element )
			end
		end
		return RichTextMessage
	end
end

return ChatAPI
