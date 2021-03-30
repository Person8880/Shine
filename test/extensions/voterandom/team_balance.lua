--[[
	Team balance function tests.
]]

local UnitTest = Shine.UnitTest

local VoteShuffle = UnitTest:LoadExtension( "voterandom" )
if not VoteShuffle or not VoteShuffle.Config then return end

local MockShuffle = UnitTest.MockOf( VoteShuffle )

local MockClient = UnitTest.MakeMockClient( 123 )
local MockPlayer

UnitTest:Before( function()
	MockPlayer = {
		GetPlayerSkill = function() return 1000 end,
		GetPlayerSkillOffset = function() return 500 end,
		GetCommanderSkill = function() return 500 end,
		GetCommanderSkillOffset = function() return 100 end,
		GetClient = function() return MockClient end,
		GetTeamNumber = function() return 2 end,
		isa = function( self, Name ) return Name == "Commander" end
	}
end )

UnitTest:Test( "SkillGetters.GetHiveSkill - Returns commander skill for a commander on the evaluated team with no blending", function( Assert )
	local Skill = MockShuffle.SkillGetters.GetHiveSkill( MockPlayer, 2, true, true )
	Assert.Equals( "Should use commander skill", 400, Skill )
end )

UnitTest:Test( "SkillGetters.GetHiveSkill - Returns field skill if commanders skills are not enabled", function( Assert )
	local Skill = MockShuffle.SkillGetters.GetHiveSkill( MockPlayer, 1, true, false )
	Assert.Equals( "Should use field skill", 1500, Skill )
end )

UnitTest:Test( "SkillGetters.GetHiveSkill - Returns field skill for a commander not on the evaluated team", function( Assert )
	local Skill = MockShuffle.SkillGetters.GetHiveSkill( MockPlayer, 1, true, true )
	Assert.Equals( "Should use field skill", 1500, Skill )
end )

UnitTest:Test( "SkillGetters.GetHiveSkill - Returns field skill for a field player", function( Assert )
	MockPlayer.isa = function() return false end

	local Skill = MockShuffle.SkillGetters.GetHiveSkill( MockPlayer, 2, true, true )
	Assert.Equals( "Should use field skill", 500, Skill )
end )

UnitTest:Test( "SkillGetters.GetHiveSkill - Returns blended field and commander skill if blending is applicable and enabled", function( Assert )
	local Skill = MockShuffle.SkillGetters.GetHiveSkill( MockPlayer, 2, true, true, {
		BlendAlienCommanderAndFieldSkills = true
	} )
	Assert.Equals( "Should use blended skill", 450, Skill )
end )

UnitTest:Test( "SkillGetters.GetHiveSkill - Returns average commander skill when team skills are disabled", function( Assert )
	local Skill = MockShuffle.SkillGetters.GetHiveSkill( MockPlayer, 2, false, true )
	Assert.Equals( "Should use average commander skill", 500, Skill )
end )

UnitTest:Test( "SkillGetters.GetHiveSkill - Returns average field skill when team skills are disabled", function( Assert )
	local Skill = MockShuffle.SkillGetters.GetHiveSkill( MockPlayer, 1, false, false )
	Assert.Equals( "Should use average field skill", 1000, Skill )
end )
