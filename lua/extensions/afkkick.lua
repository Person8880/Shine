--[[
	Shine AFK kick plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "AFKKick.json"

Plugin.Users = {}

function Plugin:Initialise()
	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		MinPlayers = 10,
		Delay = 1,
		WarnTime = 5,
		KickTime = 15,
		Warn = true
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing afkkick config file: "..Err )	

			return	
		end

		Notify( "Shine afkkick config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing afkkick config file: "..Err )	

		return	
	end

	Notify( "Shine afkkick config file saved." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig
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
		LastMove = Shared.GetTime() + ( self.Config.Delay * 60 ),
		Pos = Player:GetOrigin(),
		Ang = Player:GetViewAngles()
	}
end

--[[
	Update the given player/client, check if they've moved since the last time we checked.
	If they haven't moved and it's past the warn time, warn them.
	If they haven't moved and it's past the kick time, kick them.
]]
function Plugin:UpdateClient( Player, Client, DataTable, Time )	
	if not Player then return end
	if not Client then return end

	if Client:GetIsVirtual() then return end

	if Shine:HasAccess( Client, "sh_afk" ) then return end --Immunity.

	local CurPos = Player:GetOrigin()
	local CurAng = Player:GetViewAngles()

	if CurAng ~= DataTable.Ang or ( CurPos ~= DataTable.Pos and Player:GetIsOverhead() ) then
		DataTable.Ang = CurAng
		DataTable.Pos = CurPos
		DataTable.LastMove = Time

		if DataTable.Warn then
			DataTable.Warn = false
		end

		return
	end

	if not DataTable.Warn and self.Config.Warn then
		local WarnTime = self.Config.WarnTime * 60

		if DataTable.LastMove + WarnTime < Time then
			DataTable.Warn = true
			Shine:Notify( Player, "Warning", Shine.Config.ChatName, "You have been AFK for over %s. Continue and you will be kicked.", true, string.TimeToString( WarnTime ) )
			return
		end

		return
	end

	local KickTime = self.Config.KickTime * 60

	if DataTable.LastMove + KickTime < Time then
		self:ClientDisconnect( Client ) --Failsafe.
		Shine:Print( "Client %s[%s] was AFK for over %s. Kicking...", true, Player:GetName(), Client:GetUserId(), string.TimeToString( KickTime ) )
		Server.DisconnectClient( Client )
	end
end

--[[
	Every server tick, check all players.
]]
function Plugin:Think( DeltaTime )
	local Players = EntityListToTable( Shared.GetEntitiesWithClassname( "Player" ) )

	if #Players < self.Config.MinPlayers then return end

	local Time = Shared.GetTime()

	for i = 1, #Players do
		local Player = Players[ i ]
		
		if Player then
			local Client = Server.GetOwner( Player )

			if Client then
				if not Client:GetIsVirtual() and not self.Users[ Client ] then
					self:ClientConnect( Client ) --Failsafe.
				end
				
				self:UpdateClient( Player, Client, self.Users[ Client ], Time )
			end
		end
	end
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

Shine:RegisterExtension( "afkkick", Plugin )
