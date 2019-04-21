--[[
	One to many property binding.
]]

local BindingUtil = require "shine/lib/gui/binding/util"

local InvokeTarget = BindingUtil.InvokeTarget
local TableRemoveByValue = table.RemoveByValue

local PropertyBinding = Shine.TypeDef()

function PropertyBinding:Init()
	self.AutoDestroy = true
	self.Targets = {}
	return self
end

--[[
	Sets whether to destroy the binding when all targets are removed.
	By default this is enabled, assuming that the binding's targets are static
	and will never be added to after initial setup.
]]
function PropertyBinding:SetAutoDestroy( AutoDestroy )
	self.AutoDestroy = AutoDestroy
	return self
end

function PropertyBinding:From( Source )
	Source:AddListener( self )
	self.Source = Source
	return self
end

function PropertyBinding:To( Targets )
	for i = 1, #Targets do
		self.Targets[ #self.Targets + 1 ] = BindingUtil.ValidateTarget( Targets[ i ] )
	end
	return self
end

function PropertyBinding:RemoveTarget( Target )
	local Removed = TableRemoveByValue( self.Targets, Target )
	if not Removed then return Removed end

	if #self.Targets == 0 and self.AutoDestroy then
		self:Destroy()
	end

	return Removed
end

function PropertyBinding:Refresh()
	if not self.Source then return end

	self( self.Source, self.Source:GetValue() )
end

function PropertyBinding:__call( Source, Value )
	for i = 1, #self.Targets do
		InvokeTarget( self.Targets[ i ], Value )
	end
end

function PropertyBinding:Destroy()
	if self.Destroyed then return end

	self.Destroyed = true
	self.Source:RemoveListener( self )
end

return PropertyBinding
