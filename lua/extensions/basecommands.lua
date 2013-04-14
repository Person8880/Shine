--[[
	Shine basecommands system.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format
local TableShuffle = table.Shuffle
local TableSort = table.sort
local Floor = math.floor

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "BaseCommands.json"

Plugin.Commands = {}

function Plugin:Initialise()
	self.Gagged = {}

	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		AllTalk = false
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing basecommands config file: "..Err )	

			return	
		end

		Notify( "Shine basecommands config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing basecommands config file: "..Err )	

		return	
	end

	Notify( "Shine basecommands config file saved." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig
end

--[[
	Override voice chat to allow everyone to hear each other with alltalk on.
]]
function Plugin:CanPlayerHearPlayer()
	if self.Config.AllTalk then return true end
end

local function NS2ToSteamID( ID )
	ID = tonumber( ID )
	if not ID then return "" end
	
	return StringFormat( "STEAM_0:%i:%i", ID % 2, Floor( ID * 0.5 ) )
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function Help( Client, Command )
		local CommandObj = Shine.Commands[ Command ]

		if not CommandObj then
			Shine:AdminPrint( Client, StringFormat( "%s is not a valid command.", Command ) )
			return
		end

		if not Shine:GetPermission( Client, Command ) then
			Shine:AdminPrint( Client, StringFormat( "You do not have access to %s.", Command ) )
			return
		end

		Shine:AdminPrint( Client, StringFormat( "%s: %s", Command, CommandObj.Help or "No help available." ) )
	end
	Commands.HelpCommand = Shine:RegisterCommand( "sh_help", nil, Help, true )
	Commands.HelpCommand:AddParam{ Type = "string", TakeRestofLine = true, Error = "Please specify a command." }
	Commands.HelpCommand:Help( "<command> Displays usage information for the given command." )

	local function CommandsList( Client )
		local Commands = Shine.Commands

		if Client then
			ServerAdminPrint( Client, "Available commands:" )

			for Command, Object in pairs( Commands ) do
				if Shine:GetPermission( Client, Command ) then
					ServerAdminPrint( Client, StringFormat( "%s: %s", Command, Object.Help or "No help available." ) )
				end
			end

			ServerAdminPrint( Client, "End command list." )

			return
		end

		Notify( "Available commands:" )

		for Command, Object in pairs( Commands ) do
			Notify( StringFormat( "%s: %s", Command, Object.Help or "No help available." ) )
		end

		Notify( "End command list." )
	end
	Commands.CommandList = Shine:RegisterCommand( "sh_helplist", nil, CommandsList, true )
	Commands.CommandList:Help( "Displays every command you have access to and their usage." )

	local function RCon( Client, Command )
		Shared.ConsoleCommand( Command )
		Shine:Print( "%s ran console command: %s", true, Client and Client:GetControllingPlayer():GetName() or "Console", Command )
	end
	Commands.RConCommand = Shine:RegisterCommand( "sh_rcon", "rcon", RCon )
	Commands.RConCommand:AddParam{ Type = "string", TakeRestOfLine = true }
	Commands.RConCommand:Help( "<command> Executes a command on the server console." )

	local function SetPassword( Client, Password )
		Server.SetPassword( Password )
		Shine:AdminPrint( Client, "Password %s", true, Password ~= "" and "set to "..Password or "reset" )
	end
	Commands.SetPasswordCommand = Shine:RegisterCommand( "sh_password", "password", SetPassword )
	Commands.SetPasswordCommand:AddParam{ Type = "string", TakeRestOfLine = true, Optional = true, Default = "" }
	Commands.SetPasswordCommand:Help( "<password> Sets the server password." )

	local function RunLua( Client, Code )
		local Player = Client and Client:GetControllingPlayer()

		local Name = Player and Player:GetName() or "Console"

		local Func, Err = loadstring( Code )

		if Func then
			Func()
			Shine:Print( "%s ran: %s", true, Name, Code )
		else
			Shine:Print( "Lua run failed. Error: %s", true, Err )
		end
	end
	Commands.RunLuaCommand = Shine:RegisterCommand( "sh_luarun", "luarun", RunLua, false, true )
	Commands.RunLuaCommand:AddParam{ Type = "string", TakeRestOfLine = true }
	Commands.RunLuaCommand:Help( "Runs a string of Lua code on the server. Be careful with this." )

	local function AllTalk( Client, Enable )
		self.Config.AllTalk = Enable
		Shine:AdminPrint( Client, "All talk %s.", true, Enable and "enabled" or "disabled" )
	end
	Commands.AllTalkCommand = Shine:RegisterCommand( "sh_alltalk", "alltalk", AllTalk )
	Commands.AllTalkCommand:AddParam{ Type = "boolean", Optional = true, Default = function() return not self.Config.AllTalk end }
	Commands.AllTalkCommand:Help( "<true/false> Enable or disable all talk, which allows everyone to hear each others voice chat regardless of team." )

	local function Kick( Client, Target, Reason )
		Shine:Print( "%s kicked %s.%s", true, 
			Client and Client:GetControllingPlayer():GetName() or "Console", 
			Target:GetControllingPlayer():GetName(),
			Reason ~= "" and " Reason: "..Reason or ""
		)
		Server.DisconnectClient( Target )
	end
	Commands.KickCommand = Shine:RegisterCommand( "sh_kick", "kick", Kick )
	Commands.KickCommand:AddParam{ Type = "client", NotSelf = true }
	Commands.KickCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "" }
	Commands.KickCommand:Help( "<player> Kicks the given player." )

	local function Status( Client )
		local CanSeeIPs = Shine:HasAccess( Client, "sh_status" )

		local PlayerList = Shared.GetEntitiesWithClassname( "Player" )
		local Size = PlayerList:GetSize()

		local GameIDs = Shine.GameIDs
		local SortTable = {}
		local Count = 1

		for Client, ID in pairs( GameIDs ) do
			SortTable[ Count ] = { ID, Client }
			Count = Count + 1
		end

		TableSort( SortTable, function( A, B )
			if A[ 1 ] < B[ 1 ] then return true end
			return false
		end )

		if Client then
			ServerAdminPrint( Client, StringFormat( "Showing %s:", Size == 1 and "1 connected player" or Size.." connected players" ) )
			ServerAdminPrint( Client, StringFormat( "ID\t\tName\t\t\t\tSteam ID\t\t\t\t\t\t\t\t\t\t\t\tTeam%s", CanSeeIPs and "\t\t\t\t\t\tIP" or "" ) )
			ServerAdminPrint( Client, "=============================================================================" )
		else
			Notify( StringFormat( "Showing %s:", Size == 1 and "1 connected player" or Size.." connected players" ) )
			Notify( "ID\t\tName\t\t\t\tSteam ID\t\t\t\t\t\t\t\t\t\t\t\tTeam\t\t\t\t\t\tIP" )
			Notify( "=============================================================================" )
		end

		for i = 1, #SortTable do
			local Data = SortTable[ i ]

			local GameID = Data[ 1 ]
			local PlayerClient = Data[ 2 ]

			local Player = PlayerClient:GetControllingPlayer()

			local ID = PlayerClient:GetUserId()

			if Client then
				ServerAdminPrint( Client, StringFormat( "'%s'\t\t'%s'\t\t'%s'\t'%s'\t\t'%s'%s",
				GameID,
				Player:GetName(),
				ID,
				NS2ToSteamID( ID ),
				Shine:GetTeamName( Player:GetTeamNumber(), true ),
				CanSeeIPs and "\t\t"..IPAddressToString( Server.GetClientAddress( PlayerClient ) ) or "" ) )
			else
				Notify( StringFormat( "'%s'\t\t'%s'\t\t'%s'\t'%s'\t\t'%s'\t\t%s",
				GameID,
				Player:GetName(),
				ID,
				NS2ToSteamID( ID ),
				Shine:GetTeamName( Player:GetTeamNumber(), true ),
				IPAddressToString( Server.GetClientAddress( PlayerClient ) ) ) )
			end
		end
	end
	Commands.StatusCommand = Shine:RegisterCommand( "sh_status", nil, Status, true )
	Commands.StatusCommand:Help( "Prints a list of all connected players and their relevant information." )

	local function ChangeLevel( Client, MapName )
		MapCycle_ChangeMap( MapName )
	end
	Commands.ChangeLevelCommand = Shine:RegisterCommand( "sh_changelevel", "map", ChangeLevel )
	Commands.ChangeLevelCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a map to change to." }
	Commands.ChangeLevelCommand:Help( "<map> Changes the map to the given level immediately." )

	local function ListMaps( Client )
		local Maps = {}
		Shared.GetMatchingFileNames( "maps/*.level", false, Maps )

		Shine:AdminPrint( Client, "Installed maps:" )
		for _, MapPath in pairs( Maps ) do
			local MapName = MapPath:match( "maps/(.-).level" )
			Shine:AdminPrint( Client, StringFormat( "- %s", MapName ) )
		end
	end
	Commands.ListMapsCommand = Shine:RegisterCommand( "sh_listmaps", nil, ListMaps )
	Commands.ListMapsCommand:Help( "Lists all installed maps on the server." )

	local function ResetGame( Client )
		local Gamerules = GetGamerules()
		if Gamerules then
			Gamerules:ResetGame()
		end
	end
	Commands.ResetGameCommand = Shine:RegisterCommand( "sh_reset", "reset", ResetGame )
	Commands.ResetGameCommand:Help( "Resets the game round." )

	local function LoadPlugin( Client, Name )
		if Name == "basecommands" then
			Shine:AdminPrint( Client, "You cannot reload the basecommands plugin." )
			return
		end

		local Success, Err = Shine:LoadExtension( Name )

		if Success then
			Shine:AdminPrint( Client, StringFormat( "Plugin %s loaded successfully.", Name ) )
			Shine:SendPluginData( nil, Shine:BuildPluginData() ) --Update all players with the plugins state.
		else
			Shine:AdminPrint( Client, StringFormat( "Plugin %s failed to load. Error: %s", Name, Err ) )
		end
	end
	Commands.LoadPluginCommand = Shine:RegisterCommand( "sh_loadplugin", nil, LoadPlugin )
	Commands.LoadPluginCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a plugin to load." }
	Commands.LoadPluginCommand:Help( "<plugin> Loads a plugin." )

	local function UnloadPlugin( Client, Name )
		if Name == "basecommands" and Shine.Plugins[ Name ] and Shine.Plugins[ Name ].Enabled then
			Shine:AdminPrint( Client, "Unloading the basecommands plugin is ill-advised. If you wish to do so, remove it from the active plugins list in your config." )
			return
		end

		if not Shine.Plugins[ Name ] or not Shine.Plugins[ Name ].Enabled then
			Shine:AdminPrint( Client, StringFormat( "The plugin %s is not loaded.", Name ) )
			return
		end

		Shine:UnloadExtension( Name )

		Shine:AdminPrint( Client, StringFormat( "The plugin %s unloaded successfully.", Name ) )

		Shine:SendPluginData( nil, Shine:BuildPluginData() )
	end
	Commands.UnloadPluginCommand = Shine:RegisterCommand( "sh_unloadplugin", nil, UnloadPlugin )
	Commands.UnloadPluginCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a plugin to unload." }
	Commands.UnloadPluginCommand:Help( "<plugin> Unloads a plugin." )

	local function ListPlugins( Client )
		Shine:AdminPrint( Client, "Loaded plugins:" )
		for Name, Table in pairs( Shine.Plugins ) do
			if Table.Enabled then
				Shine:AdminPrint( Client, StringFormat( "%s - version: %s", Name, Table.Version or "1.0" ) )
			end
		end
	end
	Commands.ListPluginsCommand = Shine:RegisterCommand( "sh_listplugins", nil, ListPlugins )
	Commands.ListPluginsCommand:Help( "Lists all loaded plugins." )

	local function ReloadUsers( Client )
		Shine:AdminPrint( Client, "Reloading users..." )
		Shine:LoadUsers( Shine.Config.GetUsersFromWeb, true )
	end
	Commands.ReloadUsersCommand = Shine:RegisterCommand( "sh_reloadusers", nil, ReloadUsers )
	Commands.ReloadUsersCommand:Help( "Reloads the user data, either from the web or locally depending on your config settings." )

	local function ReadyRoom( Client, Targets )
		local Gamerules = GetGamerules()
		if Gamerules then
			for i = 1, #Targets do
				Gamerules:JoinTeam( Targets[ i ]:GetControllingPlayer(), kTeamReadyRoom, nil, true )
			end
		end
	end
	Commands.ReadyRoomCommand = Shine:RegisterCommand( "sh_rr", "rr", ReadyRoom )
	Commands.ReadyRoomCommand:AddParam{ Type = "clients" }
	Commands.ReadyRoomCommand:Help( "<players> Sends the given player(s) to the ready room." )

	local function ForceRandom( Client, Targets )
		local Gamerules = GetGamerules()
		if Gamerules then
			TableShuffle( Targets )

			local NumPlayers = #Targets

			local TeamSequence = math.GenerateSequence( NumPlayers, { 1, 2 } )

			for i = 1, NumPlayers do
				Gamerules:JoinTeam( Targets[ i ]:GetControllingPlayer(), TeamSequence[ i ], nil, true )
			end
		end
	end
	Commands.ForceRandomCommand = Shine:RegisterCommand( "sh_forcerandom", "forcerandom", ForceRandom )
	Commands.ForceRandomCommand:AddParam{ Type = "clients" }
	Commands.ForceRandomCommand:Help( "<players> Forces the given player(s) onto a random team." )

	local function ChangeTeam( Client, Targets, Team )
		local Gamerules = GetGamerules()
		if Gamerules then
			for i = 1, #Targets do
				Gamerules:JoinTeam( Targets[ i ]:GetControllingPlayer(), Team, nil, true )
			end
		end
	end
	Commands.ChangeTeamCommand = Shine:RegisterCommand( "sh_setteam", { "team", "setteam" }, ChangeTeam )
	Commands.ChangeTeamCommand:AddParam{ Type = "clients" }
	Commands.ChangeTeamCommand:AddParam{ Type = "team", Error = "Please specify either marines or aliens." }
	Commands.ChangeTeamCommand:Help( "<players> <marine/alien> Sets the given player(s) onto the given team." )

	local function AutoBalance( Client, Enable, UnbalanceAmount, Delay )
		Server.SetConfigSetting( "auto_team_balance", Enable and { enabled_on_unbalance_amount = UnbalanceAmount, enabled_after_seconds = Delay } or nil )
		if Enable then
			Shine:AdminPrint( Client, "Auto balance enabled. Player unbalance amount: %s. Delay: %s.", true, UnbalanceAmount, Delay )
		else
			Shine:AdminPrint( Client, "Auto balance disabled." )
		end
	end
	Commands.AutoBalanceCommand = Shine:RegisterCommand( "sh_autobalance", "autobalance", AutoBalance )
	Commands.AutoBalanceCommand:AddParam{ Type = "boolean", Error = "Please specify whether auto balance should be enabled." }
	Commands.AutoBalanceCommand:AddParam{ Type = "number", Min = 1, Round = true, Optional = true, Default = 2 }
	Commands.AutoBalanceCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = 10 }
	Commands.AutoBalanceCommand:Help( "<true/false> <player amount> <seconds> Enables or disables auto balance. Player amount and seconds are optional." )

	local function Eject( Client, Target )
		local Player = Target:GetControllingPlayer()

		if Player then
			if Player:isa( "Commander" ) then
				Player:Eject()
			else
				if Client then
					Shine:Notify( Client:GetControllingPlayer(), "Error", Shine.Config.ChatName, "%s is not a commander.", true, Player:GetName() )
				else
					Shine:Print( "%s is not a commander.", true, Player:GetName() )
				end
			end
		end
	end
	Commands.EjectCommand = Shine:RegisterCommand( "sh_eject", "eject", Eject )
	Commands.EjectCommand:AddParam{ Type = "client" }
	Commands.EjectCommand:Help( "<player> Ejects the given commander." )

	local function AdminSay( Client, Message )
		Shine:Notify( nil, "All", Shine.Config.ChatName, Message )
	end
	Commands.AdminSayCommand = Shine:RegisterCommand( "sh_say", "say", AdminSay, false, true )
	Commands.AdminSayCommand:AddParam{ Type = "string", MaxLength = kMaxChatLength, TakeRestOfLine = true, Error = "Please specify a message." }
	Commands.AdminSayCommand:Help( "<message> Sends a message to everyone from 'Admin'." )

	local function AdminTeamSay( Client, Team, Message )
		local Players = GetEntitiesForTeam( "Player", Team )
		
		Shine:Notify( Players, "Team", Shine.Config.ChatName, Message )
	end
	Commands.AdminTeamSayCommand = Shine:RegisterCommand( "sh_teamsay", "teamsay", AdminTeamSay, false, true )
	Commands.AdminTeamSayCommand:AddParam{ Type = "team", Error = "Please specify either marines or aliens." }
	Commands.AdminTeamSayCommand:AddParam{ Type = "string", TakeRestOfLine = true, MaxLength = kMaxChatLength, Error = "Please specify a message." }
	Commands.AdminTeamSayCommand:Help( "<marine/alien> <message> Sends a messages to everyone on the given team from 'Admin'." )

	local function PM( Client, Target, Message )
		local Player = Target:GetControllingPlayer()

		if Player then
			Shine:Notify( Player, "PM", Shine.Config.ChatName, Message )
		end
	end
	Commands.PMCommand = Shine:RegisterCommand( "sh_pm", "pm", PM )
	Commands.PMCommand:AddParam{ Type = "client" }
	Commands.PMCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a message to send.", MaxLength = kMaxChatLength }
	Commands.PMCommand:Help( "<player> <message> Sends a private message to the given player." )

	local function CSay( Client, Message )
		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"
		local ID = Client:GetUserId() or 0

		Shine:SendText( nil, Shine.BuildScreenMessage( 3, 0.5, 0.2, Message, 6, 255, 255, 255, 1, 2, 1 ) )
		Shine:AdminPrint( nil, "CSay from %s[%s]: %s", true, PlayerName, ID, Message )
	end
	Commands.CSayCommand = Shine:RegisterCommand( "sh_csay", "csay", CSay )
	Commands.CSayCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a message to send.", MaxLength = 128 }
	Commands.CSayCommand:Help( "Displays a message in the centre of all player's screens." )

	local function GagPlayer( Client, Target, Duration )
		self.Gagged[ Target ] = Duration == 0 and true or Shared.GetTime() + Duration

		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"
		local ID = Client:GetUserId() or 0

		local TargetPlayer = Target:GetControllingPlayer()
		local TargetName = TargetPlayer and TargetPlayer:GetName() or "<unknown>"
		local TargetID = Target:GetUserId() or 0

		Shine:AdminPrint( nil, "%s[%s] gagged %s[%s]%s", true, PlayerName, ID, TargetName, TargetID,
			Duration == 0 and "" or " for "..string.TimeToString( Duration ) )
	end
	Commands.GagCommand = Shine:RegisterCommand( "sh_gag", "gag", GagPlayer )
	Commands.GagCommand:AddParam{ Type = "client" }
	Commands.GagCommand:AddParam{ Type = "number", Round = true, Min = 0, Max = 1800, Optional = true, Default = 0 }
	Commands.GagCommand:Help( "<player> <duration> Silences the given player's chat. If no duration is given, it will hold for the remainder of the map." )

	local function UngagPlayer( Client, Target )
		local TargetPlayer = Target:GetControllingPlayer()
		local TargetName = TargetPlayer and TargetPlayer:GetName() or "<unknown>"
		local TargetID = Target:GetUserId() or 0

		if not self.Gagged[ Target ] then
			Shine:Notify( Client, "Error", Shine.Config.ChatName, "%s is not gagged.", true, TargetName )

			return
		end

		self.Gagged[ Target ] = nil

		local Player = Client and Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "Console"
		local ID = Client:GetUserId() or 0

		Shine:AdminPrint( nil, "%s[%s] ungagged %s[%s]", true, PlayerName, ID, TargetName, TargetID )
	end
	Commands.UngagCommand = Shine:RegisterCommand( "sh_ungag", "ungag", UngagPlayer )
	Commands.UngagCommand:AddParam{ Type = "client" }
	Commands.UngagCommand:Help( "<player> Stops silencing the given player's chat." )
end

--[[
	Facilitates the gag command.
]]
function Plugin:PlayerSay( Client, Message )
	local GagData = self.Gagged[ Client ]

	if not GagData then return end

	if GagData == true then return "" end
	
	if GagData > Shared.GetTime() then return "" end

	self.Gagged[ Client ] = nil
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "basecommands", Plugin )
