--[[
	AFK plugin shared.
]]

local Plugin = {}

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "AFKNotify", {}, "Client" )
end

Shine:RegisterExtension( "afkkick", Plugin )

if Server then return end

Plugin.NotifySoundEffect = "sound/NS2.fev/common/tooltip_on"
function Plugin:ReceiveAFKNotify( Data )
	-- Flash the taskbar icon and play a sound. Can't say we didn't warn you.
	Client.WindowNeedsAttention()
	StartSoundEffect( self.NotifySoundEffect )
end
