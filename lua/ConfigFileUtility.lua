// ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =====
//
// core/ConfigFileUtility.lua
//
// Created by Brian Cronin (brianc@unknownworlds.com)
//
// ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/dkjson.lua")

--[[
	I've moved the injection point to something no mod will ever need to change.

	game_setup.xml files only work for one mod, and the entry point system loads too late to override
	network messages for chat.

	The only issue here is this file is loaded by the main menu. Hence we check to make sure we aren't being
	called by it with the traceback.

	If UWE had a mod loading system that could co-operate properly and didn't load too late like the entry files,
	I wouldn't need to do this rediculous injection hack method.
]]
if not Shine then
	local Trace = debug.traceback()

	if not Trace:find( "Main.lua" ) and not Trace:find( "Loading.lua" ) then
		if Server then
			Script.Load( "lua/shine/init.lua" )
		elseif Client then
			Script.Load( "lua/shine/cl_init.lua" )
		end
	end
end

function WriteDefaultConfigFile(fileName, defaultConfig)

    local configFile = io.open("config://" .. fileName, "r")
    if not configFile then
    
        configFile = io.open("config://" .. fileName, "w+")
        if configFile == nil then
            return
        end
        configFile:write(json.encode(defaultConfig, { indent = true }))
        
    end
    
    io.close(configFile)
    
end

function CheckConfig(config, defaultConfig, dontRemove)
    local updated
    
    --Add new keys.
    local function addkeys(config, defaultConfig)
        for option, value in pairs(defaultConfig) do
            if config[option] == nil then
                config[option] = value
                updated = true
            end
            if type( config[option] ) == "table" then 
                addkeys( config[option] , defaultConfig[option])
            end
        end
    end
    addkeys(config, defaultConfig)
    
    if dontRemove then return updated end

    --Remove old keys.
    local function removekeys(config, defaultConfig)
        for option in pairs(config) do
            -- don't remove number options - they are index in json-lists
            if type(option) ~= "number" and defaultConfig[option] == nil then
                config[option] = nil
                updated = true
            end
            if type( defaultConfig[option] ) == "table" then 
                removekeys( config[option] , defaultConfig[option])
            end
        end
    end
    removekeys(config, defaultConfig)

    return updated
end

function LoadConfigFile( fileName, defaultConfig, check)

    local fname = "config://" .. fileName
        
    Shared.Message("Loading " .. fname)

    local openedFile = GetFileExists(fname) and io.open(fname, "r")
    if openedFile then
    
        local parsedFile, _, errStr = json.decode(openedFile:read("*all"))
        if errStr then
            Shared.Message("Error while opening " .. fileName .. ": " .. errStr)
        end
        io.close(openedFile)
        
        if defaultConfig and check then
            local update = CheckConfig(parsedFile, defaultConfig)
            if update then
                SaveConfigFile(fileName, parsedFile) 
            end
        end
        
        return parsedFile
        
    elseif defaultConfig then
        WriteDefaultConfigFile(fileName, defaultConfig)
        return defaultConfig
    end
    
    return
    
end

function SaveConfigFile(fileName, data)

    Shared.Message("Saving " .. "config://" .. fileName)
    
    local openedFile = io.open("config://" .. fileName, "w+")
    
    if openedFile then
    
        openedFile:write(json.encode(data, { indent = true }))
        io.close(openedFile)
        
    end
    
end