--[[
	Shine internal hook system.
]]

local Clamp = math.Clamp
local Floor = math.floor
local ReplaceMethod = Shine.ReplaceClassMethod
local StringExplode = string.Explode
local type = type
local unpack = unpack

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
	Priority = Clamp( Floor( tonumber( Priority ) or 0 ), -20, 20 )

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
	if Shine.Hook.Disabled then return end
	
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

local function AddClassHook( Class, Method, ReplacementFunc )
	local OldFunc

	OldFunc = ReplaceMethod( Class, Method, function( ... )
		return ReplacementFunc( OldFunc, ... )
	end )

	return OldFunc
end

local function AddGlobalHook( FuncName, ReplacementFunc )
	local Path = StringExplode( FuncName, "%." )

	local Func = _G
	local i = 1
	local Prev

	repeat
		Prev = Func

		Func = Func[ Path[ i ] ]

		--Doesn't exist!
		if not Func then return end

		i = i + 1
	until not Path[ i ]

	Prev[ Path[ i - 1 ] ] = function( ... )
		return ReplacementFunc( Func, ... )
	end

	return Func
end

local ClassHookModes = {
	Replace = function( Class, Method, HookName )
		AddClassHook( Class, Method, function( OldFunc, ... )
			return Call( HookName, ... )
		end )
	end,

	PassivePre = function( Class, Method, HookName )
		AddClassHook( Class, Method, function( OldFunc, ... )
			Call( HookName, ... )

			return OldFunc( ... )
		end )
	end,

	PassivePost = function( Class, Method, HookName )
		AddClassHook( Class, Method, function( OldFunc, ... )
			local Ret = { OldFunc( ... ) }

			Call( HookName, ... )

			return unpack( Ret )
		end )
	end,

	ActivePre = function( Class, Method, HookName )
		AddClassHook( Class, Method, function( OldFunc, ... )
			local Ret = { Call( HookName, ... ) }

			if Ret[ 1 ] then
				return unpack( Ret )
			end

			return OldFunc( ... )
		end )
	end,

	ActivePost = function( Class, Method, HookName )
		AddClassHook( Class, Method, function( OldFunc, ... )
			local Ret = { OldFunc( ... ) }

			local NewRet = { Call( HookName, ... ) }

			if NewRet[ 1 ] then
				return unpack( NewRet )
			end

			return unpack( Ret )
		end )
	end,

	Halt = function( Class, Method, HookName )
		AddClassHook( Class, Method, function( OldFunc, ... )
			local Ret = Call( HookName, ... )

			if Ret ~= nil then return end

			return OldFunc( ... )
		end )
	end
}

local GlobalHookModes = {
	Replace = function( FuncName, HookName )
		AddGlobalHook( FuncName, function( OldFunc, ... )
			return Call( HookName, ... )
		end )
	end,

	PassivePre = function( FuncName, HookName )
		AddGlobalHook( FuncName, function( OldFunc, ... )
			Call( HookName, ... )

			return OldFunc( ... )
		end )
	end,

	PassivePost = function( FuncName, HookName )
		AddGlobalHook( FuncName, function( OldFunc, ... )
			local Ret = { OldFunc( ... ) }

			Call( HookName, ... )

			return unpack( Ret )
		end )
	end,

	ActivePre = function( FuncName, HookName )
		AddGlobalHook( FuncName, function( OldFunc, ... )
			local Ret = { Call( HookName, ... ) }

			if Ret[ 1 ] then
				return unpack( Ret )
			end

			return OldFunc( ... )
		end )
	end,

	ActivePost = function( FuncName, HookName )
		AddGlobalHook( FuncName, function( OldFunc, ... )
			local Ret = { OldFunc( ... ) }

			local NewRet = { Call( HookName, ... ) }

			if NewRet[ 1 ] then
				return unpack( NewRet )
			end

			return unpack( Ret )
		end )
	end
}

local function isfunction( Func )
	return type( Func ) == "function"
end

local function SetupClassHook( Class, Method, HookName, Mode )
	if isfunction( Mode ) then
		return AddClassHook( Class, Method, Mode )
	end

	local HookFunc = ClassHookModes[ Mode ]

	if not HookFunc then return nil end

	return HookFunc( Class, Method, HookName )
end
Shine.Hook.SetupClassHook = SetupClassHook

local function SetupGlobalHook( FuncName, HookName, Mode )
	if isfunction( Mode ) then
		return AddGlobalHook( FuncName, Mode )
	end

	local HookFunc = GlobalHookModes[ Mode ]

	if not HookFunc then return nil end
	
	return HookFunc( FuncName, HookName )
end
Shine.Hook.SetupGlobalHook = SetupGlobalHook

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
	local Gamerules = Shine.Config.GameRules or "NS2Gamerules"

	SetupClassHook( "Player", "OnProcessMove", "OnProcessMove", "PassivePre" )
	SetupClassHook( "Player", "SetName", "PlayerNameChange", function( OldFunc, self, Name )
		local OldName = self:GetName()

		OldFunc( self, Name )

		Call( "PlayerNameChange", self, Name, OldName )
	end )

	SetupClassHook( "Spectator", "OnProcessMove", "OnProcessMove", "PassivePre" )

	SetupClassHook( Gamerules, "EndGame", "EndGame", "PassivePre" )
	SetupClassHook( Gamerules, "OnEntityKilled", "OnEntityKilled", "PassivePre" )

	SetupClassHook( "CommandStructure", "LoginPlayer", "CommLoginPlayer", "PassivePre" )
	SetupClassHook( "CommandStructure", "Logout", "CommLogout", "PassivePre" )

	SetupClassHook( "RecycleMixin", "OnResearch", "OnRecycle", "PassivePre" )
	SetupClassHook( "RecycleMixin", "OnResearchComplete", "OnBuildingRecycled", "PassivePre" )

	SetupClassHook( "ConstructMixin", "OnInitialized", "OnConstructInit", "PassivePre" )
	
	SetupClassHook( Gamerules, "UpdatePregame", "UpdatePregame", "Halt" )
	SetupClassHook( Gamerules, "CheckGameStart", "CheckGameStart", "Halt" )
	SetupClassHook( Gamerules, "CastVoteByPlayer", "CastVoteByPlayer", "Halt" )
	SetupClassHook( Gamerules, "SetGameState", "SetGameState", function( OldFunc, self, State )
		local CurState = self.gameState

		OldFunc( self, State )

		Call( "SetGameState", self, State, CurState )
	end )
	SetupClassHook( Gamerules, "GetCanPlayerHearPlayer", "CanPlayerHearPlayer", function( OldFunc, self, Listener, Speaker )
		local Result = Call( "CanPlayerHearPlayer", self, Listener, Speaker )

		if Result ~= nil then return Result end
		
		return OldFunc( self, Listener, Speaker )
	end )
	SetupClassHook( Gamerules, "JoinTeam", "JoinTeam", function( OldFunc, self, Player, NewTeam, Force, ShineForce )
		local Override, OverrideTeam = Call( "JoinTeam", self, Player, NewTeam, Force, ShineForce )

		if Override ~= nil then
			if Override then
				NewTeam = OverrideTeam
			else
				return false, Player
			end
		end

		local OldTeam = Player:GetTeamNumber()

		local Bool, Player = OldFunc( self, Player, NewTeam, Force )

		if Bool then
			Call( "PostJoinTeam", self, Player, OldTeam, NewTeam, Force, ShineForce )
		end

		return Bool, Player
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
