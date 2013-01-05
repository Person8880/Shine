--[[
	Vote menu client side stuff.
]]

Shine = Shine or {}

Shine.Maps = {}
Shine.EndTime = 0

Client.HookNetworkMessage( "Shine_VoteMenu", function( Message )
	Shine.Maps = string.Explode( Message.Options, ", " )
	Shine.EndTime = Shared.GetTime() + Message.Duration

	Shine.SentVote = false
end )

local Menu

Event.Hook( "Console_sh_votemenu", function( Client )
	if Shine.EndTime < Shared.GetTime() then return end
	
	local Manager = GetGUIManager()

	if Menu then
		Manager:DestroyGUIScript( Menu )

		Menu = nil

		return
	end

	Menu = Manager:CreateGUIScript( "GUIShineVoteMenu" )
	Menu:Populate()

	Menu:SetIsVisible( true )
end )
