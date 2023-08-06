--[[
	Admin menu module.
]]

if Server or Predict then return end

local Shine = Shine

local pairs = pairs
local rawget = rawget

local AdminMenuModule = {}

function AdminMenuModule:AddAdminMenuCommand( Category, Name, Command, MultiSelect, DoClick, Tooltip )
	self.AdminMenuCommands = rawget( self, "AdminMenuCommands" ) or Shine.Multimap()
	self.AdminMenuCommands:Add( Category, Command )

	Shine.AdminMenu:AddCommand( Category, Name, Command, MultiSelect, DoClick, Tooltip )
end

function AdminMenuModule:AddAdminMenuTab( Name, Data )
	self.AdminMenuTabs = rawget( self, "AdminMenuTabs" ) or {}
	self.AdminMenuTabs[ Name ] = true

	Shine.AdminMenu:AddTab( Name, Data )
end

function AdminMenuModule:Cleanup()
	if rawget( self, "AdminMenuCommands" ) then
		for Category, Commands in self.AdminMenuCommands:Iterate() do
			for i = 1, #Commands do
				Shine.AdminMenu:RemoveCommand( Category, Commands[ i ] )
			end
		end
		self.AdminMenuCommands = nil
	end

	if rawget( self, "AdminMenuTabs" ) then
		for Tab in pairs( self.AdminMenuTabs ) do
			Shine.AdminMenu:RemoveTab( Tab )
		end
		self.AdminMenuTabs = nil
	end
end

Shine.BasePlugin:AddModule( AdminMenuModule )
