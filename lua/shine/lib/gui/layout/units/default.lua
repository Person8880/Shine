--[[
	Default set of SGUI units.
]]

local SGUI = Shine.GUI
local Layout = SGUI.Layout
local Stream = Shine.Stream

local Absolute
local getmetatable = getmetatable
local IsType = Shine.IsType
local rawset = rawset
local select = select
local setmetatable = setmetatable
local StringFormat = string.format
local TableArraysEqual = table.ArraysEqual
local TableEmpty = table.Empty
local TableRemoveByValue = table.RemoveByValue

local function NewType( Name )
	local Meta = {}
	Layout:RegisterUnit( Name, Meta )
	return Meta
end

-- Automatically change numbers into instances of Absolute units.
local function ToUnit( Value )
	if IsType( Value, "number" ) then
		return Absolute( Value )
	end

	return Value or Absolute( 0 )
end
Layout.ToUnit = ToUnit

local function ToUnits( ... )
	local Values = { ... }
	for i = 1, select( "#", ... ) do
		Values[ i ] = ToUnit( Values[ i ] )
	end
	return Values
end

local Operators = {
	__add = {
		Key = "+",
		Apply = function( A, B ) return A + B end
	},
	__sub = {
		Key = "-",
		Apply = function( A, B ) return A - B end
	},
	__mul = {
		Key = "*",
		Apply = function( A, B ) return A * B end
	},
	__div = {
		Key = "/",
		Apply = function( A, B ) return A / B end
	}
}

local function BuildOperator( Meta, Operator )
	local Key = Operator.Key
	local Apply = Operator.Apply
	return function( A, B )
		A = ToUnit( A )
		B = ToUnit( B )

		return setmetatable( {
			GetValue = function( self, ParentSize, Element, Axis )
				return Apply(
					A:GetValue( ParentSize, Element, Axis ),
					B:GetValue( ParentSize, Element, Axis )
				)
			end,
			Operator = { A, Key, B }
		}, Meta )
	end
end

local function NewUnit( Name )
	local Meta = NewType( Name )

	function Meta:Init( Value )
		self.Value = Value
		return self
	end

	for MetaKey, Operator in pairs( Operators ) do
		Meta[ MetaKey ] = BuildOperator( Meta, Operator )
	end

	function Meta:__unm()
		return setmetatable( {
			GetValue = function( _, ParentSize, Element, Axis )
				return -self:GetValue( ParentSize, Element, Axis )
			end,
			Operator = { "-", self }
		}, Meta )
	end

	function Meta:__mod( Mod )
		return setmetatable( {
			GetValue = function( _, ParentSize, Element, Axis )
				return self:GetValue( ParentSize, Element, Axis ) % Mod
			end,
			Operator = { self, "%", Mod }
		}, Meta )
	end

	function Meta:__pow( Power )
		return setmetatable( {
			GetValue = function( _, ParentSize, Element, Axis )
				return self:GetValue( ParentSize, Element, Axis ) ^ Power
			end,
			Operator = { self, "^", Power }
		}, Meta )
	end

	-- Add some automatic convenience wrappers around common meta-methods.
	getmetatable( Meta ).__newindex = function( Meta, Key, Value )
		local NewValue = Value

		if Key == "__eq" then
			NewValue = function( self, Other )
				-- If this unit has become a composite, equality checking no longer applies as it did before.
				-- Instead, each argument of the operation needs to be equal. The original metatable is preserved here
				-- to allow detection of the left-hand side of the operator, e.g. a common use case is to combine
				-- the "Auto" unit with some extra padding space, and the detection of "Auto" is needed for things like
				-- label auto-wrapping. As equality checks are rare, this is an acceptable overhead.
				if self.Operator then
					return IsType( Other.Operator, "table" ) and TableArraysEqual( self.Operator, Other.Operator )
				end
				return Value( self, Other )
			end
		elseif Key == "__tostring" then
			NewValue = function( self )
				if self.Operator then
					return Stream( self.Operator ):Concat( " " )
				end
				return Value( self )
			end
		end

		rawset( Meta, Key, NewValue )
	end

	return Meta
