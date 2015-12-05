--[[
	SGUI layout system.
]]

local SGUI = Shine.GUI

local getmetatable = getmetatable
local rawget = rawget
local setmetatable = setmetatable
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
SGUI.AddProperty( BaseLayout, "Alignment", SGUI.LayoutAlignment.MIN )
SGUI.AddProperty( BaseLayout, "Elements" )

function BaseLayout:Init( Data )
	local Spacing = Layout.Units.Spacing

	self.Elements = Data.Elements or {}
	self.Pos = Data.Pos or Vector2( 0, 0 )
	self.AutoSize = Data.AutoSize
	self.Size = Data.Size or Vector2( 0, 0 )
	self.Margin = Data.Margin or Spacing( 0, 0, 0, 0 )
	self.Padding = Data.Padding or Spacing( 0, 0, 0, 0 )
	self.Parent = Data.Parent
	self.Anchor = Data.Anchor or SGUI.Anchors.TopLeft
	if Data.Fill == nil then
		self.Fill = true
	end

	for i = 1, #self.Elements do
		local Element = self.Elements[ i ]
		if Element.IsLayout then
			Element:SetParent( self )
		end
	end

	return self
end

function BaseLayout:GetComputedSize( Index, ParentSize )
	if not self.AutoSize then
		return ParentSize
	end

	return self.AutoSize[ Index ]:GetValue( ParentSize )
end

function BaseLayout:AddElement( Element )
	local Elements = self.Elements
	Elements[ #Elements + 1 ] = Element
	self:InvalidateLayout()
end

function BaseLayout:RemoveElement( Element )
	TableRemoveByValue( self.Elements, Element )
	self:InvalidateLayout()
end

-- Layouts inherit some basic functionality from elements.
table.Mixin( SGUI.BaseControl, BaseLayout, {
	"ComputeSpacing",
	"GetComputedPadding",
	"GetComputedMargin",
	"GetParentSize",
	"InvalidateParent",
	"InvalidateLayout",
	"HandleLayout"
} )

function BaseLayout:Think( DeltaTime )
	self:HandleLayout( DeltaTime )

	-- Layouts must make sure child layouts also think (and thus handle layout invalidations)
	for i = 1, #self.Elements do
		local Element = self.Elements[ i ]
		if Element.IsLayout then
			Element:Think( DeltaTime )
		end
	end
end

function BaseLayout:PerformLayout()
	-- This method is responsible for actually computing the layout.
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
