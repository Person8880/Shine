--[[
	Shine player functions.
]]

local Abs = math.abs
local Floor = math.floor
local GetEntsByClass
local StringFormat = string.format
local TableRemove = table.remove
local TableShuffle = table.Shuffle

Shine.Hook.Add( "PostloadConfig", "PlayerAPI", function()
	GetEntsByClass = Shared.GetEntitiesWithClassname
end )

--[[
	Returns whether the given client is valid.
]]
function Shine:IsValidClient( Client )
	return Client and self.GameIDs[ Client ] ~= nil
end

--[[
	Ensures no team has more than 1 extra player compared to the other.
]]
function Shine.EvenlySpreadTeams( Gamerules, TeamMembers )
	local Marine = TeamMembers[ 1 ]
	local Alien = TeamMembers[ 2 ]

	local NumMarine = #TeamMembers[ 1 ]
	local NumAlien = #TeamMembers[ 2 ]

	local MarineGreater = NumMarine > NumAlien
	local Diff = Abs( NumMarine - NumAlien )

	if Diff > 1 then
		local NumToMove = Floor( Diff * 0.5 ) - 1

		if MarineGreater then
			for i = NumMarine, NumMarine - NumToMove, -1 do
				local Player = Marine[ i ]

				Marine[ i ] = nil
				
				Alien[ #Alien + 1 ] = Player
			end
		else
			for i = NumAlien, NumAlien - NumToMove, -1 do
				local Player = Alien[ i ]

				Alien[ i ] = nil

				Marine[ #Marine + 1 ] = Player
			end
		end
	end

	for i = 1, #Marine do
		Gamerules:JoinTeam( Marine[ i ], 1, nil, true )
	end

	for i = 1, #Alien do
		Gamerules:JoinTeam( Alien[ i ], 2, nil, true )
	end
end

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
	Returns a table of all clients.
]]
function Shine.GetAllClients()
	local Clients = {}
	local Count = 1

	local GameIDs = Shine.GameIDs

	for Client, ID in pairs( GameIDs ) do
		Clients[ Count ] = Client
		Count = Count + 1
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
function Shine.GetClientByNS2ID( ID )
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

function Shine.NS2ToSteamID( ID )
	ID = tonumber( ID )
	if not ID then return "" end
	
	return StringFormat( "STEAM_0:%i:%i", ID % 2, Floor( ID * 0.5 ) )
end

function Shine.SteamIDToNS2( ID )
	if type( ID ) ~= "string" or not ID:match( "^STEAM_%d:%d:%d+$" ) then return nil end

	local Num = tonumber( ID:sub( 11 ) )
	local Extra = tonumber( ID:sub( 9, 9 ) )

	return Num * 2 + Extra
end

function Shine:GetClientBySteamID( ID )
	if type( ID ) ~= "string" then return nil end

	local NS2ID = self.SteamIDToNS2( ID )

	if not NS2ID then return nil end
	
	return self.GetClientByNS2ID( NS2ID )
end

--[[
	Returns a client matching the given Steam ID or name.
]]
function Shine:GetClient( String )
	if type( String ) == "number" or tonumber( String ) then
		local Num = tonumber( String )

		local Result = self.GetClientByID( Num ) or self.GetClientByNS2ID( Num )
		
		if not Result then
			return self.GetClientByName( tostring( String ) )
		end

		return Result
	end

	return self:GetClientBySteamID( String ) or self.GetClientByName( tostring( String ) )
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
	if Group ~= "guest" and not self.UserData.Groups[ Group ] then return {} end

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

--[[
	Returns a nice name for the given team number.
]]
function Shine:GetTeamName( Team, Capitals )
	if Team == 1 then
		return Capitals and "Marines" or "marines"
	elseif Team == 2 then
		return Capitals and "Aliens" or "aliens"
	elseif Team == 3 then
		return Capitals and "Spectate" or "spectate"
	else
		return Capitals and "Ready Room" or "ready room"
	end
end
