--[[
	Shine internal hook system.
]]

local Clamp = math.Clamp

local TableInsert = table.insert
local TableRemove = table.remove
local TableSort = table.sort

Shine.Hook = {}

local Hooks = {}

--[[
	Sorts the hook list.
]]
local function SortHooks( Event )
	if not Event then return end

	TableSort( Hooks[ Event ], function( A, B ) 
		if A == nil then return false end
		if B == nil then return true end
		if A.Priority < B.Priority then return true end
		if A.Priority == B.Priority and tostring( A.Index ) < tostring( B.Index ) then return true end
		return false
	end )
end

--[[
	Adds a function to Shine's internal hook system.
	Inputs: Event to hook into, unique identifier, function to run, optional priority.
]]
local function Add( Event, Index, Function, Priority )
	Priority = tonumber( Priority ) or 0

	if not Hooks[ Event ] then
		Hooks[ Event ] = {}
	end

	TableInsert( Hooks[ Event ], { Index = Index, Func = Function, Priority = Clamp( Priority, -20, 20 ) } )

	SortHooks( Event )	
end
Shine.Hook.Add = Add

--[[
	Removes a function from Shine's internal hook system.
	Inputs: Event, unique identifier.
]]
local function Remove( Event, Index )
	local EventHooks = Hooks[ Event ]

	if not EventHooks then return end
	
	for i = 1, #EventHooks do
		local Hook = EventHooks[ i ]

		if Hook and Hook.Index == Index then
			EventHooks[ i ] = nil
			return
		end
	end
end
Shine.Hook.Remove = Remove

--[[
	Calls an internal Shine hook.
	Inputs: Event name, arguments to pass.
]]
local function Call( Event, ... )
	local Plugins = Shine.Plugins

	if Plugins then
		--Automatically call the plugin hooks.
		for Plugin, Table in pairs( Plugins ) do
			if Table.Enabled then
				if Table[ Event ] and type( Table[ Event ] ) == "function" then
					local Result = { Table[ Event ]( Table, ... ) }
					if Result[ 1 ] ~= nil then return Result end
				end
			end
		end
	end

	local Hooked = Hooks[ Event ]

	if not Hooked then return end

	SortHooks( Event )

	for i = 1, #Hooked do
		if Hooked[ i ] then
			local Result = { Hooked[ i ].Func( ... ) }
			if Result[ 1 ] ~= nil then return Result end
		end
	end
end
Shine.Hook.Call = Call

--[[
	Event hooks.
]]
local function UpdateServer( DeltaTime )
	Call( "Think", DeltaTime )
end
Event.Hook( "UpdateServer", UpdateServer )

local function ClientConnect( Client )
	Call( "ClientConnect", Client )
end
Event.Hook( "ClientConnect", ClientConnect )

local function ClientDisconnect( Client )
	Call( "ClientDisconnect", Client )
end
Event.Hook( "ClientDisconnect", ClientDisconnect )

--Taken straight from NetworkMessages_Server.lua
local function GetChatPlayerData(client)
	local playerName = "Admin"
	local playerLocationId = -1
	local playerTeamNumber = kTeamReadyRoom
	local playerTeamType = kNeutralTeamType
	
	if client then
		local player = client:GetControllingPlayer()
		if not player then
			return
		end
		playerName = player:GetName()
		playerLocationId = player.locationId
		playerTeamNumber = player:GetTeamNumber()
		playerTeamType = player:GetTeamType()
	end

	return playerName, playerLocationId, playerTeamNumber, playerTeamType
end

local OldOnChatReceive

