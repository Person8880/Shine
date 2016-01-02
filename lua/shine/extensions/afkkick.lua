--[[
	Shine AFK kick plugin.
]]

local Shine = Shine

local GetHumanPlayerCount = Shine.GetHumanPlayerCount
local GetMaxPlayers = Server.GetMaxPlayers
local GetNumPlayersTotal = Server.GetNumPlayersTotal
local GetOwner = Server.GetOwner
local Max = math.max
local pcall = pcall
local SharedTime = Shared.GetTime
local StringTimeToString = string.TimeToString

local Plugin = {}
Plugin.Version = "1.6"
Plugin.PrintName = "AFKKick"

Plugin.HasConfig = true
Plugin.ConfigName = "AFKKick.json"

Plugin.DefaultConfig = {
	MinPlayers = 10,
	WarnMinPlayers = 5,
	Delay = 1,
	WarnTime = 5,
	KickTime = 15,
	IgnoreSpectators = false,
	Warn = true,
	MoveToReadyRoomOnWarn = false,
	MoveToSpectateOnWarn = false,
	OnlyCheckOnStarted = false,
	KickOnConnect = false
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:OnFirstThink()
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

	Shine.Hook.SetupClassHook( "Commander", "OrderEntities", "OnCommanderOrderEntities", "PassivePost" )
end

do
	local Validator = Shine.Validator()
	Validator:AddRule( {
		Matches = function( self, Config )
			return Config.WarnMinPlayers > Config.MinPlayers
		end,
		Fix = function( self, Config )
			Config.WarnMinPlayers = Config.MinPlayers
		end
	} )
	Validator:AddRule( {
		Matches = function( self, Config )
			return Config.MoveToReadyRoomOnWarn and Config.MoveToSpectateOnWarn
		end,
		Fix = function( self, Config )
			Config.MoveToReadyRoomOnWarn = false
		end
	} )

	function Plugin:Initialise()
		if Validator:Validate( self.Config ) then
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

function Plugin:KickClient( Client )
	Client.DisconnectReason = "AFK for too long"
	Server.DisconnectClient( Client )
end

--[[
	On a new connection attempt when the server is full, kick the longest AFK player past
	the kick time.
]]
function Plugin:CheckConnectionAllowed( ID )
	if not self.Config.KickOnConnect then return end
	if GetNumPlayersTotal() < GetMaxPlayers() then return end

	local AFKForLongest
	local TimeAFK = 0
	local KickTime = self.Config.KickTime * 60

	for Client, Data in pairs( self.Users ) do
		if not ( Shine:HasAccess( Client, "sh_afk" )
		or Shine:HasAccess( Client, "sh_afk_partial" ) )
		and Data.AFKAmount >= KickTime and Data.AFKAmount > TimeAFK then
			TimeAFK = Data.AFKAmount
			AFKForLongest = Client
		end
	end

	if not AFKForLongest then return end

	self:Print( "Kicking %s to make room for connecting player (NS2ID: %s). AFK time was %s.",
		true, Shine.GetClientInfo( AFKForLongest ), ID,
		StringTimeToString( TimeAFK ) )

	self:KickClient( AFKForLongest )
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
	if DataTable.LastMove > Time then return end

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

	if self.Config.KickOnConnect or Shine:HasAccess( Client, "sh_afk_partial" ) then return end

	--Only kick if we're past the min player count to do so, and use their "total" time.
	if AFKAmount >= KickTime and Players >= self.Config.MinPlayers then
		self:Print( "Client %s[%s] was AFK for over %s. Player count: %i. Min Players: %i. Kicking...",
			true, Player:GetName(), Client:GetUserId(), StringTimeToString( KickTime ),
			Players, self.Config.MinPlayers )

		self:KickClient( Client )
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
		local Team = Building:GetTeam()
		if not Team or not Team.GetCommander then return end

		local Commander = Team:GetCommander()
		if not Commander then return end

		local Client = GetOwner( Commander )
		if not Client then return end

		self:ResetAFKTime( Client )
	end

	local function ResetForCommander()
		return function( self, Commander )
			local Client = GetOwner( Commander )
			if not Client then return end

			self:ResetAFKTime( Client )
		end
	end

	Plugin.OnCommanderTechTreeAction = ResetForCommander()
	Plugin.OnCommanderNotify = ResetForCommander()
	Plugin.OnCommanderOrderEntities = ResetForCommander()
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

	do
		local function CheckPlayerIsAFK( Player )
			if not Player then return end

			local Client = GetOwner( Player )
			if not Client then return end

			if not Plugin:IsAFKFor( Client, 60 ) then
				JoinRandomTeam( Player )
				return
			end

			if PlayingTeamNumbers[ Player:GetTeamNumber() ] then
				local Gamerules = GetGamerules()

				pcall( Gamerules.JoinTeam, Gamerules, Player,
					kTeamReadyRoom, nil, true )
			end
		end

		SetVoteSuccessfulCallback( "VoteRandomizeRR", 2, function( Data )
			local ReadyRoomPlayers = GetGamerules():GetTeam( kTeamReadyRoom ):GetPlayers()
			local Enabled = Shine:IsExtensionEnabled( "afkkick" )
			local Action = Enabled and CheckPlayerIsAFK or JoinRandomTeam

			Shine.Stream( ReadyRoomPlayers ):ForEach( Action )
		end )
	end

	if Shine.IsNS2Combat then return end

	local function FilterPlayers( Player )
		local ShouldKeep = true
		local Client = GetOwner( Player )

		if not Client or Plugin:IsAFKFor( Client, 60 ) then
			ShouldKeep = false

			if Client and PlayingTeamNumbers[ Player:GetTeamNumber() ] then
				local Gamerules = GetGamerules()

				pcall( Gamerules.JoinTeam, Gamerules, Player, kTeamReadyRoom, nil, true )
			end
		end

		return ShouldKeep
	end

	local OldGetPlayers = ForceEvenTeams_GetPlayers
	function ForceEvenTeams_GetPlayers()
		local Enabled = Shine:IsExtensionEnabled( "afkkick" )
		if not Enabled then
			return OldGetPlayers()
		end

		local Players = OldGetPlayers()

		Shine.Stream( Players ):Filter( FilterPlayers )

		return Players
	end
end )

Shine:RegisterExtension( "afkkick", Plugin )
