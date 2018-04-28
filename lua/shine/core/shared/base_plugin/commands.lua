--[[
	Commands module.
]]

local Shine = Shine

local rawget = rawget

local CommandsModule = {}

if Server then
	--[[
		Bind a command to the plugin.
		If you call the base class Cleanup, the command will be removed on plugin unload.
	]]
	function CommandsModule:BindCommand( ConCommand, ChatCommand, Func, NoPerm, Silent )
		self.Commands = rawget( self, "Commands" ) or {}

		local Command  = Shine:RegisterCommand( ConCommand, ChatCommand, Func, NoPerm, Silent )
		self.Commands[ ConCommand ] = Command

		return Command
	end

	function CommandsModule:BindCommandAlias( ConCommand, Alias )
		self.Commands = rawget( self, "Commands" ) or {}

		local Command = Shine:RegisterCommandAlias( ConCommand, Alias )
		self.Commands[ Alias ] = Command

		return Command
	end

	function CommandsModule:Cleanup()
		if rawget( self, "Commands" ) then
			for Key, Command in pairs( self.Commands ) do
				Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
				self.Commands[ Key ] = nil
			end
		end
	end
else
	function CommandsModule:BindCommand( ConCommand, Func )
		self.Commands = rawget( self, "Commands" ) or {}

		local Command = Shine:RegisterClientCommand( ConCommand, Func )
		self.Commands[ ConCommand ] = Command

		return Command
	end

	function CommandsModule:Cleanup()
		if rawget( self, "Commands" ) then
			for Key, Command in pairs( self.Commands ) do
				Shine:RemoveClientCommand( Command.ConCmd, Command.ChatCmd )
				self.Commands[ Key ] = nil
			end
		end
	end
end

function CommandsModule:Suspend()
	if rawget( self, "Commands" ) then
		for Key, Command in pairs( self.Commands ) do
			Command.Disabled = true
		end
	end
end

function CommandsModule:Resume()
	if rawget( self, "Commands" ) then
		for Key, Command in pairs( self.Commands ) do
			Command.Disabled = nil
		end
	end
end

Shine.BasePlugin:AddModule( CommandsModule )
