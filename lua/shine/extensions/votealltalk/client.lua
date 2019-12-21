--[[
	All talk voting client-side.
]]

local Plugin = ...

Plugin.VoteButtonName = "VoteAllTalk"

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

	RichTextMessageOptions[ "PLAYER_VOTED_ENABLE" ] = VoteMessageOptions
	RichTextMessageOptions[ "PLAYER_VOTED_DISABLE" ] = VoteMessageOptions

	Plugin.RichTextMessageOptions = RichTextMessageOptions
end

Shine.VoteMenu:EditPage( "Main", Plugin:WrapCallback( function( VoteMenu )
	-- Ensure the text reflects the outcome of the vote.
	local ButtonText = Plugin:GetPhrase( Plugin.dt.IsEnabled and "DISABLE_ALLTALK" or "ENABLE_ALLTALK" )

	local Button = VoteMenu:AddSideButton( ButtonText, function()
		VoteMenu.GenericClick( "sh_votealltalk" )
	end )

	-- Allow the button to be retrieved to have its counter updated.
	Button.Plugin = Plugin.VoteButtonName
	Button.DefaultText = ButtonText
	Button.CheckMarkXScale = 0.5
end ) )
