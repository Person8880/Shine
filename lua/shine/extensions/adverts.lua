--[[
	Shine adverts system.
]]

local Shine = Shine

local Encode, Decode = json.encode, json.decode
local Notify = Shared.Message

local TableRemove = table.remove
local type = type

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
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing adverts config file: "..Err )	

			return	
		end

		Notify( "Shine adverts config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing adverts config file: "..Err )	

		return	
	end

	Notify( "Shine adverts config file saved." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig
end

local function isstring( String )
	return type( String ) == "string"
end

local function istable( Table )
	return type( Table ) == "table"
end

function Plugin:ParseAdvert( ID, Advert )
	if isstring( Advert ) then
		Shine:NotifyDualColour( nil, 255, 255, 255, Advert, 0, 0, 0, "  " )

		return
	end

	if istable( Advert ) then
		local Message = Advert.Message

		if not Message then
			Shine:Print( "[Adverts] Misconfigured advert #%i, missing \"Message\" value.", true, ID )

			TableRemove( self.Config.Adverts, ID )

			return
		end

		local R = Advert.R or Advert.r or 255
		local G = Advert.G or Advert.g or 255
		local B = Advert.B or Advert.b or 255

		local Type = Advert.Type

		if not Type or Type == "chat" then
			Shine:NotifyDualColour( nil, R, G, B, Message, 0, 0, 0, "  " )
		else
			local Position = ( Advert.Position or "top" ):lower()

			local X, Y = 0.5, 0.15
			local Align = 1

			--[[if Position == "left" then
				X, Y = 0.1, 0.5
				Align = 0
			elseif Position == "right" then
				X, Y = 0.9, 0.5
				Align = 2
			else]]if Position == "bottom" then
				X, Y = 0.5, 0.8
			end

			Shine:SendText( nil, Shine.BuildScreenMessage( 20, X, Y, Message, 7, R, G, B, Align, 2, 1 ) )
		end
	end
end

function Plugin:SetupTimer()
	if Shine.Timer.Exists( self.TimerName ) then
		Shine.Timer.Destroy( self.TimerName )
	end

	if #self.Config.Adverts == 0 then return end

	local Message = 1

	Shine.Timer.Create( self.TimerName, self.Config.Interval, -1, function()
		self:ParseAdvert( Message, self.Config.Adverts[ Message ] )
		Message = ( Message % #self.Config.Adverts ) + 1
	end )
end

function Plugin:Cleanup()
	Shine.Timer.Destroy( self.TimerName )

	self.Enabled = false
end

Shine:RegisterExtension( "adverts", Plugin )
