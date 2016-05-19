--[[
	Shine MotD system.
]]

local Shine = Shine

local tonumber = tonumber

local Plugin = {}
Plugin.Version = "1.2"

Plugin.HasConfig = true
Plugin.ConfigName = "MotD.json"

Plugin.TEXT_MODE = 1
Plugin.HTML_MODE = 2
Plugin.HYBRID_MODE = 3

Plugin.DefaultConfig = {
	Mode = Plugin.TEXT_MODE,
	URL = "http://www.unknownworlds.com/ns2/",
	MessageText = {
		"Welcome to my awesome server!",
		"Admins can be reached @ mywebsite.com",
		"Have a pleasant stay!"
	},
	MessageColour = { 255, 255, 255 },
	Accepted = {},
	Delay = 5
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.PrintName = "MOTD"
Plugin.NotifyPrefixColour = {
	0, 100, 255
}

function Plugin:Initialise()
	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:ShowMotD( Client, OnConnect )
	if not Shine:IsValidClient( Client ) then return end

	local Mode = self.Config.Mode

	if Mode == self.TEXT_MODE or ( Mode == self.HYBRID_MODE and OnConnect ) then
		local Messages = self.Config.MessageText
		local Colour = self.Config.MessageColour

		local function GetColourValue( Index )
			return tonumber( Colour[ Index ] ) or 255
		end

		for i = 1, #Messages do
			Shine:NotifyColour( Client,
				GetColourValue( 1 ), GetColourValue( 2 ), GetColourValue( 3 ),
				Messages[ i ] )
		end

		return
	end

	Shine.SendNetworkMessage( Client, "Shine_Web", {
		URL = self.Config.URL,
		Title = "MESSAGE_OF_THE_DAY"
	}, true )
end

function Plugin:ClientConfirmConnect( Client )
	if Client:GetIsVirtual() then return end

	local ID = Client:GetUserId()

	if self.Config.Accepted[ tostring( ID ) ] then return end

	if Shine:HasAccess( Client, "sh_showmotd" ) then return end

	self:SimpleTimer( self.Config.Delay, function()
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
			self:NotifyTranslated( Client, "ALREADY_ACCEPTED_MOTD" )

			return
		end

		self.Config.Accepted[ tostring( ID ) ] = true
		self:SaveConfig( true )

		self:NotifyTranslated( Client, "ACCEPTED_MOTD_RESPONSE" )
	end
	local AcceptMotDCommand = self:BindCommand( "sh_acceptmotd", "acceptmotd", AcceptMotD, true )
	AcceptMotDCommand:Help( "Accepts the message of the day so you no longer see it on connect." )

	local function ShowMotD( Client, Target )
		self:ShowMotD( Target )
	end
	local ShowMotDCommand = self:BindCommand( "sh_showmotd", "showmotd", ShowMotD )
	ShowMotDCommand:AddParam{ Type = "client" }
	ShowMotDCommand:Help( "Shows the message of the day to the given player." )
end

Shine:RegisterExtension( "motd", Plugin )