end

--[[
	Spacing type, handles padding and margins.
]]
do
	local rawget = rawget

	local Spacing = NewType( "Spacing" )

	function Spacing.Uniform( Amount )
		return Spacing( Amount, Amount, Amount, Amount )
	end

	function Spacing:Init( L, U, R, D )
		self[ 1 ] = ToUnit( L )
		self[ 2 ] = ToUnit( U )
		self[ 3 ] = ToUnit( R )
		self[ 4 ] = ToUnit( D )

		return self
	end

	function Spacing:GetWidth()
		return self[ 1 ] + self[ 3 ]
	end

	function Spacing:GetHeight()
		return self[ 2 ] + self[ 4 ]
	end

	local KeyMap = {
		Left = 1,
		Up = 2,
		Right = 3,
		Down = 4
	}
	function Spacing:__index( Key )
		return Spacing[ Key ] or rawget( self, KeyMap[ Key ] )
	end

	function Spacing:WithLeft( Left )
		return Spacing( Left, self[ 2 ], self[ 3 ], self[ 4 ] )
	end

	function Spacing:WithUp( Up )
		return Spacing( self[ 1 ], Up, self[ 3 ], self[ 4 ] )
	end

	function Spacing:WithRight( Right )
		return Spacing( self[ 1 ], self[ 2 ], Right, self[ 4 ] )
	end

	function Spacing:WithDown( Down )
		return Spacing( self[ 1 ], self[ 2 ], self[ 3 ], Down )
	end

	function Spacing:__tostring()
		return StringFormat( "Spacing( %s, %s, %s, %s )", self[ 1 ], self[ 2 ], self[ 3 ], self[ 4 ] )
	end
end

--[[
	Unit vector, handles holding a pair of units.
]]
do
	local rawget = rawget

	local UnitVector = NewType( "UnitVector" )

	function UnitVector.Uniform( Size )
		return UnitVector( Size, Size )
	end

	function UnitVector:Init( X, Y )
		self[ 1 ] = ToUnit( X )
		self[ 2 ] = ToUnit( Y )

		return self
	end

	function UnitVector:Set( UnitVector )
		for i = 1, 2 do
			self[ i ] = UnitVector[ i ]
		end
		return self
	end

	function UnitVector:GetValue( ParentSize, Element )
		return Vector2(
			self[ 1 ]:GetValue( ParentSize.x, Element, 1 ),
			self[ 2 ]:GetValue( ParentSize.y, Element, 2 )
		)
	end

	local KeyMap = {
		x = 1, y = 2
	}
	function UnitVector:__index( Key )
		return UnitVector[ Key ] or rawget( self, KeyMap[ Key ] )
	end

	function UnitVector:__tostring()
		return StringFormat( "UnitVector( %s, %s )", self[ 1 ], self[ 2 ] )
	end
end

--[[
	Dummy type, just returns the passed value. This is used to enable unit arithmetic with constant number values.
]]
do
	Absolute = NewUnit( "Absolute" )

	function Absolute:GetValue()
		return self.Value
	end

	function Absolute:__eq( Other )
		return self.Value == Other.Value
	end

	function Absolute:__tostring()
		return StringFormat( "Absolute( %s )", self.Value )
	end
end

--[[
	Scaled using SGUI.LinearScale().

	The name is for backwards compatibility. This used to use GUIScale but no longer does to avoid global HUD scaling
	options messing with SGUI layout.
]]
do
	local GUIScaled = NewUnit( "GUIScaled" )

	function GUIScaled:GetValue()
		return SGUI.LinearScale( self.Value )
	end

	function GUIScaled:__eq( Other )
		return self.Value == Other.Value
	end

	function GUIScaled:__tostring()
		return StringFormat( "GUIScaled( %s )", self.Value )
	end
end

