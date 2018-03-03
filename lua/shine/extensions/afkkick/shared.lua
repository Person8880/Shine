--[[
	AFK plugin shared.
]]

local Plugin = {}
Plugin.NotifyPrefixColour = { 255, 50, 0 }

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "AFKNotify", {}, "Client" )
	self:AddNetworkMessage( "SteamOverlay", { Open = "boolean" }, "Server" )
	self:AddTranslatedNotify( "WARN_KICK_ON_CONNECT", {
		AFKTime = "integer"
	} )
end

Shine:RegisterExtension( "afkkick", Plugin )

Shine.UpdateClassNetVars( "PlayerInfoEntity", "lua/PlayerInfoEntity.lua", {
	afk = "boolean"
} )

if Server then return end

local xpcall = xpcall

Plugin.NotifySoundEffect = "sound/NS2.fev/common/tooltip_on"
function Plugin:ReceiveAFKNotify( Data )
	-- Flash the taskbar icon and play a sound. Can't say we didn't warn you.
	Client.WindowNeedsAttention()
	StartSoundEffect( self.NotifySoundEffect )
end

function Plugin:SetupAFKScoreboardPrefix()
	Shine.Hook.SetupGlobalHook( "Scoreboard_ReloadPlayerData",
		"PostScoreboardReload", "PassivePost" )

	local AFK_PREFIX = "AFK - "
	local CALLING = false

	local function UpdateNamesWithAFKState()
		local EntityList = Shared.GetEntitiesWithClassname( "PlayerInfoEntity" )
		for _, Entity in ientitylist( EntityList ) do
			local Entry = Scoreboard_GetPlayerRecord( Entity.clientId )
			if Entry and Entry.Name and Entity.afk then
				Entry.Name = AFK_PREFIX..Entry.Name
			end
		end
	end
	local ErrorHandler = Shine.BuildErrorHandler( "Scoreboard update error" )

	self.PostScoreboardReload = function( self )
		if CALLING then return end

		-- Just in case we somehow see a PlayerInfoEntity that has a client ID that is not
		-- in the scoreboard player data yet, we don't want to trigger a stack overflow.
		CALLING = true

		xpcall( UpdateNamesWithAFKState, ErrorHandler )

		CALLING = false
	end
end

local GetIsSteamOverlayActive
function Plugin:OnFirstThink()
	GetIsSteamOverlayActive = Client.GetIsSteamOverlayActive
	self:SetupAFKScoreboardPrefix()
end

local SteamOverlayIsOpen = false
function Plugin:Think()
	local CurrentOverlayState = GetIsSteamOverlayActive()

	-- Watch the Steam overlay. If it's opened, then the server should ignore all input
	-- from the player until it closes, thus treating them as AFK.
	if CurrentOverlayState ~= SteamOverlayIsOpen then
		SteamOverlayIsOpen = CurrentOverlayState
		self:SendNetworkMessage( "SteamOverlay", { Open = SteamOverlayIsOpen }, true )
	end
end
