--[[
	Shine AFK kick plugin.
]]

local Shine = Shine

local GetHumanPlayerCount = Shine.GetHumanPlayerCount
local GetOwner = Server.GetOwner
local Max = math.max
local pcall = pcall
local SharedTime = Shared.GetTime

local Plugin = {}
Plugin.Version = "1.5"

Plugin.HasConfig = true
Plugin.ConfigName = "AFKKick.json"

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

do
	local Call = Shine.Hook.Call
	local GetEntity = Shared.GetEntity

	Shine.Hook.SetupClassHook( "PlayerInfoEntity", "UpdateScore", "OnPlayerInfoUpdate",
	function( OldFunc, self )
		local Player = GetEntity( self.playerId )

		if not Player then return OldFunc( self ) end

		Call( "PrePlayerInfoUpdate", self, Player )

		local Ret = OldFunc( self )

		Call( "PostPlayerInfoUpdate", self, Player )

		return Ret
	end )
end

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
	else
		self.Users = {}
	end

	self.Enabled = true

	return true
end

do
	local OldFunc

	local function GetName( self )
		return "AFK - "..OldFunc( self )
	end

	function Plugin:PrePlayerInfoUpdate( PlayerInfo, Player )
		OldFunc = Player.GetName

		local Client = GetOwner( Player )
		local Data = Plugin.Users[ Client ]
		if not Data or not Data.IsAFK then return end

		Player.GetName = GetName
	end

	function Plugin:PostPlayerInfoUpdate( PlayerInfo, Player )
		Player.GetName = OldFunc

		OldFunc = nil
	end
end

--[[
	On client connect, add the client to our table of clients.
]]
function Plugin:ClientConnect( Client )
	if not Client then return end

	if Client:GetIsVirtual() then return end

	local Player = Client:GetControllingPlayer()
	if not Player then return end

	local MeasureStartTime = SharedTime() + ( self.Config.Delay * 60 )

	self.Users[ Client ] = {
		LastMove = MeasureStartTime,
		LastMeasurement = MeasureStartTime,
		AFKAmount = 0,
		Pos = Player:GetOrigin(),
		Ang = Player:GetViewAngles(),
		IsAFK = false
	}
end

function Plugin:ResetAFKTime( Client )
	local DataTable = self.Users[ Client ]
	if not DataTable then return end

	local Time = SharedTime()

	DataTable.LastMove = Time

	if DataTable.Warn then
		DataTable.Warn = false
	end

	DataTable.AFKAmount = 0
	DataTable.LastMeasurement = Time

	if DataTable.IsAFK then
		DataTable.IsAFK = false
	end
end

function Plugin:SubtractAFKTime( Client, Time )
	local DataTable = self.Users[ Client ]
	if not DataTable then return end

	DataTable.LastMove = SharedTime()
	DataTable.LastMeasurement = DataTable.LastMove
	DataTable.AFKAmount = Max( DataTable.AFKAmount - Time, 0 )
	DataTable.IsAFK = false
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
		self:ResetAFKTime( Client )

		return
	end

	local Players = GetHumanPlayerCount()
	if Players < self.Config.WarnMinPlayers then
		self:ResetAFKTime( Client )

		return
	end

	local Move = Input.move

	local Team = Player:GetTeamNumber()

	if Team == kSpectatorIndex and self.Config.IgnoreSpectators then
		self:ResetAFKTime( Client )

		return
	end

	--Ignore players waiting to respawn/watching the end of the game.
	if Player:GetIsWaitingForTeamBalance() or ( Player.GetIsRespawning
	and Player:GetIsRespawning() ) or Player:isa( "TeamSpectator" ) then
		self:ResetAFKTime( Client )

		return
	end

	if DataTable.LastMove > Time then return end

	local Pitch, Yaw = Input.pitch, Input.yaw
	local DeltaTime = Time - DataTable.LastMeasurement

	DataTable.LastMeasurement = Time
	local WarnTime = self.Config.WarnTime * 60

	if not ( Move.x == 0 and Move.y == 0 and Move.z == 0 and Input.commands == 0
	and DataTable.LastYaw == Yaw and DataTable.LastPitch == Pitch ) then
		DataTable.LastMove = Time

		--Subtract the measurement time from their AFK time, so they have to stay
		--active for a while to get it back to 0 time.
		--We use a multiplier as we want activity to count for more than inactivity to avoid
		--overzealous kicks.
		DataTable.AFKAmount = Max( DataTable.AFKAmount - DeltaTime * 5, 0 )

		if self.Config.Warn and DataTable.AFKAmount < WarnTime then
			if DataTable.Warn then
				DataTable.Warn = false
			end
		end
	else
		DataTable.AFKAmount = Max( DataTable.AFKAmount + DeltaTime, 0 )
	end

	DataTable.LastPitch = Pitch
	DataTable.LastYaw = Yaw

	if Shine:HasAccess( Client, "sh_afk" ) then
		return
	end

	local KickTime = self.Config.KickTime * 60

	local AFKAmount = DataTable.AFKAmount
	local TimeSinceLastMove = Time - DataTable.LastMove

	--Use time since last move rather than the total,
	--as they may have spoken in voice chat and it would look silly to
	--say they're AFK still...
	if TimeSinceLastMove > KickTime * 0.25 then
		if not DataTable.IsAFK then
			DataTable.IsAFK = true
		end
	else
		if DataTable.IsAFK then
			DataTable.IsAFK = false
		end
	end

	if not DataTable.Warn and self.Config.Warn then
		local WarnTime = self.Config.WarnTime * 60

		--Again, using time since last move so we don't end up warning players constantly
		--if they hover near the warn time barrier in total AFK time.
		if TimeSinceLastMove >= WarnTime then
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
	end

	if Shine:HasAccess( Client, "sh_afk_partial" ) then return end

	--Only kick if we're past the min player count to do so, and use their "total" time.
	if AFKAmount >= KickTime and Players >= self.Config.MinPlayers then
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
		self:SubtractAFKTime( Client, 0.1 )
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
	self.Users[ Client ] = nil
end

--Override the built in randomise ready room vote to not move AFK players.
Shine.Hook.Add( "OnFirstThink", "AFKKick_OverrideVote", function()
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
