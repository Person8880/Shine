--[[
	Deals with clicking.
]]

local SGUI = Shine.GUI
local Clock = SGUI.GetTime

local Clickable = {}

local function GetClickMethod( self, Key )
	return Key == InputKey.MouseButton0 and self.DoClick or self.DoRightClick
end

function Clickable:SetDoClick( Func )
	self.DoClick = Func
end

function Clickable:SetDoRightClick( Func )
	self.DoRightClick = Func
end

function Clickable:OnMouseDown( Key, DoubleClick )
	if Key ~= InputKey.MouseButton0 and Key ~= InputKey.MouseButton1 then return end
	if not self:GetIsVisible() or not self:MouseInControl() then return end
	if not GetClickMethod( self, Key ) then return end

	self.__LastMouseDownFrameNumber = SGUI.FrameNumber()

	return true, self
end

function Clickable:GetLastMouseDownFrameNumber()
	return self.__LastMouseDownFrameNumber
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
	if not self:MouseInControl() then return end

	local Time = Clock()
	local ClickDelay = self.ClickDelay or 0.1
	if ClickDelay > 0 and ( self.NextClick or 0 ) > Time then return true end

	self.NextClick = Time + ClickDelay

	return CallClickMethod( self, GetClickMethod( self, Key ) )
end

Shine.GUI:RegisterMixin( "Clickable", Clickable )
