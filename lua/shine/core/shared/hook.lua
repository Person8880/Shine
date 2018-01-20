--[[
	Shine internal hook system.
]]

local Shine = Shine

local Clamp = math.Clamp
local DebugSetUpValue = debug.setupvalue
local Floor = math.floor
local IsCallable = Shine.IsCallable
local IsType = Shine.IsType
local xpcall = xpcall
local ReplaceMethod = Shine.ReplaceClassMethod
local StringExplode = string.Explode
local StringFormat = string.format

local Map = Shine.Map

local Hook = {}
Shine.Hook = Hook

local Hooks = {}
local ReservedNames = {}

--[[
	Removes a function from Shine's internal hook system.
	Inputs: Event, unique identifier.
]]
local function Remove( Event, Index )
	local EventHooks = Hooks[ Event ]
	if not EventHooks then return end

	local Priority = ReservedNames[ Event ][ Index ]
	if not Priority then return end

	EventHooks[ Priority ]:Remove( Index )
	ReservedNames[ Event ][ Index ] = nil
end
Hook.Remove = Remove

--[[
	Adds a function to Shine's internal hook system.
	Inputs: Event to hook into, unique identifier, function to run, optional priority.
]]
local function Add( Event, Index, Function, Priority )
	Shine.AssertAtLevel( Event ~= nil, "Event identifier must not be nil!", 3 )
	Shine.AssertAtLevel( Index ~= nil, "Index must not be nil!", 3 )
	Shine.AssertAtLevel( IsCallable( Function ), "Function must be callable!", 3 )
	if Priority ~= nil then
		Shine.TypeCheck( Priority, "number", 4, "Add" )
	end

	Priority = Clamp( Floor( Priority or 0 ), -20, 20 )

	if not Hooks[ Event ] then
		Hooks[ Event ] = {}
		ReservedNames[ Event ] = {}
	end

	if ReservedNames[ Event ][ Index ] then
		Remove( Event, Index )
	end

	if not Hooks[ Event ][ Priority ] then
		Hooks[ Event ][ Priority ] = Map()
	end

	Hooks[ Event ][ Priority ]:Add( Index, Function )
	ReservedNames[ Event ][ Index ] = Priority
end
Hook.Add = Add

local OnError = Shine.BuildErrorHandler( "Hook error" )

local function CallHooks( HookMap, Event, ... )
	for Index, Func in HookMap:Iterate() do
		local Success, a, b, c, d, e, f = xpcall( Func, OnError, ... )

		if not Success then
			Shine:DebugPrint( "[Hook Error] %s hook '%s' failed, removing.",
				true, Event, Index )

			Remove( Event, Index )
		else
			if a ~= nil then return a, b, c, d, e, f end
		end
	end
end

-- Placeholder until the extensions file is loaded.
if not Shine.CallExtensionEvent then
	Shine.CallExtensionEvent = function() end
end

--[[
	Calls an internal Shine hook.
	Inputs: Event name, arguments to pass.
]]
local function Call( Event, ... )
	if Hook.Disabled then return end

	local Hooked = Hooks[ Event ]

	do
		local MaxPriority = Hooked and Hooked[ -20 ]
		-- Call max priority hooks BEFORE plugins.
		if MaxPriority then
			local a, b, c, d, e, f = CallHooks( MaxPriority, Event, ... )
			if a ~= nil then return a, b, c, d, e, f end
		end
	end

	-- Now call plugins (when loaded).
	do
		local a, b, c, d, e, f = Shine:CallExtensionEvent( Event, OnError, ... )
		if a ~= nil then return a, b, c, d, e, f end
	end

	if not Hooked then return end

	for i = -19, 20 do
		local HookMap = Hooked[ i ]

		if HookMap then
			local a, b, c, d, e, f = CallHooks( HookMap, Event, ... )
			if a ~= nil then return a, b, c, d, e, f end
		end
	end
end
Hook.Call = Call

local function CallOnce( Event, ... )
	local a, b, c, d, e, f = Call( Event, ... )

	Hooks[ Event ] = nil
	ReservedNames[ Event ] = nil

	return a, b, c, d, e, f
end
Hook.CallOnce = CallOnce

function Hook.GetTable()
	return Hooks
end

--[[
	Replaces the given method in the given class with ReplacementFunc.

	Inputs: Class name, method name, replacement function.
	Output: Original function.
]]
local function AddClassHook( ReplacementFunc, Class, Method )
	local OldFunc

	OldFunc = ReplaceMethod( Class, Method, function( ... )
		return ReplacementFunc( OldFunc, ... )
	end )

	return OldFunc
