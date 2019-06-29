--[[
	Auto-completion for text entries.
]]

local Max = math.max
local StringExplode = string.Explode
local StringFind = string.find
local StringReverse = string.reverse
local StringSub = string.sub
local StringUTF8Length = string.UTF8Length
local StringUTF8Lower = string.UTF8Lower
local StringUTF8Sub = string.UTF8Sub
local TableInsert = table.insert
local TableQuickCopy = table.QuickCopy

local CompletionContext = Shine.TypeDef()
function CompletionContext:Init( Matches, Input, State )
	self.Matches = Matches
	self.Input = Input
	self.State = State
	return self
end

function CompletionContext:Setup( Completion, SearchText )
	self.Completion = Completion
	self.SearchText = SearchText

	self.SearchTextWords = nil
end

function CompletionContext:AddMatch( SubWeight, Offset, Match, Weight )
	local Matches = self.Matches
	Match = Match or ( self.Completion.." " )

	if Matches.Seen[ Match ] then return end

	Matches.Seen[ Match ] = true
	Matches[ #Matches + 1 ] = {
		-- Assigned matcher weight
		Weight = Weight or self.Weight,
		-- Sub-weight to differentiate matches inside the matcher
		SubWeight = SubWeight,
		-- The suggestion that matched
		Match = Match,
		-- Byte offset from the start of the match that corresponds with the input
		Offset = Offset
	}
end

function CompletionContext:GetInputLength()
	if not self.InputLength then
		self.InputLength = StringUTF8Length( self.Input )
	end
	return self.InputLength
end

function CompletionContext:GetSearchTextWords()
	if not self.SearchTextWords then
		self.SearchTextWords = StringExplode( self.SearchText, " ", true )
	end
	return self.SearchTextWords
end

local DefaultMatchers = require "shine/lib/gui/objects/textentry/default_matchers" ()

local StandardAutoComplete = Shine.TypeDef()
StandardAutoComplete.DefaultMatchers = DefaultMatchers

--[[
	Constructs a new auto-complete handler with the given supplier and (optionally) matchers.
]]
function StandardAutoComplete:Init( CompletionSupplier, Matchers )
	self.CompletionSupplier = CompletionSupplier
	self.Index = 0
	self.Matchers = Matchers or TableQuickCopy( DefaultMatchers )
	return self
end

