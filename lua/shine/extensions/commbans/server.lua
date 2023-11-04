--[[
	Shine commander bans plugin.
]]

local JSON = require "shine/lib/json"

local Plugin = ...

local Shine = Shine

local GetClientForPlayer = Shine.GetClientForPlayer
local Max = math.max
local StringFormat = string.format
local Time = os.time

Plugin.Version = "1.0"
Plugin.HasConfig = true
Plugin.ConfigName = "CommBans.json"
Plugin.PrintName = "CommBans"

Plugin.DefaultConfig = {
	Banned = JSON.Object(),
	BansSubmitURL = "",
	BansSubmitArguments = JSON.Object(),
	LogLevel = "Info",
	MaxSubmitRetries = 3,
	SubmitTimeout = 5,
	DefaultBanTime = 60
}

Plugin.CheckConfig = true
Plugin.ListPermission = "sh_uncommban"
Plugin.OnBannedHookName = "OnCommanderBanned"
Plugin.OnUnbannedHookName = "OnCommanderUnbanned"
Plugin.CanUnbanPlayerInGame = true

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	self:BuildInitialNetworkData()

	self:VerifyConfig()

	self.Retries = {}

	self:CreateCommands()
	self:CheckBans()

	self.Enabled = true

	return true
end

--[[
	Deny commanding if they're banned.
]]
function Plugin:ValidateCommanderLogin( Gamerules, CommandStation, Player )
	local Client = GetClientForPlayer( Player )
	if not Client then
		self.Logger:Error( "Unable to get client for player %s! Cannot check for commander ban.", Player )
		return
	end

	local ID = tostring( Client:GetUserId() )
	local BanData = self.Config.Banned[ ID ]
	if not BanData then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "No commander ban on record for %s, allowing to command.",
				Shine.GetClientInfo( Client ) )
		end
		return
	end

	local CurTime = Time()

	if BanData.UnbanTime == 0 or BanData.UnbanTime > CurTime then
		if Shine:CanNotify( Client ) then
			local Duration = BanData.UnbanTime == 0 and 0
				or ( BanData.UnbanTime - CurTime )

			self:SendTranslatedNotify( Client, "BANNED_WARNING", {
				Duration = Duration
			} )
		end

		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "Preventing %s from commanding due to ban with expiry time: %s.",
				Shine.GetClientInfo( Client ), BanData.UnbanTime == 0 and "never" or BanData.UnbanTime )
		end

		return false
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Removing expired commander ban for %s (expired at %d)",
			Shine.GetClientInfo( Client ), BanData.UnbanTime )
	end

	self:RemoveBan( ID, nil, 0 )
end

Plugin.OperationSuffix = " from commanding"
Plugin.CommandNames = {
	Ban = { "sh_commban", "commban" },
	BanID = { "sh_commbanid", "commbanid" },
	Unban = { "sh_uncommban", "uncommban" }
}

function Plugin:PerformBan( Target, Player )
	if Player:isa( "Commander" ) then
		Player:Eject()
	end
end

--[[
	Creates the plugins console/chat commands.
]]
function Plugin:CreateCommands()
	self:CreateBanCommands()
end
