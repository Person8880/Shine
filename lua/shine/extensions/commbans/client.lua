--[[
	Commbans client.
]]

local Plugin = ...

Plugin.AdminTab = "Comm Bans"

Plugin.BanCommand = "sh_commbanid"
Plugin.UnbanCommand = "sh_uncommban"

function Plugin:Initialise()
	self:SetupAdminMenu()

	self.Enabled = true

	return true
end
