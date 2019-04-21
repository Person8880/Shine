--[[
	Many to many property binding.
]]

local BindingUtil = require "shine/lib/gui/binding/util"

local InvokeTarget = BindingUtil.InvokeTarget
local TableRemoveByValue = table.RemoveByValue

local MultiPropertyBinding = Shine.TypeDef()

function MultiPropertyBinding:Init()
	self.Sources = {}
	self.Targets = {}
	return self
end

function MultiPropertyBinding:WithInitialState( InitialState )
	self.InitialState = InitialState
	return self
end

function MultiPropertyBinding:ReducedWith( Reducer )
	self.Reducer = Reducer
	return self
end

function MultiPropertyBinding:AddSource( Source )
	Source:AddListener( self )
	self.Sources[ #self.Sources + 1 ] = Source
	return self
end

function MultiPropertyBinding:RemoveSource( Source )
	if not TableRemoveByValue( self.Sources, Source ) then return end
	Source:RemoveListener( self )
	return self
end

function MultiPropertyBinding:From( Sources )
	for i = 1, #Sources do
		self:AddSource( Sources[ i ] )
	end
	return self
end

function MultiPropertyBinding:AddTarget( Target )
	self.Targets[ #self.Targets + 1 ] = BindingUtil.ValidateTarget( Target )
	return self
end

function MultiPropertyBinding:RemoveTarget( Target )
	return TableRemoveByValue( self.Targets, Target )
end

function MultiPropertyBinding:To( Targets )
	for i = 1, #Targets do
		self:AddTarget( Targets[ i ] )
	end
	return self
end

function MultiPropertyBinding:Refresh()
	local State = self.InitialState
	local Reducer = self.Reducer
	for i = 1, #self.Sources do
		State = Reducer( State, self.Sources[ i ]:GetValue() )
	end

	for i = 1, #self.Targets do
		InvokeTarget( self.Targets[ i ], State )
	end
end

function MultiPropertyBinding:__call()
	self:Refresh()
end

function MultiPropertyBinding:Destroy()
	if self.Destroyed then return end

	self.Destroyed = true

	for i = 1, #self.Sources do
		self.Sources[ i ]:RemoveListener( self )
	end
end

return MultiPropertyBinding