end

--[[
	Replaces the given global function with ReplacementFunc.

	Inputs: Global function name, replacement function.
	Output: Original function.
]]
local function AddGlobalHook( ReplacementFunc, FuncName )
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

--[[
	All available preset hooking methods:

	- Replace: Replaces the function with a Shine hook call.

	- PassivePre: Calls the given Shine hook, then runs the
	original function and returns its value(s).

	- PassivePost: Runs and stores the return values of the original function,
	then calls the Shine hook, then returns the original return values.

	- ActivePre: Calls the given Shine hook and returns its values if it returned any.
	Otherwise it returns the original function's values.

	- ActivePost: Runs and stores the return values of the original function,
	then calls the Shine hook. If the Shine hook returned values, they are returned.
	Otherwise, the original values are returned.

	- Halt: Calls the given Shine hook. If it returns a non-nil value,
	the method is stopped and returns nothing. Otherwise the original method is returned.
]]
local HookModes = {
	Replace = function( Adder, HookName, ... )
		Adder( function( OldFunc, ... )
			return Call( HookName, ... )
		end, ... )
	end,
	PassivePre = function( Adder, HookName, ... )
		Adder( function( OldFunc, ... )
			Call( HookName, ... )

			return OldFunc( ... )
		end, ... )
	end,
	PassivePost = function( Adder, HookName, ... )
		Adder( function( OldFunc, ... )
			local a, b, c, d, e, f = OldFunc( ... )

			Call( HookName, ... )

			return a, b, c, d, e, f
		end, ... )
	end,

	ActivePre = function( Adder, HookName, ... )
		Adder( function( OldFunc, ... )
			local a, b, c, d, e, f = Call( HookName, ... )

			if a ~= nil then
				return a, b, c, d, e, f
			end

			return OldFunc( ... )
		end, ... )
	end,

	ActivePost = function( Adder, HookName, ... )
		Adder( function( OldFunc, ... )
			local a, b, c, d, e, f = OldFunc( ... )

			local g, h, i, j, k, l = Call( HookName, ... )

			if g ~= nil then
				return g, h, i, j, k, l
			end

			return a, b, c, d, e, f
		end, ... )
	end,

	Halt = function( Adder, HookName, ... )
		Adder( function( OldFunc, ... )
			local Ret = Call( HookName, ... )

			if Ret ~= nil then return end

			return OldFunc( ... )
		end, ... )
	end
}

--[[
	Sets up a Shine hook for a class method.

	Inputs:
		1. Class name.
		2. Method name.
		3. Shine hook name to call when this method is run.
		4. Mode to hook with.

	Output: Original function we have now replaced.

	Mode can either be a string from the HookModes table above,
	or it can be a custom hook function.

	The function will be passed the original function, then the arguments it was run with.
]]
local function SetupClassHook( Class, Method, HookName, Mode )
	if IsType( Mode, "function" ) then
		return AddClassHook( Mode, Class, Method )
	end

	local HookFunc = HookModes[ Mode ]
	if not HookFunc then return nil end

	return HookFunc( AddClassHook, HookName, Class, Method )
end
Hook.SetupClassHook = SetupClassHook

--[[
	Sets up a Shine hook for a global function.

	Inputs:
		1. Global function name.
		2. Mode to hook with.

	Output: Original function we have now replaced.

	Mode can either be a string from the HookModes table above,
	or it can be a custom hook function.

	The function will be passed the original function, then the arguments it was run with.
]]
local function SetupGlobalHook( FuncName, HookName, Mode )
	if IsType( Mode, "function" ) then
		return AddGlobalHook( Mode, FuncName )
	end

	local HookFunc = HookModes[ Mode ]
	if not HookFunc then return nil end

	return HookFunc( AddGlobalHook, HookName, FuncName )
end
Hook.SetupGlobalHook = SetupGlobalHook

