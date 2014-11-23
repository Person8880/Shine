--[[
	Shine AFK kick plugin.
]]

local Shine = Shine

local GetHumanPlayerCount = Shine.GetHumanPlayerCount
local GetOwner = Server.GetOwner
local pcall = pcall
local SharedTime = Shared.GetTime

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "AFKKick.json"

Plugin.Users = setmetatable( {}, { __mode = "k" } )

Plugin.DefaultConfig = {
	MinPlayers = 10,
	WarnMinPlayers = 5,
	Delay = 1,
	WarnTime = 5,
	KickTime = 15,
	--CommanderTime = 0.5,
	IgnoreSpectators = false,
	Warn = true,
	MoveToReadyRoomOnWarn = false,
	MoveToSpectateOnWarn = false,
	OnlyCheckOnStarted = false
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	local Edited
	if self.Config.WarnMinPlayers > self.Config.MinPlayers then
		self.Config.WarnMinPlayers = self.Config.MinPlayers
		Edited = true
	end

	if self.Config.MoveToReadyRoomOnWarn and self.Config.MoveToSpectateOnWarn then
		self.Config.MoveToReadyRoomOnWarn = false
		Edited = true
	end

	if Edited then
		self:SaveConfig( true )
	end

	if self.Enabled ~= nil then
		for Client in pairs( self.Users ) do
			if Shine:IsValidClient( Client ) then
				self:ResetAFKTime( Client )
			else
				self.Users[ Client ] = nil
			end
		end

		local Clients, Count = Shine.GetAllClients()
		for i = 1, Count do
			local Client = Clients[ i ]
			if not self.Users[ Client ] then
				self:ClientConnect( Client )
			end
		end
	end

	self.Enabled = true

	return true
end

--[[
	On client connect, add the client to our table of clients.
]]
function Plugin:ClientConnect( Client )
	if not Client then return end

	if Client:GetIsVirtual() then return end

	local Player = Client:GetControllingPlayer()

	if not Player then return end

	self.Users[ Client ] = {
		LastMove = SharedTime() + ( self.Config.Delay * 60 ),
		Pos = Player:GetOrigin(),
		Ang = Player:GetViewAngles()
	}
end

function Plugin:ResetAFKTime( Client )
	local DataTable = self.Users[ Client ]

	if not DataTable then return end

	DataTable.LastMove = SharedTime()

	if DataTable.Warn then
		DataTable.Warn = false
	end
end

--[[
	Hook into movement processing to help prevent false positive AFK kicking.
]]
function Plugin:OnProcessMove( Player, Input )
	local Gamerules = GetGamerules()
	local Started = Gamerules and Gamerules:GetGameStarted()

	local Client = GetOwner( Player )

	if not Client then return end
	if Client:GetIsVirtual() then return end

	local DataTable = self.Users[ Client ]
	if not DataTable then return end

	local Time = SharedTime()

	if self.Config.OnlyCheckOnStarted and not Started then
		DataTable.LastMove = Time

		return
	end

	local Players = GetHumanPlayerCount()
	if Players < self.Config.WarnMinPlayers then
		DataTable.LastMove = Time

		return
	end

	local Move = Input.move

	local Team = Player:GetTeamNumber()

	if Team == kSpectatorIndex and self.Config.IgnoreSpectators then
		DataTable.LastMove = Time
		DataTable.Warn = false

		return
	end

	--Ignore players waiting to respawn/watching the end of the game.
	if Player:GetIsWaitingForTeamBalance() or ( Player.GetIsRespawning
	and Player:GetIsRespawning() ) or Player:isa( "TeamSpectator" ) then
		DataTable.LastMove = Time
		DataTable.Warn = false

		return
	end

	local Pitch, Yaw = Input.pitch, Input.yaw

	if not ( Move.x == 0 and Move.y == 0 and Move.z == 0 and Input.commands == 0
	and DataTable.LastYaw == Yaw and DataTable.LastPitch == Pitch ) then
		DataTable.LastMove = Time

		if DataTable.Warn then
			DataTable.Warn = false
		end
	end

	DataTable.LastPitch = Pitch
	DataTable.LastYaw = Yaw

	if Shine:HasAccess( Client, "sh_afk" ) then --Immunity.
		return
	end

	local KickTime = self.Config.KickTime * 60

	if not DataTable.Warn and self.Config.Warn then
		local WarnTime = self.Config.WarnTime * 60

		if DataTable.LastMove + WarnTime < Time then
			DataTable.Warn = true

			local AFKTime = Time - DataTable.LastMove
			
			Shine.SendNetworkMessage( Client, "AFKWarning", {
				timeAFK = AFKTime,
				maxAFKTime = KickTime
			}, true )

			--Sometimes this event receives one of the weird "ghost" players that can't switch teams.
			if self.Config.MoveToReadyRoomOnWarn and Team ~= kTeamReadyRoom then
				Player = Client:GetControllingPlayer()
				pcall( Gamerules.JoinTeam, Gamerules, Player, kTeamReadyRoom, nil, true )
			elseif self.Config.MoveToSpectateOnWarn and Team ~= kSpectatorIndex then
				Player = Client:GetControllingPlayer()
				pcall( Gamerules.JoinTeam, Gamerules, Player, kSpectatorIndex, nil, true )
			end

			return
		end

		return
	end

	if Shine:HasAccess( Client, "sh_afk_partial" ) then return end

	--Only kick if we're past the min player count to do so.
	if DataTable.LastMove + KickTime < Time and Players >= self.Config.MinPlayers then
		self:ClientDisconnect( Client ) --Failsafe.

		Shine:Print( "Client %s[%s] was AFK for over %s. Player count: %i. Min Players: %i. Kicking...",
			true, Player:GetName(), Client:GetUserId(), string.TimeToString( KickTime ),
			Players, self.Config.MinPlayers )

		Client.DisconnectReason = "AFK for too long"

		Server.DisconnectClient( Client )
	end
end

function Plugin:PlayerSay( Client, MessageTable )
	self:ResetAFKTime( Client )
end

function Plugin:CanPlayerHearPlayer( Gamerules, Listener, Speaker )
	local Client = GetOwner( Speaker )
	if Client then
		self:ResetAFKTime( Client )
	end
end

if not Shine.IsNS2Combat then
	function Plugin:OnConstructInit( Building )
		local ID = Building:GetId()
		local Team = Building:GetTeam()

		if not Team or not Team.GetCommander then return end

		local Owner = Building:GetOwner()
		Owner = Owner or Team:GetCommander()

		if not Owner then return end
		
		local Client = GetOwner( Owner )

		if not Client then return end

		self:ResetAFKTime( Client )
	end

	function Plugin:OnRecycle( Building, ResearchID )
		local ID = Building:GetId()
		local Team = Building:GetTeam()

		if not Team or not Team.GetCommander then return end

		local Commander = Team:GetCommander()
		if not Commander then return end

		local Client = GetOwner( Commander )
		if not Client then return end
		
		self:ResetAFKTime( Client )
	end

	function Plugin:OnCommanderTechTreeAction( Commander, ... )
		local Client = GetOwner( Commander )
		if not Client then return end
		
		self:ResetAFKTime( Client )
	end

	function Plugin:OnCommanderNotify( Commander, ... )
		local Client = GetOwner( Commander )
		if not Client then return end
		
		self:ResetAFKTime( Client )
	end
end

--[[
	Other plugins may wish to know this.
]]
function Plugin:GetLastMoveTime( Client )
	if not self.Users[ Client ] then return nil end
	return self.Users[ Client ].LastMove
end

--[[
	Returns true if the given client has been AFK for greater than the given time.
]]
function Plugin:IsAFKFor( Client, Time )
	local LastMove = self:GetLastMoveTime( Client )
	if not LastMove then return false end

	return SharedTime() - LastMove > Time
end

--[[
	When a client disconnects, remove them from the player list.
]]
function Plugin:ClientDisconnect( Client )
	if self.Users[ Client ] then
		self.Users[ Client ] = nil
	end
end

--Override the built in randomise ready room vote to not move AFK players.
Shine.Hook.Add( "Think", "AFKKick_OverrideVote", function()
	Shine.Hook.Remove( "Think", "AFKKick_OverrideVote" )

	local PlayingTeamNumbers = {
		true, true
	}

	SetVoteSuccessfulCallback( "VoteRandomizeRR", 2, function( Data )
		local Gamerules = GetGamerules()
		local ReadyRoomPlayers = Gamerules:GetTeam( kTeamReadyRoom ):GetPlayers()
		local Enabled, AFKPlugin = Shine:IsExtensionEnabled( "afkkick" )

		for i = #ReadyRoomPlayers, 1, -1 do
			local Player = ReadyRoomPlayers[ i ]

			if Enabled then
				if Player then
					local Client = GetOwner( Player )

					if Client then
						if not AFKPlugin:IsAFKFor( Client, 60 ) then
							JoinRandomTeam( Player )
						else
							local Team = Player:GetTeamNumber()
							if PlayingTeamNumbers[ Team ] then
								pcall( Gamerules.JoinTeam, Gamerules, Player, 
									kTeamReadyRoom, nil, true )
							end
						end
					end
				end
			else
				JoinRandomTeam( Player )
			end
		end
	end )

	if Shine.IsNS2Combat then return end

	local TableRemove = table.remove

	local OldGetPlayers
	OldGetPlayers = Shine.SetUpValue( ForceEvenTeams, "ForceEvenTeams_GetPlayers", function()
		local Enabled, AFKPlugin = Shine:IsExtensionEnabled( "afkkick" )
		if not Enabled then
			return OldGetPlayers()
		end

		local Gamerules = GetGamerules()
		local Players, Count = Shine.GetAllPlayers()
		local Offset = 0

		for i = 1, Count do
			local Key = i - Offset
			local Player = Players[ Key ]
			local Client = GetOwner( Player )

			if not Client or AFKPlugin:IsAFKFor( Client, 60 ) then
				TableRemove( Players, Key )
				Offset = Offset + 1

				if Client and PlayingTeamNumbers[ Player:GetTeamNumber() ] then
					pcall( Gamerules.JoinTeam, Gamerules, Player, kTeamReadyRoom, nil, true )
				end
			end
		end

		return Players
	end )
end )

Shine:RegisterExtension( "afkkick", Plugin )
