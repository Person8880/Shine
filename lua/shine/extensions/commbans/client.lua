--[[
	Commbans client.
]]

local Plugin = ...

Plugin.AdminTab = "Comm Bans"

Plugin.BanCommand = "sh_commbanid"
Plugin.UnbanCommand = "sh_uncommban"

Plugin.AdminMenuIcon = Shine.GUI.Icons.Ionicons.Thumbsdown

function Plugin:Initialise()
	self:SetupAdminMenu()

	self.Enabled = true

	return true
end
