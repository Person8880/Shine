--[[
	Timer module.
]]

if Predict then return end

local pairs = pairs
local rawget = rawget
local setmetatable = setmetatable
local StringFormat = string.format

local TimerModule = {}

--[[
	Creates a timer and adds it to the list of timers associated to the plugin.
	These timers are removed when the plugin unloads in the base Cleanup method.

	Inputs: Same as Shine.Timer.Create.
]]
function TimerModule:CreateTimer( Name, Delay, Reps, Func, Data )
	Shine.TypeCheck( Delay, "number", 2, "CreateTimer" )
	Shine.TypeCheck( Reps, "number", 3, "CreateTimer" )
	Shine.TypeCheck( Func, "function", 4, "CreateTimer" )

	self.Timers = rawget( self, "Timers" ) or setmetatable( {}, { __mode = "v" } )

	local RealName = StringFormat( "%s_%s", self.__Name, Name )
	local Timer = Shine.Timer.Create( RealName, Delay, Reps, Func, Data )

	self.Timers[ Name ] = Timer

	return Timer
end

--[[
	Creates a simple timer and adds it to the list of timers associated to the plugin.
	Inputs: Same as Shine.Timer.Simple.
]]
function TimerModule:SimpleTimer( Delay, Func, Data )
	Shine.TypeCheck( Delay, "number", 1, "SimpleTimer" )
	Shine.TypeCheck( Func, "function", 2, "SimpleTimer" )

	self.Timers = rawget( self, "Timers" ) or setmetatable( {}, { __mode = "v" } )

	local Timer = Shine.Timer.Simple( Delay, Func, Data )

	self.Timers[ Timer.Name ] = Timer

	return Timer
end

function TimerModule:GetTimer( Name )
	if not rawget( self, "Timers" ) or not self.Timers[ Name ] then return nil end

	return self.Timers[ Name ]
end

function TimerModule:GetTimers()
	return rawget( self, "Timers" )
end

function TimerModule:TimerExists( Name )
	return Shine.Timer.Exists( StringFormat( "%s_%s", self.__Name, Name ) )
end

function TimerModule:PauseTimer( Name )
	if not rawget( self, "Timers" ) or not self.Timers[ Name ] then return end

	self.Timers[ Name ]:Pause()
end

function TimerModule:ResumeTimer( Name )
	if not rawget( self, "Timers" ) or not self.Timers[ Name ] then return end

	self.Timers[ Name ]:Resume()
end

function TimerModule:DestroyTimer( Name )
	if not rawget( self, "Timers" ) or not self.Timers[ Name ] then return end

	self.Timers[ Name ]:Destroy()

	self.Timers[ Name ] = nil
end

function TimerModule:DestroyAllTimers()
	if rawget( self, "Timers" ) then
		for Name, Timer in pairs( self.Timers ) do
			Timer:Destroy()
			self.Timers[ Name ] = nil
		end
	end
end

function TimerModule:Cleanup()
	self:DestroyAllTimers()
end

function TimerModule:Suspend()
	if rawget( self, "Timers" ) then
		for Name, Timer in pairs( self.Timers ) do
			Timer:Pause()
		end
	end
end

function TimerModule:Resume()
	if rawget( self, "Timers" ) then
		for Name, Timer in pairs( self.Timers ) do
			Timer:Resume()
		end
	end
end

Shine.BasePlugin:AddModule( TimerModule )
