--[[
	Shine player functions.
]]

local Shine = Shine
local Hook = Shine.Hook

local TeamNames = {
	ns2 = {
		{ "Marines", "marines", "marine team" },
		{ "Aliens", "aliens", "alien team" },
		{ "Spectate", "spectators", "spectate" },
		{ "Ready Room", "ready room", "ready room" }
	},
	mvm = {
		{ "Blue Team", "blue team", "blue team" },
		{ "Gold Team", "gold team", "gold team" },
		{ "Spectate", "spectators", "spectate" },
		{ "Ready Room", "ready room", "ready room" }
	}
}
TeamNames.combat = TeamNames.ns2

--[[
	Returns a nice name for the given team number.
]]
function Shine:GetTeamName( Team, Capitals, Singular )
	local Gamemode = self.GetGamemode()
	local Names = TeamNames[ Gamemode ] or TeamNames.ns2

	if Team > 3 or Team < 1 then
		Team = 4
	end

	if Capitals then
		return Names[ Team ][ 1 ]
	end

	if Singular then
		return Names[ Team ][ 3 ]
	end

	return Names[ Team ][ 2 ]
end

do
	local PlayingTeams = { true, true }

	function Shine.IsPlayingTeam( TeamNumber )
		return PlayingTeams[ TeamNumber ] or false
	end
end

if Client then
	local Indexes = {
		ByName = {},
		ByClientID = {}
	}

	--[[
		Returns the scoreboard entry for the player with the given name.

		This accounts for possible client-side name changes (such as an AFK prefix), returning the same entry for the
		original player name and the altered name.
	]]
	function Shine.GetScoreboardEntryByName( Name )
		local Entry = Scoreboard_GetPlayerRecordByName and Scoreboard_GetPlayerRecordByName( Name )
		if Entry then
			return Entry
		end

		return Indexes.ByName[ Name ]
	end

	function Shine.GetScoreboardEntryByClientID( ClientID )
		local Entry = Scoreboard_GetPlayerRecord and Scoreboard_GetPlayerRecord( ClientID )
		if Entry then
			return Entry
		end

		return Indexes.ByClientID[ ClientID ]
	end

	Hook.CallAfterFileLoad( "lua/Scoreboard.lua", function()
		local ErrorHandler = Shine.BuildErrorHandler( "Scoreboard update error" )
		local TableEmpty = table.Empty
		local xpcall = xpcall

		Hook.SetupGlobalHook( "Scoreboard_ReloadPlayerData", "PostScoreboardReload", "PassivePost" )

		local function UpdateScoreboardEntries()
			TableEmpty( Indexes.ByName )
			TableEmpty( Indexes.ByClientID )

			local EntityList = Shared.GetEntitiesWithClassname( "PlayerInfoEntity" )
			for _, Entity in ientitylist( EntityList ) do
				local Entry = Scoreboard_GetPlayerRecord( Entity.clientId )
				if Entry and Entry.Name then
					Indexes.ByName[ Entry.Name ] = Entry

					if Entry.ClientIndex then
						Indexes.ByClientID[ Entry.ClientIndex ] = Entry
					end

					Hook.Call( "OnScoreboardEntryReload", Entry, Entity )

					-- Update in case the name was changed elsewhere (assume the change is unique).
					Indexes.ByName[ Entry.Name ] = Entry
				end
			end
		end

		local CALLING = false
		Hook.Add( "PostScoreboardReload", "IndexPlayerEntries", function()
			if CALLING then return end

			-- Just in case we somehow see a PlayerInfoEntity that has a client ID that is not
			-- in the scoreboard player data yet, we don't want to trigger a stack overflow.
			CALLING = true

			xpcall( UpdateScoreboardEntries, ErrorHandler )

			CALLING = false
		end )
	end )

	return
end

local Abs = math.abs
local Floor = math.floor
local IsType = Shine.IsType
local pairs = pairs
local StringFind = string.find
local StringFormat = string.format
local StringLower = string.lower
local StringMatch = string.match
local TableNew = require "table.new"
local TableRemove = table.remove
local TableShallowCopy = table.ShallowCopy
local TableShuffle = table.Shuffle
local TableSort = table.sort
local TableToString = table.ToString
local tonumber = tonumber

--[[
	Returns whether the given client is valid.
]]
function Shine:IsValidClient( Client )
	return Client and self.GameIDs:Get( Client ) ~= nil
end

--[[
	Returns the client associated with the given player.
]]
function Shine.GetClientForPlayer( Player )
	return Player.GetClient and Player:GetClient()
end