function StandardAutoComplete:AddMatcherToEnd( Matcher )
	Shine.AssertAtLevel( Shine.IsCallable( Matcher ), "Matcher must be a function or callable object!", 3 )
	self.Matchers[ #self.Matchers + 1 ] = Matcher
	return self
end

function StandardAutoComplete:AddMatcherToStart( Matcher )
	Shine.AssertAtLevel( Shine.IsCallable( Matcher ), "Matcher must be a function or callable object!", 3 )
	TableInsert( self.Matchers, 1, Matcher )
	return self
end

function StandardAutoComplete:IsAutoCompleting()
	return self.Completions ~= nil
end

function StandardAutoComplete:Reset()
	self.Index = 0
	self.Completions = nil
end

function StandardAutoComplete:PerformCompletion( State, ReverseDirection )
	local Built = false
	if not self.Completions then
		Built = true

		self.Completions = self:BuildCompletions( State )
		if not self.Completions then
			return nil
		end
	end

	-- Advance to next/previous completion depending on direction.
	local Index = self.Index
	if ReverseDirection then
		Index = Index - 1
		if Index <= 0 then
			Index = Max( #self.Completions + Index, 1 )
		end
	else
		Index = ( Index % #self.Completions ) + 1
	end

	if not Built and Index == 1 then
		-- On cycling back to the start, rebuild the matches.
		-- This allows a refresh in case suggestions will change with time.
		self.Completions = self:BuildCompletions( State )
		if not self.Completions then
			return nil
		end
	end

	self.Index = Index

	-- Extract the next completion and advance.
	local Completion = self.Completions[ Index ]

	-- Return the text with the current word replaced with the completion.
	return self:ReplaceWord( State, Completion, self.Completions.Word )
end

function StandardAutoComplete:BuildCompletions( State )
	local Candidates = self.CompletionSupplier()
	local Completions = self:FindMatches( Candidates, State )

	if not Completions or #Completions == 0 then
		return nil
	end

	return Completions
end

function StandardAutoComplete:ReplaceWord( State, Completion, Word )
	local TextBefore = StringUTF8Sub( State.Text, 1, State.CaretPos )
	TextBefore = StringSub( TextBefore, 1, #TextBefore - #Word )

	-- If the text before the last word matches exactly the text before the point we
	-- found a match for the completion, treat it as part of the text being inserted.
	-- For example, if there's a location named "The X" and they type "The x" and trigger
	-- auto-complete, it should only replace "x".
	local Prefix = StringSub( TextBefore, #TextBefore - Completion.Offset + 1 )
	if StringUTF8Lower( Prefix ) == StringUTF8Lower( StringSub( Completion.Match, 1, Completion.Offset ) ) then
		TextBefore = StringSub( TextBefore, 1, #TextBefore - Completion.Offset )
	end

	local NewTextBefore = TextBefore..Completion.Match

	return {
		Text = NewTextBefore..StringUTF8Sub( State.Text, State.CaretPos + 1 ),
		CaretPos = StringUTF8Length( NewTextBefore )
	}
end

-- Rank matches based on their listing/matcher weight, then how close of a match they are
-- within that matcher/listing.
local CompareMatches = Shine.Comparator(
	"Composition",
	-- Weight descending, SubWeight descending.
	Shine.Comparator( "Field", -1, "SubWeight" ),
	Shine.Comparator( "Field", -1, "Weight" )
):CompileStable()

function StandardAutoComplete:FindMatches( Candidates, State )
	local Word = self:GetWord( State )
	if #Word == 0 then return nil end

	-- Assume a query with non-lower case letters is case-sensitive.
	local IsCaseSensitive = StringUTF8Lower( Word ) ~= Word

	-- Assign a higher weighting to elements in lower index lists.
	local NUM_PASSES = #self.Matchers
	local Weight = #Candidates * NUM_PASSES
	local Matches = {
		Word = Word,
		Seen = {}
	}

	local Context = CompletionContext( Matches, Word, State )

	for i = 1, #Candidates do
		local Completions = Candidates[ i ]
		self:FindFromList( Completions, Context, Weight, IsCaseSensitive )
		-- Drop the weight for the next list of completions.
		Weight = Weight - NUM_PASSES
	end

	-- Add the identity match last so they can always tab back to what they wrote.
	Context:AddMatch( 0, 1, Word, 0 )

	-- Stable-sort the matches to avoid them jumping around.
	return Shine.Stream( Matches ):StableSort( CompareMatches ):AsTable()
end

function StandardAutoComplete:GetWord( State )
	-- Find the text before the caret's position.
	local TextBeforeCaret = StringUTF8Sub( State.Text, 1, State.CaretPos )
	local Length = #TextBeforeCaret

	-- Find the first space/@ character behind the caret (byte offset).
	local LastSpaceOffset = StringFind( StringReverse( TextBeforeCaret ), "[%s@]" )
	if LastSpaceOffset == 1 then return "" end

	-- Cut to the start if no space/@ is behind the caret.
	LastSpaceOffset = LastSpaceOffset or ( Length + 1 )

	return StringSub( State.Text, Length - LastSpaceOffset + 2, Length )
end

function StandardAutoComplete:FindFromList( Completions, Context, Weight, IsCaseSensitive )
	for i = 1, #Completions do
		local Completion = Completions[ i ]
		local SearchText = Completion

		-- Search input will be all lower case if not performing a case-sensitive match.
		if not IsCaseSensitive then
			SearchText = StringUTF8Lower( Completion )
		end

		Context:Setup( Completion, SearchText )

		-- Apply matchers in order, decreasing the weight assigned as each
		-- matcher is attempted.
		local MatcherWeight = Weight
		for j = 1, #self.Matchers do
			Context.Weight = MatcherWeight

			self.Matchers[ j ]( Context )

			MatcherWeight = MatcherWeight - 1
		end
	end
end

return StandardAutoComplete
