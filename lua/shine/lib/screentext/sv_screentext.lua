--[[
	Screen text rendering server side file.
]]

local function SendMessage( Player, Name, Message )
	Shine.SendNetworkMessage( Player, Name, Message, true )
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