--[[
	Scales the value only if the resolution is > 1080p.
]]
do
	local HighResScaled = NewUnit( "HighResScaled" )
	local HIGH_RES_WIDTH = 1920

	function HighResScaled:GetValue()
		return SGUI.GetScreenSize() > HIGH_RES_WIDTH and SGUI.LinearScale( self.Value ) or self.Value
	end

	function HighResScaled:__eq( Other )
		return self.Value == Other.Value
	end

	function HighResScaled:__tostring()
		return StringFormat( "HighResScaled( %s )", self.Value )
	end
end

--[[
	Arbitrary scale.
]]
do
	local Scaled = NewUnit( "Scaled" )
	local Round = math.Round

	function Scaled:Init( Value, Scale )
		self.Value = Value
		self.Scale = Scale

		return self
	end

	function Scaled:GetValue()
		return Round( self.Value * self.Scale )
	end

	function Scaled:__eq( Other )
		return self.Value == Other.Value and self.Scale == Other.Scale
	end

	function Scaled:__tostring()
		return StringFormat( "Scaled( %s, %s )", self.Value, self.Scale )
	end
end

--[[
	Percentage units are computed based on the parent's size.
]]
do
	local Percentage = NewUnit( "Percentage" )

	function Percentage:Init( Value )
		self.Value = Value * 0.01
		return self
	end

	function Percentage:GetValue( ParentSize )
		return ParentSize * self.Value
	end

	function Percentage:__eq( Other )
		return self.Value == Other.Value
	end

	function Percentage:__tostring()
		return StringFormat( "Percentage( %s )", self.Value * 100 )
	end

	local OneHundred = Percentage( 100 )
	-- Optimise out the redundant multiplier.
	function OneHundred:GetValue( ParentSize )
		return ParentSize
	end

	-- Avoid creating lots of repeated units.
	Percentage.ONE_HUNDRED = OneHundred
	Percentage.SEVENTY_FIVE = Percentage( 75 )
	Percentage.FIFTY = Percentage( 50 )
	Percentage.TWENTY_FIVE = Percentage( 25 )
end

--[[
	Percentage of another element in the tree, usually an ancestor.
]]
do
	local PercentageOfElement = NewUnit( "PercentageOfElement" )

	function PercentageOfElement:Init( Element, Value )
		Shine.AssertAtLevel(
			Shine.IsCallable( Element.GetSizeForAxis ),
			"Element must implement GetSizeForAxis method!",
			3
		)

		self.Element = Element
		self.Value = Value * 0.01

		return self
	end

	function PercentageOfElement:GetValue( ParentSize, Element, Axis )
		-- Note that this assumes the referenced element has already been through the layout process at this point (i.e.
		-- that its an ancestor element), otherwise this isn't going to give consistent results.
		return self.Element:GetSizeForAxis( Axis ) * self.Value
	end

	function PercentageOfElement:__eq( Other )
		return self.Element == Other.Element and self.Value == Other.Value
	end

	function PercentageOfElement:__tostring()
		return StringFormat( "PercentageOfElement( %s, %s )", self.Element, self.Value * 100 )
	end
end

--[[
	Automatic size based on the contents of a given element, or the element the unit is being evaluated against.
]]
do
	local Auto = NewUnit( "Auto" )

	function Auto:Init( Element )
		if Element then
			Shine.AssertAtLevel(
				Shine.IsCallable( Element.GetContentSizeForAxis ),
				"Element must implement GetContentSizeForAxis method!",
				3
			)
			self.GetValue = self.GetValueFromConfiguredElement
		else
			self.GetValue = self.GetValueFromGivenElement
		end

		self.Element = Element

		return self
	end

	function Auto:GetValueFromGivenElement( ParentSize, Element, Axis )
		return Element:GetContentSizeForAxis( Axis )
	end

	function Auto:GetValueFromConfiguredElement( ParentSize, Element, Axis )
		return self.Element:GetContentSizeForAxis( Axis )
	end

	function Auto:__eq( Other )
		return self.Element == Other.Element
	end

	function Auto:__tostring()
		return StringFormat( "Auto( %s )", self.Element )
	end

	Auto.INSTANCE = Auto()
end

