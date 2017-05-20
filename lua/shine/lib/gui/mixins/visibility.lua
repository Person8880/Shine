--[[
	Deals with visibility.
]]

local Visibility = {}

function Visibility:Init()
	self.VisibilityStack = self.VisibilityStack or {}
end

local function GetVisibilityStackSize( self )
	return self.VisibilityStack and #self.VisibilityStack or 0
end

--[[
	Pushes a temporary visibility state to the element.
]]
function Visibility:PushVisible( Visible )
	self:Init()

	local CurrentVisibility = self:GetIsVisible()
	self.VisibilityStack[ #self.VisibilityStack + 1 ] = CurrentVisibility

	self:SetIsVisible( Visible, true )
end

--[[
	Pops a temporary visibility state, if one has been pushed.
]]
function Visibility:PopVisible()
	if GetVisibilityStackSize( self ) == 0 then return end

	local PreviousVisibility = self.VisibilityStack[ #self.VisibilityStack ]
	self.VisibilityStack[ #self.VisibilityStack ] = nil
	self:SetIsVisible( PreviousVisibility, true )
end

--[[
	Binds visibility to hide when "HideEvent" is called, and to show again when
	"ShowEvent" is called.
]]
function Visibility:BindVisibilityToEvents( HideEvent, ShowEvent )
	Shine.Hook.Add( HideEvent, self, function()
		self:PushVisible( false )
	end )
	Shine.Hook.Add( ShowEvent, self, function()
		self:PopVisible()
	end )
end

function Visibility:ClearVisibility()
	self.VisibilityStack = {}
end

--[[
	Resets all visibility state and hides the element.
]]
function Visibility:ForceHide()
	self:ClearVisibility()
	return self:Hide()
end

--[[
	Attempts to make the element visible.
	If the element has been affected by a pushed state, this will do nothing.

	Returns true if the visibility state changed, false otherwise.
]]
function Visibility:Show()
	if GetVisibilityStackSize( self ) > 0 then return false end

	return self:SetIsVisible( true )
end

--[[
	Attempts to make the element invisible.
	If the element has been affected by a pushed state, this will do nothing.

	Returns true if the visibility state changed, false otherwise.
]]
function Visibility:Hide()
	if GetVisibilityStackSize( self ) > 0 then return false end

	return self:SetIsVisible( false )
end

Shine.GUI:RegisterMixin( "Visibility", Visibility )
