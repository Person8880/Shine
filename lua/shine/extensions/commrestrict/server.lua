--[[
	Shine commander deprioritization plugin.
]]

local Plugin = ...

local Shine = Shine

local GetOwner = Server.GetOwner
local Max = math.max
local StringFormat = string.format
local Time = os.time
local SharedTime = Shared.GetTime

Plugin.Version = "1.0"
Plugin.HasConfig = true
Plugin.ConfigName = "CommDeps.json"
Plugin.PrintName = "CommDeps"

Plugin.DefaultConfig = {
	Banned = {},
	BansSubmitURL = "",
	BansSubmitArguments = {},
	LogLevel = "Info",
	MaxSubmitRetries = 3,
	SubmitTimeout = 5,
	DefaultBanTime = 60,
	DepTimeInSeconds = 60
}

Plugin.CheckConfig = true
Plugin.ListPermission = "sh_uncommdep"
Plugin.OnBannedHookName = "OnCommanderDeprioritized"
Plugin.OnUnbannedHookName = "OnCommanderReprioritized"

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	self:BuildInitialNetworkData()

	self:VerifyConfig()

	self.Retries = {}

	self:CreateCommands()
	self:CheckBans()

	self.Enabled = true
	self.DeprioritizedCooldown = SharedTime() + self.Config.DepTimeInSeconds

	return true
end

--[[
	Deny commanding if they're deprioritized during the cooldown period.
]]
function Plugin:ValidateCommanderLogin( Gamerules, CommandStation, Player )
	local Client = GetOwner( Player )
	if not Client then
		self.Logger:Error( "Unable to get client for player %s! Cannot check for commander deprioritize.", Player )
		return
	end

	local ID = tostring( Client:GetUserId() )
	local BanData = self.Config.Banned[ ID ]
	if not BanData then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "No commander deprioritize on record for %s, allowing to command.",
				Shine.GetClientInfo( Client ) )
		end
		return
	end

	local CurTime = Time()

	if BanData.UnbanTime == 0 or BanData.UnbanTime > CurTime then
		
		-- If the cooldown is over, allow the player to command
		if SharedTime() > self.DeprioritizedCooldown then
			return true
		end
		
		if Shine:CanNotify( Client ) then
			local Duration = self.DeprioritizedCooldown - SharedTime()

			self:SendTranslatedNotify( Client, "DEPRIORITIZED_WARNING", {
				Duration = Duration
			} )
		end

		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "Preventing %s from commanding due to deprioritization with expiry time: %s.",
				Shine.GetClientInfo( Client ), BanData.UnbanTime == 0 and "never" or BanData.UnbanTime )
		end

		return false
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Removing expired commander deprioritization for %s (expired at %d)",
			Shine.GetClientInfo( Client ), BanData.UnbanTime )
	end

	self:RemoveBan( ID, nil, 0 )
end

Plugin.OperationSuffix = " from commanding"
Plugin.CommandNames = {
	Ban = { "sh_commdep", "commdep" },
	BanID = { "sh_commdepid", "commdepid" },
	Unban = { "sh_uncommdep", "uncommdep" }
}

-- Hook this function to override the default kicking behaviour
function Plugin:PerformBan( Target, Player )

end

--[[
	Creates the plugins console/chat commands.
]]
function Plugin:CreateCommands()
	self:CreateBanCommands()
end
