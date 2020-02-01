--[[
	Shine ban system.
]]

local Shine = Shine
local Hook = Shine.Hook

local IsType = Shine.IsType

local Plugin = ...
Plugin.Version = "1.6"

local Ceil = math.ceil
local Clamp = math.Clamp
local Encode, Decode = json.encode, json.decode
local Max = math.max
local Notify = Shared.Message
local pairs = pairs
local StringFind = string.find
local StringFormat = string.format
local StringStartsWith = string.StartsWith
local StringUTF8Lower = string.UTF8Lower
local TableConcat = table.concat
local TableCopy = table.Copy
local TableFindByField = table.FindByField
local TableMergeSort = table.MergeSort
local TableQuickCopy = table.QuickCopy
local TableRemove = table.remove
local TableShallowMerge = table.ShallowMerge
local TableSort = table.sort
local Time = os.time

Plugin.HasConfig = true
Plugin.ConfigName = "Bans.json"
Plugin.PrintName = "Bans"

Plugin.VanillaConfig = "config://BannedPlayers.json" -- Auto-convert the old ban file if it's found.

-- Max number of ban entries to network in one go.
Plugin.MAX_BAN_PER_NETMESSAGE = 15
-- Permission required to receive the ban list.
Plugin.ListPermission = "sh_unban"

Plugin.OnBannedHookName = "OnPlayerBanned"
Plugin.OnUnbannedHookName = "OnPlayerUnbanned"

local Hooked

