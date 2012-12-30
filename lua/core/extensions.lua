--[[
	Shine extension system.
]]

local include = Script.Load
local Encode, Decode = json.encode, json.decode

Shine.Plugins = {}

function Shine:RegisterExtension( Name, Table )
	self.Plugins[ Name ] = Table
end

function Shine:LoadExtension( Name )
	if self.Plugins[ Name ].Enabled then
		self:UnloadExtension( Name )
	end

	local Success, Err = pcall( include, "lua/extensions/"..Name..".lua" )

	if not Success then
		return false, "plugin does not exist."
	end

	if not self.Plugins[ Name ] then
		return false, "plugin did not register itself."
	end

	if self.Plugins[ Name ].HasConfig then
		self.Plugins[ Name ]:LoadConfig()
	end

	return self.Plugins[ Name ]:Initialise()
end

function Shine:UnloadExtension( Name )
	if not self.Plugins[ Name ] then return end

	self.Plugins[ Name ]:Cleanup()

	--self.Plugins[ Name ] = nil
end
