--[[
	Shine player functions.
]]

local Abs = math.abs
local Floor = math.floor
local GetEntsByClass = Shared.GetEntitiesWithClassname
local GetOwner = Server.GetOwner
local pairs = pairs
local StringFormat = string.format
local TableRemove = table.remove
local TableShuffle = table.Shuffle
local TableSort = table.sort
local TableToString = table.ToString
local Traceback = debug.traceback

--[[
	Returns whether the given client is valid.
]]
function Shine:IsValidClient( Client )
	return Client and self.GameIDs[ Client ] ~= nil
end

local function OnJoinError( Error )
	local Trace = Traceback()

	Shine:DebugLog( "Error: %s.\nEvenlySpreadTeams failed. %s", true, Error, Trace )
	Shine:AddErrorReport( StringFormat( "A player failed to join a team in EvenlySpreadTeams: %s.", Error ), Trace )
end

local OldRespawnPlayer = Team.RespawnPlayer

--[[
	Occasionally Gamerules or whatever is repsonsible for adding players to teams
	fails to do so. So, let's make sure a player is properly added to the team
	when asked to respawn.
]]
function Team:RespawnPlayer( Player, Origin, Angles )
	self:AddPlayer( Player )

	return OldRespawnPlayer( self, Player, Origin, Angles )
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

	local Reported

	if Abs( #Marine - #Alien ) > 1 then
		local VoteRandom = Shine.Plugins.voterandom

		if VoteRandom then
			local BalanceMode = VoteRandom.Config.BalanceMode

			local Marines = TableToString( Marine )
			local Aliens = TableToString( Alien )

			Shine:AddErrorReport( "Team sorting resulted in imbalanced teams before applying.",
				"Balance Mode: %s. Marine Size: %s. Alien Size: %s. Diff: %s. New Teams:\nMarines:\n%s\nAliens:\n%s",
				true, BalanceMode, NumMarine, NumAlien, Diff, Marines, Aliens )
		end

		Reported = true
	end

	local MarineTeam = Gamerules.team1
	local AlienTeam = Gamerules.team2

	for i, Player in pairs( Marine ) do
		local Success, JoinSuccess, NewPlayer = xpcall( Gamerules.JoinTeam, OnJoinError, Gamerules, Player, 1, nil, true )

		if Success then
			Marine[ i ] = NewPlayer
		else
			Marine[ i ] = nil
		end
	end

	for i, Player in pairs( Alien ) do
		local Success, JoinSuccess, NewPlayer = xpcall( Gamerules.JoinTeam, OnJoinError, Gamerules, Player, 2, nil, true )

		if Success then
			Alien[ i ] = NewPlayer
		else
			Alien[ i ] = nil
		end
	end

	local NewMarineCount = MarineTeam:GetNumPlayers()
	local NewAlienCount = AlienTeam:GetNumPlayers()
	local NewDiff = Abs( NewMarineCount - NewAlienCount )

	if NewDiff > 1 and not Reported then
		local VoteRandom = Shine.Plugins.voterandom

		if VoteRandom then
			local BalanceMode = VoteRandom.Config.BalanceMode

			local Marines = TableToString( Marine )
			local Aliens = TableToString( Alien )

			Shine:AddErrorReport( "Team sorting resulted in imbalanced teams after applying.",
				"Balance Mode: %s. Table Marine Size: %s. Table Alien Size: %s. Table Diff: %s.\nActual Marine Size: %s. Actual Alien Size: %s. Actual Diff: %s.\nNew Teams:\nMarines:\n%s\nAliens:\n%s",
				true, BalanceMode, NumMarine, NumAlien, Diff, NewMarineCount, NewAlienCount, NewDiff, Marines, Aliens )
		end
	end
end

--[[
	Returns the number of human players (clients).
]]
function Shine.GetHumanPlayerCount()
	local Count = 0

	local GameIDs = Shine.GameIDs

	for Client, ID in pairs( GameIDs ) do
		if Client.GetIsVirtual and not Client:GetIsVirtual() then
			Count = Count + 1
		end
	end
	
	return Count
end

--[[
	Returns a table of all players.
]]
function Shine.GetAllPlayers()
	local Players = {}
	local Count = 1

	local GameIDs = Shine.GameIDs

	for Client, ID in pairs( GameIDs ) do
		local Player = Client.GetControllingPlayer and Client:GetControllingPlayer()

		if Player then
			Players[ Count ] = Player
			
			Count = Count + 1
		end
	end

	return Players
end

--[[
	Returns a table of all players sorted randomly.
]]
function Shine.GetRandomPlayerList()
	local Players = Shine.GetAllPlayers()

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
			local Client = GetOwner( Ply )

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
	
	local Clients = Shine.GameIDs
	
	for Client in pairs( Clients ) do
		if Client:GetUserId() == ID then
			return Client
		end
	end

	return nil
end

--[[
	Returns the client closest matching the given name.
]]
function Shine.GetClientByName( Name )
	if type( Name ) ~= "string" then return nil end

	Name = Name:lower()

	local Clients = Shine.GameIDs
	local SortTable = {}
	local Count = 0

	for Client in pairs( Clients ) do
		local Player = Client:GetControllingPlayer()

		if Player then
			local Find = Player:GetName():lower():find( Name, 1, true )

			if Find then
				Count = Count + 1
				SortTable[ Count ] = { Client = Client, Index = Find }
			end
		end
	end

	if Count == 0 then return nil end

	--Get the match with the string furthest to the left in their name.
	TableSort( SortTable, function( A, B )
		return A.Index < B.Index
	end )

	return SortTable[ 1 ].Client
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
	Returns all clients with access to the given string.
]]
function Shine:GetClientsWithAccess( Access )
	local Ret = {}
	local Count = 0

	for Client in pairs( self.GameIDs ) do
		if self:HasAccess( Client, Access ) then
			Count = Count + 1
			Ret[ Count ] = Client
		end
	end

	return Ret, Count
end

--[[
	Returns all clients with permission to see log messages.
]]
function Shine:GetClientsForLog()
	return self:GetClientsWithAccess( "sh_seelogechos" )
end

--[[
	Returns all clients in the given group.
]]
function Shine:GetClientsByGroup( Group )
	if Group ~= "guest" and not self.UserData.Groups[ Group ] then return {} end

	local Clients = self.GameIDs

	local Count = 0
	local Ret = {}

	for Client in pairs( Clients ) do
		if self:IsInGroup( Client, Group ) then
			Count = Count + 1
			Ret[ Count ] = Client
		end
	end

	return Ret
end

local TeamNames = {
	ns2 = {
		{ "Marines", "marines" },
		{ "Aliens", "aliens" },
		{ "Spectate", "spectate" },
		{ "Ready Room", "ready room" }
	},
	mvm = {
		{ "Team Blue", "team blue" },
		{ "Team Gold", "team gold" },
		{ "Spectate", "spectate" },
		{ "Ready Room", "ready room" }
	}
}

--[[
	Returns a nice name for the given team number.
]]
function Shine:GetTeamName( Team, Capitals )
	local Gamemode = self.GetGamemode()
	local Names = TeamNames[ Gamemode ] or TeamNames.ns2

	if Team > 3 or Team < 1 then
		Team = 4
	end

	return Capitals and Names[ Team ][ 1 ] or Names[ Team ][ 2 ]
end

local ConsoleInfo = "Console[N/A]"

function Shine.GetClientInfo( Client )
	if not Client then return ConsoleInfo end

	local Player = Client:GetControllingPlayer()

	if not Player then return ConsoleInfo end

	return StringFormat( "%s[%s]", Player:GetName(), Client:GetUserId() )
end
