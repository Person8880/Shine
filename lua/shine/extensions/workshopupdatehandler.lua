local lastKnownUpdate = {}
local changedModName
local remainingNotifications = math.huge
local CHECK_FOR_MOD_CHANGE_TIMER_ID = "CheckForModChange"

local function secondsToHoursMinutesSeconds(sSeconds)
	local nHours = 0
	local nMins = 0
	local nSecs = 0
	local nSeconds = tonumber(sSeconds)
	if nSeconds ~= 0 then
		nHours = string.format("%02.f", math.floor(nSeconds/3600));
		nMins = string.format("%02.f", math.floor(nSeconds/60 - (nHours*60)));
		nSecs = string.format("%02.f", math.floor(nSeconds - nHours*3600 - nMins *60));
	end
	return nHours, nMins, nSecs
end

local function getTimeRemainingDescriptor(secondsRemaining)
	local result
	local hours, minutes, seconds = secondsToHoursMinutesSeconds(secondsRemaining)
	if tonumber(hours) > 0 then
		result = string.format("in %s:%s:%s", hours, minutes, seconds)
	elseif tonumber(minutes) > 0 then
		result = string.format("in %s minute", tonumber(minutes));
		if tonumber(minutes) > 1 then
			result = result .. "s"
		else
		end
		if tonumber(seconds) > 0 then
			result = result .. string.format(" and %s seconds", tonumber(seconds));
		else

		end
	else
		result = string.format("in %s seconds", tonumber(seconds));
	end
	return result
end

local function findCharactersBetween(response, openingCharacters, closingCharacters)
	local result = nil
	local indexOfOpeningCharacters = response:find(openingCharacters)
	if indexOfOpeningCharacters then
		local foundCharacters = string.sub(response, indexOfOpeningCharacters + string.len(openingCharacters))
		local indexOfClosingCharacters = foundCharacters:find(closingCharacters)
		if indexOfClosingCharacters then
			foundCharacters = string.sub(foundCharacters, 1, indexOfClosingCharacters - 1)
			foundCharacters = StringTrim(foundCharacters)
			result = foundCharacters
		end
	end
	return result
end

local function getUpdatedTimeFromResponse(response)
	local result = findCharactersBetween(response, "Update:", "</div>")
	return result
end

local function getModNameFromResponse(response)
	local result = findCharactersBetween(response, "<div class=\"workshopItemTitle\">", "</div>")
	return result
end

local Plugin = {}

Plugin.HasConfig = true
Plugin.ConfigName = "WorkshopUpdateHandler.json"
Plugin.CheckConfig = true
Plugin.DefaultConfig = {
	CheckIntervalInSeconds = 60,
	RepeatNotifications = true,
	NotifyIntervalInSeconds = 180,
	ForceMapChangeAfterNotifications = 5
}

function Plugin:CheckForModChange(plugin)
    for i = 1, Server.GetNumActiveMods() do
    	local id = tonumber(Server.GetActiveModId(i), 16)
		local url = "http://steamcommunity.com/sharedfiles/filedetails/changelog/" .. id
		Shared.SendHTTPRequest(url, "GET", function(response)
			if not changedModName then
				local update = getUpdatedTimeFromResponse(response)
				if lastKnownUpdate[id] == nil then
					lastKnownUpdate[id] = update
				elseif lastKnownUpdate[id] ~= update then
					lastKnownUpdate[id] = update
					local modName = getModNameFromResponse(response)
					if modName and modName ~= "" then
						changedModName = modName
						Shine.Timer.Destroy(CHECK_FOR_MOD_CHANGE_TIMER_ID)
						self:NotifyOrCycle()
					end
				end
			end
		end)
    end
end

function Plugin:NotifyOrCycle()
	Shine:Notify( nil, "All", Shine.Config.ChatName, string.format("%s mod has updated in Steam Workshop.", changedModName) )
	Shine:Notify( nil, "All", Shine.Config.ChatName, "Players cannot connect to the server until mapchange." )
	if remainingNotifications < math.huge then
		local timeRemainingBeforeForcedMapChangeDescriptor = "now"
		remainingNotifications = remainingNotifications - 1
		local secondsRemainingBeforeForcedMapChange = remainingNotifications * self.Config.NotifyIntervalInSeconds
		if secondsRemainingBeforeForcedMapChange > 5 then
			timeRemainingBeforeForcedMapChangeDescriptor = getTimeRemainingDescriptor(secondsRemainingBeforeForcedMapChange)
		end
		local message = string.format("Map will cycle automatically %s.", timeRemainingBeforeForcedMapChangeDescriptor)
		Shine:Notify( nil, "All", Shine.Config.ChatName, message )
	end
	if #Shine.GetAllPlayers() == 0 or remainingNotifications == 0 then
		Shine.Timer.Simple(3, function() MapCycle_CycleMap() end )
	end
	if self.Config.RepeatNotifications then
		Shine.Timer.Simple(self.Config.NotifyIntervalInSeconds, function() self:NotifyOrCycle() end )
	end
end

function Plugin:Initialise()
    self.Enabled = true
    if self.Config.ForceMapChangeAfterNotifications > 0 then
	    remainingNotifications = self.Config.ForceMapChangeAfterNotifications
    end
    Shine.Timer.Create(CHECK_FOR_MOD_CHANGE_TIMER_ID, self.Config.CheckIntervalInSeconds, math.huge, function() self:CheckForModChange() end )
    return true
end

function Plugin:Cleanup()
    --Cleanup your extra stuff like timers, data etc..
    self.BaseClass.Cleanup( self )
end

Shine:RegisterExtension("workshopupdatehandler", Plugin )