--[[
	Replaces a function upvalue in the upvalues of TargetFunc.
	Your replacement receives a copy of every upvalue from the original function.

	Inputs:
		1. Function to grab the upvalue from.
		2. Name of the upvalue function you want to replace.
		3. The replacement function you want to use.
		4. Any upvalues you want to change for your replacement version.
		5. Should said upvalues be replaced recursively?

	Output:
		The original function that has now been replaced.
]]
function Hook.ReplaceLocalFunction( TargetFunc, UpvalueName, Replacement, DifferingValues, Recursive )
	local Value, i, Func = Shine.GetUpValue( TargetFunc, UpvalueName )

	if not Value or not IsType( Value, "function" ) then return end

	--Copy all the upvalues from the original function to our replacement.
	Shine.MimicFunction( Value, Replacement, DifferingValues, Recursive )

	--Now replace the local function in the original location with our replacement version.
	DebugSetUpValue( Func or TargetFunc, i, Replacement )

	return Value
end

do
	--[[
		Event hooks.
	]]
	local function Think( DeltaTime )
		Call( "Think", DeltaTime )
	end
	Event.Hook( Server and "UpdateServer" or "UpdateClient", Think )
end

do
	local OldScriptLoad = Script.Load

	--Override Script.Load during the load process to allow finer entry point control.
	local function ScriptLoad( Script, Reload )
		Call( "PreLoadScript", Script, Reload )

		local Ret = OldScriptLoad( Script, Reload )

		Call( "PostLoadScript", Script, Reload )

		return Ret
	end
	Script.Load = ScriptLoad

	local function MapPreLoad()
		--Restore Script.Load so we don't bog it down anymore.
		if Script.Load == ScriptLoad then
			Script.Load = OldScriptLoad
		else
			--Find the point that overrode our override, and replace their upvalue of us, with the original.
			Shine.SetUpValueByValue( Script.Load, ScriptLoad, OldScriptLoad, true )
		end

		CallOnce "MapPreLoad"
	end
	Event.Hook( "MapPreLoad", MapPreLoad )

	local function MapPostLoad()
		CallOnce "MapPostLoad"
	end
	Event.Hook( "MapPostLoad", MapPostLoad )
end

--Client specific hooks.
if Client then
	local function LoadComplete()
		CallOnce "OnMapLoad"
	end
	Event.Hook( "LoadComplete", LoadComplete )

	local function OnClientDisconnected( Reason )
		Call( "ClientDisconnected", Reason )
	end
	Event.Hook( "ClientDisconnected", OnClientDisconnected )

	--Need to hook the GUI manager, hooking the events directly blocks all input for some reason...
	Add( "OnMapLoad", "HookGUIEvents", function()
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

		local OldResChange = GUIManager.OnResolutionChanged

		function GUIManager:OnResolutionChanged( OldX, OldY, NewX, NewY )
			Call( "PreOnResolutionChanged", OldX, OldY, NewX, NewY )

			OldResChange( self, OldX, OldY, NewX, NewY )

			Call( "OnResolutionChanged", OldX, OldY, NewX, NewY )
		end

		SetupGlobalHook( "ChatUI_EnterChatMessage", "StartChat", "ActivePre" )
		SetupGlobalHook( "CommanderUI_Logout", "OnCommanderUILogout", "PassivePost" )

		SetupClassHook( "HelpScreen", "Display", "OnHelpScreenDisplay", "PassivePost" )
		SetupClassHook( "HelpScreen", "Hide", "OnHelpScreenHide", "PassivePost" )
	end, -20 )

	Add( "Think", "ClientOnFirstThink", function()
		CallOnce( "OnFirstThink" )
		Remove( "Think", "ClientOnFirstThink" )
	end )

	return
end

do
	local function ClientConnect( Client )
		Call( "ClientConnect", Client )
	end
	Event.Hook( "ClientConnect", ClientConnect )

	local function ClientDisconnect( Client )
		Call( "ClientDisconnect", Client )
	end
	Event.Hook( "ClientDisconnect", ClientDisconnect )

	local function MapLoadEntity( MapName, GroupName, Values )
		Call( "MapLoadEntity", MapName, GroupName, Values )
	end
	Event.Hook( "MapLoadEntity", MapLoadEntity )
end

do
	local OldEventHook = Event.Hook
	local OldReservedSlot

	local function CheckConnectionAllowed( ID )
		local Result, Reason = Call( "CheckConnectionAllowed", ID )

		if Result ~= nil then return Result, Reason end

		return OldReservedSlot( ID )
	end

	--[[
		Detour the event hook function so we can override the result of
		CheckConnectionAllowed. Otherwise it would return the default function's value
		and never call our hook.
	]]
	function Event.Hook( Name, Func )
		local Override, NewFunc = Call( "NS2EventHook", Name, Func )

		if Override then
			return OldEventHook( Name, NewFunc )
		end

		if Name ~= "CheckConnectionAllowed" then
			return OldEventHook( Name, Func )
		end

		OldReservedSlot = Func

		Func = CheckConnectionAllowed

		return OldEventHook( Name, Func )
	end
