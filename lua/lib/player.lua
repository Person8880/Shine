--[[
	Shine player functions.
]]

local GetEntsByClass
local TableRemove = table.remove
local TableShuffle = table.Shuffle
local TableSort = table.sort
local Ranomd = math.random

Shine.Hook.Add( "PostloadConfig", "PlayerAPI", function()
	GetEntsByClass = Shared.GetEntitiesWithClassname
end )

--[[
	Returns a table of all players.
]]
function Shine.GetAllPlayers()
	return EntityListToTable( GetEntsByClass( "Player" ) )
end

--[[
	Returns a table of all players sorted randomly.
]]
function Shine.GetRandomPlayerList()
	local Players = EntityListToTable( GetEntsByClass( "Player" ) )

	TableShuffle( Players )

	return Players
end

--[[
	Returns a table of all clients on the given team.
]]
function Shine.GetTeamClients( Team )
	local Players = GetEntitiesForTeam( "Player", Team )

	local Clients = {}
	local Count = 1

	for i = 1, #Players do
		local Client = Server.GetOwner( Players[ i ] )

		if Client then
			Clients[ Count ] = Client
			Count = Count + 1			
		end
	end

	return Clients
end

--[[
	Returns a table of all clients.
]]
function Shine.GetAllClients()
	local Players = EntityListToTable( GetEntsByClass( "Player" ) )

	local Clients = {}
	local Count = 1

	for i = 1, #Players do
		local Ply = Players[ i ]

		if Ply then
			local Client = Ply:GetClient()
			if Client then
				Clients[ Count ] = Client
				Count = Count + 1
			end
		end
	end

	return Clients
end

--[[
	Returns a client matching the given game ID.
]]
function Shine.GetClientByID( ID )
	local GameIDs = Shine.GameIDs

	for Client, GameID in pairs( GameIDs ) do
		if ID == GameID then
			return Client
		end
	end

	return nil
end

--[[
	Returns a client matching the given Steam ID.
]]
function Shine.GetClientBySteamID( ID )
	if type( ID ) ~= "number" then return nil end
	
	local Players = EntityListToTable( GetEntsByClass( "Player" ) )
	for i = 1, #Players do
		local Ply = Players[ i ]
		
		if Ply then
			local Client = Ply:GetClient()
			if Client then
				if Client:GetUserId() == ID then
					return Client
				end
			end
		end				
	end
	
	return nil
end

--[[
	Returns a client matching the given name.
]]
function Shine.GetClientByName( Name )
	if type( Name ) ~= "string" then return nil end

	Name = Name:lower()
	
	local Players = EntityListToTable( GetEntsByClass( "Player" ) )

	for i = 1, #Players do
		local Ply = Players[ i ]

		if Ply then
			local Client = Ply:GetClient()
			if Client then
				if Ply:GetName():lower():find( Name, 1, true ) then
					return Client
				end
			end
		end
	end

	return nil
end

--[[
	Returns a client matching the given Steam ID or name.
]]
function Shine:GetClient( String )
	if type( String ) == "number" or tonumber( String ) then
		local Num = tonumber( String )

		local Result = self.GetClientByID( Num ) or self.GetClientBySteamID( Num )
		
		if not Result then
			return self.GetClientByName( tostring( String ) )
		end

		return Result
	end

	return self.GetClientByName( tostring( String ) )
end

--[[
	Returns all clients with permission to see log messages.
]]
function Shine:GetClientsForLog()
	local Clients = self.GetAllClients()

	local Ret = {}
	local Count = 1

	for i = 1, #Clients do
		local Client = Clients[ i ]
		if self:HasAccess( Client, "sh_seelogechos" ) then
			Ret[ Count ] = Client
			Count = Count + 1
		end
	end

	return Ret
end

--[[
	Returns all clients in the given group.
]]
function Shine:GetClientsByGroup( Group )
	if not self.UserData.Groups[ Group ] then return nil end

	local Clients = self.GetAllClients()

	local Ret = {}
	local Count = 1

	for i = 1, #Clients do
		local Client = Clients[ i ]
		if self:IsInGroup( Client, Group ) then
			Ret[ Count ] = Client
			Count = Count + 1
		end
	end

	return Ret
end
