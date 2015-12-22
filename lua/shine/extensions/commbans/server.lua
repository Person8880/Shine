--[[
	Shine commander bans plugin.
]]

local Plugin = Plugin

local Shine = Shine

local GetOwner = Server.GetOwner
local Max = math.max
local StringFormat = string.format
local Time = os.time

Plugin.Version = "1.0"
Plugin.HasConfig = true
Plugin.ConfigName = "CommBans.json"
Plugin.PrintName = "CommBans"

Plugin.DefaultConfig = {
	Banned = {},
	BansSubmitURL = "",
	BansSubmitArguments = {},
	MaxSubmitRetries = 3,
	SubmitTimeout = 5,
	DefaultBanTime = 60
}

Plugin.CheckConfig = true
Plugin.ListPermission = "sh_uncommban"

function Plugin:Initialise()
	self:GenerateNetworkData()

	self:VerifyConfig()

	self.Retries = {}

	self:CreateCommands()
	self:CheckBans()

	self.Enabled = true

	return true
end

function Plugin:Notify( Player, String, Format, ... )
	Shine:NotifyDualColour( Player, 255, 50, 0, "[CommBan]", 255, 255, 255, String, Format, ... )
end

--[[
	Deny commanding if they're banned.
]]
function Plugin:CheckCommLogin( CommandStation, Player )
	local Client = GetOwner( Player )
	if not Client then return end

	local ID = tostring( Client:GetUserId() )
	local BanData = self.Config.Banned[ ID ]

	if not BanData then return end

	local CurTime = Time()

	if BanData.UnbanTime == 0 or BanData.UnbanTime > CurTime then
		if Player.TriggerInvalidSound then
			Player:TriggerInvalidSound()
		end

		if Shine:CanNotify( Client ) then
			local Duration = BanData.UnbanTime == 0 and "permanently"
				or "for "..string.TimeToString( BanData.UnbanTime - CurTime )

			self:Notify( Client, "You are banned from commanding %s.", true, Duration )
		end

		return false
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
