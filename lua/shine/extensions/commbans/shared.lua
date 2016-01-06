--[[
	Shine commander bans plugin.
]]

local Plugin = {}

Plugin.NS2Only = true

Shine:RegisterExtension( "commbans", Plugin, {
	Base = "ban",
	BlacklistKeys = {
		CheckConnectionAllowed = true,
		ClientConnect = true,
		OnWebConfigLoaded = true,
		BanNetworkData = true,
		BanNetworkedClients = true,
		BanList = true,
		Rows = true,
		BanData = true,
		SaveConfig = true
	}
} )

if Server then return end

Plugin.AdminTab = "Comm Bans"

Plugin.BanCommand = "sh_commbanid"
Plugin.UnbanCommand = "sh_uncommban"

function Plugin:Initialise()
	self:SetupAdminMenu()

	self.Enabled = true

	return true
end
