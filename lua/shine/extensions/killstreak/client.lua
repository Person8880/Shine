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
    SoundVolume = 1
}

Plugin.CheckConfig = true
Plugin.SilentConfigSave = true

function Plugin:Initialise()
    self.Enabled = true
    
    Notify(StringFormat( "Shine is set to %s Killstreak Sounds. You can change this with sh_disablesounds", Plugin.Config.PlaySounds and "play" or "mute" ))
  
    return true
end

function Plugin:ReceivePlaySound(Message)
    if not Message.Name then return end
    
    if self.Config.PlaySounds then    
        StartSoundEffect(Plugin.Sounds[Message.Name],self.Config.SoundVolume)
    end
end

Shine:LoadClientBaseConfig()

local DisableSounds = Shine:RegisterClientCommand( "sh_disablesounds", function( Bool )
  Plugin.Config.PlaySounds = Bool

  Notify( StringFormat( "[Shine] Playing Killstreak Sounds has been %s.", Bool and "enabled" or "disabled") )

  Plugin:SaveConfig() 
end)
DisableSounds:AddParam{ Type = "boolean", Optional = true, Default = function() return not Plugin.Config.PlaySounds end }

function Plugin:Cleanup()
    self.Enabled = false
end    
    