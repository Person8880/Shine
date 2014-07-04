--[[
	Screen text rendering server side file.
]]

local function SendMessage( Player, Name, Message )
	if Player then
		Shine.SendNetworkMessage( Player, Name, Message, true )
	else
		Shine.SendNetworkMessage( Name, Message, true )
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
