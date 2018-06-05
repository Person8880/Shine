--[[
	Provides rate limiting functionality.
]]

local RateLimiter = Shine.TypeDef()
Shine.RateLimiter = RateLimiter

-- Provides exponentially growing backoff every time the limit is hit.
RateLimiter.ExponentialBackoff = function( Interval ) return Interval * 2 end

-- Generates a backoff function that increases the interval by the given value
-- every time the limit is hit.
RateLimiter.LinearBackoff = function( IntervalGrowthRate )
	return function( Interval )
		return Interval + IntervalGrowthRate
	end
end

-- Provides no backoff at all (the default).
RateLimiter.NullBackoff = function( Interval ) return Interval end

function RateLimiter:Init( MaxPerInterval, Interval, Clock, BackoffFunc )
	self.MaxPerInterval = MaxPerInterval
	self.DefaultInterval = Interval
	self.Clock = Clock
	self.BackoffFunc = BackoffFunc or RateLimiter.NullBackoff

	self.CurrentInterval = Interval
	self.Value = MaxPerInterval
	self.NextReset = Clock() + Interval

	return self
end

function RateLimiter:GetRemainingAmount()
	return self.Value
end

-- Consumes the given amount from the limiter. If the amount exceeds the remaining
-- allocation, the method will return false. Otherwise the value is updated and backoff
-- is applied when reaching 0 allocation.
function RateLimiter:Consume( Amount )
	local Time = self.Clock()
	if Time >= self.NextReset then
		local IntervalsPassed = ( Time - self.NextReset ) / self.CurrentInterval
		if self.Value == self.MaxPerInterval or IntervalsPassed >= 1 then
			-- If the limiter wasn't hit at all last interval, reset back to
			-- normal, removing any backoff.
			self.CurrentInterval = self.DefaultInterval
		end

		self.Value = self.MaxPerInterval
		self.NextReset = Time + self.CurrentInterval

		self:OnReset()
	end

	local NewValue = self.Value - Amount
	if NewValue < 0 then
		return false
	end

	self.Value = NewValue

	if NewValue == 0 then
		-- The entire allocation for this interval was used, so apply
		-- any backoff to the interval.
		self.CurrentInterval = self.BackoffFunc( self.CurrentInterval )
	end

	return true
end

function RateLimiter:OnReset()

end