local function OnChatReceived( client, message )
	chatMessage = string.sub(message.message, 1, kMaxChatLength)

	--Combat mode stuff.
	local CombatMessage

	if combatCommands then
		for i, entry in pairs( combatCommands ) do
			if chatMessage:sub( 1, #entry ) == entry then
			   CombatMessage = true 
			   break
			end
		end   

		if CombatMessage then
			local player = client:GetControllingPlayer()
			Server.ClientCommand( player, chatMessage )

			return
		end
	end

	if chatMessage and string.len(chatMessage) > 0 then
		--Begin modification to hook directly into the chat.
		local Result = Call( "PlayerSay", client, message )
		if Result then
			if Result[ 1 ] == "" then return end
			chatMessage = Result[ 1 ]:sub( 1, kMaxChatLength )
		end
	
		local playerName, playerLocationId, playerTeamNumber, playerTeamType = GetChatPlayerData(client)
		
		if playerName then
		
			if message.teamOnly then
			
				local players = GetEntitiesForTeam("Player", playerTeamNumber)
				for index, player in ipairs(players) do
					Server.SendNetworkMessage(player, "Chat", BuildChatMessage(true, playerName, playerLocationId, playerTeamNumber, playerTeamType, chatMessage), true)
				end
				
			else
				Server.SendNetworkMessage("Chat", BuildChatMessage(false, playerName, playerLocationId, playerTeamNumber, playerTeamType, chatMessage), true)
			end
			
			Shared.Message("Chat " .. (message.teamOnly and "Team - " or "All - ") .. playerName .. ": " .. chatMessage)
			
			Server.AddChatToHistory(chatMessage, playerName, client:GetUserId(), playerTeamNumber, message.teamOnly)
			
		end
	end
end

local OriginalHookNWMessage = Server.HookNetworkMessage

function Server.HookNetworkMessage( Message, Callback )
	if Message == "ChatClient" then
		OldOnChatReceive = Callback
		Callback = OnChatReceived
	end

	OriginalHookNWMessage( Message, Callback )
end

--[[
	Hook to run after everything has loaded. 
	Here we replace class methods in order to hook into certain important events.
]]
Add( "Think", "ReplaceMethods", function()
	local ReplaceMethod = Shine.ReplaceClassMethod
	local Gamerules = Shine.Config.GameRules or "NS2Gamerules"

	local OldJoinTeam

	OldJoinTeam = ReplaceMethod( Gamerules, "JoinTeam", function( self, Player, NewTeam, Force, ShineForce )
		local Result = Call( "JoinTeam", self, Player, NewTeam, Force, ShineForce )

		if Result then
			if Result[ 1 ] then
				NewTeam = Result[ 2 ]
			else
				return
			end
		end

		return OldJoinTeam( self, Player, NewTeam, Force )
	end )

	local OldEndGame

	OldEndGame = ReplaceMethod( Gamerules, "EndGame", function( self, WinningTeam ) 
		Call( "EndGame", self, WinningTeam )

		return OldEndGame( self, WinningTeam )
	end )

	local OldEntityKilled

	OldEntityKilled = ReplaceMethod( Gamerules, "OnEntityKilled", function( self, TargetEnt, Attacker, Inflictor, Point, Dir )
		Call( "OnEntityKilled", self, TargetEnt, Attacker, Inflictor, Point, Dir )
		
		return OldEntityKilled( self, TargetEnt, Attacker, Inflictor, Point, Dir )
	end )

	local OldPreGame

	OldPreGame = ReplaceMethod( Gamerules, "UpdatePregame", function( self, TimePassed ) 
		local Result = Call( "UpdatePregame", self, TimePassed )

		if Result then return end
		
		return OldPreGame( self, TimePassed )
	end )

	local OldCheckGameStart

	OldCheckGameStart = ReplaceMethod( Gamerules, "CheckGameStart", function( self )
		local Result = Call( "CheckGameStart", self )

		if Result then return end
		
		return OldCheckGameStart( self )
	end )

	local OldCastVote

	OldCastVote = ReplaceMethod( Gamerules, "CastVoteByPlayer", function( self, VoteTechID, Player )
		local Result = Call( "CastVoteByPlayer", self, VoteTechID, Player )

		if Result then return end
		
		OldCastVote( self, VoteTechID, Player )
	end )

	local OldSetGameState

	OldSetGameState = ReplaceMethod( Gamerules, "SetGameState", function( self, State ) 
		local CurState = self.gameState

		OldSetGameState( self, State )

		Call( "SetGameState", self, State, CurState )
	end )

	local OldCanHear

	OldCanHear = ReplaceMethod( Gamerules, "GetCanPlayerHearPlayer", function( self, Listener, Speaker )
		local Result = Call( "CanPlayerHearPlayer", self, Listener, Speaker )

		if Result then return Result[ 1 ] end
		
		return OldCanHear( self, Listener, Speaker )
	end )

	local OldLoginPlayer
		
	OldLoginPlayer = ReplaceMethod( "CommandStructure", "LoginPlayer", function( self, Player )
		Call( "CommLoginPlayer", self, Player )

		return OldLoginPlayer( self, Player )
	end )
	
	local OldLogout
	
	OldLogout = ReplaceMethod( "CommandStructure", "Logout", function( self )
		Call( "CommLogout", self )

		return OldLogout( self )
	end )
	
	local OldOnResearchComplete
	
	OldOnResearchComplete = ReplaceMethod( "RecycleMixin", "OnResearchComplete", function( self, ResearchID )
		Call( "OnBuildingRecycled", self, ResearchID )

		return OldOnResearchComplete( self, ResearchID )
	end )
	
	local OldOnResearch
	
	OldOnResearch = ReplaceMethod( "RecycleMixin", "OnResearch", function( self, ResearchID ) 
		Call( "OnRecycle", self, ResearchID )

		return OldOnResearch( self, ResearchID )
	end )
	
	local OldConstructInit
	
	OldConstructInit = ReplaceMethod( "ConstructMixin", "OnInitialized", function( self )
		Call( "OnConstructInit", self )

		return OldConstructInit( self )
	end )

	local OldPlayerSetName

	OldPlayerSetName = ReplaceMethod( "Player", "SetName", function( self, Name )
		local OldName = self:GetName()

		OldPlayerSetName( self, Name )

		Call( "PlayerNameChange", self, Name, OldName )
	end )

	local OldCycleMap = MapCycle_CycleMap
	local OldChangeMap = MapCycle_ChangeMap

	if not OldCycleMap then
		Script.Load "lua/MapCycle.lua"
		OldCycleMap = MapCycle_CycleMap
		OldChangeMap = MapCycle_ChangeMap
	end

	function MapCycle_ChangeMap( MapName )
		Call( "MapChange" )

		return OldChangeMap( MapName )
	end

	function MapCycle_CycleMap()
		local Result = Call( "OnCycleMap" )

		if Result then return end

		Call( "MapChange" )

		return OldCycleMap()
	end

	local OldTestCycle = MapCycle_TestCycleMap

	function MapCycle_TestCycleMap()
		local Result = Call( "ShouldCycleMap" )

		if Result then return Result[ 1 ] end

		return OldTestCycle()
	end

	Remove( "Think", "ReplaceMethods" )
end )

--[[
	Fix for NS2Stats way of overriding gamerules functions.
]]
Add( "ClientConnect", "ReplaceOnKilled", function( Client )
	if not RBPS then 
		Remove( "ClientConnect", "ReplaceOnKilled" )
		
		return 
	end

	--They override the gamerules entity instead of the gamerules class...
	local Ents = Shared.GetEntitiesWithClassname( "NS2Gamerules" )
	local Gamerules = Ents:GetEntityAtIndex( 0 )

	local OldOnEntityKilled = Gamerules.OnEntityKilled

	function Gamerules:OnEntityKilled( TargetEnt, Attacker, Inflictor, Point, Dir )
		Call( "OnEntityKilled", self, TargetEnt, Attacker, Inflictor, Point, Dir )
		
		return OldOnEntityKilled( self, TargetEnt, Attacker, Inflictor, Point, Dir )
	end

	Remove( "ClientConnect", "ReplaceOnKilled" )
end )
