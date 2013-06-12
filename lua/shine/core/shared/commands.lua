--[[
	Shine remote command system.
]]

Shine = Shine or {}

local ConCommand = {
	Command = "string (255)"
}

Shared.RegisterNetworkMessage( "Shine_Command", ConCommand )

if Server then return end

Client.HookNetworkMessage( "Shine_Command", function( Message )
	Shared.ConsoleCommand( Message.Command )
end )
