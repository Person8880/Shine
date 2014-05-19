--[[
	Shine AFK kick plugin.
]]

local Shine = Shine

local GetHumanPlayerCount = Shine.GetHumanPlayerCount
local GetOwner = Server.GetOwner
local SharedTime = Shared.GetTime

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "AFKKick.json"

Plugin.Users = {}

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
	OnlyCheckOnStarted = false
}

Plugin.CheckConfig = true

function Plugin:Initialise()
	if self.Config.WarnMinPlayers > self.Config.MinPlayers then
		self.Config.WarnMinPlayers = self.Config.MinPlayers
		self:SaveConfig( true )
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

	if Team == 3 and self.Config.IgnoreSpectators then
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

	if not ( Move.x == 0 and Move.y == 0 and Move.z == 0 and Input.commands == 0 and DataTable.LastYaw == Yaw and DataTable.LastPitch == Pitch ) then
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
			
			Server.SendNetworkMessage( Client, "AFKWarning", { timeAFK = AFKTime, maxAFKTime = KickTime }, true )

			if self.Config.MoveToReadyRoomOnWarn and Player:GetTeamNumber() ~= kTeamReadyRoom then
				Gamerules:JoinTeam( Player, 0, nil, true )
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

--[[
	Other plugins may wish to know this.
]]
function Plugin:GetLastMoveTime( Client )
	if not self.Users[ Client ] then return nil end
	return self.Users[ Client ].LastMove
end

--[[
	When a client disconnects, remove them from the player list.
]]
function Plugin:ClientDisconnect( Client )
	if self.Users[ Client ] then
		self.Users[ Client ] = nil
	end
end

function Plugin:Cleanup()
	for k, v in pairs( self.Users ) do
		self.Users[ k ] = nil
	end

	self.Enabled = false
end

--Override the built in randomise ready room vote to not move AFK players.
Shine.Hook.Add( "Think", "AFKKick_OverrideVote", function()
	SetVoteSuccessfulCallback( "VoteRandomizeRR", 2, function( Data )
		local ReadyRoomPlayers = GetGamerules():GetTeam( kTeamReadyRoom ):GetPlayers()
		local Enabled, AFKPlugin = Shine:IsExtensionEnabled( "afkkick" )

		for i = #ReadyRoomPlayers, 1, -1 do
			local Player = ReadyRoomPlayers[ i ]

			if Enabled then
				if Player then
					local Client = GetOwner( Player )

					if Client then
						local LastMove = AFKPlugin:GetLastMoveTime( Client )
						local Time = SharedTime()

						if not ( LastMove and Time - LastMove > 60 ) then
							JoinRandomTeam( Player )
						end
					end
				end
			else
				JoinRandomTeam( Player )
			end
		end
	end )

	Shine.Hook.Remove( "Think", "AFKKick_OverrideVote" )
end )

Shine:RegisterExtension( "afkkick", Plugin )
