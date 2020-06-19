--[[
	Set object unit tests.
]]

local UnitTest = Shine.UnitTest

local function RunSetTests( TypeName, SetType )
	UnitTest:Test( TypeName.." - Construction from lookup", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Assert:Equals( 3, Set:GetCount() )
		Assert:True( Set:Contains( "a" ) )
		Assert:True( Set:Contains( "b" ) )
		Assert:True( Set:Contains( "c" ) )
	end )

	UnitTest:Test( TypeName.." - Construction from list", function( Assert )
		local Set = SetType.FromList( { "a", "b", "c" } )
		Assert:Equals( 3, Set:GetCount() )
		Assert:True( Set:Contains( "a" ) )
		Assert:True( Set:Contains( "b" ) )
		Assert:True( Set:Contains( "c" ) )
	end )

	UnitTest:Test( TypeName.." - Intersection", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Set:Intersection( { a = true, b = true, d = true } )

		Assert:Equals( 2, Set:GetCount() )
		Assert:True( Set:Contains( "a" ) )
		Assert:True( Set:Contains( "b" ) )
		Assert:False( Set:Contains( "c" ) )
	end )

	UnitTest:Test( TypeName.." - Union", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Set:Union( SetType( { a = true, b = true, d = true } ) )

		Assert:Equals( 4, Set:GetCount() )
		Assert:True( Set:Contains( "a" ) )
		Assert:True( Set:Contains( "b" ) )
		Assert:True( Set:Contains( "c" ) )
		Assert:True( Set:Contains( "d" ) )
	end )

	UnitTest:Test( TypeName.." - Filter", function( Assert )
		local Set = SetType.FromList( { "a", "b", "c" } )
		Set:Filter( function( Value ) return Value == "c" end )

		Assert:Equals( 1, Set:GetCount() )
		Assert:True( Set:Contains( "c" ) )
		Assert:False( Set:Contains( "a" ) )
		Assert:False( Set:Contains( "b" ) )

		if TypeName == "UnorderedSet" then
			Assert.DeepEquals( "Should have updated the index mapping", {
				c = 1
			}, Set.Lookup )
		end
	end )

	UnitTest:Test( TypeName.." - Add existing element", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Assert:Equals( 3, Set:GetCount() )
		Assert:True( Set:Contains( "a" ) )

		Set:Add( "a" )

		Assert:Equals( 3, Set:GetCount() )
		Assert:True( Set:Contains( "a" ) )
	end )

	UnitTest:Test( TypeName.." - Add non-existing element", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Assert:Equals( 3, Set:GetCount() )

		Set:Add( "d" )

		Assert:Equals( 4, Set:GetCount() )
		Assert:True( Set:Contains( "d" ) )
	end )

	UnitTest:Test( TypeName.." - AddAll", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Assert:Equals( 3, Set:GetCount() )

		Set:AddAll( { "c", "d", "e" } )
		Assert:Equals( 5, Set:GetCount() )
		Assert:True( Set:Contains( "d" ) )
		Assert:True( Set:Contains( "e" ) )
	end )

	UnitTest:Test( TypeName.." - ReplaceMatchingValue - should replace when a value matches", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Assert:Equals( 3, Set:GetCount() )

		Set:ReplaceMatchingValue( "d", function( Value ) return Value == "c" end )
		Assert:Equals( 3, Set:GetCount() )
		Assert:True( Set:Contains( "d" ) )
		Assert:False( Set:Contains( "c" ) )
	end )

	UnitTest:Test( TypeName.." - ReplaceMatchingValue - should not replace when no value matches", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Assert:Equals( 3, Set:GetCount() )

		Set:ReplaceMatchingValue( "d", function( Value ) return Value == "d" end )
		Assert:Equals( 3, Set:GetCount() )
		Assert:False( Set:Contains( "d" ) )
		Assert:True( Set:Contains( "a" ) )
		Assert:True( Set:Contains( "b" ) )
		Assert:True( Set:Contains( "c" ) )
	end )

	UnitTest:Test( TypeName.." - Remove", function( Assert )
		local Set = SetType()
		Set:AddAll( { "a", "b", "c" } )
		Assert:Equals( 3, Set:GetCount() )

		Set:Remove( "a" )

		Assert:Equals( 2, Set:GetCount() )
		Assert:False( Set:Contains( "a" ) )
		Assert:Missing( Set.List, "a" )

		Set:Remove( "c" )

		Assert:Equals( 1, Set:GetCount() )
		Assert:False( Set:Contains( "c" ) )
		Assert:Missing( Set.List, "c" )
	end )

	UnitTest:Test( TypeName.." - RemoveAll", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Assert:Equals( 3, Set:GetCount() )

		Set:RemoveAll( { "a", "b" } )

		Assert:Equals( 1, Set:GetCount() )
		Assert:False( Set:Contains( "a" ) )
		Assert:Missing( Set.List, "a" )
		Assert:False( Set:Contains( "b" ) )
		Assert:Missing( Set.List, "b" )
		Assert:True( Set:Contains( "c" ) )
		Assert:Contains( Set.List, "c" )
	end )

	UnitTest:Test( TypeName.." - Iteration", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		local Seen = SetType()

		for Value in Set:Iterate() do
			Seen:Add( Value )
		end

		Assert:Equals( Seen, Set )
	end )

	UnitTest:Test( TypeName.." - Clear", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Set:Clear()

		Assert:Equals( 0, Set:GetCount() )
		Assert:False( Set:Contains( "a" ) )
		Assert:False( Set:Contains( "b" ) )
		Assert:False( Set:Contains( "c" ) )
	end )

	UnitTest:Test( TypeName.." - Length meta-method", function( Assert )
		local Set = SetType( { a = true, b = true, c = true } )
		Assert:Equals( 3, #Set )
	end )

	UnitTest:Test( TypeName.." - Equality", function( Assert )
		Assert:Equals( SetType( { a = true, b = true, c = true } ), SetType( { a = true, b = true, c = true } ) )
		Assert:NotEquals( SetType( { a = true, b = true, c = true } ), SetType( { a = true, c = true } ) )
		Assert:NotEquals( SetType( { a = true, b = true, c = true } ), SetType( { a = true, c = true, d = true } ) )
	end )
end

RunSetTests( "Set", Shine.Set )
RunSetTests( "UnorderedSet", Shine.UnorderedSet )
