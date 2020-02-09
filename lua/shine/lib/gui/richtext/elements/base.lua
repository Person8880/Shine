
local Base = {}

function Base:GetLines()
	return nil
end

function Base:IsVisibleElement()
	return false
end

function Base.AddThinkFunction( Element, ExtraThink )
	-- Remove any old override (so Think comes from the metatable).
	Element.Think = nil

	if not ExtraThink then return end

	local OldThink = Element.Think
	function Element:Think( DeltaTime )
		ExtraThink( self, DeltaTime )
		return OldThink( self, DeltaTime )
	end
end

function Base:Setup( Element )
	-- To be overridden.
end

function Base:Copy()
	error( "Copy() method has not been implemented" )
end

return Base
