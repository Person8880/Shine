--[[
    Shine ModUpdateChecker
]]

local lastKnownUpdate = {}
local changedModName
local announceChangedModInterval = 10

local Plugin = {}
Plugin.Version = 1.0
Plugin.HasConfig = true
Plugin.ConfigName = "modupdatechecker.json"

Plugin.DefaultConfig= {
    MOD_IDS = {"171315805", "117887554"},
    CheckInterval = 60,
    ChangeMapatUpdate = false,
    MapChangeTime = 5,
    RepeatUpdateMessage = false,
    RepeatTime = 30,
    UpdateMessage = {"%s mod has updated in Steam Workshop.", "Players cannot connect to the server until mapchange.")   
}
Plugin.CheckConfig = true

--checkupdate functions by lancehilliard

local function announceChangedMod()
	if Sever.GetNumPlayers() == 0 then
		MapCycle_CycleMap()
	else
		self:Notify(nil,string.format(self.Config.UpdateMessage , changedModName))
		
		if self.Config.RepeatUpdateMessage then
		    Sine.Timer.Create("ModUpdateInform",self.Config.RepeatTime, -1, function() self:Notify(nil,string.format(self.Config.UpdateMessage , changedModName)) end)
		end
		
		if self.Config.ChangeMapatUpdate then
		    Shine.Timer.Simple(self.Config.MapChangeTime * 60, function() MapCycle_CycleMap() end)
		end
		
	end
end

local function getUpdateFromResponse(response)
	local result = nil
	local indexOfUpdatedLabel = response:find("Update: ") 
	if indexOfUpdatedLabel then
		local update = TGNS.Substring(response, indexOfUpdatedLabel)
		local indexOfUpdateEnder = update:find("</div>")
		if indexOfUpdateEnderthen
			update = update:sub(1, indexOfUpdateEnder - 1)
			update = StringTrim(update)
			result = update
		end
	end
	return result
end

local function getModNameFromResponse(response)
	local result = nil
	local openingTag = "<div class=\"workshopItemTitle\">"
	local closingTag = "</div>"
	local indexOfOpeningTag = response:find(openingTag)
	if indexOfOpeningTag then
		local modName = response:sub(indexOfOpeningTag + string.len(openingTag))
		local indexOfClosingTag = modName:find(closingTag)
		if indexOfClosingTag then
			modName = modName:sub(1, indexOfClosingTag - 1)
			modName = StringTrim(modName)
			result = modName
		end
	end
	return result
end

local function checkForModChange()
	if not changedModName then
		for i=1,#self.Config.MOD_IDS do
			local url = "http://steamcommunity.com/sharedfiles/filedetails/changelog/" .. self.Config.MOD_IDS[i]
			 Shared.SendHTTPRequest(url, function(response)
				if not changedModName then
					local update = getUpdateFromResponse(response)
					if lastKnownUpdate[id] == nil then
						lastKnownUpdate[id] = update
					elseif lastKnownUpdate[id] ~= update then
						lastKnownUpdate[id] = update
						changedModName = getModNameFromResponse(response)
						announceChangedMod()
					end
				end
			end)
	    end
	end
end

function Plugin:Initialise()
    self.Enabled = true
	Shine.Timer.Create("CheckForModUpdate", self.CheckInterval,-1, self.checkForModChange() )
    return true
end

function Plugin:Notify( Player, Message, Format, ... )
   for i = 1, #Message do
        Shine:NotifyDualColour( Player, 100, 255, 100, "[ModUpdateChecker]", 255, 255, 255,Message[i], Format, ... )  
   end    
end

function Plugin:Cleanup()    
    self.Enabled = false
    Shine.Timer.Destroy("CheckForModUpdate")
    Shine.Timer.Destroy("ModUpdateInform")   
end

Shine:RegisterExtension("modupdatechecker", Plugin )