Plugin.DefaultConfig = {
	Banned = {},
	DefaultBanTime = 60, -- Default of 1 hour ban if a time is not given.
	GetBansFromWeb = false,
	GetBansWithPOST = false, -- Should we use POST with extra keys to get bans?
	BansURL = "",
	BansSubmitURL = "",
	BansSubmitArguments = {},
	MaxSubmitRetries = 3,
	SubmitTimeout = 5,
	VanillaConfigUpToDate = false,
	-- Whether to check if players are using family sharing, and to enforce bans on the main
	-- account to all accounts it is shared with.
	CheckFamilySharing = false,
	-- Whether to ban the account sharing the game when any account playing through
	-- family sharing is banned.
	BanSharerOnSharedBan = false,
	-- Whether to always block players that are playing through family sharing, even
	-- if the sharer hasn't been banned.
	AlwaysBlockFamilySharedPlayers = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.SilentConfigSave = true

--[[
	Called on plugin startup, we create the chat commands and set ourself to enabled.
	We return true to indicate a successful startup.
]]
function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	self.Retries = {}

	if self.Config.GetBansFromWeb then
		-- Load bans list after everything else.
		self:SimpleTimer( 1, function()
			self:LoadBansFromWeb()
		end )
		self:BuildInitialNetworkData()
	else
		self:MergeNS2IntoShine()
	end

	self:CreateCommands()
	self:CheckBans()

	if not Hooked then
		-- Hook into the default banning commands.
		Event.Hook( "Console_sv_ban", function( Client, ... )
			Shine:RunCommand( Client, "sh_ban", false, ... )
		end )

		Event.Hook( "Console_sv_unban", function( Client, ... )
			Shine:RunCommand( Client, "sh_unban", false, ... )
		end )

		-- Override the bans list function (have to do it after everything's loaded).
		self:SimpleTimer( 1, function()
			function GetBannedPlayersList()
				local Bans = self.Config.Banned
				local Ret = {}

				local Count = 1

				for ID, Data in pairs( Bans ) do
					Ret[ Count ] = { name = Data.Name, id = ID, reason = Data.Reason,
						time = Data.UnbanTime }

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
			self.Logger:Error( "Loading bans from the web failed. Check the config to make sure the URL is correct." )
			return
		end

		local BansData, Pos, Err = Decode( Response )
		if not IsType( BansData, "table" ) then
			self.Logger:Error( "Loading bans from the web received invalid JSON. Error: %s.",
				Err )
			self.Logger:Debug( "Response content:\n%s", Response )
			return
		end

		local Edited
		if BansData.Banned then
			Edited = true
			self.Config.Banned = BansData.Banned
		elseif BansData[ 1 ] and BanData[ 1 ].id then
			Edited = true
			self.Config.Banned = self:NS2ToShine( BansData )
		end

		-- Cache the data in case we get a bad response later.
		if Edited and not self:CheckBans() then
			self:SaveConfig()
		end
		self:BuildInitialNetworkData()

		self.Logger:Info( "Loaded bans from web successfully." )
	end

	local Callbacks = {
		OnSuccess = BansResponse,
		OnFailure = function()
			self.Logger:Error( "No response from server when attempting to load bans." )
		end
	}

	self.Logger:Debug( "Retrieving bans from: %s", self.Config.BansURL )

	if self.Config.GetBansWithPOST then
		Shine.HTTPRequestWithRetry( self.Config.BansURL, "POST", self.Config.BansSubmitArguments,
			Callbacks, self.Config.MaxSubmitRetries, self.Config.SubmitTimeout )
	else
		Shine.HTTPRequestWithRetry( self.Config.BansURL, "GET", Callbacks,
			self.Config.MaxSubmitRetries, self.Config.SubmitTimeout )
	end
end

function Plugin:SaveConfig()
	self:ShineToNS2()

	self.BaseClass.SaveConfig( self )
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

local function NS2EntryToShineEntry( Table )
	local Duration = tonumber( Table.duration )
	local UnbanTime = tonumber( Table.time )
	if not Duration and UnbanTime then
		Duration = UnbanTime > 0 and UnbanTime - Time() or 0
	end

	return {
		Name = Table.name,
		UnbanTime = UnbanTime or 0,
		Reason = Table.reason,
		BannedBy = Table.bannedby or "<unknown>",
		BannerID = Table.bannerid or 0,
		Duration = Duration or 0
	}
end

local function IsValidSteamID( ID )
	return StringFind( ID, "^%d+$" )
end

function Plugin:AddNS2BansIntoTable( VanillaBans, MergedTable )
	local Edited
	local VanillaIDs = {}

	local function CheckAndUpdateBan( BanEntry )
		if not BanEntry.id then return end

		-- Make sure the ID is valid before adding it.
		local ID = tostring( BanEntry.id )
		if not IsValidSteamID( ID ) then return end

		VanillaIDs[ ID ] = true

		if MergedTable[ ID ] and MergedTable[ ID ].UnbanTime == BanEntry.time then
			-- Ban is up to date, nothing to do.
			return
		end

		self.Logger:Info(
			"%s ban for ID %s from the vanilla bans as it is out of sync with the plugin's bans.",
			not MergedTable[ ID ] and "Adding" or "Updating",
			ID
		)
		MergedTable[ ID ] = NS2EntryToShineEntry( BanEntry )

		Edited = true
	end

	for i = 1, #VanillaBans do
		CheckAndUpdateBan( VanillaBans[ i ] )
	end

	return VanillaIDs, Edited
end

--[[
	Merges the NS2/Dak config into the Shine config.
]]
function Plugin:MergeNS2IntoShine()
	local VanillaBans = Shine.LoadJSONFile( self.VanillaConfig )
	local MergedTable = self.Config.Banned

	if IsType( VanillaBans, "table" ) then
		local VanillaIDs, Edited = self:AddNS2BansIntoTable( VanillaBans, MergedTable )

		if self.Config.VanillaConfigUpToDate then
			for ID in pairs( MergedTable ) do
				if not VanillaIDs[ ID ] then
					self.Logger:Info( "Removing ban for ID %s as it is no longer present in the vanilla bans.", ID )
					MergedTable[ ID ] = nil
					Edited = true
				end
			end
		else
			Edited = true
			self.Config.VanillaConfigUpToDate = true
		end

		if Edited then
			self:SaveConfig()
		end
	end

	self:BuildInitialNetworkData()
end

--[[
	Converts the NS2/DAK bans format into one compatible with Shine.
]]
function Plugin:NS2ToShine( Data )
	for i = 1, #Data do
		local Table = Data[ i ]
		local SteamID = Table.id and tostring( Table.id )

		if SteamID and IsValidSteamID( SteamID ) then
			Data[ SteamID ] = NS2EntryToShineEntry( Table )
		end

		Data[ i ] = nil
	end

	return Data
end

--[[
	Saves the Shine bans in the vanilla bans config
]]
function Plugin:ShineToNS2()
	local NS2Bans = {}

	for ID, Table in pairs( self.Config.Banned ) do
		NS2Bans[ #NS2Bans + 1 ] = {
			name = Table.Name,
			id = tonumber( ID ),
			reason = Table.Reason,
			time = Table.UnbanTime,
			bannedby = Table.BannedBy,
			bannerid = Table.BannerID,
			duration = Table.Duration
		}
	end

	Shine.SaveJSONFile( NS2Bans, self.VanillaConfig )
end

--[[
	Checks bans on startup.
]]
function Plugin:CheckBans()
	local Bans = self.Config.Banned
	local Edited

	for ID, Data in pairs( Bans ) do
		if self:IsBanExpired( Data ) then
			self:RemoveBan( ID, true )
			Edited = true
		end
	end

	if Edited then
		self:SaveConfig()
	end

	return Edited
end

function Plugin:SendHTTPRequest( ID, PostParams, Operation, Revert )
	TableShallowMerge( self.Config.BansSubmitArguments, PostParams )

	local Callbacks = {
		OnSuccess = function( Data )
			self.Logger:Debug( "Received response from server for %s of %s", Operation, ID )

			self.Retries[ ID ] = nil

			if not Data then
				self.Logger:Error( "Received no repsonse for %s of %s.", Operation, ID )
				return
			end

			local Decoded, Pos, Err = Decode( Data )
			if not Decoded then
				self.Logger:Error( "Received invalid JSON for %s of %s. Error: %s", Operation, ID, Err )
				self.Logger:Debug( "Response content:\n%s", Data )
				return
			end

			if Decoded.success == false then
				Revert()
				self:SaveConfig()
				self.Logger:Info( "Server rejected %s of %s, reverting...", Operation, ID )
			end
		end,
		OnFailure = function()
			self.Retries[ ID ] = nil
			self.Logger:Error( "Sending %s for %s timed out after %i retries.", Operation, ID,
				self.Config.MaxSubmitRetries )
		end
	}

	self.Retries[ ID ] = true

	self.Logger:Debug( "Sending %s of %s to: %s", Operation, ID, self.Config.BansSubmitURL )

	Shine.HTTPRequestWithRetry( self.Config.BansSubmitURL, "POST", PostParams,
		Callbacks, self.Config.MaxSubmitRetries, self.Config.SubmitTimeout )
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

	if self.Config.BansSubmitURL ~= "" and not self.Retries[ ID ] then
		self:SendHTTPRequest( ID, {
			bandata = Encode( BanData ),
			unban = 0
		}, "ban", function()
			-- The web request told us that they shouldn't be banned.
			self.Config.Banned[ ID ] = nil
			self:RemoveBanFromNetData( ID )
		end )
	end

	if self.Config.BanSharerOnSharedBan then
		-- If the player has the game shared to them, ban the player sharing it.
		local function BanSharer( IsBannedAlready, Sharer )
			if IsBannedAlready or not Sharer then return end

			self:AddBan( Sharer, "<unknown>", Duration, BannedBy, BanningID, "Sharing to a banned account." )
		end
		BanSharer( self:CheckFamilySharing( ID, false, BanSharer ) )
	end

	if self.OnBannedHookName then
		Hook.Call( self.OnBannedHookName, ID, Name, Duration, BannedBy, Reason )
	end

	return true
end

--[[
	Removes a ban.
	Input: Steam ID.
]]
function Plugin:RemoveBan( ID, DontSave, UnbannerID )
	ID = tostring( ID )

	local BanData = self.Config.Banned[ ID ]
	if not BanData then return end

	self.Config.Banned[ ID ] = nil

	if self:RemoveBanFromNetData( ID ) then
		self:NotifyClientsOfBanDataChange()
	end

	if self.Config.BansSubmitURL ~= "" and not self.Retries[ ID ] then
		self:SendHTTPRequest( ID, {
			unbandata = Encode{
				ID = ID,
				UnbannerID = UnbannerID or 0
			},
			unban = 1
		}, "unban", function()
			-- The web request told us that they shouldn't be unbanned.
			BanData.ID = ID
			self.Config.Banned[ ID ] = BanData
			self:AddBanToNetData( BanData )
		end )
	end

	if self.OnUnbannedHookName then
		Hook.Call( self.OnUnbannedHookName, ID )
	end

	if DontSave then return end

	self:SaveConfig()
end

Plugin.OperationSuffix = ""
Plugin.CommandNames = {
	Ban = { "sh_ban", "ban" },
	BanID = { "sh_banid", "banid" },
	Unban = { "sh_unban", "unban" }
}

function Plugin:PerformBan( Target, Player, BanningName, Duration, Reason )
	local BanMessage = StringFormat( "Banned from server by %s %s: %s",
		BanningName,
		string.TimeToDuration( Duration ),
		Reason )

	Server.DisconnectClient( Target, BanMessage )
end

--[[
	Creates the plugins console/chat commands.
]]
function Plugin:CreateBanCommands()
	--[[
		Bans by name/Steam ID when in the server.
	]]
	local function Ban( Client, Target, Duration, Reason )
		Duration = Duration * 60
		local ID = tostring( Target:GetUserId() )

		-- We're currently waiting for a response on this ban.
		if self.Retries[ ID ] then
			if Client then
				self:SendTranslatedCommandError( Client, "PLAYER_REQUEST_IN_PROGRESS", {
					ID = ID
				} )
			end
			Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.",
				true, ID )

			return
		end

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local BanningID = Client and Client:GetUserId() or 0
		local Player = Target:GetControllingPlayer()
		local TargetName = Player:GetName()

		self:AddBan( ID, TargetName, Duration, BanningName, BanningID, Reason )
		self:PerformBan( Target, Player, BanningName, Duration, Reason )

		local DurationString = string.TimeToDuration( Duration )

		self:SendTranslatedMessage( Client, "PLAYER_BANNED", {
			TargetName = TargetName,
			Duration = Duration,
			Reason = Reason
		} )
		Shine:AdminPrint( nil, "%s banned %s%s %s.", true,
			Shine.GetClientInfo( Client ),
			Shine.GetClientInfo( Target ),
			self.OperationSuffix, DurationString )
	end
	local BanCommand = self:BindCommand( self.CommandNames.Ban[ 1 ], self.CommandNames.Ban[ 2 ], Ban )
	BanCommand:AddParam{ Type = "client", NotSelf = true }
	BanCommand:AddParam{ Type = "time", Units = "minutes", Min = 0, Round = true, Optional = true,
		Default = self.Config.DefaultBanTime }
	BanCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true,
		Default = "No reason given.", Help = "reason" }
	BanCommand:Help( StringFormat( "Bans the given player%s for the given time in minutes. 0 is a permanent ban.",
		self.OperationSuffix ) )

	--[[
		Unban by Steam ID.
	]]
	local function Unban( Client, ID )
		local IDString = tostring( ID )

		if self.Config.Banned[ IDString ] then
			-- We're currently waiting for a response on this ban.
			if self.Retries[ IDString ] then
				if Client then
					self:SendTranslatedCommandError( Client, "PLAYER_REQUEST_IN_PROGRESS", {
						ID = IDString
					} )
				end
				Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.",
					true, IDString )

				return
			end

			local Unbanner = ( Client and Client.GetUserId and Client:GetUserId() ) or 0

			self:RemoveBan( IDString, nil, Unbanner )

			Shine:AdminPrint( nil, "%s unbanned %s%s.", true, Shine.GetClientInfo( Client ),
				IDString, self.OperationSuffix )

			if self.CanUnbanPlayerInGame then
				local Target = Shine.GetClientByNS2ID( ID )
				if Target then
					local TargetName = Target:GetControllingPlayer():GetName()
					self:SendTranslatedMessage( Client, "PLAYER_UNBANNED", {
						TargetName = TargetName
					} )
				end
			end

			return
		end

		local ErrorText = StringFormat( "%s is not banned%s.", IDString, self.OperationSuffix )

		if Client then
			self:SendTranslatedCommandError( Client, "ERROR_NOT_BANNED", {
				ID = IDString
			} )
		end
		Shine:AdminPrint( Client, ErrorText )
	end
	local UnbanCommand = self:BindCommand( self.CommandNames.Unban[ 1 ], self.CommandNames.Unban[ 2 ], Unban )
	UnbanCommand:AddParam{ Type = "steamid", Error = "Please specify a Steam ID to unban.", IgnoreCanTarget = true }
	UnbanCommand:Help( StringFormat( "Unbans the given Steam ID%s.", self.OperationSuffix ) )

	--[[
		Ban by Steam ID whether they're in the server or not.
	]]
	local function BanID( Client, ID, Duration, Reason )
		Duration = Duration * 60

		local IDString = tostring( ID )

		-- We're currently waiting for a response on this ban.
		if self.Retries[ IDString ] then
			if Client then
				self:SendTranslatedCommandError( Client, "PLAYER_REQUEST_IN_PROGRESS", {
					ID = ID
				} )
			end
			Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.",
				true, IDString )

			return
		end

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local BanningID = Client and Client:GetUserId() or 0
		local Target = Shine.GetClientByNS2ID( ID )
		local TargetName = "<unknown>"

		if Target then
			TargetName = Target:GetControllingPlayer():GetName()
		end

		if self:AddBan( IDString, TargetName, Duration, BanningName, BanningID, Reason ) then
			local DurationString = string.TimeToDuration( Duration )

			Shine:AdminPrint( nil, "%s banned %s[%s]%s %s.", true, Shine.GetClientInfo( Client ),
				TargetName, IDString, self.OperationSuffix, DurationString )

			if Target then
				self:PerformBan( Target, Target:GetControllingPlayer(), BanningName, Duration, Reason )
				self:SendTranslatedMessage( Client, "PLAYER_BANNED", {
					TargetName = TargetName,
					Duration = Duration,
					Reason = Reason
				} )
			end

			return
		end

		if Client then
			self:NotifyTranslatedCommandError( Client, "ERROR_INVALID_STEAMID" )
		end
		Shine:AdminPrint( Client, "Invalid Steam ID for banning." )
	end
	local BanIDCommand = self:BindCommand( self.CommandNames.BanID[ 1 ], self.CommandNames.BanID[ 2 ], BanID )
	BanIDCommand:AddParam{ Type = "steamid", Error = "Please specify a Steam ID to ban." }
	BanIDCommand:AddParam{ Type = "time", Units = "minutes", Min = 0, Round = true, Optional = true,
		Default = self.Config.DefaultBanTime }
	BanIDCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true,
		Default = "No reason given.", Help = "reason" }
	BanIDCommand:Help( StringFormat( "Bans the given Steam ID%s for the given time in minutes. 0 is a permanent ban.",
		self.OperationSuffix ) )
