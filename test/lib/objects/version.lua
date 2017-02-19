--[[
	Version object tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Equality", function( Assert )
	Assert:Equals( Shine.VersionHolder( "1.0.0" ), Shine.VersionHolder( "1.0.0" ) )
end )

UnitTest:Test( "Less than", function( Assert )
	Assert:True( Shine.VersionHolder( "1.0.0" ) < Shine.VersionHolder( "1.0.1" ) )
	Assert:True( Shine.VersionHolder( "1.0.0" ) < Shine.VersionHolder( "1.1.0" ) )
	Assert:True( Shine.VersionHolder( "1.0.0" ) < Shine.VersionHolder( "2.0.0" ) )

	Assert:False( Shine.VersionHolder( "1.0.0" ) > Shine.VersionHolder( "1.0.1" ) )
	Assert:False( Shine.VersionHolder( "1.0.0" ) > Shine.VersionHolder( "1.1.0" ) )
	Assert:False( Shine.VersionHolder( "1.0.0" ) > Shine.VersionHolder( "2.0.0" ) )
end )

UnitTest:Test( "Less or equal", function( Assert )
	Assert:True( Shine.VersionHolder( "1.0.0" ) <= Shine.VersionHolder( "1.0.0" ) )
	Assert:True( Shine.VersionHolder( "1.0.0" ) <= Shine.VersionHolder( "1.0.1" ) )
	Assert:True( Shine.VersionHolder( "1.0.0" ) <= Shine.VersionHolder( "1.1.0" ) )
	Assert:True( Shine.VersionHolder( "1.0.0" ) <= Shine.VersionHolder( "2.0.0" ) )

	Assert:False( Shine.VersionHolder( "1.0.0" ) >= Shine.VersionHolder( "1.0.1" ) )
	Assert:False( Shine.VersionHolder( "1.0.0" ) >= Shine.VersionHolder( "1.1.0" ) )
	Assert:False( Shine.VersionHolder( "1.0.0" ) >= Shine.VersionHolder( "2.0.0" ) )
end )
