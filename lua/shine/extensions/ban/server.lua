--[[
	Shine ban system.
]]

local Shine = Shine
local Hook = Shine.Hook

local IsType = Shine.IsType

local Plugin = Plugin
Plugin.Version = "1.4"

local Notify = Shared.Message
local Clamp = math.Clamp
local Encode, Decode = json.encode, json.decode
local Max = math.max
local pairs = pairs
local StringFormat = string.format
local TableCopy = table.Copy
local TableRemove = table.remove
local Time = os.time

Plugin.HasConfig = true
Plugin.ConfigName = "Bans.json"

Plugin.VanillaConfig = "config://BannedPlayers.json" --Auto-convert the old ban file if it's found.

--Max number of ban entries to network in one go.
Plugin.MAX_BAN_PER_NETMESSAGE = 10
--Permission required to receive the ban list.
Plugin.ListPermission = "sh_unban"

local Hooked

Plugin.DefaultConfig = {
	Banned = {},
	DefaultBanTime = 60, --Default of 1 hour ban if a time is not given.
	GetBansFromWeb = false,
	GetBansWithPOST = false, --Should we use POST with extra keys to get bans?
	BansURL = "",
	BansSubmitURL = "",
	BansSubmitArguments = {},
	MaxSubmitRetries = 3,
	SubmitTimeout = 5
	VanillaConfigUpToDate = false,
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.SilentConfigSave = true

--[[
	Called on plugin startup, we create the chat commands and set ourself to enabled.
	We return true to indicate a successful startup.
]]
function Plugin:Initialise()
	self.Retries = {}
	
	if self.Config.GetBansFromWeb then
		--Load bans list after everything else.
		self:SimpleTimer( 1, function()
			self:LoadBansFromWeb()
		end)
	else
		self:MergeNS2IntoShine()
	end
	
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
		self:SimpleTimer( 1, function()
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
		end )

		Hooked = true
	end
	
	self:VerifyConfig()
	
	self.Enabled = true

	return true
end

function Plugin:VerifyConfig()
	self.Config.MaxSubmitRetries = Max( self.Config.MaxSubmitRetries, 0 )
	self.Config.SubmitTimeout = Max( self.Config.SubmitTimeout, 0 )
	self.Config.DefaultBanTime = Max( self.Config.DefaultBanTime, 0 )
end

function Plugin:LoadBansFromWeb()
	local function BansResponse( Response )
		if not Response then
			Shine:Print( "[Error] Loading bans from the web failed. Check the config to make sure the URL is correct." )

			return
		end

		local BansData = Decode( Response ) or {}
		
		if BansData.Banned then
			self.Config.Banned = BansData.Banned
		elseif BansData[ 1 ] and BanData[ 1 ].id then
			self.Config.Banned = self:NS2ToShine( BansData )
		else
			self.Config.Banned = {}
		end

		self:GenerateNetworkData()

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

	self:VerifyConfig()
end

--[[
	Merges the NS2/Dak config into the Shine config.
]]
function Plugin:MergeNS2IntoShine()
	local Edited
	
	local VanillaBans = Shine.LoadJSONFile( self.VanillaConfig )
	local MergedTable = self.Config.Banned
	local VanillaIDs = {}

	for i = 1, #VanillaBans do
		local Table = VanillaBans[ i ]
		local ID = tostring( Table.id )
		
		if ID then
			VanillaIDs[ ID ] = true
			
			if not MergedTable[ ID ] or MergedTable[ ID ] and MergedTable[ ID ].UnbanTime ~= Table.time then
				MergedTable[ ID ] = { Name = Table.name, UnbanTime = Table.time, Reason = Table.reason, BannedBy = Table.bannedby or "<unknown", BannerID = Table.bannerid or 0, Duration = Table.duration or Table.time > 0 and Table.time - Time() or 0 }
				
				Edited = true
			end
		end		
	end
	
	if self.Config.VanillaConfigUpToDate then
		for ID in pairs( MergedTable ) do
			if not VanillaIDs[ ID ] then
				MergedTable[ ID ] = nil
				Edited = true
			end
		end
	else
		if not Edited then 
			self:ShineToNS2()
		end
		self.Config.VanillaConfigUpToDate = true
	end
	
	if Edited then
		self:SaveConfig()
	end
end

--[[
	Converts the NS2/DAK bans format into one compatible with Shine.
]]
function Plugin:NS2ToShine( Data )
	for ID, Table in ipairs( Data ) do
		local SteamID = tostring( Table.id )
		if SteamID then			
			Data[ SteamID ] = { Name = Table.name, UnbanTime = Table.time, Reason = Table.reason, BannedBy = Table.bannedby or "<unknown", BannerID = Table.bannerid or 0, Duration = Table.duration or Table.time > 0 and Table.time - Time() or 0 }
		end
		
		Data[ ID ] = nil
	end
	
	return Data
end

--[[
	Saves the Shine bans in the vanilla bans config
]]
function Plugin:ShineToNS2()
	local NS2Bans = {}
	
	for ID, Table in pairs( self.Config.Banned ) do
		NS2Bans[ #NS2Bans + 1 ] = { name = Table.Name , id = tonumber( ID ), reason = Table.Reason, time = Table.UnbanTime, bannedby = Table.BannedBy, bannerid = Table.BannerID, duration = Table.Duration }
	end
	
	Shine.SaveJSONFile( NS2Bans, self.VanillaConfig )
end

function Plugin:GenerateNetworkData()
	local BanData = TableCopy( self.Config.Banned )

	local NetData = self.BanNetworkData or {}

	--Remove all the bans we already know about.
	for i = 1, #NetData do
		local ID = NetData[ i ].ID

		--Update ban data.
		if BanData[ ID ] then
			NetData[ i ] = BanData[ ID ]
			NetData[ i ].ID = ID

			BanData[ ID ] = nil
		end
	end

	--Fill in the rest at the end of the network list.
	for ID, Data in pairs( BanData ) do
		NetData[ #NetData + 1 ] = Data
		Data.ID = ID
	end

	self.BanNetworkData = NetData
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

	self:AddBanToNetData( BanData )

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

				self:NetworkUnban( ID )

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

	self:NetworkUnban( ID )

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

				self:AddBanToNetData( BanData )

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
			Shine:NotifyError( Client, "Please wait for the current ban request on %s to finish.", true, ID )
			Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.", true, ID )

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
	BanCommand:Help( "<player> <duration in minutes> <reason> Bans the given player for the given time in minutes. 0 is a permanent ban." )

	--[[
		Unban by Steam ID.
	]]
	local function Unban( Client, ID )
		if self.Config.Banned[ ID ] then
			--We're currently waiting for a response on this ban.
			if self.Retries[ ID ] then
				Shine:NotifyError( Client, "Please wait for the current ban request on %s to finish.", true, ID )
				Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.", true, ID )

				return
			end

			local Unbanner = ( Client and Client.GetUserId and Client:GetUserId() ) or 0

			self:RemoveBan( ID, nil, Unbanner )
			Shine:AdminPrint( nil, "%s unbanned %s.", true, Client and Client:GetControllingPlayer():GetName() or "Console", ID )

			return
		end

		local ErrorText = StringFormat( "%s is not banned.", ID )

		Shine:NotifyError( Client, ErrorText )
		Shine:AdminPrint( Client, ErrorText )
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
				Shine:NotifyError( Client, "Invalid Steam ID for banning." )
				Shine:AdminPrint( Client, "Invalid Steam ID for banning." )

				return
			end
		end

		if not Shine:CanTarget( Client, tonumber( ID ) ) then
			Shine:NotifyError( Client, "You cannot ban %s.", true, ID )
			Shine:AdminPrint( Client, "You cannot ban %s.", true, ID )

			return
		end

		--We're currently waiting for a response on this ban.
		if self.Retries[ ID ] then
			Shine:NotifyError( Client, "Please wait for the current ban request on %s to finish.", true, ID )
			Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.", true, ID )

			return
		end

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local BanningID = Client and Client:GetUserId() or 0
		local Target = Shine.GetClientByNS2ID( tonumber( ID ) )
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

		Shine:NotifyError( Client, "Invalid Steam ID for banning." )
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

function Plugin:ClientDisconnect( Client )
	if not self.BanNetworkedClients then return end

	self.BanNetworkedClients[ Client ] = nil
end

function Plugin:SaveConfig()
	self:ShineToNS2()
	
	self.BaseClass.SaveConfig( self )
end

function Plugin:NetworkBan( BanData, Client )
	if not Client and not self.BanNetworkedClients then return end

	local NetData = {
		ID = BanData.ID,
		Name = BanData.Name or "Unknown",
		Duration = BanData.Duration or 0,
		UnbanTime = BanData.UnbanTime,
		BannedBy = BanData.BannedBy or "Unknown",
		BannerID = BanData.BannerID or 0,
		Reason = BanData.Reason or "",
		Issued = BanData.Issued or 0
	}

	if Client then
		self:SendNetworkMessage( Client, "BanData", NetData, true )
	else
		for Client in pairs( self.BanNetworkedClients ) do
			self:SendNetworkMessage( Client, "BanData", NetData, true )
		end
	end
end

function Plugin:NetworkUnban( ID )
	local NetData = self.BanNetworkData

	if NetData then
		for i = 1, #NetData do
			local Data = NetData[ i ]

			--Remove the ban from the network data.
			if Data.ID == ID then
				TableRemove( NetData, i )

				--Anyone on an index bigger than this one needs to go down 1.
				if self.BanNetworkedClients then
					for Client, Index in pairs( self.BanNetworkedClients ) do
						if Index > i then
							self.BanNetworkedClients[ Client ] = Index - 1
						end
					end
				end

				break
			end
		end
	end

	if not self.BanNetworkedClients then return end
	
	for Client in pairs( self.BanNetworkedClients ) do
		self:SendNetworkMessage( Client, "Unban", { ID = ID }, true )
	end
end

function Plugin:ReceiveRequestBanData( Client, Data )
	if not Shine:GetPermission( Client, self.ListPermission ) then return end
	
	self.BanNetworkedClients = self.BanNetworkedClients or {}

	self.BanNetworkedClients[ Client ] = self.BanNetworkedClients[ Client ] or 1
	local Index = self.BanNetworkedClients[ Client ]

	local NetworkData = self.BanNetworkData

	if not NetworkData then return end

	for i = Index, Clamp( Index + self.MAX_BAN_PER_NETMESSAGE - 1, 0, #NetworkData ) do
		if NetworkData[ i ] then
			self:NetworkBan( NetworkData[ i ], Client )
		end
	end

	self.BanNetworkedClients[ Client ] = Clamp( Index + self.MAX_BAN_PER_NETMESSAGE, 0, #NetworkData + 1 )
end

function Plugin:AddBanToNetData( BanData )
	self.BanNetworkData = self.BanNetworkData or {}

	local NetData = self.BanNetworkData

	for i = 1, #NetData do
		local Data = NetData[ i ]

		if Data.ID == BanData.ID then
			NetData[ i ] = BanData

			if self.BanNetworkedClients then
				for Client, Index in pairs( self.BanNetworkedClients ) do
					if Index > i then
						self:NetworkBan( BanData, Client )
					end
				end
			end

			return
		end
	end

	NetData[ #NetData + 1 ] = BanData
end