end

function Plugin:CreateCommands()
	self:CreateBanCommands()

	local function ListBans( Client )
		if not next( self.Config.Banned ) then
			Shine:AdminPrint( Client, "There are no bans on record." )
			return
		end

		Shine:AdminPrint( Client, "Currently stored bans:" )
		for ID, BanTable in pairs( self.Config.Banned ) do
			local TimeRemaining = BanTable.UnbanTime == 0 and "Forever"
				or string.TimeToString( BanTable.UnbanTime - Time() )

			Shine:AdminPrint( Client, "- ID: %s. Name: %s. Time remaining: %s. Reason: %s",
				true, ID, BanTable.Name or "<unknown>", TimeRemaining,
				BanTable.Reason or "No reason given." )
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

function Plugin:GetBanEntry( ID )
	return self.Config.Banned[ tostring( ID ) ]
end

function Plugin:IsBanExpired( BanEntry )
	return BanEntry.UnbanTime and BanEntry.UnbanTime ~= 0 and BanEntry.UnbanTime <= Time()
end

function Plugin:IsIDBanned( ID )
	local BanEntry = self:GetBanEntry( ID )
	if not BanEntry or self:IsBanExpired( BanEntry ) then return false end

	return true
end

--[[
	Checks whether the given ID is family sharing with a banned account.
]]
function Plugin:CheckFamilySharing( ID, NoAPIRequest, OnAsyncResponse )
	local RequestParams = {
		steamid = ID
	}

	local Sharer = Shine.ExternalAPIHandler:GetCachedValue( "Steam", "IsPlayingSharedGame", RequestParams )
	if Sharer ~= nil then
		self.Logger:Debug( "Have cached response for family sharing state of %s: %s", ID, Sharer )

		if not Sharer then return false end

		return self:IsIDBanned( Sharer ), Sharer
	end

	if NoAPIRequest then return false end
	if not Shine.ExternalAPIHandler:HasAPIKey( "Steam" ) then
		self.Logger:Warn( "No Steam API key has been configured, thus family sharing cannot be queried." )
		return false
	end

	self.Logger:Debug( "Querying Steam for family sharing state of %s...", ID )

	Shine.ExternalAPIHandler:PerformRequest( "Steam", "IsPlayingSharedGame", RequestParams, {
		OnSuccess = self:WrapCallback( function( Sharer )
			if not Sharer then
				self.Logger:Debug( "Steam responded with no sharer for %s.", ID )
				return OnAsyncResponse( false )
			end

			self:Print( "Player %s is playing through family sharing from account with ID: %s.", true, ID, Sharer )

			OnAsyncResponse( self:IsIDBanned( Sharer ), Sharer )
		end ),
		OnFailure = function()
			self:Print( "Failed to receive response from Steam for user %s's family sharing status.",
				true, ID )
		end
	} )

	return false
