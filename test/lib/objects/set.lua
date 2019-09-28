--[[
	Set object unit tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Construction from lookup", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Assert:Equals( 3, Set:GetCount() )
	Assert:True( Set:Contains( "a" ) )
	Assert:True( Set:Contains( "b" ) )
	Assert:True( Set:Contains( "c" ) )
end )

UnitTest:Test( "Construction from list", function( Assert )
	local Set = Shine.Set.FromList( { "a", "b", "c" } )
	Assert:Equals( 3, Set:GetCount() )
	Assert:True( Set:Contains( "a" ) )
	Assert:True( Set:Contains( "b" ) )
	Assert:True( Set:Contains( "c" ) )
end )

UnitTest:Test( "Intersection", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Set:Intersection( { a = true, b = true, d = true } )

	Assert:Equals( 2, Set:GetCount() )
	Assert:True( Set:Contains( "a" ) )
	Assert:True( Set:Contains( "b" ) )
	Assert:False( Set:Contains( "c" ) )
end )

UnitTest:Test( "Union", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Set:Union( Shine.Set( { a = true, b = true, d = true } ) )

	Assert:Equals( 4, Set:GetCount() )
	Assert:True( Set:Contains( "a" ) )
	Assert:True( Set:Contains( "b" ) )
	Assert:True( Set:Contains( "c" ) )
	Assert:True( Set:Contains( "d" ) )
end )

UnitTest:Test( "Filter", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Set:Filter( function( Value ) return Value == "a" end )

	Assert:Equals( 1, Set:GetCount() )
	Assert:True( Set:Contains( "a" ) )
	Assert:False( Set:Contains( "b" ) )
	Assert:False( Set:Contains( "c" ) )
end )

UnitTest:Test( "Add existing element", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Assert:Equals( 3, Set:GetCount() )
	Assert:True( Set:Contains( "a" ) )

	Set:Add( "a" )

	Assert:Equals( 3, Set:GetCount() )
	Assert:True( Set:Contains( "a" ) )
end )

UnitTest:Test( "Add non-existing element", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Assert:Equals( 3, Set:GetCount() )

	Set:Add( "d" )

	Assert:Equals( 4, Set:GetCount() )
	Assert:True( Set:Contains( "d" ) )
end )

UnitTest:Test( "AddAll", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Assert:Equals( 3, Set:GetCount() )

	Set:AddAll( { "c", "d", "e" } )
	Assert:Equals( 5, Set:GetCount() )
	Assert:True( Set:Contains( "d" ) )
	Assert:True( Set:Contains( "e" ) )
end )

UnitTest:Test( "ReplaceMatchingValue - should replace when a value matches", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Assert:Equals( 3, Set:GetCount() )

	Set:ReplaceMatchingValue( "d", function( Value ) return Value == "c" end )
	Assert:Equals( 3, Set:GetCount() )
	Assert:True( Set:Contains( "d" ) )
	Assert:False( Set:Contains( "c" ) )
end )

UnitTest:Test( "ReplaceMatchingValue - should not replace when no value matches", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Assert:Equals( 3, Set:GetCount() )

	Set:ReplaceMatchingValue( "d", function( Value ) return Value == "d" end )
	Assert:Equals( 3, Set:GetCount() )
	Assert:False( Set:Contains( "d" ) )
	Assert:True( Set:Contains( "a" ) )
	Assert:True( Set:Contains( "b" ) )
	Assert:True( Set:Contains( "c" ) )
end )

UnitTest:Test( "Remove", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Assert:Equals( 3, Set:GetCount() )

	Set:Remove( "a" )

	Assert:Equals( 2, Set:GetCount() )
	Assert:False( Set:Contains( "a" ) )
end )

UnitTest:Test( "RemoveAll", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Assert:Equals( 3, Set:GetCount() )

	Set:RemoveAll( { "a", "b" } )

	Assert:Equals( 1, Set:GetCount() )
	Assert:False( Set:Contains( "a" ) )
	Assert:False( Set:Contains( "b" ) )
	Assert:True( Set:Contains( "c" ) )
end )

UnitTest:Test( "Iteration", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	local Seen = Shine.Set()

	for Value in Set:Iterate() do
		Seen:Add( Value )
	end

	Assert:Equals( Seen, Set )
end )

UnitTest:Test( "Clear", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Set:Clear()

	Assert:Equals( 0, Set:GetCount() )
	Assert:False( Set:Contains( "a" ) )
	Assert:False( Set:Contains( "b" ) )
	Assert:False( Set:Contains( "c" ) )
end )

UnitTest:Test( "Length meta-method", function( Assert )
	local Set = Shine.Set( { a = true, b = true, c = true } )
	Assert:Equals( 3, #Set )
end )

UnitTest:Test( "Equality", function( Assert )
	Assert:Equals( Shine.Set( { a = true, b = true, c = true } ), Shine.Set( { a = true, b = true, c = true } ) )
	Assert:NotEquals( Shine.Set( { a = true, b = true, c = true } ), Shine.Set( { a = true, c = true } ) )
	Assert:NotEquals( Shine.Set( { a = true, b = true, c = true } ), Shine.Set( { a = true, c = true, d = true } ) )
end )
