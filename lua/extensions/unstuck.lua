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

Plugin.Commands = {}

function Plugin:Initialise()
	self.Users = {}

	self:CreateCommands()

	self.Enabled = true
	
	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		DistanceToCheck = 6,
		TimeBetweenUse = 30,
		MinTime = 5
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing unstuck config file: "..Err )	

			return	
		end

		Notify( "Shine unstuck config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing unstuck config file: "..Err )	

		return	
	end

	Notify( "Shine unstuck config file saved." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig
end

function Plugin:UnstickPlayer( Player, Pos )
	local TechID = kTechId.Skulk

	if Player:GetIsAlive() then
		TechID = Player:GetTechId()
	end

	local Bounds = LookupTechData( TechID, kTechDataMaxExtents )
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
	local Commands = self.Commands

	local function Unstick( Client )
		if not Client then return end
		local Player = Client:GetControllingPlayer()

		if not Player then return end
		
		local Time = Shared.GetTime()

		local NextUse = self.Users[ Client ]
		if NextUse and NextUse > Time then
			Shine:Notify( Player, "Error", Shine.Config.ChatName, "You must wait %s before using unstuck again.", true, string.TimeToString( NextUse - Time ) )

			return
		end
		

		local Success = self:UnstickPlayer( Player, Player:GetOrigin() )

		if Success then
			Shine:Notify( Player, "Unstuck", Shine.Config.ChatName, "Successfully unstuck." )

			self.Users[ Client ] = Time + self.Config.TimeBetweenUse
		else
			Shine:Notify( Player, "Error", Shine.Config.ChatName, "Unable to unstick. Try again in %s.", true, string.TimeToString( self.Config.MinTime ) )

			self.Users[ Client ] = Time + self.Config.MinTime
		end
	end
	Commands.UnstickCommand = Shine:RegisterCommand( "sh_unstuck", { "unstuck", "stuck" }, Unstick, true )
	Commands.UnstickCommand:Help( "Attempts to free you from being trapped inside world geometry." )
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "unstuck", Plugin )
