--[[
	Screen text rendering server side file.
]]

Shine = Shine or {}

function Shine:SendText( Player, Message )
	if Player then
		Server.SendNetworkMessage( Player, "Shine_ScreenText", Message, true )
	else
		local Players = self.GetAllClients()

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_ScreenText", Message, true )
		end
	end
end

function Shine:UpdateText( Player, Message )
	if Player then
		Server.SendNetworkMesage( Player, "Shine_ScreenTextUpdate", Message, true )
	else
		local Players = self.GetAllClients()

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_ScreenTextUpdate", Message, true )
		end
	end
end

function Shine:RemoveText( Player, Message )
	if Player then
		Server.SendNetworkMesage( Player, "Shine_ScreenTextRemove", Message, true )
	else
		local Players = self.GetAllClients()

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_ScreenTextRemove", Message, true )
		end
	end
end
