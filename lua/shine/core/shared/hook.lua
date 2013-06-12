--[[
	Shine internal hook system.
]]

local Clamp = math.Clamp

local TableInsert = table.insert
local TableRemove = table.remove
local TableSort = table.sort

Shine.Hook = {}

local Hooks = {}
local ReservedNames = {}

--[[
	Removes a function from Shine's internal hook system.
	Inputs: Event, unique identifier.
]]
local function Remove( Event, Index )
	local EventHooks = Hooks[ Event ]

	if not EventHooks then return end
	
	for i = -20, 20 do
		local HookTable = EventHooks[ i ]

		if HookTable and HookTable[ Index ] then
			HookTable[ Index ] = nil

			return
		end
	end

	ReservedNames[ Event ][ Index ] = nil
end
Shine.Hook.Remove = Remove

--[[
	Adds a function to Shine's internal hook system.
	Inputs: Event to hook into, unique identifier, function to run, optional priority.
]]
local function Add( Event, Index, Function, Priority )
	Priority = tonumber( Priority ) or 0

	if not Hooks[ Event ] then
		Hooks[ Event ] = {}
		ReservedNames[ Event ] = {}
	end

	if ReservedNames[ Event ][ Index ] then
		Remove( Event, Index )
		ReservedNames[ Event ][ Index ] = nil
	end

	if not Hooks[ Event ][ Priority ] then
		Hooks[ Event ][ Priority ] = {}
	end

	Hooks[ Event ][ Priority ][ Index ] = Function

	ReservedNames[ Event ][ Index ] = true
end
Shine.Hook.Add = Add

--[[
	Calls an internal Shine hook.
	Inputs: Event name, arguments to pass.
]]
local function Call( Event, ... )
	local Plugins = Shine.Plugins

	local Hooked = Hooks[ Event ]

	local MaxPriority = Hooked and Hooked[ -20 ]

	--Call max priority hooks BEFORE plugins.
	if MaxPriority then
		for Index, Func in pairs( MaxPriority ) do
			local a, b, c, d, e = Func( ... )
			if a ~= nil then return a, b, c, d, e end
		end
	end

	if Plugins then
		--Automatically call the plugin hooks.
		for Plugin, Table in pairs( Plugins ) do
			if Table.Enabled then
				if Table[ Event ] and type( Table[ Event ] ) == "function" then
					local a, b, c, d, e = Table[ Event ]( Table, ... )
					if a ~= nil then return a, b, c, d, e end
				end
			end
		end
	end

	if not Hooked then return end

	for i = -19, 20 do
		local HookTable = Hooked[ i ]

		if HookTable then
			for Index, Func in pairs( HookTable ) do
				local a, b, c, d, e = Func( ... )
				if a ~= nil then return a, b, c, d, e end
			end
		end
	end
end
Shine.Hook.Call = Call

function Shine.Hook.GetTable()
	return Hooks
end

--[[
	Event hooks.
]]
local function UpdateServer( DeltaTime )
	Call( "Think", DeltaTime )
end
Event.Hook( Server and "UpdateServer" or "UpdateClient", UpdateServer )

--Client specific hooks.
if Client then
	local function LoadComplete()
		Call "OnMapLoad"
	end
	Event.Hook( "LoadComplete", LoadComplete )

	--Need to hook the GUI manager, hooking the events directly blocks all input for some reason...
	Add( "OnMapLoad", "Hook", function()
		local GUIManager = GetGUIManager()
		local OldSendKeyEvent = GUIManager.SendKeyEvent

		function GUIManager:SendKeyEvent( Key, Down, Amount )
			local Result = Call( "PlayerKeyPress", Key, Down, Amount )

			if Result then return true end

			return OldSendKeyEvent( self, Key, Down, Amount )
		end

		local OldSendCharacterEvent = GUIManager.SendCharacterEvent

		function GUIManager:SendCharacterEvent( Char )
			local Result = Call( "PlayerType", Char )

			if Result then return true end

			return OldSendCharacterEvent( self, Char )
		end
	end, -20 )

	return
end

local function ClientConnect( Client )
	Call( "ClientConnect", Client )
end
Event.Hook( "ClientConnect", ClientConnect )

local function ClientDisconnect( Client )
	Call( "ClientDisconnect", Client )
end
Event.Hook( "ClientDisconnect", ClientDisconnect )

local OldOnChatReceive

local function OnChatReceived( Client, Message )
	local Result = Call( "PlayerSay", Client, Message )
	if Result then
		if Result == "" then return end
		Message.message = Result
	end
	
	return OldOnChatReceive( Client, Message )
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

	local OldProcessMove

	OldProcessMove = ReplaceMethod( "Player", "OnProcessMove", function( self, Input )
		Call( "OnProcessMove", self, Input )

		return OldProcessMove( self, Input )
	end )

	local OldProcessSpecMove

	OldProcessSpecMove = ReplaceMethod( "Spectator", "OnProcessMove", function( self, Input )
		Call( "OnProcessMove", self, Input )

		return OldProcessSpecMove( self, Input )
	end )

	local OldJoinTeam

	OldJoinTeam = ReplaceMethod( Gamerules, "JoinTeam", function( self, Player, NewTeam, Force, ShineForce )
		local Override, OverrideTeam = Call( "JoinTeam", self, Player, NewTeam, Force, ShineForce )

		if Override ~= nil then
			if Override then
				NewTeam = OverrideTeam
			else
				return false, Player
			end
		end

		local OldTeam = Player:GetTeamNumber()

		local Bool, Player = OldJoinTeam( self, Player, NewTeam, Force )

		if Bool then
			Call( "PostJoinTeam", self, Player, OldTeam, NewTeam, Force, ShineForce )
		end

		return Bool, Player
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

		if Result ~= nil then return end
		
		return OldPreGame( self, TimePassed )
	end )

	local OldCheckGameStart

	OldCheckGameStart = ReplaceMethod( Gamerules, "CheckGameStart", function( self )
		local Result = Call( "CheckGameStart", self )

		if Result ~= nil then return end
		
		return OldCheckGameStart( self )
	end )

	local OldCastVote

	OldCastVote = ReplaceMethod( Gamerules, "CastVoteByPlayer", function( self, VoteTechID, Player )
		local Result = Call( "CastVoteByPlayer", self, VoteTechID, Player )

		if Result ~= nil then return end
		
		return OldCastVote( self, VoteTechID, Player )
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

		if Result ~= nil then return Result end
		
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

		if Result ~= nil then return end

		Call( "MapChange" )

		return OldCycleMap()
	end

	local OldTestCycle = MapCycle_TestCycleMap

	function MapCycle_TestCycleMap()
		local Result = Call( "ShouldCycleMap" )

		if Result ~= nil then return Result end

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
