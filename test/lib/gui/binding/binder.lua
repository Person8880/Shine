--[[
	Binder tests.
]]

local UnitTest = Shine.UnitTest
local Binder = require "shine/lib/gui/binding/binder"

local MockElement

UnitTest:Before( function()
	MockElement = {
		CallOnRemoves = {},
		GetPropertySource = function( self, Name )
			return {
				Element = self,
				Property = Name,
				Listeners = {},
				Value = Name,
				GetValue = function( self ) return self.Value end,
				AddListener = function( self, Listener )
					self.Listeners[ #self.Listeners + 1 ] = Listener
				end
			}
		end,
		GetPropertyTarget = function( self, Name )
			return UnitTest.MockFunction()
		end,
		CallOnRemove = function( self, Func )
			self.CallOnRemoves[ #self.CallOnRemoves + 1 ] = Func
		end
	}
end )

UnitTest:Test( "Binds a single property to many as expected", function( Assert )
	local Listener = UnitTest.MockFunction()
	local Params = {
		Filter = function() return true end,
		Transformer = function( Value ) return not Value end
	}
	local Binding = Binder():FromElement( MockElement, "Test" )
		:ToElement( MockElement, "Test2" )
		:ToElement( MockElement, "Test3", Params )
		:ToListener( Listener, {
			Filter = function() return false end
		} )
		:ToListener( Listener ):BindProperty()

	Assert.Equals( "Should have set the source from the element", MockElement, Binding.Source.Element )
	Assert.DeepEquals( "Should have added the binding to the source as a listener", {
		Binding
	}, Binding.Source.Listeners )
	Assert.Equals( "Should have setup removal callbacks for each element target", 2,
		#MockElement.CallOnRemoves )

	local function AssertInvoked( Index, Target, InvokedWith )
		Assert.DeepEquals( "Should have invoked the sink as expected for target "..Index,
			{ Invocations = InvokedWith }, Binding.Targets[ Index ].Sink )
		for Key, Value in pairs( Target ) do
			Assert.Equals( "Should have expected value at key "..Key, Value, Binding.Targets[ Index ][ Key ] )
		end
	end

	AssertInvoked( 1, { Element = MockElement }, {
		{
			ArgCount = 1,
			"Test"
		}
	} )
	AssertInvoked( 2, { Element = MockElement, Filter = Params.Filter, Transformer = Params.Transformer }, {
		{
			ArgCount = 1,
			false
		}
	} )
	AssertInvoked( 1, {}, {
		{
			ArgCount = 1,
			"Test"
		}
	} )
end )

UnitTest:Test( "Binds multiple properties as expected", function( Assert )
	local Listener = UnitTest.MockFunction()
	local Params = {
		Filter = function() return true end,
		Transformer = function( Value ) return not Value end
	}
	local Reducer = function( State, Value ) return State..Value end
	local Binding = Binder():FromElement( MockElement, "Test1" )
		:FromElement( MockElement, "Test2" )
		:WithReducer( Reducer )
		:WithInitialState( "abc" )
		:ToElement( MockElement, "Test3" )
		:ToElement( MockElement, "Test4", Params )
		:ToListener( Listener, {
			Filter = function() return false end
		} )
		:ToListener( Listener ):BindProperties()

	Assert.Equals( "Should have set the sources from the element", 2, #Binding.Sources )
	for i = 1, #Binding.Sources do
		local Source = Binding.Sources[ i ]
		Assert.Equals( "Source should be from the element", MockElement, Source.Element )
		Assert.Equals( "Source property should be as expected", "Test"..i, Source.Property )
		Assert.DeepEquals( "Should have added the binding to the source as a listener", {
			Binding
		}, Source.Listeners )
	end

	Assert.Equals( "Reducer should be set", Reducer, Binding.Reducer )
	Assert.Equals( "Initial state should be set", "abc", Binding.InitialState )

	Assert.Equals( "Should have setup removal callbacks for each element source/target", 4,
		#MockElement.CallOnRemoves )

	local function AssertInvoked( Index, Target, InvokedWith )
		Assert.DeepEquals( "Should have invoked the sink as expected for target "..Index,
			{ Invocations = InvokedWith }, Binding.Targets[ Index ].Sink )
		for Key, Value in pairs( Target ) do
			Assert.Equals( "Should have expected value at key "..Key, Value, Binding.Targets[ Index ][ Key ] )
		end
	end
	AssertInvoked( 1, { Element = MockElement }, {
		{
			ArgCount = 1,
			"abcTest1Test2"
		}
	} )
	AssertInvoked( 2, { Element = MockElement, Filter = Params.Filter, Transformer = Params.Transformer }, {
		{
			ArgCount = 1,
			false
		}
	} )
	AssertInvoked( 1, {}, {
		{
			ArgCount = 1,
			"abcTest1Test2"
		}
	} )
end )
