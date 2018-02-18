--[[
	Configurable default auto-complete text matchers.
]]

local StringFind = string.find
local StringLower = string.lower
local StringGMatch = string.gmatch
local StringStartsWith = string.StartsWith
local StringSub = string.sub
local StringUTF8Length = string.UTF8Length
local TableConcat = table.concat

return function( Options )
	-- How long does the input have to be (in UTF8 characters) to allow for containment search.
	local MIN_CONTAINMENT_INPUT_LENGTH = Options and Options.MinContainmentLength or 4
	-- Common prefixes to be replaced as part of matching.
	local COMMON_PREFIXES = Options and Options.CommonPrefixes or {
		-- Crossroads -> xroads
		{ Prefix = "cross", Replacement = "x" },
		-- Operations -> ops
		{ Prefix = "operation", Replacement = "op" },
		-- Exchange -> xchange
		{ Prefix = "ex", Replacement = "x" }
	}

	return {
		-- Checks each word in the completion to see if it starts with the input.
		-- If so, it will assign a sub-weight based on which word matched and how much of it was consumed.
		function( Context )
			local Word = Context.Input
			local WordLength = Context:GetInputLength()
			local WordsInCompletion = Context:GetSearchTextWords()

			for i = 1, #WordsInCompletion do
				local CompletionWord = WordsInCompletion[ i ]

				if StringStartsWith( CompletionWord, Word ) then
					-- How far into the completion is this word
					local WordPositionWeighting = ( 1 / i ) ^ 2
					-- How much of the word is consumed by the query
					local WordSegmentWeighting = 1 / ( StringUTF8Length( CompletionWord ) - WordLength + 1 )
					local SubWeight = WordPositionWeighting * WordSegmentWeighting
					local Offset = #TableConcat( WordsInCompletion, " ", 1, i - 1 ) + 1

					Context:AddMatch( SubWeight, Offset )
				end
			end
		end,
		-- Attempts to build acronyms from the completion, and checks the input to see if
		-- it corresponds to one.
		function( Context )
			local Word = Context.Input

			-- Build an acronym for the text, e.g. "North Tunnel" becomes "nt"
			-- Only supports ASCII uppercase.
			local Acronym = {}
			for UpperCase in StringGMatch( Context.Completion, "%u" ) do
				Acronym[ #Acronym + 1 ] = StringLower( UpperCase )
			end

			if StringLower( Word ) == TableConcat( Acronym ) then
				Context:AddMatch( 1, 1 )
			end
		end,
		-- Attempts to replace common shortened prefixes, and then checks
		-- to see if the shortened version starts with the input text.
		function( Context )
			local Word = StringLower( Context.Input )
			local SearchText = StringLower( Context.SearchText )

			for i = 1, #COMMON_PREFIXES do
				local PrefixEntry = COMMON_PREFIXES[ i ]

				if StringStartsWith( SearchText, PrefixEntry.Prefix ) then
					local ShortenedVersion = PrefixEntry.Replacement..
						StringSub( SearchText, #PrefixEntry.Prefix + 1 )

					if StringStartsWith( ShortenedVersion, Word ) then
						Context:AddMatch( 1, 1 )
					end
				end
			end
		end,
		-- Checks the completion to see if it contains the input anywhere inside it.
		-- This is a less effective match and thus is ranked lower than word matches.
		function( Context )
			-- Skip over any text that is too short to bother with a containment match.
			if Context:GetInputLength() < MIN_CONTAINMENT_INPUT_LENGTH then return end

			local Start = StringFind( Context.SearchText, Context.Input, 1, true )
			-- Consider only matches that are large enough and towards the start.
			-- Otherwise we can end up finding everything containing a single letter
			-- which is almost certainly not the intention.
			if Start and #Context.Input / Start > 0.5 then
				Context:AddMatch( 1 / Start, Start - 1 )
			end
		end
	}
end
