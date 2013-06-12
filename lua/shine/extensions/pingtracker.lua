--[[
	Shine ping tracking plugin.
]]

local Plugin = {}

local Abs = math.abs
local Ceil = math.ceil
local Floor = math.floor
local Notify = Shared.Message
local pairs = pairs
local StringFormat = string.format
local TableAverage = table.Average
local TableEmpty = table.Empty

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "PingTracker.json"

function Plugin:Initialise()
	self.Players = {}

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		MaxPing = 200, --Maximum allowed average ping.
		MaxJitter = 50, --Maximum allowed average jitter.
		Warn = true, --Should players be warned first?
		MeasureInterval = 1, --Time in seconds between measurements.
		CheckInterval = 60, --Interval to check averages and warn/kick.
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing pingtracker config file: "..Err )	

			return	
		end

		Notify( "Shine pingtracker config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing pingtracker config file: "..Err )

		return	
	end

	Notify( "Shine pingtracker config file updated." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig

	self.Config.CheckInterval = Floor( self.Config.CheckInterval )
end

function Plugin:ClientConnect( Client )
	local Time = Shared.GetTime()

	local FirstCheck = Time + 30
	local NextAverage = FirstCheck + self.Config.CheckInterval

	self.Players[ Client ] = {
		NextCheck = FirstCheck,
		NextAverage = NextAverage,
		TimesOver = 0,
		Pings = {},
		DeltaPings = {}
	}
end

function Plugin:ClientDisconnect( Client )
	self.Players[ Client ] = nil
end

function Plugin:CheckClient( Client, Data, Time )
	if not self.Players[ Client ] then return end
	if Shine:HasAccess( Client, "sh_pingimmune" ) then return end

	if Data.NextCheck > Time then return end
	
	Data.NextCheck = Time + self.Config.MeasureInterval

	local Pings = Data.Pings
	local DeltaPings = Data.DeltaPings

	local Ping = Client:GetPing()
	local LastPing = Pings[ #Pings ]

	if LastPing then
		DeltaPings[ #DeltaPings + 1 ] = Abs( Ping - LastPing )
	end

	Pings[ #Pings + 1 ] = Ping

	if Data.NextAverage < Time then
		local AveragePing = TableAverage( Pings )
		local AverageJitter = TableAverage( DeltaPings )

		local ShouldIncrease

		if AveragePing > self.Config.MaxPing then
			if Data.TimesOver == 0 and self.Config.Warn then
				ShouldIncrease = true

				Shine:NotifyColour( Client, 255, 160, 0, "Your ping is averaging at %s, which is too high for this server.", true, Ceil( AveragePing ) )
				Shine:NotifyColour( Client, 255, 160, 0, "If you do not lower it you will be kicked." )
			else
				Shine:LogString( StringFormat( "[PingTracker] Kicked client %s[%s]. Average ping: %.2f. Average jitter: %.2f.", 
					Client:GetControllingPlayer():GetName(), Client:GetUserId(), AveragePing, AverageJitter ) )

				Server.DisconnectClient( Client )

				return
			end
		end

		if AverageJitter > self.Config.MaxJitter then
			if Data.TimesOver == 0 and self.Config.Warn then
				ShouldIncrease = true

				Shine:NotifyColour( Client, 255, 160, 0, "Your ping is varying by an average of %s, which is too high for this server.", true, Ceil( AverageJitter ) )
				Shine:NotifyColour( Client, 255, 160, 0, "If you do not lower it you will be kicked." )
			else
				Shine:LogString( StringFormat( "[PingTracker] Kicked client %s[%s]. Average ping: %.2f. Average jitter: %.2f.", 
					Client:GetControllingPlayer():GetName(), Client:GetUserId(), AveragePing, AverageJitter ) )

				Server.DisconnectClient( Client )

				return
			end
		end

		if ShouldIncrease then
			Data.TimesOver = 1
		end

		TableEmpty( Pings )
		TableEmpty( DeltaPings )

		Data.NextAverage = Time + self.Config.CheckInterval
	end
end

function Plugin:Think()
	local Time = Shared.GetTime()

	for Client, Data in pairs( self.Players ) do
		self:CheckClient( Client, Data, Time )
	end
end

function Plugin:Cleanup()
	self.Players = nil

	self.Enabled = false
end

Shine:RegisterExtension( "pingtracker", Plugin )
