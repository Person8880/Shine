local lastKnownUpdate = {}
local changedModName
local whenToNextCheck = 0
local whenToNextNotify = 0

local function notifyOrCycle()
	if #Shine.GetAllPlayers() == 0 then
		MapCycle_CycleMap()
	else
		Shine:Notify( nil, "All", Shine.Config.ChatName, string.format("%s mod has updated in Steam Workshop.", changedModName) )
		Shine:Notify( nil, "All", Shine.Config.ChatName, string.format("Players cannot connect to the server until mapchange.", changedModName) )
	end
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

local function getUpdateFromResponse(response)
	local result = findCharactersBetween(response, "Update:", "</div>")
	return result
end

local function getModNameFromResponse(response)
	local result = findCharactersBetween(response, "<div class=\"workshopItemTitle\">", "</div>")
	return result
end

local function checkForModChange()
    for i = 1, Server.GetNumActiveMods() do
    	local id = tonumber(Server.GetActiveModId(i), 16)
		local url = "http://steamcommunity.com/sharedfiles/filedetails/changelog/" .. id
		Shared.SendHTTPRequest(url, "GET", function(response)
			if not changedModName then
				local update = getUpdateFromResponse(response)
				if lastKnownUpdate[id] == nil then
					lastKnownUpdate[id] = update
				elseif lastKnownUpdate[id] ~= update then
					lastKnownUpdate[id] = update
					local modName = getModNameFromResponse(response)
					if modName and modName ~= "" then
						changedModName = modName
					end
				end
			end
		end)
    end
end

local Plugin = {}

Plugin.HasConfig = true
Plugin.ConfigName = "WorkshopUpdateHandler.json"

Plugin.DefaultConfig = {
	CheckIntervalInSeconds = 60,
	RepeatNotifications = true,
	NotifyIntervalInSeconds = 180
}

function Plugin:Think()
	local now = Shared.GetTime()
	if changedModName then
		if now > whenToNextNotify then
			notifyOrCycle()
			if self.Config.RepeatNotifications then
				whenToNextNotify = Shared.GetTime() + self.Config.NotifyIntervalInSeconds
			else
				whenToNextNotify = math.huge
			end
		end
	else
		if now > whenToNextCheck  then
    		checkForModChange()
			whenToNextCheck = Shared.GetTime() + self.Config.CheckIntervalInSeconds
		end
	end
end

function Plugin:Initialise()
    self.Enabled = true
    return true
end

function Plugin:Cleanup()
    --Cleanup your extra stuff like timers, data etc..
    self.BaseClass.Cleanup( self )
end

Shine:RegisterExtension("workshopupdatehandler", Plugin )