end

function Plugin:KickForFamilySharingWhenBanned( Client, Sharer )
	self:Print( "Kicking %s for family sharing with a banned account. Sharer ID: %s.", true,
			Shine.GetClientInfo( Client ), Sharer )
	Server.DisconnectClient( Client, "Family sharing with a banned account." )
end

function Plugin:KickForFamilySharing( Client, Sharer )
	self:Print( "Kicking %s for family sharing. Sharer ID: %s.", true,
		Shine.GetClientInfo( Client ), Sharer )
	Server.DisconnectClient( Client, "Family sharing is not permitted here." )
end

--[[
	On client connect, check if they're family sharing without an API request.

	This will pick up on the result of a request sent on connection that's finished now
	the client's connected.
]]
function Plugin:ClientConnect( Client )
	if not self.Config.CheckFamilySharing then return end

	local IsSharingFromBannedAccount, Sharer = self:CheckFamilySharing( Client:GetUserId(), true )
	if IsSharingFromBannedAccount then
		self:KickForFamilySharingWhenBanned( Client, Sharer )
	elseif Sharer and self.Config.AlwaysBlockFamilySharedPlayers then
		self:KickForFamilySharing( Client, Sharer )
	end
end

function Plugin:GetBanMessage( BanEntry )
	local Message = { "Banned from server" }

	if BanEntry.BannedBy then
		Message[ #Message + 1 ] = " by "
		Message[ #Message + 1 ] = BanEntry.BannedBy
	end

	Message[ #Message + 1 ] = " "

	local Duration = 0
	if BanEntry.Duration then
		Duration = BanEntry.Duration
	elseif BanEntry.UnbanTime and BanEntry.UnbanTime ~= 0 then
		Duration = BanEntry.UnbanTime - Time()
	end

	Message[ #Message + 1 ] = string.TimeToDuration( Duration )

	if BanEntry.Reason and BanEntry.Reason ~= "" then
		Message[ #Message + 1 ] = ": "
		Message[ #Message + 1 ] = BanEntry.Reason
	end

	if not StringFind( Message[ #Message ], "[%.!%?]$" ) then
		Message[ #Message + 1 ] = "."
	end

	return TableConcat( Message )
end

--[[
	Runs on client connection attempt.
	Rejects a client if they're on the ban list and still banned.
	If they're past their ban time, their ban is removed.
]]
function Plugin:CheckConnectionAllowed( ID )
	if self:IsIDBanned( ID ) then
		return false, self:GetBanMessage( self:GetBanEntry( ID ) )
	end

	self:RemoveBan( ID )

	if not self.Config.CheckFamilySharing then return end

	local function OnSharingChecked( IsSharerBanned, Sharer )
		if not Sharer then return end

		if not IsSharerBanned then
			-- Player is playing through family sharing, but the sharer isn't banned.
			if self.Config.AlwaysBlockFamilySharedPlayers then
				local Target = Shine.GetClientByNS2ID( ID )
				if Target then
					self:KickForFamilySharing( Target, Sharer )
				end
			end

			return
		end

		-- Unlikely, but possible that the client's already loaded before Steam responds.
		local Target = Shine.GetClientByNS2ID( ID )
		if Target then
			self:KickForFamilySharingWhenBanned( Target, Sharer )
		end
	end

	local IsSharingFromBannedAccount, Sharer = self:CheckFamilySharing( ID, false, OnSharingChecked )
	if IsSharingFromBannedAccount then
		return false, "Family sharing with a banned account."
	end

	if Sharer and self.Config.AlwaysBlockFamilySharedPlayers then
		return false, "Family sharing is not permitted here."
	end
end

function Plugin:NetworkBan( BanData, Client )
	if not Client then return end

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

	self:SendNetworkMessage( Client, "BanData", NetData, true )
end

local DEFAULT_NAME = "Unknown"
Plugin.SortComparators = {
	-- Sort by name.
	Shine.Comparator( "Field", 1, "Name", DEFAULT_NAME ):CompileStable(),

	-- Sort by banned by, then name.
	Shine.Comparator( "Composition",
		Shine.Comparator( "Field", 1, "Name", DEFAULT_NAME ),
		Shine.Comparator( "Field", 1, "BannerID", 0 )
	):CompileStable(),

	-- Sort by expiry time (treating permanent as the highest), then name.
	Shine.Comparator( "Composition", Shine.Comparator( "Field", 1, "Name", DEFAULT_NAME ), {
		Compare = function( self, A, B )
			local AIsPerma = not A.UnbanTime or A.UnbanTime == 0
			local BIsPerma = not B.UnbanTime or B.UnbanTime == 0

			if AIsPerma and BIsPerma then
				return 0
			end

			if AIsPerma then
				-- Push permanent bans back to the end of the list.
				return 1
			end

			if BIsPerma then
				return -1
			end

			if A.UnbanTime == B.UnbanTime then
				return 0
			end

			return A.UnbanTime < B.UnbanTime and -1 or 1
		end
	} ):CompileStable()
}

function Plugin:BuildInitialNetworkData()
	local Bans = {}

	for ID, Data in pairs( TableCopy( self.Config.Banned ) ) do
		Bans[ #Bans + 1 ] = Data
		Data.ID = ID
	end

	local SortedBans = {}
	for i = 1, #self.SortColumn do
		local Sorted = TableQuickCopy( Bans )
		TableMergeSort( Sorted, self.SortComparators[ i ] )
		SortedBans[ i ] = Sorted
	end

	self.SortedBans = SortedBans
end

function Plugin:NotifyClientsOfBanDataChange()
	local Clients = Shine:GetClientsWithAccess( self.ListPermission )
	if #Clients > 0 then
		self:SendNetworkMessage( Clients, "BanDataChanged", {}, true )
	end
end

function Plugin:AddBanToNetData( BanData )
	-- First remove the old ban, if it exists.
	self:RemoveBanFromNetData( BanData.ID )

	for i = 1, #self.SortColumn do
		local Data = self.SortedBans[ i ]
		Data[ #Data + 1 ] = BanData
		TableMergeSort( Data, self.SortComparators[ i ] )
	end

	self:NotifyClientsOfBanDataChange()
end

function Plugin:RemoveBanFromNetData( ID )
	local Changed = false
	for i = 1, #self.SortColumn do
		local Data = self.SortedBans[ i ]
		local Ban, Index = TableFindByField( Data, "ID", ID )
		if Index then
			Changed = true
			TableRemove( Data, Index )
		end
	end
	return Changed
end

function Plugin:FilterData( Data, Filter )
	local Results = {}

	for i = 1, #Data do
		local Ban = Data[ i ]
		if self:MatchesFilter( Ban, Filter ) then
			Results[ #Results + 1 ] = Ban
		end
	end

	return Results
end

function Plugin:MatchesFilter( Ban, Filter )
	if Ban.ID == Filter then
		return true
	end

	if Ban.BannerID and tostring( Ban.BannerID ) == Filter then
		return true
	end

	if StringStartsWith( StringUTF8Lower( Ban.Name or DEFAULT_NAME ), Filter ) then
		return true
	end

	if StringStartsWith( StringUTF8Lower( Ban.BannedBy or DEFAULT_NAME ), Filter ) then
		return true
	end

	return false
end

function Plugin:ReceiveRequestBanPage( Client, PageRequest )
	if not Shine:GetPermission( Client, self.ListPermission ) then return end

	local Data = self.SortedBans[ PageRequest.SortColumn ]
	if not Data then return end

	if PageRequest.Filter ~= "" then
		Data = self:FilterData( Data, StringUTF8Lower( PageRequest.Filter ) )
	end

	local StartIndex, EndIndex, Dir
	local MaxResults = Clamp( PageRequest.MaxResults, 5, self.MAX_BAN_PER_NETMESSAGE )
	local NumPages = Max( 1, Ceil( #Data / MaxResults ) )
	local Page = Clamp( PageRequest.Page, 1, NumPages )

	if PageRequest.SortAscending then
		StartIndex = 1 + ( Page - 1 ) * MaxResults
		EndIndex = StartIndex + MaxResults - 1
		Dir = 1
	else
		EndIndex = #Data - Page * MaxResults + 1
		StartIndex = EndIndex + MaxResults - 1
		Dir = -1
	end

	local Results = {}
	for i = StartIndex, EndIndex, Dir do
		local Ban = Data[ i ]
		if not Ban then break end

		Results[ #Results + 1 ] = Ban
	end

	self:SendNetworkMessage( Client, "BanPage", {
		Page = Page,
		NumPages = NumPages,
		MaxResults = MaxResults,
		TotalNumResults = #Data
	}, true )

	for i = 1, #Results do
		self:NetworkBan( Results[ i ], Client )
	end
end

Shine.LoadPluginModule( "logger.lua", Plugin )
