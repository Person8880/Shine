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
	Adds a function to Shine's internal hook system.
	Inputs: Event to hook into, unique identifier, function to run, optional priority.
]]
local function Add( Event, Index, Function, Priority )
	Priority = tonumber( Priority ) or 0

	if not Hooks[ Event ] then
		Hooks[ Event ] = {}
	end

	TableInsert( Hooks[ Event ], { Index = Index, Func = Function, Priority = Clamp( Priority, -20, 20 ) } )

	TableSort( Hooks[ Event ], function( A, B ) return A.Priority < B.Priority end )
end
Shine.Hook.Add = Add

--[[
	Removes a function from Shine's internal hook system.
	Inputs: Event, unique identifier.
]]
function Shine.Hook.Remove( Event, Index )
	local EventHooks = Hooks[ Event ]

	if not EventHooks then return end
	
	for i = 1, #EventHooks do
		local Hook = EventHooks[ i ]

		if Hook.Index == Index then
			TableRemove( EventHooks, i )
			return
		end
	end
end

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

	for i = 1, #Hooked do
		local Result = { Hooked[ i ].Func( ... ) }
		if Result[ 1 ] ~= nil then return Result end
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

--[[
	Hook to run after the config file has loaded. 
	Here we replace class methods in order to hook into certain important events.
]]
Add( "PostloadConfig", "ReplaceMethods", function()
	local ReplaceMethod = Shine.ReplaceClassMethod
	local Gamerules = Shine.Config.GameRules or "NS2Gamerules"

	--An annoyingly hacky fix to CombatMode's complete override of the chat.
	if Shine.Config.CombatMode then
		local OldOnChatReceive

		local function OnChatReceived( client, message )
			chatMessage = string.sub(message.message, 1, kMaxChatLength)

			--Combat mode stuff.
			local CombatMessage

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

			if chatMessage and string.len(chatMessage) > 0 then
				--Begin modification to hook directly into the chat.
				local Result = Shine.Hook.Call( "PlayerSay", client, message )
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
	end

	local OldJoinTeam

	OldJoinTeam = ReplaceMethod( Gamerules, "JoinTeam", function( self, Player, NewTeam, Force )
		local Result = Call( "JoinTeam", self, Player, NewTeam, Force )

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

		OldLoginPlayer( self, Player )
	end )
	
	local OldLogout
	
	OldLogout = ReplaceMethod( "CommandStructure", "Logout", function( self )
		Call( "CommLogout", self )

		OldLogout( self )
	end )
	
	local OldOnResearchComplete
	
	OldOnResearchComplete = ReplaceMethod( "RecycleMixin", "OnResearchComplete", function( self, ResearchID )
		Call( "OnBuildingRecycled", self, ResearchID )

		OldOnResearchComplete( self, ResearchID )
	end )
	
	local OldOnResearch
	
	OldOnResearch = ReplaceMethod( "RecycleMixin", "OnResearch", function( self, ResearchID ) 
		Call( "OnRecycle", self, ResearchID )

		OldOnResearch( self, ResearchID )
	end )
	
	local OldConstructInit
	
	OldConstructInit = ReplaceMethod( "ConstructMixin", "OnInitialized", function( self )
		Call( "OnConstructInit", self )

		OldConstructInit( self )
	end )

	local OldPlayerSetName

	OldPlayerSetName = ReplaceMethod( "Player", "SetName", function( self, Name )
		local OldName = self:GetName()

		OldPlayerSetName( self, Name )

		Call( "PlayerNameChange", self, Name, OldName )
	end )

	local OldCycleMap = MapCycle_CycleMap

	if not OldCycleMap then
		Script.Load "lua/MapCycle.lua"
		OldCycleMap = MapCycle_CycleMap
	end

	function MapCycle_CycleMap()
		local Result = Call( "OnCycleMap" )

		if Result then return end

		return OldCycleMap()
	end

	local OldTestCycle = MapCycle_TestCycleMap

	function MapCycle_TestCycleMap()
		local Result = Call( "ShouldCycleMap" )

		if Result then return Result[ 1 ] end

		return OldTestCycle()
	end
end )
