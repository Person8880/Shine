--[[
	Shine welcome message plugin.
]]

local Shine = Shine

local GetOwner = Server.GetOwner
local StringFormat = string.format
local TableEmpty = table.Empty

local Plugin = Plugin
Plugin.Version = "1.2"

Plugin.HasConfig = true
Plugin.ConfigName = "WelcomeMessages.json"

Plugin.DefaultConfig = {
	MessageDelay = 5,
	Users = {
		[ "90000001" ] = {
			Welcome = "Bob has joined the party!",
			Leave = "Bob is off to fight more important battles."
		}
	},
	ShowGeneric = false
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.SilentConfigSave = true

function Plugin:Initialise()
	self.Welcomed = {}
	self.Enabled = true

	return true
end

function Plugin:ClientConnect( Client )
	self:SimpleTimer( self.Config.MessageDelay, function()
		if not Shine:IsValidClient( Client ) then return end

		local ID = Client:GetUserId()
		local MessageTable = self.Config.Users[ tostring( ID ) ]

		if MessageTable and MessageTable.Welcome then
			if not MessageTable.Said then
				Shine:NotifyColour( nil, 255, 255, 255, MessageTable.Welcome )

				MessageTable.Said = true

				self:SaveConfig()
			end

			self.Welcomed[ Client ] = true

			return
		end

		if not self.Config.ShowGeneric then return end

		self.Welcomed[ Client ] = true

		local Player = Client:GetControllingPlayer()
		if not Player then return end

		self:SendTranslatedNotifyColour( nil, "PLAYER_JOINED_GENERIC", {
			R = 255, G = 255, B = 255,
			TargetName = Player:GetName()
		} )
	end )
end

local Ceil = math.ceil

local function ColourIntToTable( Int, Multiplier )
	local Colour = ColorIntToColor( Int )
	return { Ceil( Colour.r * 255 * Multiplier ), Ceil( Colour.g * 255 * Multiplier ),
		Ceil( Colour.b * 255 * Multiplier ) }
end

local TeamColours = {
	[ 0 ] = { 255, 255, 255 },
	[ 1 ] = ColourIntToTable( kMarineTeamColor or 0x4DB1FF, 0.8 ),
	[ 2 ] = ColourIntToTable( kAlienTeamColor or 0xFFCA3A, 0.8 )
}

function Plugin:ClientDisconnect( Client )
	if not self.Welcomed[ Client ] then return end

	self.Welcomed[ Client ] = nil

	local ID = Client:GetUserId()
	local MessageTable = self.Config.Users[ tostring( ID ) ]

	if MessageTable and MessageTable.Leave then
		Shine:NotifyColour( nil, 255, 255, 255, MessageTable.Leave )

		MessageTable.Said = nil

		self:SaveConfig()

		return
	end

	if not self.Config.ShowGeneric then return end

	local Player = Client:GetControllingPlayer()
	if not Player then return end

	local Team = Client.DisconnectTeam or 0
	local Colour = TeamColours[ Team ] or TeamColours[ 0 ]

	if not Client.DisconnectReason then
		self:SendTranslatedNotifyColour( nil, "PLAYER_LEAVE_GENERIC", {
			R = Colour[ 1 ], G = Colour[ 2 ], B = Colour[ 3 ],
			TargetName = Player:GetName()
		} )
	else
		self:SendTranslatedNotifyColour( nil, "PLAYER_LEAVE_REASON", {
			R = Colour[ 1 ], G = Colour[ 2 ], B = Colour[ 3 ],
			TargetName = Player:GetName(),
			Reason = Client.DisconnectReason
		} )
	end
end

function Plugin:OnScriptDisconnect( Client )
	local Player = Client:GetControllingPlayer()

	if not Player then return end

	local Team = Player.GetTeamNumber and Player:GetTeamNumber()
	if not Team then return end

	Client.DisconnectTeam = Team
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if NewTeam < 0 then return end
	if not Player then return end

	local Client = GetOwner( Player )

	if Client then
		Client.DisconnectTeam = NewTeam
	end
end

function Plugin:Cleanup()
	self.Welcomed = nil
	self.BaseClass.Cleanup( self )

	self.Enabled = false
end

Shine.Hook.SetupGlobalHook( "Server.DisconnectClient", "OnScriptDisconnect", "PassivePre" )
