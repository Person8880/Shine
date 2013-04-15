--[[
	Shine ban system.

	This plugin is a good example of a Shine plugin, it uses most if not all of the available features.
]]

local Shine = Shine

local Plugin = {}
Plugin.Version = "1.0"

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local Time = Shared.GetSystemTime
local StringFormat = string.format

Plugin.HasConfig = true --This plugin needs a config file.
Plugin.ConfigName = "Bans.json" --Here it is!

Plugin.SecondaryConfig = "config://BannedPlayers.json" --Auto-convert the old ban file if it's found.

--[[
	Called on plugin startup, we create the chat commands and set ourself to enabled.
	We return true to indicate a successful startup.
]]
function Plugin:Initialise()
	self:CreateCommands()
	self:CheckBans()

	self.Enabled = true

	return true
end

--[[
	Generates the default bans config.
	This is called if no config file exists.
]]
function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		Banned = {},
		DefaultBanTime = 60 --Default of 1 hour ban if a time is not given.
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing bans file: "..Err )	

			return	
		end

		Notify( "Shine bans file created." )
	end
end

--[[
	Saves the bans.
	This is called when a ban is added or removed.
]]
function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing bans file: "..Err )	

		return	
	end

	Notify( "Bans successfully saved." )
end

--[[
	Loads the bans.
	TODO: Web server synchronised bans?
]]
function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		PluginConfig = Shine.LoadJSONFile( self.SecondaryConfig )

		if not PluginConfig then
			self:GenerateDefaultConfig( true )

			return
		end
	end

	self.Config = PluginConfig

	self:ConvertData( self.Config )
end

--[[
	Converts the NS2/DAK bans format into one compatible with Shine.
]]
function Plugin:ConvertData( Data )
	local Edited

	if not Data.Banned then
		Notify( "Converting bans from NS2/DAK format to Shine format..." )
		
		Data.Banned = {}

		for i = 1, #Data do
			local Ban = Data[ i ]

			Data.Banned[ tostring( Ban.id ) ] = { Name = Ban.name, UnbanTime = Ban.time, Reason = Ban.reason }

			Data[ i ] = nil

			Edited = true
		end
	end

	--Consistency check.
	local Banned = Data.Banned

	for ID, Table in pairs( Banned ) do
		if Table.id then
			Banned[ tostring( Table.id ) ] = { Name = Table.name, UnbanTime = Table.time, Reason = Table.reason }
			
			Banned[ ID ] = nil

			Edited = true
		end
	end

	if not Data.DefaultBanTime then
		Data.DefaultBanTime = 60
		Edited = true
	end

	if Edited then
		self:SaveConfig()
	end
end

--[[
	Checks bans on startup.
]]
function Plugin:CheckBans()
	local Time = Shared.GetSystemTime()
	local Bans = self.Config.Banned
	local Edited

	for ID, Data in pairs( Bans ) do
		if Data.UnbanTime and Data.UnbanTime ~= 0 and Data.UnbanTime < Time then
			self:RemoveBan( ID, true )
			Edited = true
		end
	end

	if Edited then
		self:SaveConfig()
	end
end

--[[
	Registers a ban.
	Inputs: Steam ID, player name, ban duration in seconds, name of player performing the ban.
	Output: Success.
]]
function Plugin:AddBan( ID, Name, Duration, BannedBy, Reason )
	if not tonumber( ID ) then 
		ID = Shine.SteamIDToNS2( ID )

		if not ID then
			return false, "invalid Steam ID" 
		end
	end

	self.Config.Banned[ tostring( ID ) ] = {
		Name = Name,
		Duration = Duration,
		UnbanTime = Duration ~= 0 and ( Time() + Duration ) or 0,
		BannedBy = BannedBy,
		Reason = Reason
	}

	self:SaveConfig()

	return true
end

--[[
	Removes a ban.
	Input: Steam ID.
]]
function Plugin:RemoveBan( ID, DontSave )
	self.Config.Banned[ tostring( ID ) ] = nil

	if DontSave then return end

	self:SaveConfig()
end

