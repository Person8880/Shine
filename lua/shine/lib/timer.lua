--[[
	Shine timer library.
]]

local Shine = Shine

local SharedTime = Shared.GetTime
local Timers = Shine.Map()
local Timer = {}
Shine.Timer = Timer

local TimerMeta = {}
TimerMeta.__index = TimerMeta

function TimerMeta:Destroy()
	Timers:Remove( self.Name )
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
end

function TimerMeta:Resume()
	if not self.Paused then return end

	self.Paused = nil
	self.NextRun = SharedTime() + self.TimeLeft
	self.TimeLeft = nil
end

do
	local setmetatable = setmetatable

	--[[
		Creates a timer.
		Inputs: Name, delay in seconds, number of times to repeat, function to run.
		Pass a negative number to reps to have it repeat indefinitely.
	]]
	local function Create( Name, Delay, Reps, Func )
		-- Edit it so it's not destroyed if it's created again inside its old function.
		local TimerObject = Timers:Get( Name )
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

		return TimerObject
	end
	Timer.Create = Create

	local SimpleCount = 1

	--[[
		Creates a simple timer.
		Inputs: Delay in seconds, function to run.
		Unlike a standard timer, this will only run once.
	]]
	function Timer.Simple( Delay, Func )
		local Index = "Simple"..SimpleCount
		SimpleCount = SimpleCount + 1

		return Create( Index, Delay, 1, Func )
	end
end

--[[
	Removes a timer.
	Input: Timer name to remove.
]]
function Timer.Destroy( Name )
	Timers:Remove( Name )
end

do
	--[[
		Returns whether the given timer exists.
		Input: Timer name to check.
	]]
	local function Exists( Name )
		return Timers:Get( Name ) ~= nil
	end
	Timer.Exists = Exists

	function Timer.Pause( Name )
		if not Exists( Name ) then return end
		Timers:Get( Name ):Pause()
	end

	function Timer.Resume( Name )
		if not Exists( Name ) then return end
		Timers:Get( Name ):Resume()
	end
end

local Error
local StackTrace

local function OnError( Err )
	Error = Err
	StackTrace = Shine.Traceback( 2 )
end

local StringFormat = string.format
local xpcall = xpcall

--[[
	Checks and executes timers on server update.
]]
Shine.Hook.Add( "Think", "Timers", function( DeltaTime )
	local Time = SharedTime()

	for Name, Timer in Timers:Iterate() do
		if Timer.NextRun <= Time and not Timer.Paused then
			if Timer.Reps > 0 then
				Timer.Reps = Timer.Reps - 1
			end

			local Success = xpcall( Timer.Func, OnError, Timer )
			if not Success then
				Shine:DebugPrint( "Timer %s failed: %s.\n%s", true,
					Name, Error, StackTrace )
				Shine:AddErrorReport( StringFormat( "Timer %s failed: %s.",
					Name, Error ), StackTrace )

				Error = nil
				StackTrace = nil

				Timer:Destroy()
			else
				if Timer.Reps == 0 then
					Timer:Destroy()
				else
					Timer.LastRun = Time
					Timer.NextRun = Time + Timer.Delay
				end
			end
		end
	end
end )
