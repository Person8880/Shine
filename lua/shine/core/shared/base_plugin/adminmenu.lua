--[[
	Admin menu module.
]]

if Server then return end

local Shine = Shine

local pairs = pairs
local rawget = rawget

local AdminMenuModule = {}

function AdminMenuModule:AddAdminMenuCommand( Category, Name, Command, MultiSelect, DoClick, Tooltip )
	self.AdminMenuCommands = rawget( self, "AdminMenuCommands" ) or {}
	self.AdminMenuCommands[ Category ] = true

	Shine.AdminMenu:AddCommand( Category, Name, Command, MultiSelect, DoClick, Tooltip )
end

function AdminMenuModule:AddAdminMenuTab( Name, Data )
	self.AdminMenuTabs = rawget( self, "AdminMenuTabs" ) or {}
	self.AdminMenuTabs[ Name ] = true

	Shine.AdminMenu:AddTab( Name, Data )
end

function AdminMenuModule:Cleanup()
	if rawget( self, "AdminMenuCommands" ) then
		for Category in pairs( self.AdminMenuCommands ) do
			Shine.AdminMenu:RemoveCommandCategory( Category )
		end
	end

	if rawget( self, "AdminMenuTabs" ) then
		for Tab in pairs( self.AdminMenuTabs ) do
			Shine.AdminMenu:RemoveTab( Tab )
		end
	end
end

Shine.BasePlugin:AddModule( AdminMenuModule )
