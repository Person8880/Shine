--[[
	Screen text rendering server side file.
]]

function Shine:SendText( Player, Message )
	self:ApplyNetworkMessage( Player, "Shine_ScreenText", Message, true )
end

function Shine:UpdateText( Player, Message )
	self:ApplyNetworkMessage( Player, "Shine_ScreenTextUpdate", Message, true )
end

function Shine:RemoveText( Player, Message )
	self:ApplyNetworkMessage( Player, "Shine_ScreenTextRemove", Message, true )
end
