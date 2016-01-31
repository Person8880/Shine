--[[
	Easy comparator definitions.

	To use a comparator, pass it to table.sort() or Stream:Sort()
	by passing the result of its Compile() method.
]]

local Comparators = {}
local setmetatable = setmetatable

function Shine.Comparator( Type, ... )
	return Comparators[ Type ]( ... )
end

local Operators = {
	[ 1 ] = function( A, B )
		if A == B then return 0 end
		return A < B and -1 or 1
	end,
	[ -1 ] = function( A, B )
		if A == B then return 0 end
		return A > B and -1 or 1
	end
}

local function Compile( Comparator )
	return function( A, B )
		local Outcome = Comparator:Compare( A, B )
		return Outcome < 0
	end
end

local function CompileStable( Comparator )
	return function( A, B )
		return Comparator:Compare( A, B )
	end
end

local function NewComparatorType( Name )
	local Meta = Shine.TypeDef()
	Meta.Compile = Compile
	Meta.CompileStable = CompileStable

	Comparators[ Name ] = Meta

	return Meta
end

do
	local FieldComparator = NewComparatorType( "Field" )

	function FieldComparator:Init( Type, Field, Default )
		self.Type = Type
		self.Field = Field
		self.Default = Default

		return self
	end

	function FieldComparator:Compare( A, B )
		return Operators[ self.Type ]( A[ self.Field ] or Default, B[ self.Field ] or Default )
	end
end

do
	local MethodComparator = NewComparatorType( "Method" )
	local Identity = function( Value ) return Value end

	function MethodComparator:Init( Type, Method, Arg, Transformer )
		self.Type = Type
		self.Method = Method
		self.Arg = Arg
		self.Transformer = Transformer or Identity

		return self
	end

	function MethodComparator:Compare( A, B )
		return Operators[ self.Type ]( self.Transformer( A[ self.Method ]( A, self.Arg ) ),
			self.Transformer( B[ self.Method ]( B, self.Arg ) ) )
	end
end

do
	local ComposedComparator = NewComparatorType( "Composition" )

	--[[
		Composes comparison operations to allow for sub-sorting.
		Comparators are passed in order from least important to most important.
	]]
	function ComposedComparator:Init( ... )
		self.Comparators = { ... }
		self.NumComparators = select( "#", ... )

		return self
	end

	function ComposedComparator:Compare( A, B )
		local Comparators = self.Comparators

		local Value = 0
		for i = 1, self.NumComparators do
			Value = Value + 2 ^ ( i - 1 ) * Comparators[ i ]:Compare( A, B )
		end

		return Value
	end
end