function Shine.EqualiseTeamCounts( TeamMembers )
	local Marine = TeamMembers[ 1 ]
	local Alien = TeamMembers[ 2 ]

	local NumMarine = #Marine
	local NumAlien = #Alien

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

	return Diff
end

do
	local OnJoinError = Shine.BuildErrorHandler( "EvenlySpreadTeams team join error" )

	local function MoveToTeam( Gamerules, Players, TeamNumber )
		for i = #Players, 1, -1 do
			local Player = Players[ i ]
			if Player:GetTeamNumber() ~= TeamNumber then
				local Success, JoinSuccess, NewPlayer = xpcall( Gamerules.JoinTeam,
					OnJoinError, Gamerules, Player, TeamNumber,
					true, true )

				if Success then
					Players[ i ] = NewPlayer
				else
					TableRemove( Players, i )
				end
			end
		end
	end

	local function ForceTeamSwap( Gamerules, Player, TeamNumber, Force, ShineForce )
		if ShineForce then
			return true, TeamNumber
		end
	end

	local Inspect = require "shine/lib/inspect"

	local function PlayerToOutput( Player )
		local Client = Shine.GetClientForPlayer( Player )
		local ClientID = "?"
		local IsVirtual = false
		if Shine:IsValidClient( Client ) then
			ClientID = Client:GetId()
			IsVirtual = Client:GetIsVirtual()
		end
		return StringFormat( "%s (%s[%s])", Inspect.ToString( Player ), IsVirtual and "Bot" or "Player", ClientID )
	end

	local function PlayersToString( Players )
		return TableToString( Shine.Stream.Of( Players ):Map( PlayerToOutput ):AsTable() )
	end

	--[[
		Ensures no team has more than 1 extra player compared to the other.
	]]
	function Shine.EvenlySpreadTeams( Gamerules, TeamMembers )
		Hook.Call( "PreEvenlySpreadTeams", Gamerules, TeamMembers )

		-- Yes, we repeat this, but the reporting needs it...
		local Marine = TeamMembers[ 1 ]
		local Alien = TeamMembers[ 2 ]

		local NumMarine = #Marine
		local NumAlien = #Alien
		local Diff = Shine.EqualiseTeamCounts( TeamMembers )

		local MarineTeam = Gamerules.team1
		local AlienTeam = Gamerules.team2

		-- Override all plugin hooks to prevent them interfering with the swapping process.
		-- Some people implement JoinTeam hooks without respecting the ShineForce parameter...
		Hook.Add( "JoinTeam", "StopPeopleBreakingShuffle", ForceTeamSwap, Hook.MAX_PRIORITY )

		MoveToTeam( Gamerules, Marine, 1 )
		MoveToTeam( Gamerules, Alien, 2 )

		Hook.Remove( "JoinTeam", "StopPeopleBreakingShuffle" )

		local NewMarineCount = MarineTeam:GetNumPlayers()
		local NewAlienCount = AlienTeam:GetNumPlayers()
		local NewDiff = Abs( NewMarineCount - NewAlienCount )
		-- If the number of players has changed, something else is interfering with teams and it's not our fault.
		local IsSameAmountOfPlayers = NumMarine + NumAlien == NewMarineCount + NewAlienCount

		if NewDiff > 1 and IsSameAmountOfPlayers then
			local VoteRandom = Shine.Plugins.voterandom

			if VoteRandom then
				local BalanceMode = VoteRandom.Config.BalanceMode

				local Marines = PlayersToString( Marine )
				local Aliens = PlayersToString( Alien )
				local NewMarines = PlayersToString( MarineTeam:GetPlayers() )
				local NewAliens = PlayersToString( AlienTeam:GetPlayers() )

				Shine:AddErrorReport(
					"Team sorting resulted in imbalanced teams after applying.",
					"Balance Mode: %s. Table Marine Size: %s. Table Alien Size: %s. Table Diff: %s.\n"..
					"Actual Marine Size: %s. Actual Alien Size: %s. Actual Diff: %s.\n"..
					"New Teams:\nMarines:\n%s\nActual Marines:\n%s\nAliens:\n%s\nActual Aliens:\n%s",
					true,
					BalanceMode, NumMarine, NumAlien, Diff,
					NewMarineCount, NewAlienCount, NewDiff,
					Marines, NewMarines, Aliens, NewAliens
				)
			end
		end

		Hook.Call( "PostEvenlySpreadTeams", Gamerules, TeamMembers )
	end
end

function Shine.IterateClients()
	return Shine.GameIDs:Iterate()
end

