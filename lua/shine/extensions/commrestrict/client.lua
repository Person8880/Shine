--[[
	Commbans client.
]]

local Plugin = ...

Plugin.AdminTab = "Comm Deprioritize"

Plugin.BanCommand = "sh_commdepid"
Plugin.UnbanCommand = "sh_uncommdep"

Plugin.AdminMenuIcon = Shine.GUI.Icons.Ionicons.Thumbsdown

function Plugin:Initialise()
	self:SetupAdminMenu()

	self.Enabled = true

	return true
end
