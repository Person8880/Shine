--[[
	Auto completion tests.
]]

local UnitTest = Shine.UnitTest
local StandardAutoComplete = require "shine/lib/gui/objects/textentry/auto_complete"

local function NewCompletionHandler()
	return StandardAutoComplete( function()
		return {
			{ "Turbine", "Heat Transfer", "Administration", "Nope" },
			{ "Too", "Tooo", "Something", "No" }
		}
	end )
end

UnitTest:Test( "By word completion", function( Assert )
	local CompletionHandler = NewCompletionHandler()

	-- Should pick the entry whose word starts with t first.
	local InitialState = { Text = "t", CaretPos = 1 }
	local NewState = CompletionHandler:PerformCompletion( InitialState )
	Assert:Equals( "Turbine", NewState.Text )
	Assert:Equals( #( "Turbine" ), NewState.CaretPos )

	NewState = CompletionHandler:PerformCompletion( InitialState )
	Assert:Equals( "Heat Transfer", NewState.Text )
	Assert:Equals( #( "Heat Transfer" ), NewState.CaretPos )

	-- Skip "Adminstration" as the match is too weak.

	-- Then move on to the next list of completions, and match those in order.
	-- Start with the shortest word that matches the start.
	NewState = CompletionHandler:PerformCompletion( InitialState )
	Assert:Equals( "Too", NewState.Text )
	Assert:Equals( #( "Too" ), NewState.CaretPos )

	-- Then a slightly longer word.
	NewState = CompletionHandler:PerformCompletion( InitialState )
	Assert:Equals( "Tooo", NewState.Text )
	Assert:Equals( #( "Tooo" ), NewState.CaretPos )

	-- Skip "Something" as the match is too weak.

	-- Then finally come back to 't'
	NewState = CompletionHandler:PerformCompletion( InitialState )
	Assert:Equals( "t", NewState.Text )
	Assert:Equals( #( "t" ), NewState.CaretPos )

	local RebuiltCompletions = false
	CompletionHandler.BuildCompletions = function( self )
		RebuiltCompletions = true
		return self.Completions
	end

	NewState = CompletionHandler:PerformCompletion( InitialState )
	Assert:Equals( "Turbine", NewState.Text )
	Assert:Equals( #( "Turbine" ), NewState.CaretPos )

	Assert.True( "Should have rebuilt completions on returning to index 1", RebuiltCompletions )
end )

UnitTest:Test( "Contains completion", function( Assert )
	local CompletionHandler = NewCompletionHandler()

	local InitialState = { Text = "rans", CaretPos = 4 }

	-- "Heat Transfer" is a strong enough containment match to be suggested.
	local NewState = CompletionHandler:PerformCompletion( InitialState )
	Assert:Equals( "Heat Transfer", NewState.Text )
	Assert:Equals( #( "Heat Transfer" ), NewState.CaretPos )

	-- No other values will match, so cycle back to the original input.
	NewState = CompletionHandler:PerformCompletion( InitialState )
	Assert:Equals( "rans", NewState.Text )
	Assert:Equals( #( "rans" ), NewState.CaretPos )
end )

UnitTest:Test( "Completion order", function( Assert )
	local CompletionHandler = NewCompletionHandler()

	local Completions = CompletionHandler:BuildCompletions( { Text = "t", CaretPos = 1 } )
	local Expected = { "Turbine", "Heat Transfer", "Too", "Tooo", "t" }
	Assert.Equals( "Number of completions doesn't match expected", #Expected, #Completions )
	for i = 1, #Expected do
		Assert.Equals( ( "Completion %d doesn't match expected" ):format( i ),
			Expected[ i ], Completions[ i ].Match )
	end
end )

UnitTest:Test( "Replace word with no prefix", function( Assert )
	local CompletionHandler = NewCompletionHandler()

	local Text = "Things at tur"
	local NewState = CompletionHandler:ReplaceWord( { Text = Text, CaretPos = #Text }, {
		Match = "Turbine",
		Offset = 1
	}, "tur" )
	Assert.Equals( "New text hasn't replaced word", "Things at Turbine", NewState.Text )
	Assert.Equals( "New caret pos isn't at end of text", #NewState.Text, NewState.CaretPos )
end )

UnitTest:Test( "Replace word with prefix", function( Assert )
	local CompletionHandler = NewCompletionHandler()

	local Text = "Things at heat tra"
	local NewState = CompletionHandler:ReplaceWord( { Text = Text, CaretPos = #Text }, {
		Match = "Heat Transfer",
		Offset = #( "Heat " )
	}, "tra" )
	Assert.Equals( "New text hasn't replaced word and prefix", "Things at Heat Transfer", NewState.Text )
	Assert.Equals( "New caret pos isn't at end of text", #NewState.Text, NewState.CaretPos )
end )

UnitTest:Test( "Get word with no punctuation", function( Assert )
	local CompletionHandler = NewCompletionHandler()

	local Word = CompletionHandler:GetWord( { Text = "tur", CaretPos = 3 } )
	Assert:Equals( "tur", Word )
end )

UnitTest:Test( "Get word with space behind", function( Assert )
	local CompletionHandler = NewCompletionHandler()

	local Text = "Hello in tur"
	local Word = CompletionHandler:GetWord( { Text = Text, CaretPos = #Text } )
	Assert:Equals( "tur", Word )
end )

UnitTest:Test( "Get word with punctuation behind", function( Assert )
	local CompletionHandler = NewCompletionHandler()

	local Text = "@tur"
	local Word = CompletionHandler:GetWord( { Text = Text, CaretPos = #Text } )
	Assert:Equals( "tur", Word )
end )

UnitTest:Test( "Get word with UTF8", function( Assert )
	local CompletionHandler = NewCompletionHandler()

	local Text = "éééé ááíó"
	local Word = CompletionHandler:GetWord( { Text = Text, CaretPos = Text:UTF8Length() } )
	Assert:Equals( "ááíó", Word )
end )
