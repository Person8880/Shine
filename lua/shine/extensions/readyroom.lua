--[[
	Shine ready room plugin.

	Allows for setting a max idle time in the ready room, disabling the spectator mode etc.
]]

local Shine = Shine

local Notify = Shared.Message
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

function Plugin:Initialise()
	local Gamerules = GetGamerules()

	if Gamerules and Gamerules:GetGameStarted() then
		self.GameStarted = true
	end 

	self.ReadyRoomTracker = {}
	self.BlockedClients = {}

	self.TeamMemory = {}

	self.Enabled = true

	return true
end

--Prevent players from joining the spectator team, and prevent going back to the ready room after being forced out of it.
function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce then return end
	if NewTeam ~= kSpectatorIndex and NewTeam ~= kTeamReadyRoom then return end

	local Client = Player:GetClient()

	if not Client then return end

	local Time = SharedTime()

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

	local ReadyRoomTracker = self.ReadyRoomTracker

	for k in pairs( ReadyRoomTracker ) do
		ReadyRoomTracker[ k ] = nil
	end

	local BlockedClients = self.BlockedClients

	for k in pairs( BlockedClients ) do
		BlockedClients[ k ] = nil
	end

	local Players = Shine.GetAllPlayers()
	local GetOwner = Server.GetOwner

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
	
	if Team1 < Team2 then
		Gamerules:JoinTeam( Player, 1, nil, true )
	elseif Team2 < Team1 then
		Gamerules:JoinTeam( Player, 2, nil, true )
	else
		local Client = Server.GetOwner( Player )

		if Client then
			local LastTeam = self.TeamMemory[ Client ]

			--Place them on the opposite team to their last round.
			if LastTeam == 1 then
				Gamerules:JoinTeam( Player, 2, nil, true )

				return
			elseif LastTeam == 2 then
				Gamerules:JoinTeam( Player, 1, nil, true )
			
				return
			end
		end

		if Random() < 0.5 then
			Gamerules:JoinTeam( Player, 1, nil, true )
		else
			Gamerules:JoinTeam( Player, 2, nil, true )
		end
	end
end

function Plugin:AssignToTeam( Player )
	if self.Config.NotifyOnTeamForce then
		Shine:NotifyColour( Player, 255, 160, 0, "You were moved onto a random team for being in the ready room too long." )
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
		local AFKKick = Shine.Plugins.afkkick

		if AFKKick and AFKKick.Enabled then
			local LastMoveTime = AFKKick:GetLastMoveTime( Client )

			--Ignore AFK players.
			if Time - LastMoveTime >= ( AFKKick.Config.WarnTime * 60 ) then
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

	local MapVote = Shine.Plugins.mapvote
	local Time = SharedTime()

	--Disable on map cycling/end vote.
	if MapVote and MapVote.Enabled then
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
