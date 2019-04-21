--[[
	SGUI layout system.
]]

local SGUI = Shine.GUI

local getmetatable = getmetatable
local rawget = rawget
local setmetatable = setmetatable
local TableInsert = table.insert
local TableRemoveByValue = table.RemoveByValue

local Layout = {}
SGUI.Layout = Layout

local BaseLayout = {}
BaseLayout.__index = BaseLayout

BaseLayout.IsLayout = true

SGUI.AddProperty( BaseLayout, "Parent" )
SGUI.AddProperty( BaseLayout, "Pos" )
SGUI.AddProperty( BaseLayout, "Fill", nil, { "InvalidatesParent" } )
SGUI.AddProperty( BaseLayout, "Size", nil, { "InvalidatesLayout" } )
SGUI.AddProperty( BaseLayout, "AutoSize", nil, { "InvalidatesParent" } )
SGUI.AddProperty( BaseLayout, "Padding", nil, { "InvalidatesLayout" } )
SGUI.AddProperty( BaseLayout, "Margin", nil, { "InvalidatesParent" } )
SGUI.AddProperty( BaseLayout, "Alignment", SGUI.LayoutAlignment.MIN, { "InvalidatesParent" } )
SGUI.AddProperty( BaseLayout, "CrossAxisAlignment", SGUI.LayoutAlignment.MIN, { "InvalidatesParent" } )
SGUI.AddProperty( BaseLayout, "IsVisible", true, { "InvalidatesParent" } )
SGUI.AddProperty( BaseLayout, "Elements" )

function BaseLayout:Init( Data )
	local Spacing = Layout.Units.Spacing

	self.Elements = Data and Data.Elements or {}
	self.LayoutChildren = {}
	self.Pos = Data and Data.Pos or Vector2( 0, 0 )
	self.AutoSize = Data and Data.AutoSize
	self.Size = Data and Data.Size or Vector2( 0, 0 )
	self.Margin = Data and Data.Margin or Spacing( 0, 0, 0, 0 )
	self.Padding = Data and Data.Padding or Spacing( 0, 0, 0, 0 )
	self.Parent = Data and Data.Parent
	self.Anchor = Data and Data.Anchor or SGUI.Anchors.TopLeft
	self.Alignment = Data and Data.Alignment or SGUI.LayoutAlignment.MIN

	if not Data or Data.Fill ~= false then
		self.Fill = true
	end

	for i = 1, #self.Elements do
		local Element = self.Elements[ i ]
		if Element.IsLayout then
			Element:SetParent( self )
			self.LayoutChildren[ #self.LayoutChildren + 1 ] = Element
		end
	end

	return self
end

local function ChildIterator( State )
	State.Index = State.Index + 1
	return State.Elements[ State.Index ]
end

function BaseLayout:IterateChildren()
	return ChildIterator, { Elements = self.Elements, Index = 0 }
end

local function OnAddElement( self, Element )
	if Element.IsLayout then
		Element:SetParent( self )
		self.LayoutChildren[ #self.LayoutChildren + 1 ] = Element
	else
		Element.LayoutParent = self
	end

	self:InvalidateLayout()
end

function BaseLayout:AddElement( Element )
	local Elements = self.Elements
	Elements[ #Elements + 1 ] = Element

	OnAddElement( self, Element )
end

function BaseLayout:InsertElement( Element, Index )
	TableInsert( self.Elements, Index, Element )
	OnAddElement( self, Element )
end

function BaseLayout:InsertElementAfter( Element, AfterElement )
	local Elements = self.Elements
	for i = 1, #Elements do
		if Elements[ i ] == Element then
			TableInsert( Elements, i + 1, AfterElement )
			break
		end
	end

	OnAddElement( self, Element )
end

function BaseLayout:RemoveElement( Element )
	if not TableRemoveByValue( self.Elements, Element ) then return end

	if Element.IsLayout then
		TableRemoveByValue( self.LayoutChildren, Element )
		if Element.Parent == self then
			Element:SetParent( nil )
		end
	elseif Element.LayoutParent == self then
		Element.LayoutParent = nil
	end

	self:InvalidateLayout()
end

-- Layouts inherit some basic functionality from elements.
table.Mixin( SGUI.BaseControl, BaseLayout, {
	"ComputeSpacing",
	"GetContentSizeForAxis",
	"GetMaxSizeAlongAxis",
	"GetComputedPadding",
	"GetComputedMargin",
	"GetComputedSize",
	"GetParentSize",
	"InvalidateParent",
	"InvalidateLayout",
	"HandleLayout",
	"PreComputeWidth",
	"PreComputeHeight",
	"OnPropertyChanged",
	"AddPropertyChangeListener",
	"GetPropertySource",
	"GetPropertyTarget",
	"RemovePropertyChangeListener"
} )

function BaseLayout:Think( DeltaTime )
	self:HandleLayout( DeltaTime )

	-- Layouts must make sure child layouts also think (and thus handle layout invalidations)
	for i = 1, #self.LayoutChildren do
		local Element = self.LayoutChildren[ i ]
		Element:Think( DeltaTime )
	end
end

function BaseLayout:PerformLayout()
	-- When this layout is invalidated, invalidate all of its children too.
	-- This ensures layout changes cascade downwards in a single frame, rather than
	-- some children waiting for the next frame to invalidate and thus causing a slight jitter.
	for i = 1, #self.LayoutChildren do
		self.LayoutChildren[ i ]:InvalidateLayout( true )
	end
end

Layout.Types = {}
Layout.Units = {}

function Layout:RegisterType( Name, MetaTable, Parent )
	MetaTable.__index = MetaTable
	MetaTable.__Base = Parent
	MetaTable.BaseClass = BaseLayout
	self.Types[ Name ] = MetaTable
end

function Layout:RegisterUnit( Name, MetaTable )
	MetaTable.__index = MetaTable

	setmetatable( MetaTable, {
		__call = function( self, ... )
			return setmetatable( {}, self ):Init( ... )
		end
	} )

	self.Units[ Name ] = MetaTable
end

function Layout:CreateLayout( Name, ... )
	local MetaTable = self.Types[ Name ]
	if not MetaTable or rawget( MetaTable, "IsAbstract" ) then return nil end

	return setmetatable( {}, self.Types[ Name ] ):Init( ... )
end

Shine.LoadScriptsByPath( "lua/shine/lib/gui/layout/units" )
Shine.LoadScriptsByPath( "lua/shine/lib/gui/layout/types" )

-- Resolve parent types.
for Name, MetaTable in pairs( Layout.Types ) do
	local Parent = MetaTable.__Base
	local TargetMeta

	if Parent and Layout.Types[ Parent ] then
		TargetMeta = Layout.Types[ Parent ]
	else
		TargetMeta = BaseLayout
	end

	setmetatable( MetaTable, TargetMeta )
end
