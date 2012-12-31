--[[
	Shine adverts system.
]]

local Encode, Decode = json.encode, json.decode
local Notify = Shared.Message

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "Adverts.json"

Plugin.TimerName = "Adverts"

function Plugin:Initialise()
	self:SetupTimer()

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		Adverts = { "Welcome to Natural Selection 2.", "This server is running the Shine administration mod." },
		Interval = 60
	}

	if Save then
		local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

		if not PluginConfig then
			Notify( "Error writing adverts config file: "..Err )	

			return	
		end

		PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

		Notify( "Shine adverts config file created." )

		PluginConfig:close()
	end
end

function Plugin:SaveConfig()
	local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

	if not PluginConfig then
		Notify( "Error writing adverts config file: "..Err )	

		return	
	end

	PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

	Shine:Print( "Shine adverts config file saved." )

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

function Plugin:SetupTimer()
	if Shine.Timer.Exists( self.TimerName ) then
		Shine.Timer.Destroy( self.TimerName )
	end

	if #self.Config.Adverts == 0 then return end

	local Message = 1

	Shine.Timer.Create( self.TimerName, self.Config.Interval, -1, function()
		Shine:Notify( nil, "", "", self.Config.Adverts[ Message ] )
		Message = ( Message % #self.Config.Adverts ) + 1
	end )
end

function Plugin:Cleanup()
	Shine.Timer.Destroy( self.TimerName )

	self.Enabled = false
end

Shine:RegisterExtension( "adverts", Plugin )
