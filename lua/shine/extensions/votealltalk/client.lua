--[[
	All talk voting client-side.
]]

local Plugin = Plugin

Plugin.VoteButtonName = "VoteAllTalk"

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