--[[
	Creates the plugins console/chat commands.
]]
function Plugin:CreateCommands()
	self.Commands = {}
	local Commands = self.Commands

	--[[
		Bans by name/Steam ID when in the server.
	]]
	local function Ban( Client, Target, Duration, Reason )
		Duration = Duration * 60
		local ID = Target:GetUserId()

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local Player = Target:GetControllingPlayer()
		local TargetName = Player:GetName()

		self:AddBan( tostring( ID ), TargetName, Duration, BanningName, Reason )

		Server.DisconnectClient( Target )

		Shine:AdminPrint( nil, "%s banned %s[%s] for %s.", true, BanningName, TargetName, ID, Duration ~= 0 and string.TimeToString( Duration ) or "permanently" )
	end
	Commands.BanCommand = Shine:RegisterCommand( "sh_ban", "ban", Ban )
	Commands.BanCommand:AddParam{ Type = "client", NotSelf = true }
	Commands.BanCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = self.Config.DefaultBanTime }
	Commands.BanCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "No reason given." }
	Commands.BanCommand:Help( "<player> <duration in minutes> Bans the given player for the given time in minutes. 0 is a permanent ban." )

	--[[
		Unban by Steam ID.
	]]
	local function Unban( Client, ID )
		if self.Config.Banned[ ID ] then
			self:RemoveBan( ID )
			Shine:AdminPrint( nil, "%s unbanned %s.", true, Client and Client:GetControllingPlayer():GetName() or "Console", ID )

			return
		end

		Shine:AdminPrint( Client, StringFormat( "%s is not banned.", ID ) )
	end
	Commands.UnbanCommand = Shine:RegisterCommand( "sh_unban", "unban", Unban )
	Commands.UnbanCommand:AddParam{ Type = "string", Error = "Please specify a Steam ID to unban." }
	Commands.UnbanCommand:Help( "<steamid> Unbans the given Steam ID." )

	--[[
		Ban by Steam ID whether they're in the server or not.
	]]
	local function BanID( Client, ID, Duration, Reason )
		Duration = Duration * 60

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local Target = Shine:GetClient( ID )
		local TargetName = "<unknown>"
		
		if Target then
			TargetName = Target:GetControllingPlayer():GetName()
		end
		
		if self:AddBan( ID, TargetName, Duration, BanningName, Reason ) then
			Shine:AdminPrint( nil, "%s banned %s[%s] for %s.", true, BanningName, TargetName, ID, Duration ~= 0 and string.TimeToString( Duration ) or "permanently" )
			if Target then
				Server.DisconnectClient( Target )
			end
			return
		end

		Shine:AdminPrint( Client, "Invalid Steam ID for banning." )
	end
	Commands.BanIDCommand = Shine:RegisterCommand( "sh_banid", "banid", BanID )
	Commands.BanIDCommand:AddParam{ Type = "string", Error = "Please specify a Steam ID to ban." }
	Commands.BanIDCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = self.Config.DefaultBanTime }
	Commands.BanIDCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "No reason given." }
	Commands.BanIDCommand:Help( "<steamid> <duration in minutes> <reason> Bans the given Steam ID for the given time in minutes. 0 is a permanent ban." )

	local function ListBans( Client )
		if not next( self.Config.Banned ) then
			Shine:AdminPrint( Client, "There are no bans on record." )
			return
		end
		
		Shine:AdminPrint( Client, "Currently stored bans:" )
		for ID, BanTable in pairs( self.Config.Banned ) do
			local TimeRemaining = BanTable.UnbanTime == 0 and "Forever" or string.TimeToString( BanTable.UnbanTime - Time() )
			Shine:AdminPrint( Client, "- ID: %s. Name: %s. Time remaining: %s. Reason: %s", true, ID, BanTable.Name or "<unknown>", TimeRemaining, BanTable.Reason or "No reason given." )
		end
	end
	Commands.ListBansCommand = Shine:RegisterCommand( "sh_listbans", nil, ListBans )
	Commands.ListBansCommand:Help( "Lists all stored bans from Shine." )
end

--[[
	Runs on client connect.
	Drops a client if they're on the ban list and still banned.
	If they're past their ban time, their ban is removed.
]]
function Plugin:ClientConnect( Client )
	local ID = Client:GetUserId()

	local BanEntry = self.Config.Banned[ tostring( ID ) ]

	if BanEntry then
		local SysTime = Time()

		if not BanEntry.UnbanTime or BanEntry.UnbanTime == 0 or BanEntry.UnbanTime > Time() then --Either a perma-ban or not expired.
			Server.DisconnectClient( Client )
		else
			self:RemoveBan( ID )
		end
	end
end

--[[
	Called when disabling the plugin.
]]
function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "ban", Plugin )
