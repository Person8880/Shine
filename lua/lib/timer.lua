--[[
	Shine timer library.
]]

local StringFormat = string.format
local TableRemove = table.remove

local Timers = {}
local Simples = {}

Shine.Timer = {}

local TimerMeta = {}
TimerMeta.__index = TimerMeta

function TimerMeta:Destroy()
	if self.Name then
		Timers[ self.Name ] = nil
	end
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

function TimerMeta:SetReps( Reps )
	self.Reps = Reps
end

function TimerMeta:SetDelay( Delay )
	self.Delay = Delay
end

function TimerMeta:SetFunction( Func )
	self.Func = Func
end

--[[
	Creates a timer.
	Inputs: Name, delay in seconds, number of times to repeat, function to run.
	Pass a negative number to reps to have it repeat indefinitely.
]]
local function Create( Name, Delay, Reps, Func )
	local Timer = setmetatable( {
		Name = Name,
		Delay = Delay,
		Reps = Reps,
		Func = Func,
		LastRun = 0,
		NextRun = Shared.GetTime() + Delay,
		StackTrace = debug.traceback()
	}, TimerMeta )

	Timers[ Name ] = Timer

	return Timer
end
Shine.Timer.Create = Create

--[[
	Creates a simple timer.
	Inputs: Delay in seconds, function to run.
	Unlike a standard timer, this will only run once.
]]
local function Simple( Delay, Func )
	local Index = #Simples + 1

	local Timer = {
		Index = Index,
		NextRun = Shared.GetTime() + Delay,
		Func = Func,
		StackTrace = debug.traceback()
	}

	Simples[ Index ] = Timer
end
Shine.Timer.Simple = Simple

--[[
	Removes a timer.
	Input: Timer name to remove.
]]
local function Destroy( Name )
	if Timers[ Name ] then
		Timers[ Name ] = nil
	end
end
Shine.Timer.Destroy = Destroy

--[[
	Returns whether the given timer exists.
	Input: Timer name to check.
]]
local function Exists( Name )
	return Timers[ Name ] ~= nil
end
Shine.Timer.Exists = Exists

--[[
	Checks and executes timers on server update.
]]
Shine.Hook.Add( "Think", "Timers", function( DeltaTime )
	local Time = Shared.GetTime()

	--Run the standard timers.
	for Name, Timer in pairs( Timers ) do
		if Timer.NextRun <= Time then
			if Timer.Reps > 0 then
				Timer.Reps = Timer.Reps - 1
			end

			local Success, Err = pcall( Timer.Func )

			if not Success then
				Shared.Message( StringFormat( "Timer %s failed: %s. %s", Name, Err, Timer.StackTrace ) )
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

	local ToRemove = {}

	--Run the simple timers.
	for i = 1, #Simples do
		local Timer = Simples[ i ]
		if Timer.NextRun <= Time then
			local Success, Err = pcall( Timer.Func )

			if not Success then
				Shared.Message( StringFormat( "Simple timer failed: %s. %s", Err, Timer.StackTrace ) )
			end

			ToRemove[ Timer.Index ] = true
		end
	end

	for Index, Remove in pairs( ToRemove ) do
		for i = 1, #Simples do
			local Timer = Simples[ i ]
			if Timer and Timer.Index == Index then
				TableRemove( Simples, i )
				break
			end
		end
	end
end )