--[[
	A composite unit that computes the maximum of a given list of unit values.
]]
do
	local MathMax = math.max

	local Max = NewUnit( "Max" )

	function Max:Init( ... )
		self.Values = ToUnits( ... )
		self.NumValues = select( "#", ... )
		return self
	end

	function Max:SetValue( Index, Value )
		self.Values[ Index ] = ToUnit( Value )
		return self
	end

	function Max:AddValue( Value )
		self.NumValues = self.NumValues + 1
		self.Values[ self.NumValues ] = ToUnit( Value )
		return self
	end

	function Max:RemoveValue( Value )
		if TableRemoveByValue( self.Values, ToUnit( Value ) ) then
			self.NumValues = self.NumValues - 1
		end
		return self
	end

	function Max:Clear()
		TableEmpty( self.Values )
		self.NumValues = 0
		return self
	end

	function Max:GetValue( ParentSize, Element, Axis )
		local MaxValue = 0
		for i = 1, self.NumValues do
			MaxValue = MathMax( MaxValue, self.Values[ i ]:GetValue( ParentSize, Element, Axis ) )
		end
		return MaxValue
	end

	function Max:__eq( Other )
		return TableArraysEqual( self.Values, Other.Values )
	end

	function Max:__tostring()
		return StringFormat( "Max( %s )", Stream.Of( self.Values ):Concat( ", " ) )
	end
end

--[[
	Turns the value returned by another unit value into an integer.

	This is useful to avoid sub-pixel sizes that result in gaps in rendering.
]]
do
	local Ceil = math.ceil
	local Integer = NewUnit( "Integer" )

	function Integer:Init( Value )
		self.Value = ToUnit( Value )
		return self
	end

	function Integer:GetValue( ParentSize, Element, Axis )
		return Ceil( self.Value:GetValue( ParentSize, Element, Axis ) )
	end

	function Integer:__eq( Other )
		return self.Value == Other.Value
	end

	function Integer:__tostring()
		return StringFormat( "Integer( %s )", self.Value )
	end
end

--[[
	A composite unit that computes the minimum of a given list of unit values.
]]
do
	local Huge = math.huge
	local MathMin = math.min

	local Min = NewUnit( "Min" )

	function Min:Init( ... )
		self.Values = ToUnits( ... )
		self.NumValues = select( "#", ... )
		return self
	end

	function Min:AddValue( Value )
		self.NumValues = self.NumValues + 1
		self.Values[ self.NumValues ] = ToUnit( Value )
		return self
	end

	function Min:RemoveValue( Value )
		if TableRemoveByValue( self.Values, ToUnit( Value ) ) then
			self.NumValues = self.NumValues - 1
		end
		return self
	end

	function Min:Clear()
		TableEmpty( self.Values )
		self.NumValues = 0
		return self
	end

	function Min:GetValue( ParentSize, Element, Axis )
		local MinValue = Huge
		for i = 1, self.NumValues do
			MinValue = MathMin( MinValue, self.Values[ i ]:GetValue( ParentSize, Element, Axis ) )
		end
		return MinValue
	end

	function Min:__eq( Other )
		return TableArraysEqual( self.Values, Other.Values )
	end

	function Min:__tostring()
		return StringFormat( "Min( %s )", Stream.Of( self.Values ):Concat( ", " ) )
	end
end

--[[
	Rounds the value returned by another unit value to the nearest power of two.

	This is useful to ensure symmetry.
]]
do
	local Ceil = math.ceil
	local RoundTo = math.RoundTo

	local MultipleOf2 = NewUnit( "MultipleOf2" )
	function MultipleOf2:Init( Value )
		self.Value = ToUnit( Value )
		return self
	end

	function MultipleOf2:GetValue( ParentSize, Element, Axis )
		return RoundTo( Ceil( self.Value:GetValue( ParentSize, Element, Axis ) ), 2 )
	end

	function MultipleOf2:__eq( Other )
		return self.Value == Other.Value
	end

	function MultipleOf2:__tostring()
		return StringFormat( "MultipleOf2( %s )", self.Value )
	end
end
