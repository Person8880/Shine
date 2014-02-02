--[[
	Workshop mod update checker.
]]

local Shine = Shine

local Max = math.max
local HTTPRequest = Shared.SendHTTPRequest
local Huge = math.huge
local StringFormat = string.format
local tonumber = tonumber

local Plugin = {}

Plugin.HasConfig = true
Plugin.ConfigName = "WorkshopUpdater.json"
Plugin.CheckConfig = true

Plugin.DefaultConfig = {
	CheckInterval = 60,
	RepeatNotifications = true,
	NotifyInterval = 180,
	ForceMapChangeAfterNotifications = 5,
	ForceMapvote = false,
	ForceMapvoteAtRoundEnd = false	
}

local RemainingNotifications = Huge
local ModChangeTimer = "CheckForModChange"
local RepeatMessageTimer = "RepeatModUpdateMessage"

function Plugin:Initialise()
	self.Config.CheckInterval = Max( self.Config.CheckInterval, 15 )
	self.Config.NotifyInterval = Max( self.Config.NotifyInterval, 15 )
	self.Config.ForceMapChangeAfterNotifications = Max( self.Config.ForceMapChangeAfterNotifications, 0 )

	if self.Config.ForceMapChangeAfterNotifications > 0 then
		RemainingNotifications = self.Config.ForceMapChangeAfterNotifications
	end

	self:CreateTimer( ModChangeTimer, self.Config.CheckInterval, -1, function()
		self:CheckForModChange()
	end )

	self.Enabled = true
	
	return true
end

function Plugin:Notify( String, Format, ... )
	String = Format and StringFormat( String, ... ) or String

	Shine:NotifyDualColour( nil, 255, 160, 0, "[Workshop]", 255, 255, 255, String )
end

local LastKnownUpdate = {}

local function FindCharactersBetween( Response, OpeningCharacters, ClosingCharacters )
	local Result

	local IndexOfOpeningCharacters = Response:find( OpeningCharacters )
	
	if IndexOfOpeningCharacters then
		local FoundCharacters = Response:sub( IndexOfOpeningCharacters + #OpeningCharacters )
		local IndexOfClosingCharacters = FoundCharacters:find( ClosingCharacters )
	
		if IndexOfClosingCharacters then
			FoundCharacters = FoundCharacters:sub( 1, IndexOfClosingCharacters - 1 )
			FoundCharacters = StringTrim( FoundCharacters )

			Result = FoundCharacters
		end
	end
	
	return Result
end

local function GetUpdatedTime( Response )
	return FindCharactersBetween( Response, "Update:", "</div>" )
end

local function GetModName( Response )
	return FindCharactersBetween( Response, "<div class=\"workshopItemTitle\">", "</div>" )
end

--[[
	Checks a specific mod ID for an update.
	Input: Base 10 mod ID.
]]
function Plugin:CheckModID( ID )
	local URL = "http://steamcommunity.com/sharedfiles/filedetails/changelog/"..ID

	HTTPRequest( URL, "GET", function( Response )
		if not Response or #Response == 0 then return end
		if self.ChangedModName then return end

		local Update = GetUpdatedTime( Response )

		if not Update then return end

		if not LastKnownUpdate[ ID ] then
			LastKnownUpdate[ ID ] = Update
		elseif LastKnownUpdate[ ID ] ~= Update then
			LastKnownUpdate[ ID ] = Update

			local ModName = GetModName( Response )

			if ModName and ModName ~= "" then
				self.ChangedModName = ModName

				self:DestroyTimer( ModChangeTimer )

				self:NotifyOrCycle()
			end
		end
	end )
end

--[[
	Checks all installed mods for updates.
]]
function Plugin:CheckForModChange()
	local GetMod = Server.GetActiveModId
	
	for i = 1, Server.GetNumActiveMods() do
		local ID = tonumber( GetMod( i ), 16 )
		
		self:CheckModID( ID )
	end
end

--[[
	Informs connected players of the first mod in need of updating.
	Will cycle the map if the server is empty, or we've gone past the max
	number of notifications.
]]
function Plugin:NotifyOrCycle( recall )
	if #Shine.GetAllPlayers() == 0 then
		self:SimpleTimer( 5, function() MapCycle_CycleMap() end )
		return
	end

	local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )

	--Mapvote actions
	if Enabled and not recall then
		--Deny extension of the map.
		MapVote.Config.AllowExtend = false
		
		if self.Config.ForceMapvote and not MapVote:VoteStarted() then
		    MapVote:StartVote( nil, true )   
		elseif self.Config.ForceMapvoteAtRoundEnd then
		    MapVote.VoteOnEnd = true
		    MapVote.Round = MapVote.Config.RoundLimit
		    MapVote.MapCycle.time = Shared.GetTime() / 60		    		    
		end
	end

	self:Notify( "The \"%s\" mod has updated on the Steam Workshop.", true, self.ChangedModName )
	self:Notify( "Players cannot connect to the server until map change." )

	if RemainingNotifications < Huge then
		local TimeRemainingString = "now"
		RemainingNotifications = RemainingNotifications - 1

		local TimeBeforeChange = RemainingNotifications * self.Config.NotifyInterval
		if TimeBeforeChange > 5 then
			TimeRemainingString = "in "..string.TimeToString( TimeBeforeChange )
		end

		self:Notify( "The map will cycle %s.", true, TimeRemainingString )
	end

	if RemainingNotifications == 0 then
		self:SimpleTimer( 5, function() MapCycle_CycleMap() end )
		return
	end

	if self.Config.RepeatNotifications then
		self:CreateTimer( RepeatMessageTimer, self.Config.NotifyInterval, 1, function() self:NotifyOrCycle( true ) end )
	end
end

Shine:RegisterExtension( "workshopupdater", Plugin )
