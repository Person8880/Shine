--[[
	Shine unstuck plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "Unstuck.json"

Plugin.DefaultConfig = {
	DistanceToCheck = 6,
	TimeBetweenUse = 30,
	MinTime = 5
}

Plugin.CheckConfig = true

function Plugin:Initialise()
	self.Users = {}

	self:CreateCommands()

	self.Enabled = true
	
	return true
end

function Plugin:Notify( Player, String, Format, ... )
	Shine:NotifyDualColour( Player, 100, 100, 100, "[Unstuck]", 255, 255, 255, String, Format, ... )
end

function Plugin:UnstickPlayer( Player, Pos )
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
		SpawnPlayerAtPoint( Player, SpawnPoint )

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
			Shine:NotifyError( Player, "You cannot be unstuck when you are dead." )

			return
		end
		
		local Time = Shared.GetTime()

		local NextUse = self.Users[ Client ]
		if NextUse and NextUse > Time then
			Shine:NotifyError( Player, "You must wait %s before using unstuck again.", true, string.TimeToString( NextUse - Time ) )

			return
		end

		Server.SendNetworkMessage( Client, "Shine_Command", { Command = "annotate Shine unstuck was used here." }, true )

		local Success = self:UnstickPlayer( Player, Player:GetOrigin() )

		if Success then
			self:Notify( Player, "Successfully unstuck." )

			self.Users[ Client ] = Time + self.Config.TimeBetweenUse
		else
			Shine:NotifyError( Player, "Unable to unstick. Try again in %s.", true, string.TimeToString( self.Config.MinTime ) )

			self.Users[ Client ] = Time + self.Config.MinTime
		end
	end
	local UnstickCommand = self:BindCommand( "sh_unstuck", { "unstuck", "stuck" }, Unstick, true )
	UnstickCommand:Help( "Attempts to free you from being trapped inside world geometry." )
end

Shine:RegisterExtension( "unstuck", Plugin )
