--[[
	Shine ready room plugin.

	Allows for setting a max idle time in the ready room, disabling the spectator mode etc.
]]

local Shine = Shine

local Notify = Shared.Message
local pairs = pairs
local StringFormat = string.format

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ReadyRoom.json"

function Plugin:Initialise()
	local Gamerules = GetGamerules()

	if Gamerules and Gamerules:GetGameStarted() then
		self.GameStarted = true
	end 

	self.ReadyRoomTracker = {}
	self.BlockedClients = {}

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		TrackReadyRoomPlayers = true, --Should it track people in the ready room?
		MaxIdleTime = 120, --Max time in seconds to allow sitting in the ready room.
		TimeToBlockF4 = 120, --Time to block going back to the ready room after being forced out of it.
		DisableSpectate = false, --Disable spectate?
		TrackOnRoundStart = true, --Only track when a round has started?
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing readyroom config file: "..Err )	

			return	
		end

		Notify( "Shine readyroom config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing readyroom config file: "..Err )

		return	
	end

	Notify( "Shine readyroom config file updated." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig

	if self.Config.TrackOnRoundStart == nil then
		self.Config.TrackOnRoundStart = true
		self:SaveConfig()
	end
end

--Prevent players from joining the spectator team, and prevent going back to the ready room after being forced out of it.
function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if NewTeam ~= kSpectatorIndex and NewTeam ~= kTeamReadyRoom then return end

	local Client = Player:GetClient()

	if not Client then return end

	local Time = Shared.GetTime()

	if NewTeam == kTeamReadyRoom then --Block people from going back to the ready room.
		local TimeToAllow = self.BlockedClients[ Client ]

		if TimeToAllow and TimeToAllow > Time then
			local NextNotify = Client.SHNextNotify or 0

			if NextNotify > Time then return false end

			Client.SHNextNotify = Time + 5

			Shine:NotifyColour( Client, 255, 160, 0, "You have just been moved to a team. You cannot go back to the ready room yet." )

			return false
		end

		return
	end

	if not self.Config.DisableSpectate then return end
	if Shine:HasAccess( Client, "sh_idleimmune" ) then return end

	local NextNotify = Client.SHNextNotify or 0

	if NextNotify > Time then return false end

	Client.SHNextNotify = Time + 5 --Prevent message spam.

	Shine:NotifyColour( Client, 255, 160, 0, "Spectator mode has been disabled." )

	local Team = Player:GetTeam():GetTeamNumber()

	--Move ready room players onto a team if they attempt to spectate.
	if Team == kTeamReadyRoom then
		JoinRandomTeam( Player )
	end

	return false
end

function Plugin:SetGameState( Gamerules, State, OldState )
	if State == kGameState.Started then
		self.GameStarted = true
	end
end

--[[
	Clear out the tracking times and blocking on game end.
]]
function Plugin:EndGame()
	self.GameStarted = false

	local ReadyRoomTracker = self.ReadyRoomTracker

	for k in pairs( ReadyRoomTracker ) do
		ReadyRoomTracker[ k ] = nil
	end

	local BlockedClients = self.BlockedClients

	for k in pairs( BlockedClients ) do
		BlockedClients[ k ] = nil
	end
end

function Plugin:AssignToTeam( Player )
	Shine:NotifyColour( Player, 255, 160, 0, "You were moved onto a random team for being in the ready room too long." )
	return JoinRandomTeam( Player )
end

function Plugin:ProcessClient( Client, Time )
	local ReadyRoomTracker = self.ReadyRoomTracker
	local BlockedClients = self.BlockedClients

	if Shine:HasAccess( Client, "sh_idleimmune" ) then return end --Immunity for admins.

	local Player = Client:GetControllingPlayer()

	if not Player then return end
	
	local Team = Player:GetTeam():GetTeamNumber()

	if Team == kTeamReadyRoom then
		local TimeToMove = ReadyRoomTracker[ Client ]
		
		if not TimeToMove then
			ReadyRoomTracker[ Client ] = Time + self.Config.MaxIdleTime
		else
			if TimeToMove < Time then
				self:AssignToTeam( Player )
				ReadyRoomTracker[ Client ] = nil
				BlockedClients[ Client ] = Time + self.Config.TimeToBlockF4
			end
		end
	else
		if ReadyRoomTracker[ Client ] then
			ReadyRoomTracker[ Client ] = nil
		end

		local BlockTime = BlockedClients[ Client ]

		if BlockTime and BlockTime < Time then
			BlockedClients[ Client ] = nil
		end
	end
end

--[[
	Updates the state of ready room idling/time to allow going back to the ready room.
]]
function Plugin:Think()
	if not self.GameStarted and self.Config.TrackOnRoundStart then return end
	if not self.Config.TrackReadyRoomPlayers then return end

	local Time = Shared.GetTime()

	if ( self.NextThink or 0 ) > Time then return end
	
	self.NextThink = Time + 1

	local Clients = Shine.GameIDs

	for Client in pairs( Clients ) do
		self:ProcessClient( Client, Time )
	end
end

function Plugin:Cleanup()
	self.ReadyRoomTracker = nil
	self.BlockedClients = nil

	self.GameStarted = nil

	self.Enabled = false
end

Shine:RegisterExtension( "readyroom", Plugin )
