--[[
	Shine ping tracking plugin.
]]

local Plugin = {}

local Abs = math.abs
local Ceil = math.ceil
local Floor = math.floor
local SharedGetTime = Shared.GetTime
local StringFormat = string.format
local TableAverage = table.Average
local TableEmpty = table.Empty

local Map = Shine.Map

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "PingTracker.json"

Plugin.DefaultConfig = {
	MaxPing = 200, --Maximum allowed average ping.
	MaxJitter = 50, --Maximum allowed average jitter.
	Warn = true, --Should players be warned first?
	MeasureInterval = 1, --Time in seconds between measurements.
	CheckInterval = 60, --Interval to check averages and warn/kick.
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Config.CheckInterval = Floor( self.Config.CheckInterval )

	self.Players = Map()

	self.Enabled = true

	return true
end

function Plugin:ClientConnect( Client )
	local Time = Shared.GetTime()

	local FirstCheck = Time + 30
	local NextAverage = FirstCheck + self.Config.CheckInterval

	self.Players:Add( Client, {
		NextCheck = FirstCheck,
		NextAverage = NextAverage,
		TimesOver = 0,
		Pings = {},
		DeltaPings = {}
	} )
end

function Plugin:ClientDisconnect( Client )
	self.Players:Remove( Client )
end

function Plugin:CheckClient( Client, Data, Time )
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
				local Player = Client:GetControllingPlayer()
				local Name = Player and Player:GetName() or "<unknown>"

				Shine:LogString( StringFormat( "[PingTracker] Kicked client %s[%s]. Average ping: %.2f. Average jitter: %.2f.", 
					Name, Client:GetUserId(), AveragePing, AverageJitter ) )

				Client.DisconnectReason = "Ping too high"

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
				local Player = Client:GetControllingPlayer()
				local Name = Player and Player:GetName() or "<unknown>"
				
				Shine:LogString( StringFormat( "[PingTracker] Kicked client %s[%s]. Average ping: %.2f. Average jitter: %.2f.", 
					Name, Client:GetUserId(), AveragePing, AverageJitter ) )

				Client.DisconnectReason = "Ping jitter too high"

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
	local Time = SharedGetTime()

	for Client, Data in self.Players:Iterate() do
		self:CheckClient( Client, Data, Time )
	end
end

function Plugin:Cleanup()
	self.Players = nil

	self.Enabled = false
end

Shine:RegisterExtension( "pingtracker", Plugin )
