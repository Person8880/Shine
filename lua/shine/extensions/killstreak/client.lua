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

-- create PlayShineSound value if it doesn't exist
if Shine.Config.PlayShineSounds == nil then
    Shine.Config.PlayShineSounds = true
    Shine:SaveClientBaseConfig()
end 

--Startup Message
Shine.AddStartupMessage(StringFormat( "Shine is set to %s Shine Sounds. You can change this with sh_disablesounds", Shine.Config.PlayShineSounds and "play" or "mute" )) 

function Plugin:ReceivePlaySound(Message)
    if not Message.Name then return end
    if Shine.Config.PlayShineSounds then
        StartSoundEffect(Message.Name)
    end
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
    