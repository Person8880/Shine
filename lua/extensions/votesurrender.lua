--[[
	Shine surrender vote plugin.
]]

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format

local Ceil = math.ceil
local Floor = math.floor
local Random = math.random

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteSurrender.json"

Plugin.Commands = {}

function Plugin:Initialise()
	self.Votes = {}
	self.Votes[ 1 ] = 0
	self.Votes[ 2 ] = 0

	self.Voted = {}
	self.Voted[ 1 ] = {}
	self.Voted[ 2 ] = {}

	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		PercentNeeded = 0.75, --Percentage of the population needing to vote in order to scramble.
		VoteDelay = 10, --Time after round start before surrender vote is available
		MinPlayers = 10, --Min players needed for voting to be enabled.
	}

	if Save then
		local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

		if not PluginConfig then
			Notify( "Error writing votesurrender config file: "..Err )	

			return	
		end

		PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

		Notify( "Shine votesurrender config file created." )

		PluginConfig:close()
	end
end

function Plugin:SaveConfig()
	local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

	if not PluginConfig then
		Notify( "Error writing votesurrender config file: "..Err )	

		return	
	end

	PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

	Shine:Print( "Shine votesurrender config file saved." )

	PluginConfig:close()
end

function Plugin:LoadConfig()
	local PluginConfig = io.open( Shine.Config.ExtensionDir..self.ConfigName, "r" )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = Decode( PluginConfig:read( "*all" ) )

	PluginConfig:close()
end

function Plugin:CreateCommands()

end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "votesurrender", Plugin )
