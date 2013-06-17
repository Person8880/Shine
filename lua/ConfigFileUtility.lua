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

    if not Trace:find( "Main.lua" ) then
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

function LoadConfigFile(fileName)

    Shared.Message("Loading " .. "config://" .. fileName)
    
    local openedFile = io.open("config://" .. fileName, "r")
    if openedFile then
    
        local parsedFile, _, errStr = json.decode(openedFile:read("*all"))
        if errStr then
            Shared.Message("Error while opening " .. fileName .. ": " .. errStr)
        end
        io.close(openedFile)
        return parsedFile
        
    end
    
    return nil
    
end

function SaveConfigFile(fileName, data)

    Shared.Message("Saving " .. "config://" .. fileName)
    
    local openedFile = io.open("config://" .. fileName, "w+")
    
    if openedFile then
    
        openedFile:write(json.encode(data, { indent = true }))
        io.close(openedFile)
        
    end
    
end