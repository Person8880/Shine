--[[
	Shine timer library.
]]

local Shine = Shine

local SharedTime = Shared.GetTime
local Timers = Shine.UnorderedMap()
local PausedTimers = {}

local Timer = {}
Shine.Timer = Timer

local TimerMeta = {}
TimerMeta.__index = TimerMeta

function TimerMeta:Destroy()
	Timers:Remove( self.Name )
	PausedTimers[ self.Name ] = nil
end

function TimerMeta:GetReps()
	return self.Reps
end

function TimerMeta:GetLastRun()
	return self.LastRun
end

function TimerMeta:GetNextRun()
	return self.NextRun
end

function TimerMeta:GetTimeUntilNextRun()
	return self.NextRun - SharedTime()
end

function TimerMeta:SetReps( Reps )
	self.Reps = Reps
end

function TimerMeta:SetDelay( Delay )
	self.Delay = Delay
end

function TimerMeta:SetFunction( Func )
	self.Func = Func
end

function TimerMeta:Debounce()
	self.NextRun = SharedTime() + self.Delay
end

function TimerMeta:Pause()
	if self.Paused then return end

	self.Paused = true
	self.TimeLeft = self:GetTimeUntilNextRun()

	PausedTimers[ self.Name ] = self
	Timers:Remove( self.Name )
end

function TimerMeta:Resume()
	if not self.Paused then return end

	PausedTimers[ self.Name ] = nil
	Timers:Add( self.Name, self )

	self.Paused = nil
	self.NextRun = SharedTime() + self.TimeLeft
	self.TimeLeft = nil
end

do
	local setmetatable = setmetatable

	--[[
		Creates a timer.
		Inputs: Name, delay in seconds, number of times to repeat, function to run, optional data to attach.
		Pass a negative number to reps to have it repeat indefinitely.
	]]
	local function Create( Name, Delay, Reps, Func, Data )
		-- Edit it so it's not destroyed if it's created again inside its old function.
		local TimerObject = Timers:Get( Name ) or PausedTimers[ Name ]
		if not TimerObject then
			TimerObject = setmetatable( {}, TimerMeta )
			Timers:Add( Name, TimerObject )
		end

		TimerObject.Name = Name
		TimerObject.Delay = Delay
		TimerObject.Reps = Reps
		TimerObject.Func = Func
		TimerObject.LastRun = 0
		TimerObject.NextRun = SharedTime() + Delay
		TimerObject.Data = Data

		return TimerObject
	end
	Timer.Create = Create

	local SimpleCount = 1

	--[[
		Creates a simple timer.
		Inputs: Delay in seconds, function to run, optional data to attach.
		Unlike a standard timer, this will only run once.
	]]
	function Timer.Simple( Delay, Func, Data )
		local Index = "Simple"..SimpleCount
		SimpleCount = SimpleCount + 1

		return Create( Index, Delay, 1, Func, Data )
	end
end

--[[
	Removes a timer.
	Input: Timer name to remove.
]]
function Timer.Destroy( Name )
	Timers:Remove( Name )
	PausedTimers[ Name ] = nil
end

do
	--[[
		Returns whether the given timer exists.
		Input: Timer name to check.
	]]
	local function Exists( Name )
		return Timers:Get( Name ) ~= nil or PausedTimers[ Name ] ~= nil
	end
	Timer.Exists = Exists

	function Timer.Pause( Name )
		local Instance = Timers:Get( Name )
		if not Instance then return end

		Instance:Pause()
	end

	function Timer.Resume( Name )
		local Instance = PausedTimers[ Name ]
		if not Instance then return end

		Instance:Resume()
	end
end

local OnError = Shine.BuildErrorHandler( "Timer error" )

local StringFormat = string.format
local xpcall = xpcall

--[[
	Checks and executes timers on server update.
]]
Shine.Hook.Add( "Think", "Timers", function( DeltaTime )
	local Time = SharedTime()

	for Name, Timer in Timers:Iterate() do
		if Timer.NextRun <= Time then
			if Timer.Reps > 0 then
				Timer.Reps = Timer.Reps - 1
			end

			local Success = xpcall( Timer.Func, OnError, Timer )
			if not Success or Timer.Reps == 0 then
				Timer:Destroy()
			else
				Timer.LastRun = Time
				Timer.NextRun = Time + Timer.Delay
			end
		end
	end
end )
