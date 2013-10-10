--[[
	Shine MotD system.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode

local Plugin = {}
Plugin.Version = "1.1"

Plugin.HasConfig = true
Plugin.ConfigName = "MotD.json"

Plugin.TEXT_MODE = 1
Plugin.HTML_MODE = 2
Plugin.HYBRID_MODE = 3

Plugin.DefaultConfig = {
	Mode = Plugin.TEXT_MODE,
	URL = "http://www.unknownworlds.com/ns2/",
	MessageText = { "Welcome to my awesome server!", "Admins can be reached @ mywebsite.com", "Have a pleasant stay!" }, --Message lines.
	Accepted = {},
	Delay = 5
}

Plugin.CheckConfig = true

function Plugin:Initialise()
	self:CreateCommands()

	self.Enabled = true
	
	return true
end

function Plugin:Notify( Player, String, Format, ... )
	Shine:NotifyDualColour( Player, 0, 100, 255, "[MOTD]", 255, 255, 255, String, Format, ... )
end

function Plugin:ShowMotD( Client, OnConnect )
	if not Shine:IsValidClient( Client ) then return end
	
	local Mode = self.Config.Mode

	if Mode == self.TEXT_MODE or ( Mode == self.HYBRID_MODE and OnConnect ) then
		local Messages = self.Config.MessageText

		for i = 1, #Messages do
			Shine:Notify( Client, "", "", Messages[ i ] )
		end

		return
	end

	Server.SendNetworkMessage( Client, "Shine_Web", { URL = self.Config.URL, Title = "Message of the day" }, true )
end

function Plugin:ClientConfirmConnect( Client )
	if Client:GetIsVirtual() then return end
	
	local ID = Client:GetUserId()

	if self.Config.Accepted[ tostring( ID ) ] then return end

	if Shine:HasAccess( Client, "sh_showmotd" ) then return end

	Shine.Timer.Simple( self.Config.Delay, function()
		self:ShowMotD( Client, true )
	end )
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function MotD( Client )
		if not Client then return end

		self:ShowMotD( Client )
	end
	local MotDCommand = self:BindCommand( "sh_motd", "motd", MotD, true )
	MotDCommand:Help( "Shows the message of the day." )

	local function AcceptMotD( Client )
		if not Client then return end

		local ID = Client:GetUserId()

		if self.Config.Accepted[ tostring( ID ) ] then
			self:Notify( Client, "You have already accepted the message of the day." )

			return
		end

		self.Config.Accepted[ tostring( ID ) ] = true
		self:SaveConfig()

		self:Notify( Client, "Thank you for accepting the message of the day." )
	end
	local AcceptMotDCommand = self:BindCommand( "sh_acceptmotd", "acceptmotd", AcceptMotD, true )
	AcceptMotDCommand:Help( "Accepts the message of the day so you no longer see it on connect." )

	local function ShowMotD( Client, Target )
		self:ShowMotD( Target )
	end
	local ShowMotDCommand = self:BindCommand( "sh_showmotd", "showmotd", ShowMotD )
	ShowMotDCommand:AddParam{ Type = "client" }
	ShowMotDCommand:Help( "<player> Shows the message of the day to the given player." )
end

Shine:RegisterExtension( "motd", Plugin )