end

do
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
end

--[[
	Hook to run after everything has loaded.
	Here we replace class methods in order to hook into certain important events.
]]
Add( "Think", "ReplaceMethods", function()
	Remove( "Think", "ReplaceMethods" )

	SetupGlobalHook( "GetHasReservedSlotAccess", "HasReservedSlotAccess", "ActivePre" )

	local Gamerules = "NS2Gamerules"

	--For the factions mod.
	if FactionGamerules then
		Gamerules = "FactionGamerules"
	end

	SetupClassHook( "Player", "OnProcessMove", "OnProcessMove", "PassivePre" )
	SetupClassHook( "Player", "SetName", "PlayerNameChange", function( OldFunc, self, Name )
		local OldName = self:GetName()

		OldFunc( self, Name )

		Call( "PlayerNameChange", self, Name, OldName )
	end )

	SetupClassHook( "Spectator", "OnProcessMove", "OnProcessMove", "PassivePre" )

	SetupClassHook( Gamerules, "EndGame", "EndGame", "PassivePre" )
	SetupClassHook( Gamerules, "OnEntityKilled", "OnEntityKilled", "PassivePre" )

	if not Shine.IsNS2Combat then
		SetupClassHook( "CommandStructure", "LoginPlayer", "CommLoginPlayer", "PassivePre" )
		SetupClassHook( "CommandStructure", "Logout", "CommLogout", "PassivePre" )
		SetupClassHook( "CommandStructure", "OnUse", "CheckCommLogin", "ActivePre" )

		SetupClassHook( "RecycleMixin", "OnResearch", "OnRecycle", "PassivePre" )
		SetupClassHook( "RecycleMixin", "OnResearchComplete", "OnBuildingRecycled", "PassivePre" )

		SetupClassHook( "Commander", "ProcessTechTreeActionForEntity", "OnCommanderTechTreeAction",
			"PassivePre" )
		SetupClassHook( "Commander", "TriggerNotification", "OnCommanderNotify", "PassivePre" )
	end

	SetupClassHook( "ConstructMixin", "OnInitialized", "OnConstructInit", "PassivePre" )

	SetupClassHook( Gamerules, "UpdatePregame", "UpdatePregame", "Halt" )
	SetupClassHook( Gamerules, "UpdateWarmUp", "UpdateWarmUp", "Halt" )
	SetupClassHook( Gamerules, "CheckGameStart", "CheckGameStart", "Halt" )
	SetupClassHook( Gamerules, "CastVoteByPlayer", "CastVoteByPlayer", "Halt" )
	SetupClassHook( Gamerules, "SetGameState", "SetGameState", function( OldFunc, self, State )
		local CurState = self.gameState

		OldFunc( self, State )

		Call( "SetGameState", self, State, CurState )
	end )
	SetupClassHook( Gamerules, "ResetGame", "ResetGame", "PassivePost" )
	SetupClassHook( Gamerules, "GetCanPlayerHearPlayer", "CanPlayerHearPlayer", "ActivePre" )
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

		local Bool, NewPlayer = OldFunc( self, Player, NewTeam, Force )

		if Bool then
			Call( "PostJoinTeam", self, NewPlayer, OldTeam, NewTeam, Force, ShineForce )
		end

		return Bool, NewPlayer or Player
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

	function MapCycle_CycleMap( CurrentMap )
		local Result = Call( "OnCycleMap" )

		if Result ~= nil then return end

		Call( "MapChange" )

		return OldCycleMap( CurrentMap )
	end

	local OldTestCycle = MapCycle_TestCycleMap

	function MapCycle_TestCycleMap()
		local Result = Call( "ShouldCycleMap" )

		if Result ~= nil then return Result end

		return OldTestCycle()
	end

	local OldStartVote = StartVote
	if OldStartVote then
		StartVote = function( VoteName, Client, Data )
			if Call( "NS2StartVote", VoteName, Client, Data ) == false then
				Shine.SendNetworkMessage( Client, "VoteCannotStart", {
					reason = kVoteCannotStartReason.DisabledByAdmin
				}, true )

				return
			end

			return OldStartVote( VoteName, Client, Data )
		end

		Shine.StartNS2Vote = OldStartVote
	end

	CallOnce( "OnFirstThink" )
end )
