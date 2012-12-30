--[[
	Shine unstuck plugin.
]]

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
		local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

		if not PluginConfig then
			Notify( "Error writing unstuck config file: "..Err )	

			return	
		end

		PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

		Notify( "Shine unstuck config file created." )

		PluginConfig:close()
	end
end

function Plugin:SaveConfig()
	local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

	if not PluginConfig then
		Notify( "Error writing unstuck config file: "..Err )	

		return	
	end

	PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

	Shine:Print( "Shine unstuck config file saved." )

	PluginConfig:close()
end

function Plugin:LoadConfig()
	local PluginConfig = io.open( Shine.Config.ExtensionDir..self.ConfigName, "r" )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = Decode( PluginConfig:read( "*all" ) )

	PluginConfig:close()
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
			Shine:Notify( Player, "You must wait %s before using unstuck again.", true, string.TimeToString( NextUse - Time ) )

			return
		end
		

		local Success = self:UnstickPlayer( Player, Player:GetOrigin() )

		if Success then
			Shine:Notify( Player, "Successfully unstuck." )

			self.Users[ Client ] = Time + self.Config.TimeBetweenUse
		else
			Shine:Notify( Player, "Unable to unstick. Try again in %s.", true, string.TimeToString( self.Config.MinTime ) )

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
