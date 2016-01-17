--[[
	Shine ready room plugin.

	Allows for setting a max idle time in the ready room, disabling the spectator mode etc.
]]

local Shine = Shine

local GetOwner = Server.GetOwner
local pairs = pairs
local Random = math.random
local SharedTime = Shared.GetTime
local StringFormat = string.format
local TableEmpty = table.Empty

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ReadyRoom.json"

Plugin.DefaultConfig = {
	TrackReadyRoomPlayers = true, --Should it track people in the ready room?
	MaxIdleTime = 120, --Max time in seconds to allow sitting in the ready room.
	TimeToBlockF4 = 120, --Time to block going back to the ready room after being forced out of it.
	DisableSpectate = false, --Disable spectate?
	TrackOnRoundStart = true, --Only track when a round has started?
	NotifyOnTeamForce = true, --Tell players they've been placed on a team?
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.NotifyPrefixColour = {
	255, 160, 0
}

function Plugin:Initialise()
	local Gamerules = GetGamerules and GetGamerules()

	if Gamerules and Gamerules:GetGameStarted() then
		self.GameStarted = true
	end

	self.ReadyRoomTracker = {}
	self.BlockedClients = {}

	self.TeamMemory = {}

	self.Enabled = true

	return true
end

--[[
	Prevent players from joining the spectator team,
	and prevent going back to the ready room after being forced out of it.
]]
function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce then return end

	if NewTeam ~= kSpectatorIndex and NewTeam ~= kTeamReadyRoom then return end

	local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
	if Enabled and ( MapVote.CyclingMap or MapVote:IsEndVote() ) then
		return
	end

	local Client = GetOwner( Player )

	if not Client then return end
	if Client.JoinTeamRRPlugin then return end

	local Time = SharedTime()

	if NewTeam == kTeamReadyRoom then --Block people from going back to the ready room.
		local TimeToAllow = self.BlockedClients[ Client ]

		if TimeToAllow and TimeToAllow > Time then
			if not Shine:CanNotify( Client ) then return false end

			self:NotifyTranslated( Client, "SWITCH_TEAM_BLOCKED" )

			return false
		end

		return
	end

	if not self.Config.DisableSpectate then return end
	if Shine:HasAccess( Client, "sh_idleimmune" ) then return end

	if Shine:CanNotify( Client ) then
		self:NotifyTranslated( Client, "SPECTATOR_DISABLED" )
	end

	local Team = Player:GetTeam():GetTeamNumber()

	--Move ready room players onto a team if they attempt to spectate.
	if Team == kTeamReadyRoom then
		self:JoinRandomTeam( Player )
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

	TableEmpty( self.ReadyRoomTracker )
	TableEmpty( self.BlockedClients )

	local Players = Shine.GetAllPlayers()

	for i = 1, #Players do
		local Player = Players[ i ]

		if Player then
			local Client = GetOwner( Player )

			if Client then
				self.TeamMemory[ Client ] = Player:GetTeamNumber()
			end
		end
	end
end

--[[
	Remove the client from memory on disconnect.
]]
function Plugin:ClientDisconnect( Client )
	self.TeamMemory[ Client ] = nil
end

--[[
	Moves a single player onto a random team.
]]
function Plugin:JoinRandomTeam( Player )
	local Gamerules = GetGamerules()
	if not Gamerules then return end

	local Team1 = Gamerules:GetTeam( kTeam1Index ):GetNumPlayers()
	local Team2 = Gamerules:GetTeam( kTeam2Index ):GetNumPlayers()

	local Client = GetOwner( Player )

	if not Client then return end

	Client.JoinTeamRRPlugin = true

	if Team1 < Team2 then
		Gamerules:JoinTeam( Player, 1 )
	elseif Team2 < Team1 then
		Gamerules:JoinTeam( Player, 2 )
	else
		local LastTeam = self.TeamMemory[ Client ]

		--Place them on the opposite team to their last round.
		if LastTeam == 1 then
			Gamerules:JoinTeam( Player, 2 )

			return
		elseif LastTeam == 2 then
			Gamerules:JoinTeam( Player, 1 )

			return
		end

		if Random() < 0.5 then
			Gamerules:JoinTeam( Player, 1 )
		else
			Gamerules:JoinTeam( Player, 2 )
		end
	end

	Client.JoinTeamRRPlugin = nil
end

function Plugin:AssignToTeam( Player )
	if self.Config.NotifyOnTeamForce then
		self:NotifyTranslated( Player, "IN_READY_ROOM_TOO_LONG" )
	end

	return self:JoinRandomTeam( Player )
end

function Plugin:ProcessClient( Client, Time )
	if Client:GetIsVirtual() then return end

	local ReadyRoomTracker = self.ReadyRoomTracker
	local BlockedClients = self.BlockedClients

	if Shine:HasAccess( Client, "sh_idleimmune" ) then return end --Immunity for admins.

	local Player = Client:GetControllingPlayer()

	if not Player then return end

	local Team = Player:GetTeam():GetTeamNumber()

	if Team == kTeamReadyRoom then
		local Enabled, AFKKick = Shine:IsExtensionEnabled( "afkkick" )

		if Enabled then
			--Ignore AFK players.
			if AFKKick:IsAFKFor( Client, AFKKick.Config.WarnTime * 60 ) then
				return
			end
		end

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

	local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
	local Time = SharedTime()

	--Disable on map cycling/end vote.
	if Enabled then
		if MapVote.CyclingMap or MapVote:IsEndVote() then
			TableEmpty( self.ReadyRoomTracker )
			TableEmpty( self.BlockedClients )

			return
		end
	else
		local Gamerules = GetGamerules()

		if Gamerules.timeToCycleMap then return end
	end

	if ( self.NextThink or 0 ) > Time then return end

	self.NextThink = Time + 1

	local Clients = Shine.GameIDs

	for Client in Clients:Iterate() do
		self:ProcessClient( Client, Time )
	end
end

function Plugin:Cleanup()
	self.ReadyRoomTracker = nil
	self.BlockedClients = nil
	self.GameStarted = nil
	self.BaseClass.Cleanup( self )
end

Shine:RegisterExtension( "readyroom", Plugin )
