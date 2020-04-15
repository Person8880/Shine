
local Base = {}

function Base:GetLines()
	return nil
end

function Base:IsVisibleElement()
	return false
end

local function ThinkWithExtra( self, DeltaTime )
	self:__ExtraThink( DeltaTime )
	return self:__OldThink( DeltaTime )
end

function Base.AddThinkFunction( Element, ExtraThink )
	-- Remove any old override (so Think comes from the metatable).
	Element.Think = nil
	Element.__ExtraThink = nil
	Element.__OldThink = nil

	if not ExtraThink then return end

	Element.__OldThink = Element.Think
	Element.__ExtraThink = ExtraThink
	Element.Think = ThinkWithExtra
end

function Base:Setup( Element )
	-- To be overridden.
end

function Base:Copy()
	error( "Copy() method has not been implemented" )
end

return Base
