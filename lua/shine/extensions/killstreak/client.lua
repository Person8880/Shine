--[[
Shine Killstreak Plugin - Client
]]

local Shine = Shine
local Notify = Shared.Message
local StringFormat = string.format

local Plugin = Plugin


Plugin.HasConfig = true

Plugin.ConfigName = "Killstreak.json"

Plugin.DefaultConfig = {
    PlaySounds = true,
    SoundVolume = 100
}

Plugin.CheckConfig = true
Plugin.SilentConfigSave = true

function Plugin:Initialise()
    self.Enabled = true
    Notify("==============================")
    Notify("Shine Killstreak Plugin loaded sucessfull!")
    Notify(StringFormat( "- Shine is set to %s killstreak sounds. You can change this with sh_disablesounds", self.Config.PlaySounds and "play" or "mute" ))
    
    if self.Config.SoundVolume < 0 or self.Config.SoundVolume > 200 or self.Config.SoundVolume%1 ~= 0 then
       Notify ("- Warning: The set Sound Volume was outside the limit of 0 to 200")
       self.Config.SoundVolume = 100
    end
     
    if self.Config.PlaySounds then Notify( StringFormat( "- Shine is set to play killstreak sounds with a volume of %s . You can change this with sh_setsoundvolume.",self.Config.SoundVolume)) end
    Notify("==============================")
    return true
end

function Plugin:ReceivePlaySound(Message)
    if not Message.Name then return end
    
    if self.Config.PlaySounds then    
        StartSoundEffect(Plugin.Sounds[Message.Name],self.Config.SoundVolume/100)
    end
end

Shine:LoadClientBaseConfig()

local DisableSounds = Shine:RegisterClientCommand( "sh_disablesounds", function( Bool )
  Plugin.Config.PlaySounds = Bool

  Notify( StringFormat( "[Shine] Playing Killstreak Sounds has been %s.", Bool and "enabled" or "disabled") )

  Plugin:SaveConfig() 
end)
DisableSounds:AddParam{ Type = "boolean", Optional = true, Default = function() return not Plugin.Config.PlaySounds end }

local SetSoundVolume = Shine:RegisterClientCommand("sh_setsoundvolume",function (Volume)
    Plugin.Config.SoundValume = Volume
    
    Plugin:SaveConfig()
    
    Notify( StringFormat( "[Shine] Killstreak Sounds Volume has been set to %s.", Volume) )
end)
SetSoundVolume:AddParam{Type = "number",Min= 0,Max=200, Round= true, Error = "Please set a value between 0 and 200. Any value outside this limit is not allowed"}

function Plugin:Cleanup()
    self.Enabled = false
end    
    