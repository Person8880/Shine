--[[
	SGUI layout system.
]]

local SGUI = Shine.GUI

local assert = assert
local getmetatable = getmetatable
local rawget = rawget
local setmetatable = setmetatable
local StringFormat = string.format
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
	self.CrossAxisAlignment = Data and Data.CrossAxisAlignment or SGUI.LayoutAlignment.MIN

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

-- These are not inherited from the base control as position and size in layouts is just a table field, its not derived
-- from a GUIItem. Note that layouts do not support easing, so these always point at the underlying fields. Use a
-- control if easing is desired.
BaseLayout.SetLayoutPos = BaseLayout.SetPos
BaseLayout.GetLayoutPos = BaseLayout.GetPos
BaseLayout.SetLayoutSize = BaseLayout.SetSize
BaseLayout.GetLayoutSize = BaseLayout.GetSize

function BaseLayout:GetParentControl()
	local Parent = self.Parent
	while Parent and Parent.IsLayout do
		Parent = Parent.Parent
	end
	return Parent
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
	assert( not Elements[ Element ], "Attempted to add element to layout twice!" )

	Elements[ #Elements + 1 ] = Element
	Elements[ Element ] = true

	OnAddElement( self, Element )
end

function BaseLayout:InsertElement( Element, Index )
	local Elements = self.Elements
	assert( not Elements[ Element ], "Attempted to add element to layout twice!" )

	TableInsert( Elements, Index, Element )
	Elements[ Element ] = true
	OnAddElement( self, Element )
end

function BaseLayout:InsertElementAfter( Element, AfterElement )
	local Elements = self.Elements
	assert( Elements[ Element ], "Provided element to insert after is not in the layout!" )
	assert( not Elements[ AfterElement ], "Attempted to add element to layout twice!" )

	for i = 1, #Elements do
		if Elements[ i ] == Element then
			TableInsert( Elements, i + 1, AfterElement )
			break
		end
	end

	Elements[ AfterElement ] = true
	OnAddElement( self, AfterElement )
end

local function OnRemoveElement( self, Element )
	if Element.IsLayout then
		TableRemoveByValue( self.LayoutChildren, Element )
		if Element.Parent == self then
			Element:SetParent( nil )
		end
	elseif Element.LayoutParent == self then
		Element.LayoutParent = nil
	end
end

function BaseLayout:RemoveElement( Element )
	local Elements = self.Elements
	if not Elements[ Element ] then return end

	Elements[ Element ] = nil
	TableRemoveByValue( Elements, Element )

	OnRemoveElement( self, Element )

	self:InvalidateLayout()
end

--[[
	Determines whether the given element is contained within this layout, either as a direct child, or as a descendant.

	This can be useful to know whether this layout will affect the given element's position/size directly or indirectly.
]]
function BaseLayout:ContainsElement( Element )
	-- Traverse the ancestors until this layout is found or we reach the root of the element tree.
	local LayoutParent = Element.LayoutParent or Element.Parent
	while LayoutParent and LayoutParent ~= self do
		LayoutParent = LayoutParent.LayoutParent or LayoutParent.Parent
	end
	return LayoutParent == self
end

function BaseLayout:Clear()
	for i = 1, #self.Elements do
		local Element = self.Elements[ i ]
		OnRemoveElement( self, Element )
		self.Elements[ i ] = nil
		self.Elements[ Element ] = nil
	end

	self:InvalidateLayout()
end

-- Layouts inherit some basic functionality from elements.
table.Mixin( SGUI.BaseControl, BaseLayout, {
	"SetupFromTable",
	"ComputeSpacing",
	"GetContentSizeForAxis",
	"GetMaxSizeAlongAxis",
	"GetSizeForAxis",
	"GetComputedPadding",
	"GetComputedMargin",
	"GetComputedSize",
	"GetParentSize",
	"InvalidateParent",
	"InvalidateLayout",
	"HandleLayout",
	"GetLayoutOffset",
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
	for i = 1, #self.Elements do
		self.Elements[ i ]:InvalidateLayout( true )
	end
end

function BaseLayout:__tostring()
	return StringFormat(
		"[SGUI] %s Layout | %d Children (%d Layout Children) | Attached to: [%s]",
		self.Class,
		#self.Elements,
		#self.LayoutChildren,
		self:GetParentControl()
	)
end

Layout.Types = {}
Layout.Units = {}

function Layout:RegisterType( Name, MetaTable, Parent )
	MetaTable.__index = MetaTable
	MetaTable.__Base = Parent
	MetaTable.BaseClass = BaseLayout
	MetaTable.__tostring = MetaTable.__tostring or BaseLayout.__tostring
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
	Shine.AssertAtLevel(
		MetaTable and not rawget( MetaTable, "IsAbstract" ),
		"Attempted to construct unregistered or abstract layout type: %s", 3, Name
	)

	return setmetatable( { Class = Name }, self.Types[ Name ] ):Init( ... )
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
