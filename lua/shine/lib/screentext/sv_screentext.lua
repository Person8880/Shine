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

do
	local function RemoveText( ID, Player, Now )
		Shine:ApplyNetworkMessage( Player, "Shine_ScreenTextRemove", { ID = ID, Now = Now }, true )
	end

	function Shine.ScreenText.End( ID, Player )
		RemoveText( ID, Player, false )
	end

	function Shine.ScreenText.Remove( ID, Player )
		RemoveText( ID, Player, true )
	end
end
