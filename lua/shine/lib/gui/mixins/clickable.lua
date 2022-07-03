--[[
	Deals with clicking.
]]

local Clock = os.clock

local Clickable = {}

local function GetClickMethod( self, Key )
	return Key == InputKey.MouseButton0 and self.DoClick or self.DoRightClick
end

function Clickable:OnMouseDown( Key, DoubleClick )
	if Key ~= InputKey.MouseButton0 and Key ~= InputKey.MouseButton1 then return end
	if not self:GetIsVisible() or not self:HasMouseEntered() then return end
	if not GetClickMethod( self, Key ) then return end

	return true, self
end

local function CallClickMethod( self, Method )
	if not Method then return end

	local Sound = self.Sound
	if Method( self ) ~= false and Sound then
		Shared.PlaySound( nil, Sound )
	end

	return true
end

function Clickable:OnMouseUp( Key )
	if not self:HasMouseEntered() then return end

	local Time = Clock()
	if ( self.ClickDelay or 0.1 ) > 0 and ( self.NextClick or 0 ) > Time then return true end

	self.NextClick = Time + ( self.ClickDelay or 0.1 )

	return CallClickMethod( self, GetClickMethod( self, Key ) )
end

Shine.GUI:RegisterMixin( "Clickable", Clickable )
