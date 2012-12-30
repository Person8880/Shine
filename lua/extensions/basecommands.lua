--[[
	Shine basecommands system.
]]

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format
local TableShuffle = table.Shuffle

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "BaseCommands.json"

Plugin.Commands = {}

function Plugin:Initialise()
	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		AllTalk = false
	}

	if Save then
		local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

		if not PluginConfig then
			Notify( "Error writing basecommands config file: "..Err )	

			return	
		end

		PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

		Notify( "Shine basecommands config file created." )

		PluginConfig:close()
	end
end

function Plugin:SaveConfig()
	local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

	if not PluginConfig then
		Notify( "Error writing basecommands config file: "..Err )	

		return	
	end

	PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

	Shine:Print( "Shine basecommands config file saved." )

	PluginConfig:close()
end

function Plugin:LoadConfig()
	local PluginConfig = io.open( Shine.Config.ExtensionDir..self.ConfigName, "r" )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = Decode( PluginConfig:read( "*all" ) )

	PluginConfig:close()
end

--[[
	Override voice chat to allow everyone to hear each other with alltalk on.
]]
function Plugin:CanPlayerHearPlayer()
	if self.Config.AllTalk then return true end
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

		Shine:AdminPrint( Client, StringFormat( "%s: %s", Command, CommandObj.Help ) )
	end
	Commands.HelpCommand = Shine:RegisterCommand( "sh_help", nil, Help, true )
	Commands.HelpCommand:AddParam{ Type = "string", TakeRestofLine = true, Error = "Please specify a command." }
	Commands.HelpCommand:Help( "You just used it to see this..." )

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
		local Player = Client:GetControllingPlayer()

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

	local function Kick( Client, Target )
		Server.DisconnectClient( Target )
	end
	Commands.KickCommand = Shine:RegisterCommand( "sh_kick", "kick", Kick )
	Commands.KickCommand:AddParam{ Type = "client" }
	Commands.KickCommand:Help( "<playername/steam id> Kicks the given player." )

	local function Status( Client )
		local CanSeeIPs = Shine:HasAccess( Client, "sh_status" )

		local Players = Shine.GetAllPlayers()
		for i = 1, #Players do
			local Player = Players[ i ]
			local PlayerClient = Server.GetOwner( Player )

			Shine:AdminPrint( Client, StringFormat( "Name: '%s' | Steam ID: '%s' | Team: '%s'%s",
			Player:GetName(),
			PlayerClient:GetUserId(),
			Player:GetTeamNumber(),
			CanSeeIPs and " | IP: "..IPAddressToString( Server.GetClientAddress( PlayerClient ) ) or "" ) )
		end
	end
	Commands.StatusCommand = Shine:RegisterCommand( "sh_status", nil, Status, true )
	Commands.StatusCommand:Help( "Prints a list of all connected players and their relevant information." )

	local function ChangeLevel( Client, MapName )
		Server.StartWorld( {}, MapName )
	end
	Commands.ChangeLevelCommand = Shine:RegisterCommand( "sh_changelevel", "map", ChangeLevel )
	Commands.ChangeLevelCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a map to change to." }
	Commands.ChangeLevelCommand:Help( "<map> Changes the map to the given level immediately." )

	local function ListMaps( Client )
		local Maps = {}
		Shared.GetMatchingFileNames( "maps/*.level", false, Maps )

		Shine:AdminPrint( "Installed maps:" )
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
		--Name = Name:gsub( "/", "" ):gsub( "\\", "" ):gsub( "..", "" ) 
		if Name == "basecommands" then
			Shine:AdminPrint( Client, "You cannot reload the basecommands plugin." )
			return
		end

		local Success, Err = Shine:LoadExtension( Name )

		if Success then
			Shine:AdminPrint( Client, StringFormat( "Plugin %s loaded successfully.", Name ) )
		else
			Shine:AdminPrint( Client, StringFormat( "Plugin %s failed to load. Error: %s", Name, Err ) )
		end
	end
	Commands.LoadPluginCommand = Shine:RegisterCommand( "sh_loadplugin", nil, LoadPlugin )
	Commands.LoadPluginCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a plugin to load." }
	Commands.LoadPluginCommand:Help( "<plugin> Loads a plugin." )

	local function UnloadPlugin( Client, Name )
		if Name == "basecommands" and Shine.Plugins[ Name ].Enabled then
			Shine:AdminPrint( Client, "Unloading the basecommands plugin is ill-advised. If you wish to do so, remove it from the active plugins list in your config." )
			return
		end

		if not Shine.Plugins[ Name ] or not Shine.Plugins[ Name ].Enabled then
			Shine:AdminPrint( Client, StringFormat( "The plugin %s is not loaded.", Name ) )
			return
		end

		Shine:UnloadExtension( Name )

		Shine:AdminPrint( Client, StringFormat( "The plugin %s unloaded successfully.", Name ) )
	end
	Commands.UnloadPluginCommand = Shine:RegisterCommand( "sh_unloadplugin", nil, UnloadPlugin )
	Commands.UnloadPluginCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a plugin to unload." }
	Commands.UnloadPluginCommand:Help( "<plugin> Unloads a plugin." )

	local function ListPlugins( Client )
		Shine:AdminPrint( Client, "Loaded plugins:" )
		for Name, Table in pairs( Shine.Plugins ) do
			if Table.Enabled then
				Shine:AdminPrint( Client, StringFormat( "%s - version: %s", Name, Table.Version ) )
			end
		end
	end
	Commands.ListPluginsCommand = Shine:RegisterCommand( "sh_listplugins", nil, ListPlugins )
	Commands.ListPluginsCommand:Help( "Lists all loaded plugins." )

	local function ReadyRoom( Client, Targets )
		local Gamerules = GetGamerules()
		if Gamerules then
			for i = 1, #Targets do
				Gamerules:JoinTeam( Targets[ i ]:GetControllingPlayer(), kTeamReadyRoom )
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
			for i = 1, #Targets do
				local Team = ( i % 2 ) + 1
				Gamerules:JoinTeam( Targets[ i ]:GetControllingPlayer(), Team )
			end
		end
	end
	Commands.ForceRandomCommand = Shine:RegisterCommand( "sh_forcerandom", "random", ForceRandom )
	Commands.ForceRandomCommand:AddParam{ Type = "clients" }
	Commands.ForceRandomCommand:Help( "<players> Forces the given player(s) onto a random team." )

	local function ChangeTeam( Client, Targets, Team )
		local Gamerules = GetGamerules()
		if Gamerules then
			for i = 1, #Targets do
				Gamerules:JoinTeam( Targets[ i ]:GetControllingPlayer(), Team )
			end
		end
	end
	Commands.ChangeTeamCommand = Shine:RegisterCommand( "sh_setteam", "team", ChangeTeam )
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
					Shine:Notify( Client:GetControllingPlayer(), "%s is not a commander.", true, Player:GetName() )
				else
					Shine:Print( "%s is not a commander.", true, Player:GetName() )
				end
			end
		end
	end
	Commands.EjectCommand = Shine:RegisterCommand( "sh_eject", "eject", Eject )
	Commands.EjectCommand:AddParam{ Type = "client" }
	Commands.EjectCommand:Help( "<playername/steamid> Ejects the given commander." )

	local function AdminSay( Client, Message )
		Server.SendNetworkMessage( "Chat", BuildChatMessage( false, "Admin", -1, kTeamReadyRoom, kNeutralTeamType, Message ), true )
		Shared.Message( "Chat All - Admin: "..Message )
		Server.AddChatToHistory( Message, "Admin", 0, kTeamReadyRoom, false )
	end
	Commands.AdminSayCommand = Shine:RegisterCommand( "sh_say", "say", AdminSay, false, true )
	Commands.AdminSayCommand:AddParam{ Type = "string", MaxLength = kMaxChatLength, TakeRestOfLine = true, Error = "Please specify a message." }
	Commands.AdminSayCommand:Help( "<message> Sends a message to everyone from 'Admin'." )

	local function AdminTeamSay( Client, Team, Message )
		local Players = GetEntitiesForTeam( "Player", Team )
		
		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Chat", BuildChatMessage( false, "Team - Admin", -1, Team, kNeutralTeamType, Message ), true )
		end
		
		Shared.Message( "Chat Team - Admin: "..Message )
		Server.AddChatToHistory( Message, "Admin", 0, Team, true )
	end
	Commands.AdminTeamSayCommand = Shine:RegisterCommand( "sh_teamsay", "teamsay", AdminTeamSay, false, true )
	Commands.AdminTeamSayCommand:AddParam{ Type = "team", Error = "Please specify either marines or aliens." }
	Commands.AdminTeamSayCommand:AddParam{ Type = "string", TakeRestOfLine = true, MaxLength = kMaxChatLength, Error = "Please specify a message." }
	Commands.AdminTeamSayCommand:Help( "<marine/alien> <message> Sends a messages to everyone on the given team from 'Admin'." )

	local function PM( Client, Target, Message )
		local Player = Target:GetControllingPlayer()

		if Player then
			Message = Message:sub( 1, kMaxChatLength )

			Server.SendNetworkMessage( player, "Chat", BuildChatMessage( false, "PM - Admin", -1, 0, kNeutralTeamType, Message ), true )

			Shine:Print( "Chat - PM %s to %s: %s", true, Client and Client:GetControllingPlayer():GetName() or "Console", Player:GetName(), Message )
		end
	end
	Commands.PMCommand = Shine:RegisterCommand( "sh_pm", "pm", PM )
	Commands.PMCommand:AddParam{ Type = "client" }
	Commands.PMCommand:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a message to send." }
	Commands.PMCommand:Help( "<player/steam id> <message> Sends a private message to the given player." )
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "basecommands", Plugin )
