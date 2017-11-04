--[[
	Shine AFK kick plugin.
]]

local Shine = Shine

local Floor = math.floor
local GetHumanPlayerCount = Shine.GetHumanPlayerCount
local GetMaxPlayers = Server.GetMaxPlayers
local GetNumPlayersTotal = Server.GetNumPlayersTotal
local GetOwner = Server.GetOwner
local Max = math.max
local pcall = pcall
local SharedTime = Shared.GetTime
local StringTimeToString = string.TimeToString

local Plugin = Plugin
Plugin.Version = "1.7"
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
	MovementDelaySeconds = 0,
	OnlyCheckOnStarted = false,
	KickOnConnect = false,
	KickTimeIsAFKThreshold = 0.25,
	MarkPlayersAFK = true,
	LenientModeForSpectators = false,
	WarnActions = {
		-- Actions to perform to players when they are warned.
		-- May be any of: MoveToSpectate, MoveToReadyRoom, Notify
		NoImmunity = {},
		PartialImmunity = {}
	}
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.WarnAction = table.AsEnum{
	"MoveToSpectate", "MoveToReadyRoom", "Notify"
}

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.7",
		Apply = function( Config )
			local Actions = {}
			if Config.MoveToSpectateOnWarn then
				Actions[ #Actions + 1 ] = Plugin.WarnAction.MoveToSpectate
			end
			if Config.MoveToReadyRoomOnWarn then
				Actions[ #Actions + 1 ] = Plugin.WarnAction.MoveToReadyRoom
			end
			if Config.NotifyOnWarn then
				Actions[ #Actions + 1 ] = Plugin.WarnAction.Notify
			end

			Config.WarnActions = {
				NoImmunity = Actions,
				PartialImmunity = Actions
			}

			Config.MoveToSpectateOnWarn = nil
			Config.MoveToReadyRoomOnWarn = nil
			Config.NotifyOnWarn = nil
		end
	}
}

do
	local IsType = Shine.IsType
	local StringLower = string.lower

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
			local Changed
			if not IsType( Config.WarnActions.NoImmunity, "table" ) then
				Config.WarnActions.NoImmunity = {}
				Changed = true
			end
			if not IsType( Config.WarnActions.PartialImmunity, "table" ) then
				Config.WarnActions.PartialImmunity = {}
				Changed = true
			end

			local LowerCaseActions = table.AsEnum( Shine.Stream.Of( Plugin.WarnAction )
				:Map( StringLower )
				:AsTable() )
			local NotAllowedTogether = {
				[ LowerCaseActions[ "movetoreadyroom" ] ] = LowerCaseActions[ "movetospectate" ],
				[ LowerCaseActions[ "movetospectate" ] ] = LowerCaseActions[ "movetoreadyroom" ]
			}
			local function CheckActions( Actions )
				local Seen = {}
				Shine.Stream( Actions ):Filter( function( Value )
					if not IsType( Value, "string" ) or not LowerCaseActions[ StringLower( Value ) ] then
						Changed = true
						Plugin:Print( "Warn action '%s' is not valid", true, Value )
						return false
					end

					local ActionName = StringLower( Value )
					local ExclusiveAction = NotAllowedTogether[ ActionName ]
					if Seen[ ExclusiveAction ] then
						Changed = true
						Plugin:Print( "Cannot perform both of warn actions '%s' and '%s'", true,
							ActionName, ExclusiveAction )
						return false
					end
					Seen[ ActionName ] = true

					return true
				end )
			end
			CheckActions( Config.WarnActions.NoImmunity )
			CheckActions( Config.WarnActions.PartialImmunity )

			return Changed
		end
	} )

	local function MovePlayer( Client, Gamerules, DataTable, TargetTeam )
		-- Make sure the client still exists and is still AFK.
		if not Shine:IsValidClient( Client ) then return end
		if not DataTable.Warn then return end

		local CurrentPlayer = Client:GetControllingPlayer()
		local CurrentTeam = CurrentPlayer:GetTeamNumber()

		-- Sometimes this event receives one of the weird "ghost" players that can't switch teams.
		if CurrentTeam ~= TargetTeam then
			pcall( Gamerules.JoinTeam, Gamerules, CurrentPlayer, TargetTeam, nil, true )
		end
	end

	local function BuildMovementAction( TargetTeam )
		return function( self, Client, Gamerules, DataTable )
			-- Either move the player now, or after the set delay.
			if self.Config.MovementDelaySeconds <= 0 then
				MovePlayer( Client, Gamerules, DataTable, TargetTeam )
			else
				self:SimpleTimer( self.Config.MovementDelaySeconds, function()
					MovePlayer( Client, Gamerules, DataTable, TargetTeam )
				end )
			end
		end
	end

	Plugin.WarnActionFunctions = {
		[ "movetospectate" ] = BuildMovementAction( kSpectatorIndex ),
		[ "movetoreadyroom" ] = BuildMovementAction( kTeamReadyRoom ),
		[ "notify" ] = function( self, Client )
			self:SendNetworkMessage( Client, "AFKNotify", {}, true )
		end
	}

	function Plugin:BuildActions( ActionNames )
		local ActionFunctions = {}
		for i = 1, #ActionNames do
			local Action = StringLower( ActionNames[ i ] )
			ActionFunctions[ #ActionFunctions + 1 ] = self.WarnActionFunctions[ Action ]
		end
		return ActionFunctions
	end

	function Plugin:ValidateConfig()
		if Validator:Validate( self.Config ) then
			self:SaveConfig( true )
		end
	end

	function Plugin:Initialise()
		self:ValidateConfig()

		self.WarnActions = {
			NoImmunity = self:BuildActions( self.Config.WarnActions.NoImmunity ),
			PartialImmunity = self:BuildActions( self.Config.WarnActions.PartialImmunity )
		}

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

		if not self.Config.MarkPlayersAFK then return end

		local Client = GetOwner( Player )
		local Data = self.Users[ Client ]
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
	Server.DisconnectClient( Client, "AFK for too long." )
end

function Plugin:CanKickForConnectingClient()
	return GetNumPlayersTotal() >= GetMaxPlayers()
end

--[[
	On a new connection attempt when the server is full, kick the longest AFK player past
	the kick time.
]]
function Plugin:CheckConnectionAllowed( ID )
	if not self.Config.KickOnConnect then return end
	if not self:CanKickForConnectingClient() then return end

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
	Shine.Hook.Call( "AFKChanged", Client, false )
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
		Shine.Hook.Call( "AFKChanged", Client, DataTable.IsAFK )
	end
end

function Plugin:SubtractAFKTime( Client, Time )
	local DataTable = self.Users[ Client ]
	if not DataTable then return end

	-- Do not subtract any time if the player's Steam overlay is open.
	-- It could be possible to leave the voice chat button going with it open.
	if DataTable.SteamOverlayIsOpen then return end

	DataTable.LastMove = SharedTime()
	DataTable.LastMeasurement = DataTable.LastMove
	DataTable.AFKAmount = Max( DataTable.AFKAmount - Time, 0 )
	if DataTable.IsAFK then
		DataTable.IsAFK = false
		Shine.Hook.Call( "AFKChanged", Client, DataTable.IsAFK )
	end
end

function Plugin:ReceiveSteamOverlay( Client, Data )
	local DataTable = self.Users[ Client ]
	if not DataTable then return end

	-- Players with their Steam overlay open are treated as AFK, regardless of
	-- input received.
	DataTable.SteamOverlayIsOpen = Data.Open
end

local MOVEMENT_MULTIPLIER = 5
local SPECTATOR_MOVEMENT_MULTIPLIER = 20

function Plugin:GetWarnActions( IsPartiallyImmune )
	return self.WarnActions[ IsPartiallyImmune and "PartialImmunity" or "NoImmunity" ]
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
	local IsSpectator = Team == kSpectatorIndex

	if IsSpectator and self.Config.IgnoreSpectators then
		self:ResetAFKTime( Client )

		return
	end

	-- Ignore players waiting to respawn/watching the end of the game.
	if Player:isa( "TeamSpectator" )
	or ( Player.GetIsWaitingForTeamBalance and Player:GetIsWaitingForTeamBalance() )
	or ( Player.GetIsRespawning and Player:GetIsRespawning() ) then
		self:ResetAFKTime( Client )

		return
	end

	local Pitch, Yaw = Input.pitch, Input.yaw
	local DeltaTime = Time - DataTable.LastMeasurement

	DataTable.LastMeasurement = Time

	local MovementIsEmpty = Move.x == 0 and Move.y == 0 and Move.z == 0 and Input.commands == 0
	local AnglesMatch = DataTable.LastYaw == Yaw and DataTable.LastPitch == Pitch

	if not ( MovementIsEmpty and AnglesMatch or DataTable.SteamOverlayIsOpen ) then
		DataTable.LastMove = Time

		if IsSpectator and self.Config.LenientModeForSpectators then
			-- Lenient mode means reset AFK time on any movement for a spectator.
			DataTable.AFKAmount = 0
		else
			-- Spectator movement is weighted higher because it will occur less frequently.
			local Multiplier = IsSpectator and SPECTATOR_MOVEMENT_MULTIPLIER or MOVEMENT_MULTIPLIER

			-- Subtract the measurement time from their AFK time, so they have to stay
			-- active for a while to get it back to 0 time.
			-- We use a multiplier as we want activity to count for more than inactivity to avoid
			-- overzealous kicks.
			DataTable.AFKAmount = Max( DataTable.AFKAmount - DeltaTime * Multiplier, 0 )
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

	-- Use time since last move rather than the total,
	-- as they may have spoken in voice chat and it would look silly to
	-- say they're AFK still...
	if TimeSinceLastMove > KickTime * self.Config.KickTimeIsAFKThreshold then
		if not DataTable.IsAFK then
			DataTable.IsAFK = true
			Shine.Hook.Call( "AFKChanged", Client, DataTable.IsAFK )
		end
	else
		if DataTable.IsAFK then
			DataTable.IsAFK = false
			Shine.Hook.Call( "AFKChanged", Client, DataTable.IsAFK )
		end
	end

	local IsPartiallyImmune = Shine:HasAccess( Client, "sh_afk_partial" )

	if self.Config.Warn then
		local WarnTime = self.Config.WarnTime * 60

		-- Again, using time since last move so we don't end up warning players constantly
		-- if they hover near the warn time barrier in total AFK time.
		if TimeSinceLastMove < WarnTime then
			DataTable.Warn = false
		elseif not DataTable.Warn and TimeSinceLastMove >= WarnTime then
			DataTable.Warn = true

			if not IsPartiallyImmune then
				if not self.Config.KickOnConnect then
					local AFKTime = Time - DataTable.LastMove
					Shine.SendNetworkMessage( Client, "AFKWarning", {
						timeAFK = AFKTime,
						maxAFKTime = KickTime
					}, true )
				elseif Players >= self.Config.MinPlayers then
					-- Only warn players if there's actually a possibity they'll be kicked.
					self:SendTranslatedNotify( Client, "WARN_KICK_ON_CONNECT", {
						AFKTime = Floor( WarnTime )
					} )
				end
			end

			local WarnActions = self:GetWarnActions( IsPartiallyImmune )
			for i = 1, #WarnActions do
				WarnActions[ i ]( self, Client, Gamerules, DataTable )
			end

			return
		end
	end

	if self.Config.KickOnConnect or IsPartiallyImmune then return end

	-- Only kick if we're past the min player count to do so, and use their "total" time.
	if AFKAmount >= KickTime and Players >= self.Config.MinPlayers then
		self:Print( "Client %s was AFK for over %s. Player count: %i. Min Players: %i. Kicking...",
			true, Shine.GetClientInfo( Client ), StringTimeToString( KickTime ),
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

function Plugin:OnFirstThink()
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

	Shine.Hook.SetupClassHook( "Commander", "OrderEntities", "OnCommanderOrderEntities", "PassivePost" )

	do
		local function CheckPlayerIsAFK( Player )
			if not Player then return end

			local Client = GetOwner( Player )
			if not Client then return end

			if not self:IsAFKFor( Client, 60 ) then
				JoinRandomTeam( Player )
				return
			end

			if Shine.IsPlayingTeam( Player:GetTeamNumber() ) then
				local Gamerules = GetGamerules()

				pcall( Gamerules.JoinTeam, Gamerules, Player,
					kTeamReadyRoom, nil, true )
			end
		end

		-- Override the built in randomise ready room vote to not move AFK players.
		SetVoteSuccessfulCallback( "VoteRandomizeRR", 2, function( Data )
			local ReadyRoomPlayers = GetGamerules():GetTeam( kTeamReadyRoom ):GetPlayers()
			local Action = self.Enabled and CheckPlayerIsAFK or JoinRandomTeam

			Shine.Stream( ReadyRoomPlayers ):ForEach( Action )
		end )
	end

	if Shine.IsNS2Combat then return end

	local function FilterPlayers( Player )
		local ShouldKeep = true
		local Client = GetOwner( Player )

		if not Client or self:IsAFKFor( Client, 60 ) then
			ShouldKeep = false

			if Client and Shine.IsPlayingTeam( Player:GetTeamNumber() ) then
				local Gamerules = GetGamerules()

				pcall( Gamerules.JoinTeam, Gamerules, Player, kTeamReadyRoom, nil, true )
			end
		end

		return ShouldKeep
	end

	local OldGetPlayers = ForceEvenTeams_GetPlayers
	function ForceEvenTeams_GetPlayers()
		if not self.Enabled then
			return OldGetPlayers()
		end

		return Shine.Stream( OldGetPlayers() )
			:Filter( FilterPlayers )
			:AsTable()
	end
end
