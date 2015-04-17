--[[
	Screen text rendering server side file.
]]

local Shine = Shine

function Shine.ScreenText.Add( ID, Params, Player )
	Params.ID = ID

	Shine:ApplyNetworkMessage( Player, "Shine_ScreenText", Params, true )
end

function Shine.ScreenText.SetText( ID, Text, Player )
	Shine:ApplyNetworkMessage( Player, "Shine_ScreenTextUpdate", { ID = ID, Text = Text }, true )
end

function Shine.ScreenText.End( ID, Player )
	Shine:ApplyNetworkMessage( Player, "Shine_ScreenTextRemove", { ID = ID }, true )
end

--DEPRECATED! Use Shine.ScreenText.Add( ID, Params[, Player] )
function Shine:SendText( Player, Message )
	self:ApplyNetworkMessage( Player, "Shine_ScreenText", Message, true )
end

--DEPRECATED! Use Shine.ScreenText.SetText( ID, Text[, Player] )
function Shine:UpdateText( Player, Message )
	self:ApplyNetworkMessage( Player, "Shine_ScreenTextUpdate", Message, true )
end

--DEPRECATED! Use Shine.ScreenText.End( ID[, Player] )
function Shine:RemoveText( Player, Message )
	self:ApplyNetworkMessage( Player, "Shine_ScreenTextRemove", Message, true )
end
