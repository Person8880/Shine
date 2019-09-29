--[[
	Shine MotD system.
]]

local Shine = Shine

local IsType = Shine.IsType
local tonumber = tonumber

local Plugin = Shine.Plugin( ... )
Plugin.Version = "1.3"

Plugin.HasConfig = true
Plugin.ConfigName = "MotD.json"
Plugin.MessageDisplayHistoryFile = "config://shine/temp/motd_history.json"

Plugin.MessageDisplayMode = table.AsEnum{
	"TEXT_ONLY", "WEBPAGE_ONLY", "TEXT_ON_CONNECT"
}

Plugin.DefaultConfig = {
	Mode = Plugin.MessageDisplayMode.TEXT_ONLY,
	URL = "https://www.unknownworlds.com/ns2/",
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

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.3",
		Apply = Shine.Migrator()
			:UseEnum( "Mode", Plugin.MessageDisplayMode )
	}
}

do
	local Validator = Shine.Validator()

	Validator:AddFieldRule( "Mode", Validator.InEnum( Plugin.MessageDisplayMode, Plugin.DefaultConfig.Mode ) )
	Validator:AddFieldRule( "MessageColour", Validator.Each(
		Validator.IsType( "number", 255 )
	) )
	Validator:AddFieldRule( "MessageColour", Validator.Each(
		Validator.Clamp( 0, 255 )
	) )
	Validator:AddFieldRule( "Delay", Validator.Min( 0 ) )

	Plugin.ConfigValidator = Validator
end

function Plugin:Initialise()
	self:CreateCommands()
	self:LoadMessageDisplayHistory()

	self.Enabled = true

	return true
end

function Plugin:MapChange()
	self:SaveMessageDisplayHistory()
end

function Plugin:LoadMessageDisplayHistory()
	self.MessageDisplayHistory = Shine.LoadJSONFile( self.MessageDisplayHistoryFile ) or {
		Displayed = {}
	}

	if not IsType( self.MessageDisplayHistory.Displayed, "table" ) then
		self.MessageDisplayHistory.Displayed = {}
	end
end

function Plugin:SaveMessageDisplayHistory()
	Shine.SaveJSONFile( self.MessageDisplayHistory, self.MessageDisplayHistoryFile )
end

function Plugin:ShowMotD( Client, OnConnect )
	if not Shine:IsValidClient( Client ) then return false end

	local Mode = self.Config.Mode

	if Mode == self.MessageDisplayMode.TEXT_ONLY
	or ( Mode == self.MessageDisplayMode.TEXT_ON_CONNECT and OnConnect ) then
		local Messages = self.Config.MessageText
		local Colour = self.Config.MessageColour

		local function GetColourValue( Index )
			return tonumber( Colour[ Index ] ) or 255
		end

		for i = 1, #Messages do
			Shine:NotifyColour(
				Client,
				GetColourValue( 1 ), GetColourValue( 2 ), GetColourValue( 3 ),
				Messages[ i ]
			)
		end

		return true
	end

	Shine.SendNetworkMessage( Client, "Shine_Web", {
		URL = self.Config.URL,
		Title = "MESSAGE_OF_THE_DAY"
	}, true )

	return true
end

function Plugin:ClientConfirmConnect( Client )
	if Client:GetIsVirtual() then return end

	local ID = tostring( Client:GetUserId() )
	if self.Config.Accepted[ ID ] or self.MessageDisplayHistory.Displayed[ ID ] then
		return
	end

	if Shine:HasAccess( Client, "sh_showmotd" ) then return end

	self:SimpleTimer( self.Config.Delay, function()
		if self:ShowMotD( Client, true ) then
			-- Remember that the client has seen the MOTD already and don't display it again until they disconnect.
			-- This stops the message popping up after every map change.
			self.MessageDisplayHistory.Displayed[ ID ] = true
		end
	end )
end

function Plugin:ClientDisconnect( Client )
	if Client:GetIsVirtual() then return end

	local ID = tostring( Client:GetUserId() )
	if self.MessageDisplayHistory.Displayed[ ID ] then
		self.MessageDisplayHistory.Displayed[ ID ] = nil
		self:SaveMessageDisplayHistory()
	end
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

		local ID = tostring( Client:GetUserId() )

		if self.Config.Accepted[ ID ] then
			self:NotifyTranslated( Client, "ALREADY_ACCEPTED_MOTD" )
			return
		end

		self.Config.Accepted[ ID ] = true
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

return Plugin
