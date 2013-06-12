--[[
	Shine debug library.
]]

local DebugGetUpValue = debug.getupvalue

function Shine.GetUpValue( Func, Name )
	local i = 1
	while true do
		local N, Val = DebugGetUpValue( Func, i )
		if not N then break end

		if N == Name then
			return Val
		end
		i = i + 1
	end

	return nil
end
