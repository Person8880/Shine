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
			RichText[ #RichText + 1 ] = ColourElement( DefaultColour )
			RichText[ #RichText + 1 ] = TextElement( StringSub( String, CurrentIndex, Start - 1 ) )
		end

		local Result, ArgName = ApplyInterpolationTransformer( Value, Values, LangDef )
		local ColourValue = Colours[ ArgName ]
		local Colour = DefaultColour
		if IsType( ColourValue, "cdata" ) then
			Colour = ColourValue
		elseif IsCallable( ColourValue ) then
			Colour = ColourValue( Values )
		end

		RichText[ #RichText + 1 ] = ColourElement( Colour )
		RichText[ #RichText + 1 ] = TextElement( Result )

		CurrentIndex = End + 1
		Start, End, Value = StringFind( String, "{(.-)}", CurrentIndex )
	end

	if CurrentIndex <= #String then
		RichText[ #RichText + 1 ] = ColourElement( DefaultColour )
		RichText[ #RichText + 1 ] = TextElement( StringSub( String, CurrentIndex ) )
	end

	return RichText
end

return Format
