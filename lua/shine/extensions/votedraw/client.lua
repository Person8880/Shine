--[[
	Draw vote client side.
]]

local Plugin = ...

Plugin.VoteButtonName = "VoteDraw"

do
	local RichTextFormat = require "shine/lib/gui/richtext/format"
	local RichTextMessageOptions = {}
	local VoteMessageOptions = {
		Colours = {
			PlayerName = function( Values )
				return RichTextFormat.GetColourForPlayer( Values.PlayerName )
			end
		}
	}

	RichTextMessageOptions[ "PLAYER_VOTED" ] = VoteMessageOptions

	Plugin.RichTextMessageOptions = RichTextMessageOptions
end

Shine.VoteMenu:EditPage( "Main", Plugin:WrapCallback( function( VoteMenu )
	local ButtonText = Plugin:GetPhrase( "VOTEMENU_BUTTON" )

	local Button = VoteMenu:AddSideButton( ButtonText, function()
		VoteMenu.GenericClick( "sh_votedraw" )
	end )

	-- Allow the button to be retrieved to have its counter updated.
	Button.Plugin = Plugin.VoteButtonName
	Button.DefaultText = ButtonText
	Button.CheckMarkXScale = 0.75
end ) )
