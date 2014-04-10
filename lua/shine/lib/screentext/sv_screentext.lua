--[[
	Screen text rendering server side file.
]]

Shine = Shine or {}

local function SendMessage( Player, Name, Message )
	if Player then
		Server.SendNetworkMessage( Player, Name, Message, true )
	else
		Server.SendNetworkMessage( Name, Message, true )
	end
end

function Shine:SendText( Player, Message )
	SendMessage( Player, "Shine_ScreenText", Message )
end

function Shine:UpdateText( Player, Message )
	SendMessage( Player, "Shine_ScreenTextUpdate", Message )
end

function Shine:RemoveText( Player, Message )
	SendMessage( Player, "Shine_ScreenTextRemove", Message )
end
