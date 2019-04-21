--[[
	Utility functions for bindings.
]]

local BindingUtil = {}

local function NoOpTransform( Value ) return Value end
local function AlwaysPassThrough() return true end

function BindingUtil.ValidateTarget( Target )
	Shine.AssertAtLevel( Shine.IsCallable( Target.Sink ), "Sink must be callable!", 4 )

	if Target.Transformer then
		Shine.AssertAtLevel( Shine.IsCallable( Target.Transformer ), "Transformer must be callable!", 4 )
	else
		Target.Transformer = NoOpTransform
	end

	if Target.Filter then
		Shine.AssertAtLevel( Shine.IsCallable( Target.Filter ), "Filter must be callable!", 4 )
	else
		Target.Filter = AlwaysPassThrough
	end

	return Target
end

function BindingUtil.InvokeTarget( Target, Value )
	if Target.Filter( Value ) then
		Target.Sink( Target.Transformer( Value ) )
	end
end

return BindingUtil