--[[
	Returns a table of all players.
]]
function Shine.GetAllPlayers()
	local Players = {}
	local Count = 0

	for Client, ID in Shine.IterateClients() do
		local Player = Client.GetControllingPlayer and Client:GetControllingPlayer()

		if Player then
			Count = Count + 1

			Players[ Count ] = Player
		end
	end

	return Players, Count
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
			local Client = Shine.GetClientForPlayer( Ply )
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
	local Count = 0

	for Client, ID in Shine.IterateClients() do
		Count = Count + 1
		Clients[ Count ] = Client
	end

	return Clients, Count
end

local Indexes = {}
do
	local MaxClientsTotal = Server.GetMaxPlayers() + Server.GetMaxSpectators()
	Indexes.ByName = setmetatable( TableNew( 0, MaxClientsTotal ), { __mode = "v" } )
	Indexes.BySteamID = setmetatable( TableNew( 0, MaxClientsTotal ), { __mode = "v" } )
	Indexes.ByGameID = setmetatable( TableNew( 0, MaxClientsTotal ), { __mode = "v" } )
end

Hook.Add( "PlayerNameChange", Indexes, function( Player, NewName, OldName )
	-- Name uniqueness is enforced in a case-insensitive manner (at least as far as string.lower is concerned).
	-- Thus it makes sense to index by lower-cased names.
	Indexes.ByName[ StringLower( OldName ) ] = nil
	Indexes.ByName[ StringLower( NewName ) ] = Player:GetClient()
end, Hook.MAX_PRIORITY )

Hook.Add( "ClientConnect", Indexes, function( Client )
	Indexes.BySteamID[ Client:GetUserId() ] = Client
	Indexes.ByGameID[ Client.ShineGameID ] = Client
end, Hook.MAX_PRIORITY + 0.1 )

Hook.Add( "ClientDisconnect", Indexes, function( Client )
	Indexes.BySteamID[ Client:GetUserId() ] = nil
	Indexes.ByGameID[ Client.ShineGameID ] = nil

	for Name, StoredClient in pairs( Indexes.ByName ) do
		if StoredClient == Client then
			Indexes.ByName[ Name ] = nil
		end
	end
end, Hook.MIN_PRIORITY )

function Shine.GetAllClientsByNS2ID()
	return TableShallowCopy( Indexes.BySteamID )
end

--[[
	Returns a client matching the given game ID.
]]
function Shine.GetClientByID( ID )
	local IndexedClient = Indexes.ByGameID[ ID ]
	if IndexedClient then return IndexedClient end

	for Client, GameID in Shine.IterateClients() do
		if ID == GameID then
			Indexes.ByGameID[ ID ] = Client
			return Client
		end
	end

	return nil
end

--[[
	Returns a client matching the given Steam ID.
]]
function Shine.GetClientByNS2ID( ID )
	if not IsType( ID, "number" ) then return nil end

	local IndexedClient = Indexes.BySteamID[ ID ]
	if IndexedClient then return IndexedClient end

	for Client in Shine.IterateClients() do
		if Client:GetUserId() == ID then
			Indexes.BySteamID[ ID ] = Client
			return Client
		end
	end

	return nil
end

do
	-- Unlike SteamID and game ID, names can change. While the hook above should capture these changes, it doesn't hurt
	-- to be absolutely sure that the indexed client is correct and this is still less work than checking all players.
	local function SanityCheckNameIndex( Client, Name )
		if not Client then return nil end

		local Player = Client:GetControllingPlayer()
		local ActualName = Player and StringLower( Player:GetName() )
		if Name == ActualName then
			return Client
		end

		Indexes.ByName[ Name ] = nil
		if ActualName and ActualName ~= "" then
			Indexes.ByName[ ActualName ] = Client
		end

		return nil
	end

	local function CompareResults( A, B )
		return A.Index < B.Index
	end

	--[[
		Returns the client closest matching the given name.
	]]
	function Shine.GetClientByName( Name )
		if not IsType( Name, "string" ) or #Name == 0 then return nil end

		local SearchName = StringLower( Name )
		local IndexedClient = Indexes.ByName[ SearchName ]
		if SanityCheckNameIndex( IndexedClient, SearchName ) then
			return IndexedClient
		end

		local SortTable = {}
		local Count = 0

		for Client in Shine.IterateClients() do
			local Player = Client:GetControllingPlayer()
			if Player then
				local PlayerName = StringLower( Player:GetName() )
				-- Always favour an exact match.
				if PlayerName == SearchName then return Client end

				local StartIndex = StringFind( PlayerName, SearchName, 1, true )
				if StartIndex then
					Count = Count + 1
					SortTable[ Count ] = { Client = Client, Index = StartIndex }
				end
			end
		end

		if Count == 0 then return nil end

		-- Get the match with the string furthest to the left in their name.
		TableSort( SortTable, CompareResults )

		return SortTable[ 1 ].Client
	end

	--[[
		Returns the client with the exact name given (ignoring case as it is not accounted for when determining
		uniqueness of names).
	]]
	function Shine.GetClientByExactName( Name )
		if not IsType( Name, "string" ) or #Name == 0 then return nil end

		local SearchName = StringLower( Name )
		local IndexedClient = Indexes.ByName[ SearchName ]
		if SanityCheckNameIndex( IndexedClient, SearchName ) then
			return IndexedClient
		end

		for Client in Shine.IterateClients() do
			local Player = Client:GetControllingPlayer()
			if Player and StringLower( Player:GetName() ) == SearchName then
				Indexes.ByName[ SearchName ] = Client
				return Client
			end
		end

		return nil
	end
