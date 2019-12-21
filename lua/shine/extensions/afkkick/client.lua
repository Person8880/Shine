--[[
	AFK plugin client.
]]

local Plugin = ...

local GetScoreboardEntryByName = Shine.GetScoreboardEntryByName
local setmetatable = setmetatable
local StringFormat = string.format
local xpcall = xpcall

Plugin.NotifySoundEffect = "sound/NS2.fev/common/tooltip_on"
function Plugin:ReceiveAFKNotify( Data )
	-- Flash the taskbar icon and play a sound. Can't say we didn't warn you.
	Client.WindowNeedsAttention()
	StartSoundEffect( self.NotifySoundEffect )
end

function Plugin:OnScoreboardEntryReload( Entry, Entity )
	if not Entity.afk then return end

	local NewName = self.AFK_PREFIX..Entry.Name

	-- Make sure the new name is unique.
	local Index = 2
	local ExistingEntry = GetScoreboardEntryByName( NewName )
	while ExistingEntry and ExistingEntry ~= Entry do
		NewName = StringFormat( "%s%s (%s)", self.AFK_PREFIX, Entry.Name, Index )
		Index = Index + 1
		ExistingEntry = GetScoreboardEntryByName( NewName )
	end

	Entry.Name = NewName
end
