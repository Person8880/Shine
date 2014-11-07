--[[
	Fun commands shared.
]]

local Plugin = {}

Shine:RegisterExtension( "funcommands", Plugin )

if Server then return end

local SGUI = Shine.GUI

local TableConcat = table.concat

function Plugin:Initialise()
	self:SetupAdminMenuCommands()

	self.Enabled = true

	return true
end

function Plugin:SetupAdminMenuCommands()
	local Category = "Fun Commands"

	self:AddAdminMenuCommand( Category, "Go To", "sh_goto", false, nil,
		"Teleports you to the selected player." )
	self:AddAdminMenuCommand( Category, "Bring", "sh_bring", false, nil,
		"Brings the selected player to you." )
	self:AddAdminMenuCommand( Category, "Slay", "sh_slay", false, nil,
		"Kills the selected player." )
	self:AddAdminMenuCommand( Category, "Darwin Mode", "sh_darwin", true, {
		"Enable", "true",
		"Disable", "false"
	}, "Toggles invulnerability and infinite\nammo on the selected player(s)." )
end
