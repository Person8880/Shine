--[[
	Welcome messages client-side.
]]

local SGUI = Shine.GUI

local Plugin = ...

local Ceil = math.ceil
local function MakeColourFromInt( Int, Multiplier )
	return SGUI.ColourWithAlpha( ColorIntToColor( Int ) * Multiplier, 1 )
end

local DarkTeamColours = {
	[ 0 ] = Colour( 1, 1, 1 ),
	MakeColourFromInt( kMarineTeamColor or 0x4DB1FF, 0.8 ),
	MakeColourFromInt( kAlienTeamColor or 0xFFCA3A, 0.8 )
}
local TeamColours = {
	[ 0 ] = Colour( 0.6, 0.6, 0.6 ),
	ColorIntToColor( kMarineTeamColor or 0x4DB1FF ),
	ColorIntToColor( kAlienTeamColor or 0xFFCA3A )
}

local function FallbackTeamMessage( Plugin, Options )
	local Colour = DarkTeamColours[ Options.Values.Team ] or DarkTeamColours[ 0 ]

	Plugin:NotifySingleColour(
		Ceil( Colour.r * 255 ), Ceil( Colour.g * 255 ), Ceil( Colour.b * 255 ),
		Plugin:GetInterpolatedPhrase( Options.Key, Options.Values )
	)
end

local function GetTeamColour( Values )
	return TeamColours[ Values.Team ] or TeamColours[ 0 ]
end

Plugin.RichTextMessageOptions = {
	PLAYER_LEAVE_GENERIC = {
		Colours = {
			TargetName = GetTeamColour
		},
		MakeFallbackMessage = FallbackTeamMessage
	},
	PLAYER_LEAVE_REASON = {
		Colours = {
			TargetName = GetTeamColour,
			Reason = Colour( 1, 0.3, 0.3 )
		},
		MakeFallbackMessage = FallbackTeamMessage
	}
}
