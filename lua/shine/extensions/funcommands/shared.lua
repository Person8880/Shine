--[[
	Base commands shared.
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

	self:AddAdminMenuCommand( Category, "Go To", "sh_goto", false )
	self:AddAdminMenuCommand( Category, "Bring", "sh_bring", false )
	self:AddAdminMenuCommand( Category, "Slay", "sh_slay", false )
	self:AddAdminMenuCommand( Category, "Darwin Mode", "sh_darwin", true, {
		"Enable", "true",
		"Disable", "false"
	} )
end
