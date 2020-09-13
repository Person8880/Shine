--[[
	Shine AFK kick plugin.
]]

local Shine = Shine

local assert = assert
local Clamp = math.Clamp
local Floor = math.floor
local GetClientForPlayer = Shine.GetClientForPlayer
local GetHumanPlayerCount = Shine.GetHumanPlayerCount
local GetMaxPlayers = Server.GetMaxPlayers
local GetMaxSpectators = Server.GetMaxSpectators
local GetNumClientsTotal = Server.GetNumClientsTotal
local Max = math.max
local Random = math.random
local StringContainsNonUTF8Whitespace = string.ContainsNonUTF8Whitespace
local StringStartsWith = string.StartsWith
local StringSub = string.sub
local SharedTime = Shared.GetTime
local StringTimeToString = string.TimeToString
local TableConcat = table.concat
local TableSort = table.sort
local xpcall = xpcall

local Plugin = ...
Plugin.Version = "1.10"
Plugin.PrintName = "AFKKick"

Plugin.HasConfig = true
Plugin.ConfigName = "AFKKick.json"

Plugin.Leniency = table.AsEnum{
	"STRICT", "LENIENT_FOR_SPECTATORS", "LENIENT"
}

local NO_IMMUNITY = "NoImmunity"
local PARTIAL_IMMUNITY = "PartialImmunity"

