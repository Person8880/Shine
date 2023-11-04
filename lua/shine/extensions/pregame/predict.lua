--[[
	Shine pregame plugin prediction VM.
]]

-- OnFirstThink isn't called in the prediction VM as there's no update event, so need to set this up at load time.
Shine.Hook.CallAfterFileLoad( "lua/Player.lua", function()
	Shine.Hook.SetupClassHook( "Player", "GetCanAttack", "CheckPlayerCanAttack", "ActivePre" )
end )
