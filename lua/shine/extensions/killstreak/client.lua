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
    PlaySounds = true
}

Plugin.CheckConfig = true
Plugin.SilentConfigSave = true

function Plugin:Initialise()
    self.Enabled = true
    
    Notify(StringFormat( "Shine is set to %s Shine Sounds. You can change this with sh_disablesounds", Plugin.Config.PlaySounds and "play" or "mute" ))
  
    return true
end

function Plugin:ReceivePlaySound(Message)
    if not Message.Name then return end
    
    if self.Config.PlaySounds then    
        StartSoundEffect(Plugin.Sounds[Message.Name])
    end
end

Shine:LoadClientBaseConfig()

local DisableSounds = Shine:RegisterClientCommand( "sh_disablesounds", function( Bool )
  self.Config.PlaySounds = Bool

  Notify( StringFormat( "[Shine] Playing Shine Sounds has been %s.", Bool and "disabled" or "enabled" ) )

  self:SaveConfig() 
end)

function Plugin:Cleanup()
    self.Enabled = false
end    
    