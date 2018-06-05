--[[
	Rate limiter unit tests.
]]

local UnitTest = Shine.UnitTest

local TIME = 0
local function Clock()
	return TIME
end

UnitTest:Before( function()
	TIME = 0
end )

UnitTest:Test( "Consumption is denied when too large", function( Assert )
	local RateLimiter = Shine.RateLimiter( 10, 1, Clock )
	Assert.False( "Consumption should be denied when larger than current value", RateLimiter:Consume( 11 ) )
	Assert.Equals( "Nothing should have been consumed", 10, RateLimiter:GetRemainingAmount() )
end )

UnitTest:Test( "Consumption is permitted when smaller than current value", function( Assert )
	local RateLimiter = Shine.RateLimiter( 10, 1, Clock )
	Assert.True( "Consumption should be permitted when small enough", RateLimiter:Consume( 1 ) )
	Assert.Equals( "Should have consumed 1", 9, RateLimiter:GetRemainingAmount() )
end )

UnitTest:Test( "Backoff is applied when all is consumed", function( Assert )
	local RateLimiter = Shine.RateLimiter( 10, 1, Clock, Shine.RateLimiter.ExponentialBackoff )
	Assert.True( "Consumption should be permitted", RateLimiter:Consume( 10 ) )
	Assert.Equals( "Should have consumed 10", 0, RateLimiter:GetRemainingAmount() )
	Assert.Equals( "Should have doubled the interval", 2, RateLimiter.CurrentInterval )

	TIME = 1
	Assert.True( "Should permit consumption after reset time", RateLimiter:Consume( 1 ) )
	Assert.Equals( "Should have applied doubled interval to next reset time", 3, RateLimiter.NextReset )
	Assert.Equals( "Should have consumed 1", 9, RateLimiter:GetRemainingAmount() )

	-- Jump forward 2 intervals, should consider the previous interval empty.
	TIME = 5
	Assert.True( "Should permit consumption after reset time", RateLimiter:Consume( 1 ) )
	Assert.Equals( "Should have reset interval due to 0 consumption in previous interval", 6, RateLimiter.NextReset )
	Assert.Equals( "Should have consumed 1", 9, RateLimiter:GetRemainingAmount() )
end )
