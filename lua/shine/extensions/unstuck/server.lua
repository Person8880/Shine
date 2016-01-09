--[[
	Shine unstuck plugin.
]]

local Shine = Shine

local Ceil = math.ceil

local Plugin = Plugin
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "Unstuck.json"

Plugin.DefaultConfig = {
	DistanceToCheck = 6,
	TimeBetweenUse = 30,
	MinTime = 5
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.PrintName = "Unstuck"

function Plugin:Initialise()
	self.Users = {}

	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:UnstickPlayer( Player, Pos )
	-- Respawn ready room players instead of trying to find a spawn point near them.
	if Player:GetTeamNumber() == kTeamReadyRoom then
		GetGamerules():JoinTeam( Player, kTeamReadyRoom, true )
		return true
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

		local Player = Client:GetControllingPlayer()
		if not Player then return end

		if not Player:GetIsAlive() then
			self:NotifyTranslatedError( Client, "ERROR_NOT_ALIVE" )

			return
		end

		local Time = Shared.GetTime()

		local NextUse = self.Users[ Client ]
		if NextUse and NextUse > Time then
			self:SendTranslatedError( Client, "ERROR_WAIT", {
				TimeLeft = Ceil( NextUse - Time )
			} )

			return
		end

		local Success = self:UnstickPlayer( Player, Player:GetOrigin() )

		if Success then
			self:NotifyTranslated( Client, "SUCCESS" )

			self.Users[ Client ] = Time + self.Config.TimeBetweenUse
		else
			self:SendTranslatedError( Client, "ERROR_FAIL", {
				TimeLeft = Ceil( self.Config.MinTime )
			} )

			self.Users[ Client ] = Time + self.Config.MinTime
		end
	end
	local UnstickCommand = self:BindCommand( "sh_unstuck", { "unstuck", "stuck" }, Unstick, true )
	UnstickCommand:Help( "Attempts to free you from being trapped inside world geometry." )
end