Plugin.DefaultConfig = {
	MinPlayers = 10,
	WarnMinPlayers = 5,
	Delay = 1,
	WarnTimeInMinutes = 5,
	KickTimeInMinutes = 15,
	IgnoreSpectators = false,
	Warn = true,
	MovementDelaySeconds = 0,
	OnlyCheckOnStarted = false,
	KickOnConnect = false,
	KickTimeIsAFKThreshold = 0.25,
	MarkPlayersAFK = true,
	-- How frequently to sample player movement (in seconds, defaulting to ~4 times per second).
	-- Lower values will have a negative impact on performance, while higher values will reduce
	-- the accuracy of AFK checks.
	SampleIntervalInSeconds = 0.25,
	WarnActions = {
		-- Actions to perform to players when they are warned.
		-- May be any of: "MOVE_TO_SPECTATE", "MOVE_TO_READY_ROOM", "NOTIFY"
		[ NO_IMMUNITY ] = {},
		[ PARTIAL_IMMUNITY ] = {}
	},
	Leniency = {
		-- The leniency of the AFK tracking can be one of:
		-- STRICT - activity only reduces the AFK time, it does not reset it.
		-- LENIENT_FOR_SPECTATORS - spectators reset their AFK time with activity,
		-- but other players use the STRICT mode.
		-- LENIENT - all players reset their AFK time with activity.
		[ NO_IMMUNITY ] = Plugin.Leniency.STRICT,
		[ PARTIAL_IMMUNITY ] = Plugin.Leniency.STRICT
	},
	-- Rules that determine config options based on player count.
	PlayerCountRules = {}
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.WarnAction = table.AsEnum{
	"MOVE_TO_SPECTATE", "MOVE_TO_READY_ROOM", "NOTIFY"
}

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.7",
		Apply = function( Config )
			local Actions = {}
			if Config.MoveToSpectateOnWarn then
				Actions[ #Actions + 1 ] = Plugin.WarnAction.MOVE_TO_SPECTATE
			end
			if Config.MoveToReadyRoomOnWarn then
				Actions[ #Actions + 1 ] = Plugin.WarnAction.MOVE_TO_READY_ROOM
			end
			if Config.NotifyOnWarn then
				Actions[ #Actions + 1 ] = Plugin.WarnAction.NOTIFY
			end

			Config.WarnActions = {
				[ NO_IMMUNITY ] = Actions,
				[ PARTIAL_IMMUNITY ] = Actions
			}

			Config.MoveToSpectateOnWarn = nil
			Config.MoveToReadyRoomOnWarn = nil
			Config.NotifyOnWarn = nil
		end
	},
	{
		VersionTo = "1.8",
		Apply = function( Config )
			local Leniency = Plugin.Leniency.STRICT
			if Config.LenientModeForSpectators then
				Leniency = Plugin.Leniency.LENIENT_FOR_SPECTATORS
			end

			Config.Leniency = {
				[ NO_IMMUNITY ] = Leniency,
				[ PARTIAL_IMMUNITY ] = Leniency
			}
			Config.LenientModeForSpectators = nil
		end
	},
	{
		VersionTo = "1.10",
		Apply = Shine.Migrator()
			:RenameField( "WarnTime", "WarnTimeInMinutes" )
			:RenameField( "KickTime", "KickTimeInMinutes" )
			:AddField( "PlayerCountRules", Plugin.DefaultConfig.PlayerCountRules )
	}
}

local TEAM_MOVE_ERROR_HANDLER = Shine.BuildErrorHandler( "AFK team move error" )
local function AttemptToMovePlayerToTeam( Gamerules, Client, Player, Team )
	local Success, Moved = xpcall( Gamerules.JoinTeam, TEAM_MOVE_ERROR_HANDLER,
		Gamerules, Player, Team, true, true )
	if not Success or not Moved then
		Plugin.Logger:Warn( "Unable to move %s to team %s: %s",
			Shine.GetClientInfo( Client ),
			Team,
			Success and "Gamerules rejected movement" or Moved )
	end
end

do
	local IsType = Shine.IsType
	local StringUpper = string.upper

	local Validator = Shine.Validator()
	Validator:AddRule( {
		Matches = function( self, Config )
			return Config.WarnMinPlayers > Config.MinPlayers
		end,
		Fix = function( self, Config )
			Config.WarnMinPlayers = Config.MinPlayers
		end
	} )
	Validator:AddFieldRule(
		"WarnActions.NoImmunity",
		Validator.IsType( "table", Plugin.DefaultConfig.WarnActions.NoImmunity )
	)
	Validator:AddFieldRule(
		"WarnActions.PartialImmunity",
		Validator.IsType( "table", Plugin.DefaultConfig.WarnActions.PartialImmunity )
	)
	Validator:AddRule( {
		Matches = function( self, Config )
			local Changed
			local NotAllowedTogether = {
				[ Plugin.WarnAction.MOVE_TO_READY_ROOM ] = Plugin.WarnAction.MOVE_TO_SPECTATE,
				[ Plugin.WarnAction.MOVE_TO_SPECTATE ] = Plugin.WarnAction.MOVE_TO_READY_ROOM
			}
			local function CheckActions( Actions )
				local Seen = {}
				Shine.Stream( Actions ):Filter( function( Value )
					if not IsType( Value, "string" ) or not Plugin.WarnAction[ StringUpper( Value ) ] then
						Changed = true
						Plugin:Print( "Warn action '%s' is not valid", true, Value )
						return false
					end

					local ActionName = StringUpper( Value )
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
	Validator:AddFieldRule( "Leniency.NoImmunity",
		Validator.InEnum( Plugin.Leniency, Plugin.Leniency.STRICT ) )
	Validator:AddFieldRule( "Leniency.PartialImmunity",
		Validator.InEnum( Plugin.Leniency, Plugin.Leniency.STRICT ) )

	Validator:AddFieldRule( "PlayerCountRules", Validator.AllValuesSatisfy(
		Validator.ValidateField( "MaxPlayers", Validator.IsType( "number", 1 ) ),
		Validator.ValidateField( "MaxPlayers", Validator.Min( 1 ) ),

		Validator.ValidateField( "MinPlayers", Validator.IsAnyType( { "number", "nil" }, nil ) ),
		Validator.ValidateField( "MinPlayers", Validator.IfType( "number", Validator.Min( 0 ) ) ),

		Validator.ValidateField( "WarnTimeInMinutes", Validator.IsAnyType( { "number", "nil" }, nil ) ),
		Validator.ValidateField( "KickTimeInMinutes", Validator.IsAnyType( { "number", "nil" }, nil ) ),

		Validator.ValidateField( "MarkPlayersAFK", Validator.IsAnyType( { "boolean", "nil" }, nil ) )
	) )

	Plugin.ConfigValidator = Validator

	local function MovePlayer( Client, Gamerules, DataTable, TargetTeam )
		-- Make sure the client still exists and is still AFK.
		if not Shine:IsValidClient( Client ) then return end
		if not DataTable.Warn then
			if Plugin.Logger:IsDebugEnabled() then
				Plugin.Logger:Debug(
					"Skipping movement of %s to team %s as they are no longer AFK.",
					Shine.GetClientInfo( Client ),
					TargetTeam
				)
			end

			return
		end

		local CurrentPlayer = Client:GetControllingPlayer()
		-- If they don't have a player we can't move them (presumably disconnecting).
		if not CurrentPlayer then
			Plugin.Logger:Warn(
				"Unable to move %s to team %s as they have no player object assigned.",
				Shine.GetClientInfo( Client ),
				TargetTeam
			)
			return
		end

		local CurrentTeam = CurrentPlayer:GetTeamNumber()

		-- Sometimes this event receives one of the weird "ghost" players that can't switch teams.
		if CurrentTeam ~= TargetTeam then
			if Plugin.Logger:IsDebugEnabled() then
				Plugin.Logger:Debug(
					"Attempting to move %s to team %s...",
					Shine.GetClientInfo( Client ),
					TargetTeam
				)
			end

			AttemptToMovePlayerToTeam( Gamerules, Client, CurrentPlayer, TargetTeam )
		elseif Plugin.Logger:IsDebugEnabled() then
			Plugin.Logger:Debug(
				"Skipping movement of %s as they are already on team %s.",
				Shine.GetClientInfo( Client ),
				TargetTeam
			)
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
		[ Plugin.WarnAction.MOVE_TO_SPECTATE ] = BuildMovementAction( kSpectatorIndex ),
		[ Plugin.WarnAction.MOVE_TO_READY_ROOM ] = BuildMovementAction( kTeamReadyRoom ),
		[ Plugin.WarnAction.NOTIFY ] = function( self, Client )
			self:SendNetworkMessage( Client, "AFKNotify", {}, true )
		end
	}

	function Plugin:BuildActions( ActionNames )
		local ActionFunctions = {}
		for i = 1, #ActionNames do
			local Action = StringUpper( ActionNames[ i ] )
			ActionFunctions[ #ActionFunctions + 1 ] = self.WarnActionFunctions[ Action ]
		end
		return ActionFunctions
	end

	local function SortByMaxPlayers( A, B )
		return A.MaxPlayers < B.MaxPlayers
	end

	function Plugin:Initialise()
		self:BroadcastModuleEvent( "Initialise" )

		self.WarnActions = {
			NoImmunity = self:BuildActions( self.Config.WarnActions.NoImmunity ),
			PartialImmunity = self:BuildActions( self.Config.WarnActions.PartialImmunity )
		}

		-- Make sure rules are in ascending max player order.
		TableSort( self.Config.PlayerCountRules, SortByMaxPlayers )

		self:OnPlayerCountChanged()

		if self.Enabled ~= nil then
			for Client in self.Users:Iterate() do
				if Shine:IsValidClient( Client ) then
					self:ResetAFKTime( Client )
				else
					self.Users:Remove( Client )
				end
			end

			local Clients, Count = Shine.GetAllClients()
			for i = 1, Count do
				local Client = Clients[ i ]
				if not self.Users:Get( Client ) then
					self:ClientConnect( Client )
				end
			end
		else
			self.Users = Shine.UnorderedMap()
		end

		if self.Config.Warn or not self.Config.KickOnConnect then
			-- Need to periodically evaluate players if they need to be warned or if
			-- kicking is not performed at connection time.
			self:CreateTimer( "AFKCheck", 1, -1, function() self:EvaluatePlayers() end )
		end

		-- Not using a method to ensure this runs after all other plugins/hooks.
		Shine.Hook.Add( "CheckPlayerName", self, function( Player, Name )
			return self:EnsurePlayerNameIsValid( Player, Name )
		end, Shine.Hook.MIN_PRIORITY )

		self.SampleInterval = self.Config.SampleIntervalInSeconds
		self.MinPlayersToKickOnConnect = self:GetMinPlayersToKickOnConnect( GetMaxPlayers(), GetMaxSpectators() )

		self.Enabled = true

		return true
	end
end

function Plugin:GetPlayerCount()
	return GetHumanPlayerCount()
end

function Plugin:OnPlayerCountChanged()
	self.CurrentWarnTimeInSeconds = self:GetConfigValueWithRules( "WarnTimeInMinutes" ) * 60
	self.CurrentKickTimeInSeconds = self:GetConfigValueWithRules( "KickTimeInMinutes" ) * 60
	self.CurrentMarkPlayersAFK = self:GetConfigValueWithRules( "MarkPlayersAFK" )
end

function Plugin:GetWarnTimeInSeconds()
	return self.CurrentWarnTimeInSeconds
end

function Plugin:GetConfigValueWithRules( Key )
	local Default = self.Config[ Key ]
	local Rules = self.Config.PlayerCountRules

	local PlayerCount = self:GetPlayerCount()
	for i = 1, #Rules do
		local Rule = Rules[ i ]
		if Rule.MaxPlayers >= PlayerCount and ( not Rule.MinPlayers or Rule.MinPlayers <= PlayerCount ) then
			local RuleValue = Rule[ Key ]
			if RuleValue == nil then
				RuleValue = Default
			end
			return RuleValue
		end
	end

	return Default
end

function Plugin:EnsurePlayerNameIsValid( Player, Name )
	if not self.Config.MarkPlayersAFK then return end

	-- Stop players using the prefix in their actual name to avoid double "AFK -" prefixes and other awkward behaviour.
	if StringStartsWith( Name, self.AFK_PREFIX ) then
		local NewName = StringSub( Name, #self.AFK_PREFIX + 1 )

		if not StringContainsNonUTF8Whitespace( NewName ) then
			-- Player:SetName() will make sure this is unique.
			NewName = "AFK"
		end

		return NewName
	end
end

function Plugin:PrePlayerInfoUpdate( PlayerInfo, Player )
	if not self.CurrentMarkPlayersAFK then
		PlayerInfo.afk = false
		return
	end

	local Client = GetClientForPlayer( Player )
	local Data = self.Users:Get( Client )

	-- Network the AFK state of the player.
	PlayerInfo.afk = Data and Data.IsAFK or false
end

function Plugin:KickClient( Client )
	Client.DisconnectReason = "AFK for too long"
	Server.DisconnectClient( Client, "AFK for too long." )
end

function Plugin:CanCheckInCurrentGameState( Gamerules )
	return not self.Config.OnlyCheckOnStarted or ( Gamerules and Gamerules:GetGameStarted() )
end

function Plugin:GetMinPlayersToKickOnConnect( MaxPlayers, MaxSpectators )
	return Clamp( self.Config.MinPlayers, MaxPlayers, MaxPlayers + MaxSpectators )
end

function Plugin:CanKickForConnectingClient()
	return GetNumClientsTotal() >= self.MinPlayersToKickOnConnect and self:CanCheckInCurrentGameState( GetGamerules() )
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
	local KickTime = self.CurrentKickTimeInSeconds

	for Client, Data in self.Users:Iterate() do
		if not ( Shine:HasAccess( Client, "sh_afk" )
		or Shine:HasAccess( Client, "sh_afk_partial" ) )
		and Data.AFKAmount >= KickTime and Data.AFKAmount > TimeAFK then
			TimeAFK = Data.AFKAmount
			AFKForLongest = Client
		end
	end

	if not AFKForLongest then return end

	self.Logger:Info( "Kicking %s to make room for connecting player (NS2ID: %s). AFK time was %s.",
		Shine.GetClientInfo( AFKForLongest ), ID,
		StringTimeToString( TimeAFK ) )

	self:KickClient( AFKForLongest )
end

--[[
	On client connect, add the client to our table of clients.
]]
function Plugin:ClientConnect( Client )
	if not Client or Client:GetIsVirtual() then return end

	self:OnPlayerCountChanged()

	local Player = Client:GetControllingPlayer()
	assert( Player, "No player assigned to non-virtual client in ClientConnect event!" )

	local Now = SharedTime()
	local MeasureStartTime = Now + ( self.Config.Delay * 60 )

	self.Users:Add( Client, {
		LastMove = MeasureStartTime,
		LastMeasurement = Now,
		NextSample = Now,
		AFKAmount = 0,
		Pos = Player:GetOrigin(),
		Ang = Player:GetViewAngles(),
		IsAFK = false,
		HasMoved = false
	} )
	Shine.Hook.Broadcast( "AFKChanged", Client, false )
end

function Plugin:ResetAFKTime( Client )
	local DataTable = self.Users:Get( Client )
	if not DataTable then return end

	local Time = SharedTime()

	DataTable.Warn = false
	DataTable.LastMove = Time
	DataTable.LastMeasurement = Time
	DataTable.AFKAmount = 0
	DataTable.HasMoved = true

	if DataTable.IsAFK then
		DataTable.IsAFK = false
		Shine.Hook.Broadcast( "AFKChanged", Client, DataTable.IsAFK )
	end
end

function Plugin:SubtractAFKTime( Client, Time )
	local DataTable = self.Users:Get( Client )
	if not DataTable then return end

	DataTable.Warn = false
	DataTable.LastMove = SharedTime()
	DataTable.LastMeasurement = DataTable.LastMove
	DataTable.AFKAmount = Max( DataTable.AFKAmount - Time, 0 )
	DataTable.HasMoved = true

	if DataTable.IsAFK then
		DataTable.IsAFK = false
		Shine.Hook.Broadcast( "AFKChanged", Client, DataTable.IsAFK )
	end
end

function Plugin:IsClientPartiallyImmune( Client )
	return Shine:HasAccess( Client, "sh_afk_partial" )
end

function Plugin:GetWarnActions( IsPartiallyImmune )
	return self.WarnActions[ IsPartiallyImmune and PARTIAL_IMMUNITY or NO_IMMUNITY ]
end

--[[
	Determines if a player is frozen (i.e. cannot move for reasons beyond their control).
]]
function Plugin:IsPlayerFrozen( Player )
	return Player:isa( "TeamSpectator" )
		or ( Player:isa( "Spectator" ) and Player:GetIsFirstPerson() )
		or ( Player.GetIsWaitingForTeamBalance and Player:GetIsWaitingForTeamBalance() )
		or ( Player.GetIsRespawning and Player:GetIsRespawning() )
		or ( Player.GetCountdownActive and Player:GetCountdownActive() )
		or Player.concedeSequenceActive
		or Player.frozen
end

function Plugin:EvaluatePlayer( Client, DataTable, Params )
	-- Do not actually do anything with frozen players, just keep their state up to date.
	if Shine:HasAccess( Client, "sh_afk" ) or DataTable.IsPlayerFrozen then
		return
	end

	local Time = Params.Time
	if DataTable.LastMove > Time then return end

	local Player = Client:GetControllingPlayer()
	if Player and self:IsPlayerFrozen( Player ) then
		-- Need to double check here, as first person spectate does not call OnProcessMove
		-- for the player spectating. Ensure their last move time remains frozen.
		DataTable.LastMove = DataTable.LastMove + ( Time - DataTable.LastMeasurement )
		DataTable.LastMeasurement = Time

		return
	end

	local NumPlayers = Params.NumPlayers
	local KickTime = Params.KickTime

	local TimeSinceLastMove = Time - DataTable.LastMove
	local IsPartiallyImmune = self:IsClientPartiallyImmune( Client )

	if self.Config.Warn then
		local WarnTime = Params.WarnTime

		-- Again, using time since last move so we don't end up warning players constantly
		-- if they hover near the warn time barrier in total AFK time.
		if TimeSinceLastMove < WarnTime then
			DataTable.Warn = false
		elseif not DataTable.Warn and TimeSinceLastMove >= WarnTime then
			DataTable.Warn = true

			if not IsPartiallyImmune then
				if not self.Config.KickOnConnect then
					local AFKTime = Time - DataTable.LastMove

					if NumPlayers >= self.Config.MinPlayers then
						self:SendTranslatedNotify( Client, "WARN_WILL_BE_KICKED", {
							AFKTime = Floor( WarnTime ),
							KickTime = KickTime
						} )
					else
						-- Not going to kick them yet, but tell them they may be kicked later.
						self:SendTranslatedNotify( Client, "WARN_NOTIFY", {
							AFKTime = Floor( WarnTime ),
							KickTime = KickTime,
							MinPlayers = self.Config.MinPlayers
						} )
					end
				elseif Params.WillKickOnConnect then
					-- Only warn players if there's actually a possibity they'll be kicked.
					self:SendTranslatedNotify( Client, "WARN_KICK_ON_CONNECT", {
						AFKTime = Floor( WarnTime )
					} )
				end
			end

			local WarnActions = self:GetWarnActions( IsPartiallyImmune )

			if self.Logger:IsDebugEnabled() then
				self.Logger:Debug(
					"Applying %s warn actions (%s) to %s as their last move time was %.2f vs. %.2f (no movement for %.2f seconds).",
					IsPartiallyImmune and "partial immunity" or "normal",
					TableConcat( self.Config.WarnActions[ IsPartiallyImmune and PARTIAL_IMMUNITY or NO_IMMUNITY ], ", " ),
					Shine.GetClientInfo( Client ),
					DataTable.LastMove, Time, TimeSinceLastMove
				)
			end

			for i = 1, #WarnActions do
				WarnActions[ i ]( self, Client, Params.Gamerules, DataTable )
			end

			return
		end
	end

	if self.Config.KickOnConnect or IsPartiallyImmune then return end

	local AFKAmount = DataTable.AFKAmount
	-- Only kick if we're past the min player count to do so, and use their "total" time.
	if AFKAmount >= KickTime and NumPlayers >= self.Config.MinPlayers then
		self.Logger:Info( "Client %s was AFK for over %s. Player count: %d. Min Players: %d. Kicking...",
			Shine.GetClientInfo( Client ), StringTimeToString( KickTime ),
			NumPlayers, self.Config.MinPlayers )
		self.Logger:Debug( "AFK amount was %.2f vs. time since last move of %.2f.",
			AFKAmount, TimeSinceLastMove )

		self:KickClient( Client )
	end
end

function Plugin:EvaluatePlayers()
	local Gamerules = GetGamerules()
	if not self:CanCheckInCurrentGameState( Gamerules ) then return end

	local NumPlayers = self:GetPlayerCount()
	if NumPlayers < self.Config.WarnMinPlayers then return end

	local Params = {
		Time = SharedTime(),
		KickTime = self.CurrentKickTimeInSeconds,
		WarnTime = self.Config.Warn and self.CurrentWarnTimeInSeconds,
		NumPlayers = NumPlayers,
		Gamerules = Gamerules,
		WillKickOnConnect = self.Config.KickOnConnect and self:CanKickForConnectingClient()
	}

	for Client, DataTable in self.Users:Iterate() do
		self:EvaluatePlayer( Client, DataTable, Params )
	end
end

local MOVEMENT_MULTIPLIER = 5
local SPECTATOR_MOVEMENT_MULTIPLIER = 20

function Plugin:GetLeniency( IsPartiallyImmune )
	return self.Config.Leniency[ IsPartiallyImmune and PARTIAL_IMMUNITY or NO_IMMUNITY ]
end

--[[
	Track player movement, regardless of whether any actions will be applied.

	This allows other plugins that use the AFK state to have the right information,
	and means that as soon as actions should be applied, they will be.
]]
function Plugin:OnProcessMove( Player, Input )
	local Client = GetClientForPlayer( Player )
	if not Client or Client:GetIsVirtual() then return end

	local DataTable = self.Users:Get( Client )
	if not DataTable then return end

	local Time = SharedTime()
	if DataTable.NextSample > Time then return end

	-- Sample input in a fixed interval. We don't necessarily need to see every single
	-- move command to know if they're AFK (and we work on delta-time between measurements
	-- so we don't really care how long a time there is between them.)
	-- We apply a random offset to the time to avoid clients being able to predict the window.
	DataTable.NextSample = Time + self.SampleInterval + Random() * self.SampleInterval * 0.5

	local IsSpectator = Player:GetTeamNumber() == kSpectatorIndex
	if IsSpectator and self.Config.IgnoreSpectators then
		self:ResetAFKTime( Client )
		return
	end

	local Pitch, Yaw = Input.pitch, Input.yaw
	local DeltaTime = Max( Time - DataTable.LastMeasurement, 0 )

	DataTable.LastMeasurement = Time

	local Move = Input.move
	local MovementIsEmpty = Move.x == 0 and Move.y == 0 and Move.z == 0 and Input.commands == 0
	local AnglesMatch
	if DataTable.LastYaw then
		AnglesMatch = DataTable.LastYaw == Yaw and DataTable.LastPitch == Pitch
	else
		-- No data yet, don't count the initial move as activity.
		AnglesMatch = true
	end

	DataTable.LastPitch = Pitch
	DataTable.LastYaw = Yaw

	local HasMoved = not ( MovementIsEmpty and AnglesMatch )
	if DataTable.LastMove > Time then
		if HasMoved then
			-- Make sure players are still noted as moving during the initial delay time.
			DataTable.HasMoved = true
		end
		-- Ignore players during the initial delay period.
		return
	end

	-- Track frozen player's input, but do not punish them if they are not providing any.
	local IsPlayerFrozen = self:IsPlayerFrozen( Player )
	local KickTime = self.CurrentKickTimeInSeconds

	if HasMoved then
		DataTable.LastMove = Time
		DataTable.HasMoved = true

		local Leniency = self:GetLeniency( self:IsClientPartiallyImmune( Client ) )

		if Leniency == self.Leniency.LENIENT
		or ( IsSpectator and Leniency == self.Leniency.LENIENT_FOR_SPECTATORS ) then
			-- Lenient mode means reset AFK time on any movement.
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
		if not IsPlayerFrozen then
			-- Accumulate their AFK time, but prevent it from exceeding the kick time to allow
			-- any movement to prevent players being kicked.
			DataTable.AFKAmount = Clamp( DataTable.AFKAmount + DeltaTime, 0, KickTime )
		else
			-- Effectively freeze their last move time without wiping it completely.
			DataTable.LastMove = DataTable.LastMove + DeltaTime
		end
	end

	DataTable.IsPlayerFrozen = IsPlayerFrozen

	local TimeSinceLastMove = Time - DataTable.LastMove

	-- Use time since last move rather than the total,
	-- as they may have spoken in voice chat and it would look silly to
	-- say they're AFK still...
	if TimeSinceLastMove > KickTime * self.Config.KickTimeIsAFKThreshold then
		if not DataTable.IsAFK then
			DataTable.IsAFK = true
			Shine.Hook.Broadcast( "AFKChanged", Client, DataTable.IsAFK )
		end
	else
		if DataTable.IsAFK then
			DataTable.IsAFK = false
			Shine.Hook.Broadcast( "AFKChanged", Client, DataTable.IsAFK )
		end
	end
end

function Plugin:PlayerSay( Client, MessageTable )
	self:ResetAFKTime( Client )
end

function Plugin:CanPlayerHearPlayer( Gamerules, Listener, Speaker )
	local Client = GetClientForPlayer( Speaker )
	if Client then
		self:SubtractAFKTime( Client, 0.1 )
	end
end

function Plugin:OnConstructInit( Building )
	local Team = Building:GetTeam()
	if not Team or not Team.GetCommander then return end

	local Owner = Building:GetOwner()
	Owner = Owner or Team:GetCommander()
	if not Owner then return end

	local Client = GetClientForPlayer( Owner )
	if not Client then return end

	self:ResetAFKTime( Client )
end

function Plugin:OnRecycle( Building, ResearchID )
	local Team = Building:GetTeam()
	if not Team or not Team.GetCommander then return end

	local Commander = Team:GetCommander()
	if not Commander then return end

	local Client = GetClientForPlayer( Commander )
	if not Client then return end

	self:ResetAFKTime( Client )
end

do
	local function ResetForCommander()
		return function( self, Commander )
			local Client = GetClientForPlayer( Commander )
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
	local DataTable = self.Users:Get( Client )
	if not DataTable then return nil end

	return DataTable.LastMove
end

function Plugin:GetAFKTime( Client )
	local LastMove = self:GetLastMoveTime( Client )
	if not LastMove then return nil end

	return SharedTime() - LastMove
end

--[[
	Returns true if the given client has been AFK for greater than the given time.
]]
function Plugin:IsAFKFor( Client, Time )
	local AFKTime = self:GetAFKTime( Client )
	if not AFKTime then return false end

	return AFKTime > Time
end

--[[
	Returns whether the given client has been seen moving at least once since the
	plugin activated (i.e. last map load).
]]
function Plugin:HasClientMoved( Client )
	local DataTable = self.Users:Get( Client )
	if not DataTable then return true end

	return DataTable.HasMoved
end

--[[
	When a client disconnects, remove them from the player list.
]]
function Plugin:ClientDisconnect( Client )
	self.Users:Remove( Client )
	self:OnPlayerCountChanged()
end

function Plugin:OverrideAFKMixin()
	if not AFKMixin then
		self.Logger:Warn( "AFKMixin not available, unable to override methods." )
		return
	end

	-- Stop the AFKMixin doing anything as this plugin is handling it.
	-- Restoring when the plugin is disabled is a little fiddly due to the way mixin
	-- methods are dispatched, so the map will have to be changed/reloaded to remove this override.
	Shine.ReplaceClassMethod( "AFKMixin", "OnProcessMove", function() end )
	Shine.ReplaceClassMethod( "AFKMixin", "GetAFKTime", function( Player )
		return self:GetAFKTime( Player:GetClient() ) or 0
	end )
end

function Plugin:OnFirstThink()
	self:OverrideAFKMixin()

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
		local function MoveIfNotAFK( Player )
			local Client = Player and GetClientForPlayer( Player )
			if not Client or self:IsAFKFor( Client, 60 ) then return end

			JoinRandomTeam( Player )
		end

		-- Override the built in randomise ready room vote to not move AFK players.
		SetVoteSuccessfulCallback( "VoteRandomizeRR", 2, function( Data )
			local Action = self.Enabled and MoveIfNotAFK or JoinRandomTeam
			GetGamerules():GetTeam( kTeamReadyRoom ):ForEachPlayer( Action )
		end )
	end

	local function FilterPlayers( Player )
		local ShouldKeep = true
		local Client = GetClientForPlayer( Player )

		if not Client or self:IsAFKFor( Client, 60 ) then
			ShouldKeep = false

			if Client and Shine.IsPlayingTeam( Player:GetTeamNumber() ) then
				AttemptToMovePlayerToTeam( GetGamerules(), Client, Player, kTeamReadyRoom )
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

	do
		-- Treat attempting to join a team as activity.
		local Commands = {
			"j1", "jointeamone", "j2", "jointeamtwo", "j3", "jointeamthree", "rr", "readyroom", "spectate"
		}
		local OnAttemptToJoinTeam = self:WrapCallback( function( Client )
			self:SubtractAFKTime( Client, 0.1 )
		end )

		for i = 1, #Commands do
			Event.Hook( "Console_"..Commands[ i ], OnAttemptToJoinTeam )
		end
	end
end

function Plugin:Cleanup()
	local EntityList = Shared.GetEntitiesWithClassname( "PlayerInfoEntity" )
	for _, Entity in ientitylist( EntityList ) do
		Entity.afk = false
	end

	Shine.Hook.Remove( "CheckPlayerName", self )

	self.BaseClass.Cleanup( self )
end

Shine.LoadPluginModule( "logger.lua", Plugin )
