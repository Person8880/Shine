--[[
	Workshop mod update checker.
]]

local Shine = Shine

local Decode = json.decode
local HTTPRequest = Shared.SendHTTPRequest
local Huge = math.huge
local Max = math.max
local StringFormat = string.format
local tonumber = tonumber

local Plugin = {}

Plugin.HasConfig = true
Plugin.ConfigName = "WorkshopUpdater.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.DefaultConfig = {
	CheckInterval = 60,
	RepeatNotifications = true,
	NotifyInterval = 180,
	ForceMapChangeAfterNotifications = 5,
	ForceMapvote = false,
	ForceMapvoteAtRoundEnd = false
}

local RemainingNotifications = Huge
local ModChangeTimer = "CheckForModChange"

function Plugin:Initialise()
	if not Shine.IsNS2Combat then
		--Have to load manually as Server.GetConfigSetting doesn't exist at the point this is run
		local ServerConfig = Shine.LoadJSONFile( "config://ServerConfig.json" )

		if ServerConfig then
			local BackupServers = ServerConfig.settings and ServerConfig.settings.mod_backup_servers

			if BackupServers and #BackupServers > 0 then
				return false, "backup server is configured, this plugin is not required"
			end
		end
	end

	self.Config.CheckInterval = Max( self.Config.CheckInterval, 15 )
	self.Config.NotifyInterval = Max( self.Config.NotifyInterval, 15 )

	local NotificationNum = self.Config.ForceMapChangeAfterNotifications
	self.Config.ForceMapChangeAfterNotifications = Max( NotificationNum, 0 )

	if self.Config.ForceMapChangeAfterNotifications > 0 then
		RemainingNotifications = self.Config.ForceMapChangeAfterNotifications
	end

	self:CreateTimer( ModChangeTimer, self.Config.CheckInterval, -1, function()
		self:CheckForModChange()
	end )

	self.Enabled = true

	return true
end

function Plugin:Notify( String, Format, ... )
	String = Format and StringFormat( String, ... ) or String

	Shine:NotifyDualColour( nil, 255, 160, 0, "[Workshop]", 255, 255, 255, String )
end

local LastKnownUpdate = {}

--[[
	Parses Steam API response and checks if a mod has been updated.
]]
function Plugin:ParseModInfo( ModInfo )
	if not ModInfo then return end

	local Response = ModInfo.response or {}

	--Steam API error
	if Response.result ~= 1 then return end
	if not Response.publishedfiledetails then return end

	for _, Res in pairs( Response.publishedfiledetails ) do
		if Res.time_updated and Res.title and Res.publishedfileid then
			if not LastKnownUpdate[ Res.publishedfileid ] then
				LastKnownUpdate[ Res.publishedfileid ] = Res.time_updated
			elseif LastKnownUpdate[ Res.publishedfileid ] ~= Res.time_updated then
				self.ChangedModName = Res.title

				self:DestroyTimer( ModChangeTimer )

				self:NotifyOrCycle()

				return
			end
		end
	end
end

--[[
	Checks all installed mods for updates.
]]
function Plugin:CheckForModChange()
	local GetMod = Server.GetActiveModId

	local Params = {}

	Params.itemcount = Server.GetNumActiveMods()

	for i = 1, Params.itemcount do
		Params[ StringFormat( "publishedfileids[%s]", i - 1 ) ] = tonumber( GetMod( i ), 16 )
	end

	local URL = "http://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
	HTTPRequest( URL, "POST", Params, function( Response )
		self:ParseModInfo( Decode( Response ) )
	end )
end

--[[
	Informs connected players of the first mod in need of updating.
	Will cycle the map if the server is empty, or we've gone past the max
	number of notifications.
]]
function Plugin:NotifyOrCycle( Recall )
	if Shine.GetHumanPlayerCount() == 0 then
		self:SimpleTimer( 5, function() MapCycle_CycleMap() end )

		return
	end

	local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )

	--Mapvote actions
	if Enabled and not Recall then
		--Deny extension of the map.
		MapVote.Config.AllowExtend = false

		if self.Config.ForceMapvote and not MapVote:VoteStarted() then
		    MapVote:StartVote( nil, true )
		elseif self.Config.ForceMapvoteAtRoundEnd then
		    MapVote.VoteOnEnd = true
		    MapVote.Round = MapVote.Config.RoundLimit
		    MapVote.MapCycle.time = Shared.GetTime() / 60
		end
	end

	self:Notify( "The \"%s\" mod has updated on the Steam Workshop.", true, self.ChangedModName )
	self:Notify( "Players may be unable to connect to the server until map change." )

	if RemainingNotifications < Huge then
		local TimeRemainingString = "now"
		RemainingNotifications = RemainingNotifications - 1

		local TimeBeforeChange = RemainingNotifications * self.Config.NotifyInterval
		if TimeBeforeChange > 5 then
			TimeRemainingString = StringFormat( "in %s", string.TimeToString( TimeBeforeChange ) )
		end

		self:Notify( "The map will cycle %s.", true, TimeRemainingString )
	end

	if RemainingNotifications == 0 then
		self:SimpleTimer( 5, function() MapCycle_CycleMap() end )
		return
	end

	if self.Config.RepeatNotifications then
		self:SimpleTimer( self.Config.NotifyInterval, function()
			self:NotifyOrCycle( true )
		end )
	end
end

Shine:RegisterExtension( "workshopupdater", Plugin )
