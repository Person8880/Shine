--[[
	Fun commands shared.
]]

local Plugin = {}

function Plugin:SetupDataTable()
	local TeleportMessage = {
		TargetName = self:GetNameNetworkField()
	}
	self:AddTranslatedMessage( "TELEPORTED_GOTO", TeleportMessage )
	self:AddTranslatedMessage( "TELEPORTED_BRING", TeleportMessage )
end

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

	self:AddAdminMenuCommand( Category, self:GetPhrase( "GOTO" ), "sh_goto", false, nil,
		self:GetPhrase( "GOTO_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "BRING" ), "sh_bring", false, nil,
		self:GetPhrase( "BRING_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "SLAY" ), "sh_slay", false, nil,
		self:GetPhrase( "SLAY_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "DARWIN_MODE" ), "sh_darwin", true, {
		self:GetPhrase( "ENABLE" ), "true",
		self:GetPhrase( "DISABLE" ), "false"
	}, self:GetPhrase( "DARWIN_MODE_TIP" ) )
end