end

function Shine.NS2ToSteamID( ID )
	ID = tonumber( ID )
	if not ID then return "" end

	return StringFormat( "STEAM_0:%d:%d", ID % 2, Floor( ID * 0.5 ) )
end

function Shine.NS2ToSteam3ID( ID )
	ID = tonumber( ID )
	if not ID then return "" end

	return StringFormat( "[U:1:%d]", ID )
end

function Shine.SteamIDToNS2( ID )
	if not IsType( ID, "string" ) then return nil end

	-- STEAM_0:X:YYYYYYY
	local ID1, ID2 = StringMatch( ID, "^STEAM_%d:(%d):(%d+)$" )
	if ID1 then
		local Num = tonumber( ID2 )
		local Extra = tonumber( ID1 )

		return Num * 2 + Extra
	else
		-- [U:1:YYYYYYY]
		local NS2ID = StringMatch( ID, "^%[U:%d:(%d+)%]$" )
		if not NS2ID then return nil end

		return tonumber( NS2ID )
	end
end

do
	local RemovedDigits = 6
	local SteamID64Int = 197960265728
	local StringSub = string.sub

	--[[
		Lua in NS2 uses double precision floats, which cannot express a 64 bit
		integer entirely. Thus, the first 5 digits are ignored, as the 32bit
		Steam ID should never bring the 64 bit ID to the point where it has to increment
		any of those digits.
	]]
	function Shine.NS2IDTo64( ID )
		return StringFormat( "76561%s", ID + SteamID64Int )
	end

	function Shine.SteamID64ToNS2ID( SteamID64 )
		local UsableInt = tonumber( StringSub( SteamID64, RemovedDigits ) )
		return UsableInt - SteamID64Int
	end
end

function Shine:GetClientBySteamID( ID )
	if not IsType( ID, "string" ) then return nil end

	local NS2ID = self.SteamIDToNS2( ID )
	if not NS2ID then return nil end

	return self.GetClientByNS2ID( NS2ID )
end

do
	-- Only accept positive base-10 integer values, no hex, no inf, no nan.
	local function SafeToNumber( String )
		if IsType( String, "number" ) then return String end
		if not StringMatch( String, "^[0-9]+$" ) then return nil end
		return tonumber( String )
	end
	Shine.CoerceToID = SafeToNumber

	--[[
		Returns a client matching the given Steam ID or name.
	]]
	function Shine:GetClient( String )
		local NumberValue = SafeToNumber( String )
		if NumberValue then
			-- Do not look up by name if provided a number, only NS2ID and game ID.
			-- Use NS2ID first as the admin menu uses it.
			return self.GetClientByNS2ID( NumberValue ) or self.GetClientByID( NumberValue )
		end

		return self:GetClientBySteamID( String ) or self.GetClientByName( tostring( String ) )
	end
end

--[[
	Returns all clients with access to the given string.
]]
function Shine:GetClientsWithAccess( Access )
	local Ret = {}
	local Count = 0

	for Client in self.IterateClients() do
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

	local Count = 0
	local Ret = {}

	for Client in self.IterateClients() do
		if self:IsInGroup( Client, Group ) then
			Count = Count + 1
			Ret[ Count ] = Client
		end
	end

	return Ret
end

local ConsoleInfo = "Console[N/A]"

function Shine.GetClientInfo( Client )
	if not Client then return ConsoleInfo end

	local Player = Client:GetControllingPlayer()

	if not Player then
		return StringFormat( "Unknown[%d]", Client:GetUserId() )
	end

	return StringFormat( "%s[%d]", Player:GetName(), Client:GetUserId() )
end

function Shine.GetClientName( Client )
	if not Client then return "Console" end

	local Player = Client:GetControllingPlayer()
	if not Player then return "Unknown" end

	return Player:GetName()
end
