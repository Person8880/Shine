--[[
	AFK plugin shared.
]]

local Plugin = {}

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "AFKNotify", {}, "Client" )
	self:AddNetworkMessage( "SteamOverlay", { Open = "boolean" }, "Server" )
end

Shine:RegisterExtension( "afkkick", Plugin )

if Server then return end

Plugin.NotifySoundEffect = "sound/NS2.fev/common/tooltip_on"
function Plugin:ReceiveAFKNotify( Data )
	-- Flash the taskbar icon and play a sound. Can't say we didn't warn you.
	Client.WindowNeedsAttention()
	StartSoundEffect( self.NotifySoundEffect )
end

local GetIsSteamOverlayActive
function Plugin:OnFirstThink()
	GetIsSteamOverlayActive = Client.GetIsSteamOverlayActive
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
