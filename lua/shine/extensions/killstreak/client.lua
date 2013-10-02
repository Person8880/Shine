--[[
Shine Killstreak Plugin - Client
]]

local Shine = Shine
local Notify = Shared.Message
local StringFormat = string.format

local Plugin = Plugin

Plugin.Version = "1.0"

function Plugin:Initialise()
    self.Enabled = true     
    return true
end

function Plugin:ReceivePlaySound(Message)
    if not Message.Name then return end
    if Plugin.Sounds[Message.Name] then Notify(Message.Name .. " played ") end
    
    -- Need Client Option
    --if Shine.Config.PlayShineSounds then    
    StartSoundEffect(Plugin.Sounds[Message.Name])
    --end
end

Shine:LoadClientBaseConfig()

local DisableSounds = Shine:RegisterClientCommand( "sh_disablesounds", function( Bool )
  Shine.Config.PlayShineSounds = Bool

  Notify( StringFormat( "[Shine] Playing Shine Sounds has been %s.", Bool and "disabled" or "enabled" ) )

  Shine:SaveClientBaseConfig() 
end)

function Plugin:Cleanup()
    self.Enabled = false
end    
    