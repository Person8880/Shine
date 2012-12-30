--[[
	Shine MotD system.
]]

local Plugin = {}

function Plugin:Initialise()
	self.Enabled = true
	return true
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "motd", Plugin )
