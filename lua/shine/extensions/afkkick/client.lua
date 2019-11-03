--[[
	AFK plugin client.
]]

local Plugin = ...

local setmetatable = setmetatable
local StringFormat = string.format
local xpcall = xpcall

Plugin.NotifySoundEffect = "sound/NS2.fev/common/tooltip_on"
function Plugin:ReceiveAFKNotify( Data )
	-- Flash the taskbar icon and play a sound. Can't say we didn't warn you.
	Client.WindowNeedsAttention()
	StartSoundEffect( self.NotifySoundEffect )
end

function Plugin:SetupAFKScoreboardPrefix()
	local GetPlayerDataByName = Shine.GetUpValueAccessor( Scoreboard_ReloadPlayerData, "playerDataByName", {
		Recursive = true,
		Predicate = Shine.UpValuePredicates.DefinedInFile( "lua/Scoreboard.lua" )
	} )

	Shine.Hook.SetupGlobalHook( "Scoreboard_ReloadPlayerData",
		"PostScoreboardReload", "PassivePost" )

	local AFK_PREFIX = self.AFK_PREFIX
	local CALLING = false

	local function UpdateNamesWithAFKState()
		local PlayerDataByName = GetPlayerDataByName()

		local UniqueNames = setmetatable( {}, { __index = PlayerDataByName } )
		local EntityList = Shared.GetEntitiesWithClassname( "PlayerInfoEntity" )
		for _, Entity in ientitylist( EntityList ) do
			local Entry = Scoreboard_GetPlayerRecord( Entity.clientId )
			if Entry and Entry.Name then
				if Entity.afk then
					local NewName = AFK_PREFIX..Entry.Name

					-- Make sure the new name is unique.
					local Index = 2
					while UniqueNames[ NewName ] and UniqueNames[ NewName ] ~= Entry do
						NewName = StringFormat( "%s%s (%s)", AFK_PREFIX, Entry.Name, Index )
						Index = Index + 1
					end

					Entry.Name = NewName

					if PlayerDataByName then
						PlayerDataByName[ NewName ] = Entry
					end
				end

				UniqueNames[ Entry.Name ] = Entry
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

function Plugin:OnFirstThink()
	self:SetupAFKScoreboardPrefix()
end
