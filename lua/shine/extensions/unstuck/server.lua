--[[
	Shine unstuck plugin.
]]

local Shine = Shine

local Ceil = math.ceil

local Plugin = ...
Plugin.Version = "1.1"

Plugin.HasConfig = true
Plugin.ConfigName = "Unstuck.json"

Plugin.DefaultConfig = {
	-- The distance around the player to check for a valid location.
	DistanceToCheck = 6,
	-- The time between successful unstick requests (in seconds).
	TimeBetweenUse = 30,
	-- The minimum time to wait between unstick requests (in seconds).
	MinTime = 5,
	-- How long to wait before moving a player (forces them to be stationary for this time).
	DelayBeforeMovingInSeconds = 0
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.PrintName = "Unstuck"

function Plugin:Initialise()
	self.NextUsageTimes = {}
	self.ClientsBeingUnstuck = {}

	self:CreateCommands()

	self.Enabled = true

	return true
end

local function IsInEntityBounds( Entity, Origin )
	local Extents = Entity:GetExtents()
	local Coords = Entity:GetCoords()

	local LocalOrigin = Coords:GetInverse():TransformPoint( Origin )
	local Mins, Maxs = -Extents, Extents

	return LocalOrigin.x > Mins.x and LocalOrigin.y > Mins.y and LocalOrigin.z > Mins.z
		and LocalOrigin.x < Maxs.x and LocalOrigin.y < Maxs.y and LocalOrigin.z < Maxs.z
end

local function IsPlayerContainedIn( ClassName, PlayerOrigin, DistanceToCheck )
	local Entities = GetEntitiesWithinRange( ClassName, PlayerOrigin, DistanceToCheck )

	for i = 1, #Entities do
		local Entity = Entities[ i ]
		if IsInEntityBounds( Entity, PlayerOrigin ) then
			return true
		end
	end

	return false
end

-- A list of class names of objects that should not permit unsticking
-- when a player is in their (oriented) bounding box.
Plugin.BlockingClassNames = {
	"BoneWall"
}

function Plugin:ShouldPlayerBeUnstuck( Player )
	local PlayerOrigin = Player:GetOrigin()
	local DistanceToCheck = self.Config.DistanceToCheck

	for i = 1, #self.BlockingClassNames do
		local ClassName = self.BlockingClassNames[ i ]
		if IsPlayerContainedIn( ClassName, PlayerOrigin, DistanceToCheck ) then
			return false
		end
	end

	return true
end

function Plugin:UnstickPlayer( Player, Pos )
	-- Respawn ready room players instead of trying to find a spawn point near them.
	if Player:GetTeamNumber() == kTeamReadyRoom then
		GetGamerules():JoinTeam( Player, kTeamReadyRoom, true )
		return true
	end

	-- Make sure the player isn't inside something that's supposed to block them.
	if not self:ShouldPlayerBeUnstuck( Player ) then
		return false
	end

	local TechID = kTechId.Skulk
	if Player:GetIsAlive() then
		TechID = Player:GetTechId()
	end

	local Bounds = LookupTechData( TechID, kTechDataMaxExtents )
	if not Bounds then
		return false
	end

	local Height, Radius = GetTraceCapsuleFromExtents( Bounds )

	local SpawnPoint
	local ResourceNear
	local i = 1

	local Range = self.Config.DistanceToCheck

	repeat
		SpawnPoint = GetRandomSpawnForCapsule( Height, Radius, Pos, 2, Range, EntityFilterAll() )

		if SpawnPoint then
			ResourceNear = #GetEntitiesWithinRange( "ResourcePoint", SpawnPoint, 2 ) > 0
		end

		i = i + 1
	until not ResourceNear or i > 100

	if SpawnPoint then
		Player:SetOrigin( SpawnPoint )

		return true
	end

	return false
end

function Plugin:CreateCommands()
	local function Unstick( Client )
		if not Client then return end

		if self.ClientsBeingUnstuck[ Client ] then
			self:NotifyTranslatedError( Client, "ERROR_IN_PROGRESS" )
			return
		end

		local Player = Client:GetControllingPlayer()
		if not Player then return end

		if Player:isa( "Spectator" ) then
			self:NotifyTranslatedError( Client, "ERROR_NOT_APPLICABLE" )
			return
		end

		if not Player:GetIsAlive() then
			self:NotifyTranslatedError( Client, "ERROR_NOT_ALIVE" )
			return
		end

		local Time = Shared.GetTime()

		local NextUse = self.NextUsageTimes[ Client ]
		if NextUse and NextUse > Time then
			self:SendTranslatedError( Client, "ERROR_WAIT", {
				TimeLeft = Ceil( NextUse - Time )
			} )
			return
		end

		local InitialOrigin = Player:GetOrigin()
		local function UnstickPlayer()
			self.ClientsBeingUnstuck[ Client ] = nil

			if not Shine:IsValidClient( Client ) then return end
			if Player ~= Client:GetControllingPlayer() then return end

			if not Player:GetIsAlive() then
				self:NotifyTranslatedError( Client, "ERROR_NOT_ALIVE" )
				return
			end

			local CurrentOrigin = Player:GetOrigin()
			if CurrentOrigin ~= InitialOrigin then
				self:NotifyTranslatedError( Client, "ERROR_MOVED" )
				return
			end

			local Success = self:UnstickPlayer( Player, CurrentOrigin )

			if Success then
				self:NotifyTranslated( Client, "SUCCESS" )

				self.NextUsageTimes[ Client ] = Time + self.Config.TimeBetweenUse
			else
				self:SendTranslatedError( Client, "ERROR_FAIL", {
					TimeLeft = Ceil( self.Config.MinTime )
				} )

				self.NextUsageTimes[ Client ] = Time + self.Config.MinTime
			end
		end

		-- There's no point delaying unsticking for those in the ready room.
		if self.Config.DelayBeforeMovingInSeconds > 0 and Player:GetTeamNumber() ~= kTeamReadyRoom then
			self.ClientsBeingUnstuck[ Client ] = true

			self:SendTranslatedNotify( Client, "UNSTICKING", {
				TimeLeft = self.Config.DelayBeforeMovingInSeconds
			} )
			self:SimpleTimer( self.Config.DelayBeforeMovingInSeconds, UnstickPlayer )
		else
			UnstickPlayer()
		end
	end
	local UnstickCommand = self:BindCommand( "sh_unstuck", { "unstuck", "stuck" }, Unstick, true )
	UnstickCommand:Help( "Attempts to free you from being trapped inside world geometry." )
end
