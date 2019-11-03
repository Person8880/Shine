--[[
	Provides functions to format rich text messages.
]]

local ColourElement = require "shine/lib/gui/richtext/elements/colour"
local TextElement = require "shine/lib/gui/richtext/elements/text"

local ApplyInterpolationTransformer = string.ApplyInterpolationTransformer
local IsCallable = Shine.IsCallable
local IsType = Shine.IsType
local StringFind = string.find
local StringSub = string.sub

local DEFAULT_COLOUR = Colour( 1, 1, 1 )

local Format = {}

do
	local NeutralColour = Colour( 0.6, 0.6, 0.6 )
	Format.Colours = {
		Teams = {
			[ 0 ] = NeutralColour,
			ColorIntToColor( kMarineTeamColor or 0x4DB1FF ),
			ColorIntToColor( kAlienTeamColor or 0xFFCA3A ),
			NeutralColour
		},
		LightBlue = Colour( 0, 1, 1 ),
		LightRed = Colour( 1, 0.3, 0.3 )
	}
end

local function AddText( RichText, Colour, Text )
	local PreviousColour = RichText[ #RichText - 1 ]
	local PreviousText = RichText[ #RichText ]
	if PreviousText and ( PreviousColour.Value == Colour or not StringFind( Text, "[^%s]" ) ) then
		-- Either just whitespace is being added, or the previous element's colour is the same as this one, so just
		-- append the text to the previous text element.
		PreviousText.Value = PreviousText.Value..Text
	else
		RichText[ #RichText + 1 ] = ColourElement( Colour )
		RichText[ #RichText + 1 ] = TextElement( Text )
	end
end

--[[
	Takes the given interpolation string, and produces a rich text message with each argument having a specified colour.
]]
function Format.FromInterpolationString( String, Options )
	Shine.TypeCheck( String, "string", 1, "Interpolate" )
	Shine.TypeCheck( Options, "table", 2, "Interpolate" )

	Shine.TypeCheckField( Options, "Values", "table", "Options" )
	Shine.TypeCheckField( Options, "Colours", "table", "Options" )
	Shine.TypeCheckField( Options, "DefaultColour", { "nil", "cdata" }, "Options" )
	Shine.TypeCheckField( Options, "LangDef", { "nil", "table" }, "Options" )

	local Values = Options.Values
	local Colours = Options.Colours
	local DefaultColour = Options.DefaultColour or DEFAULT_COLOUR
	local LangDef = Options.LangDef

	local RichText = {}
	local CurrentIndex = 1
	local Start, End, Value = StringFind( String, "{(.-)}" )
	while Start do
		if Start > CurrentIndex then
			AddText( RichText, DefaultColour, StringSub( String, CurrentIndex, Start - 1 ) )
		end

		local Result, ArgName = ApplyInterpolationTransformer( Value, Values, LangDef )
		local ColourValue = Colours[ ArgName ]
		local Colour = DefaultColour
		if IsType( ColourValue, "cdata" ) then
			Colour = ColourValue
		elseif IsCallable( ColourValue ) then
			Colour = ColourValue( Values )
		end

		AddText( RichText, Colour, Result )

		CurrentIndex = End + 1
		Start, End, Value = StringFind( String, "{(.-)}", CurrentIndex )
	end

	if CurrentIndex <= #String then
		AddText( RichText, DefaultColour, StringSub( String, CurrentIndex ) )
	end

	return RichText
end

function Format.GetColourForPlayer( PlayerName )
	local PlayerRecord = Scoreboard_GetPlayerRecordByName and Scoreboard_GetPlayerRecordByName( PlayerName )
	if not PlayerRecord then
		return DEFAULT_COLOUR
	end

	return Format.Colours.Teams[ PlayerRecord.EntityTeamNumber ] or DEFAULT_COLOUR
end

return Format
