--[[
	Shine ban system.
]]

local Shine = Shine
local Hook = Shine.Hook

local Plugin = {}
Plugin.Version = "1.3"

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local pairs = pairs
local Time = os.time
local StringFormat = string.format

Plugin.HasConfig = true
Plugin.ConfigName = "Bans.json"

Plugin.SecondaryConfig = "config://BannedPlayers.json" --Auto-convert the old ban file if it's found.

local Hooked

--[[
	Called on plugin startup, we create the chat commands and set ourself to enabled.
	We return true to indicate a successful startup.
]]
function Plugin:Initialise()
	self.Retries = {}

	self:CreateCommands()
	self:CheckBans()

	if not Hooked then
		--Hook into the default banning commands.
		Event.Hook( "Console_sv_ban", function( Client, ... )
			Shine:RunCommand( Client, "sh_ban", ... )
		end )

		Event.Hook( "Console_sv_unban", function( Client, ... )
			Shine:RunCommand( Client, "sh_unban", ... )
		end )

		--Override the bans list function (have to do it after everything's loaded).
		Hook.Add( "Think", "Bans_Override", function()
			function GetBannedPlayersList()
				local Bans = self.Config.Banned
				local Ret = {}

				local Count = 1

				for ID, Data in pairs( Bans ) do
					Ret[ Count ] = { name = Data.Name, id = ID, reason = Data.Reason, time = Data.UnbanTime }

					Count = Count + 1
				end

				return Ret
			end

			Hook.Remove( "Think", "Bans_Override" )
		end )

		Hooked = true
	end

	self.Enabled = true

	return true
end

local DefaultConfig = {
	Banned = {},
	DefaultBanTime = 60, --Default of 1 hour ban if a time is not given.
	GetBansFromWeb = false,
	GetBansWithPOST = false, --Should we use POST with extra keys to get bans?
	BansURL = "",
	BansSubmitURL = "",
	BansSubmitArguments = {},
	MaxSubmitRetries = 3,
	SubmitTimeout = 5
}

--[[
	Generates the default bans config.
	This is called if no config file exists.
]]
function Plugin:GenerateDefaultConfig( Save )
	self.Config = DefaultConfig

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
	if self.Config.GetBansFromWeb then return end
	
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing bans file: "..Err )	

		return	
	end
end

function Plugin:LoadBansFromWeb()
	local function BansResponse( Response )
		if not Response then
			Shine:Print( "[Error] Loading bans from the web failed. Check the config to make sure the URL is correct." )

			return
		end

		local BansData = Decode( Response ) or {}
		
		--Shine config format.
		if BansData.Banned then
			self.Config.Banned = BansData.Banned
		else --NS2 bans file format.
			if not next( BansData ) then
				Shine:Print( "[Error] Received empty or corrupt bans table from the web." )

				return
			end

			self.Config.Banned = nil

			for i = 1, #BansData do
				self.Config[ i ] = BansData[ i ]
			end

			self:ConvertData( self.Config )
		end

		Shine:LogString( "Shine loaded bans from web successfully." )
	end

	if self.Config.GetBansWithPOST then
		Shared.SendHTTPRequest( self.Config.BansURL, "POST", self.Config.BansSubmitArguments, BansResponse )
	else
		Shared.SendHTTPRequest( self.Config.BansURL, "GET", BansResponse )
	end
end

--[[
	If our config is being web loaded, we'll need to retrieve web bans separately.
]]
function Plugin:OnWebConfigLoaded()
	if self.Config.GetBansFromWeb then
		self:LoadBansFromWeb()
	end
end

--[[
	Loads the bans.
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

	if Shine.CheckConfig( self.Config, DefaultConfig ) then
		Notify( "Shine bans config file updated." )
		self:SaveConfig()
	end

	if self.Config.GetBansFromWeb then
		--Load bans list after everything else.
		Hook.Add( "Think", "Bans_WebLoad", function()
			self:LoadBansFromWeb()

			Hook.Remove( "Think", "Bans_WebLoad" )
		end )

		return
	end

	self:ConvertData( self.Config )
end

--[[
	Converts the NS2/DAK bans format into one compatible with Shine.
]]
function Plugin:ConvertData( Data )
	local Edited

	if not Data.Banned then
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
	local CurTime = Time()
	local Bans = self.Config.Banned
	local Edited

	for ID, Data in pairs( Bans ) do
		if Data.UnbanTime and Data.UnbanTime ~= 0 and Data.UnbanTime < CurTime then
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
function Plugin:AddBan( ID, Name, Duration, BannedBy, BanningID, Reason )
	if not tonumber( ID ) then 
		ID = Shine.SteamIDToNS2( ID )

		if not ID then
			return false, "invalid Steam ID" 
		end
	end

	ID = tostring( ID )

	local BanData = {
		ID = ID,
		Name = Name,
		Duration = Duration,
		UnbanTime = Duration ~= 0 and ( Time() + Duration ) or 0,
		BannedBy = BannedBy,
		BannerID = BanningID,
		Reason = Reason,
		Issued = Time()
	}

	self.Config.Banned[ ID ] = BanData

	self:SaveConfig()

	if self.Config.BansSubmitURL ~= "" then
		local PostParams = {
			bandata = Encode( BanData ),
			unban = 0
		}

		for Key, Value in pairs( self.Config.BansSubmitArguments ) do
			PostParams[ Key ] = Value
		end

		local function SuccessFunc( Data )
			self.Retries[ ID ] = nil

			if not Data then return end
			
			local Decoded = Decode( Data )

			if not Decoded then return end

			if Decoded.success == false then
				--The web request told us that they shouldn't be banned.
				self.Config.Banned[ ID ] = nil

				self:SaveConfig()
			end
		end

		self.Retries[ ID ] = 0

		local TimeoutFunc
		TimeoutFunc = function()
			self.Retries[ ID ] = self.Retries[ ID ] + 1

			if self.Retries[ ID ] > self.Config.MaxSubmitRetries then
				self.Retries[ ID ] = nil

				return
			end
			
			Shine.TimedHTTPRequest( self.Config.BansSubmitURL, "POST", PostParams, SuccessFunc, TimeoutFunc, self.Config.SubmitTimeout )
		end

		Shine.TimedHTTPRequest( self.Config.BansSubmitURL, "POST", PostParams, SuccessFunc, TimeoutFunc, self.Config.SubmitTimeout )
	end

	Hook.Call( "OnPlayerBanned", ID, Name, Duration, BannedBy, Reason )

	return true
end

--[[
	Removes a ban.
	Input: Steam ID.
]]
function Plugin:RemoveBan( ID, DontSave, UnbannerID )
	ID = tostring( ID )

	local BanData = self.Config.Banned[ ID ]

	self.Config.Banned[ ID ] = nil

	if self.Config.BansSubmitURL ~= "" then
		local PostParams = {
			unbandata = Encode{
				ID = ID,
				UnbannerID = UnbannerID or 0
			},
			unban = 1
		}

		for Key, Value in pairs( self.Config.BansSubmitArguments ) do
			PostParams[ Key ] = Value
		end

		local function SuccessFunc( Data )
			self.Retries[ ID ] = nil

			if not Data then return end
			
			local Decoded = Decode( Data )

			if not Decoded then return end

			if Decoded.success == false then
				--The web request told us that they shouldn't be unbanned.
				self.Config.Banned[ ID ] = BanData

				self:SaveConfig()
			end
		end

		self.Retries[ ID ] = 0

		local TimeoutFunc
		TimeoutFunc = function()
			self.Retries[ ID ] = self.Retries[ ID ] + 1

			if self.Retries[ ID ] > self.Config.MaxSubmitRetries then
				self.Retries[ ID ] = nil

				return
			end
			
			Shine.TimedHTTPRequest( self.Config.BansSubmitURL, "POST", PostParams, SuccessFunc, TimeoutFunc, self.Config.SubmitTimeout )
		end

		Shine.TimedHTTPRequest( self.Config.BansSubmitURL, "POST", PostParams, SuccessFunc, TimeoutFunc, self.Config.SubmitTimeout )
	end

	Hook.Call( "OnPlayerUnbanned", ID )

	if DontSave then return end

	self:SaveConfig()
end

--[[
	Creates the plugins console/chat commands.
]]
function Plugin:CreateCommands()
	--[[
		Bans by name/Steam ID when in the server.
	]]
	local function Ban( Client, Target, Duration, Reason )
		Duration = Duration * 60
		local ID = tostring( Target:GetUserId() )

		--We're currently waiting for a response on this ban.
		if self.Retries[ ID ] then
			self:NotifyError( Client, "Please wait for the current ban request on %s to finish.", true, ID )
			self:AdminPrint( Client, "Please wait for the current ban request on %s to finish.", true, ID )

			return
		end

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local BanningID = Client and Client:GetUserId() or 0
		local Player = Target:GetControllingPlayer()
		local TargetName = Player:GetName()

		self:AddBan( ID, TargetName, Duration, BanningName, BanningID, Reason )

		Server.DisconnectClient( Target )

		local DurationString = Duration ~= 0 and "for "..string.TimeToString( Duration ) or "permanently"

		Shine:CommandNotify( Client, "banned %s %s.", true, TargetName, DurationString )
		Shine:AdminPrint( nil, "%s banned %s[%s] %s.", true, BanningName, TargetName, ID, DurationString )
	end
	local BanCommand = self:BindCommand( "sh_ban", "ban", Ban )
	BanCommand:AddParam{ Type = "client", NotSelf = true }
	BanCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = self.Config.DefaultBanTime }
	BanCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "No reason given." }
	BanCommand:Help( "<player> <duration in minutes> Bans the given player for the given time in minutes. 0 is a permanent ban." )

	--[[
		Unban by Steam ID.
	]]
	local function Unban( Client, ID )
		if self.Config.Banned[ ID ] then
			--We're currently waiting for a response on this ban.
			if self.Retries[ ID ] then
				self:NotifyError( Client, "Please wait for the current ban request on %s to finish.", true, ID )
				self:AdminPrint( Client, "Please wait for the current ban request on %s to finish.", true, ID )

				return
			end

			local Unbanner = ( Client and Client.GetUserId and Client:GetUserId() ) or 0

			self:RemoveBan( ID, nil, Unbanner )
			Shine:AdminPrint( nil, "%s unbanned %s.", true, Client and Client:GetControllingPlayer():GetName() or "Console", ID )

			return
		end

		Shine:AdminPrint( Client, StringFormat( "%s is not banned.", ID ) )
	end
	local UnbanCommand = self:BindCommand( "sh_unban", "unban", Unban )
	UnbanCommand:AddParam{ Type = "string", Error = "Please specify a Steam ID to unban." }
	UnbanCommand:Help( "<steamid> Unbans the given Steam ID." )

	--[[
		Ban by Steam ID whether they're in the server or not.
	]]
	local function BanID( Client, ID, Duration, Reason )
		Duration = Duration * 60

		--We want the NS2ID, not Steam ID.
		if ID:find( "STEAM" ) then
			ID = Shine.SteamIDToNS2( ID )

			if not ID then
				self:NotifyError( Client, "Invalid Steam ID for banning." )
				self:AdminPrint( Client, "Invalid Steam ID for banning." )

				return
			end
		end

		--We're currently waiting for a response on this ban.
		if self.Retries[ ID ] then
			self:NotifyError( Client, "Please wait for the current ban request on %s to finish.", true, ID )
			self:AdminPrint( Client, "Please wait for the current ban request on %s to finish.", true, ID )

			return
		end

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local BanningID = Client and Client:GetUserId() or 0
		local Target = Shine:GetClient( ID )
		local TargetName = "<unknown>"
		
		if Target then
			TargetName = Target:GetControllingPlayer():GetName()
		end
		
		if self:AddBan( ID, TargetName, Duration, BanningName, BanningID, Reason ) then
			local DurationString = Duration ~= 0 and "for "..string.TimeToString( Duration ) or "permanently"

			Shine:AdminPrint( nil, "%s banned %s[%s] %s.", true, BanningName, TargetName, ID, DurationString )
			
			if Target then
				Server.DisconnectClient( Target )

				Shine:CommandNotify( Client, "banned %s %s.", true, TargetName, DurationString )
			end

			return
		end

		Shine:AdminPrint( Client, "Invalid Steam ID for banning." )
	end
	local BanIDCommand = self:BindCommand( "sh_banid", "banid", BanID )
	BanIDCommand:AddParam{ Type = "string", Error = "Please specify a Steam ID to ban." }
	BanIDCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = self.Config.DefaultBanTime }
	BanIDCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "No reason given." }
	BanIDCommand:Help( "<steamid> <duration in minutes> <reason> Bans the given Steam ID for the given time in minutes. 0 is a permanent ban." )

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
	local ListBansCommand = self:BindCommand( "sh_listbans", nil, ListBans )
	ListBansCommand:Help( "Lists all stored bans from Shine." )

	local function ForceWebSync( Client )
		if self.Config.BansURL == "" then
			return
		end

		self:LoadBansFromWeb()

		Shine:AdminPrint( Client, "Updating bans from the web..." )
	end
	local ForceSyncCommand = self:BindCommand( "sh_forcebansync", nil, ForceWebSync )
	ForceSyncCommand:Help( "Forces the bans plugin to reload ban data from the web." )
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

Shine:RegisterExtension( "ban", Plugin )
