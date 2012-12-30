--[[
	Shine player functions.
]]

--local EntityListToTable-- = EntityListToTable
local GetEntsByClass-- = Shared.GetEntitiesWithClassname
local TableSort = table.sort
local Ranomd = math.random

Shine.Hook.Add( "PostloadConfig", "PlayerAPI", function()
	--EntityListToTable = EntityListToTable
	GetEntsByClass = Shared.GetEntitiesWithClassname
end )

function Shine.GetAllPlayers()
	return EntityListToTable( GetEntsByClass( "Player" ) )
end

function Shine.GetRandomPlayerList()
	local Players = EntityListToTable( GetEntsByClass( "Player" ) )

	TableSort( Players, function( A, B )
		return Random( 1, 100 ) > 50
	end )

	return Players
end

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

function Shine:GetClient( String )
	if type( String ) == "number" or tonumber( String ) then
		local Result = self.GetClientBySteamID( tonumber( String ) )
		if not Result then
			return self.GetClientByName( tostring( String ) )
		end

		return Result
	end

	return self.GetClientByName( tostring( String ) )
end
