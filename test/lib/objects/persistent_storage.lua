--[[
	Persistent storage tests.
]]

local UnitTest = Shine.UnitTest

local TestFilePath = "config://shine/test.json"

-- Reset the test file.
Shine.SaveJSONFile( {}, TestFilePath, { indent = false } )

local function GetTestStorage()
	return Shine.Storage( TestFilePath )
end

UnitTest:Test( "GetAtPath", function( Assert )
	local Storage = GetTestStorage()
	Storage.Data.Cake = true

	Assert:True( Storage:GetAtPath( "Cake" ) )

	Storage.Data.MoreCake = {
		More = {
			More = {
				More = {
					SugarOverload = true
				}
			}
		}
	}
	Assert:True( Storage:GetAtPath( "MoreCake", "More", "More", "More", "SugarOverload" ) )
	Assert:Equals( Storage.Data.MoreCake.More, Storage:GetAtPath( "MoreCake", "More" ) )
end )

UnitTest:Test( "SetAtPath", function( Assert )
	local Storage = GetTestStorage()
	Storage:SetAtPath( false, "MoreCake", "More", "More", "More", "SugarOverload" )
	Assert:False( Storage.Data.MoreCake.More.More.More.SugarOverload )
end )

UnitTest:Test( "Transaction commit", function( Assert )
	local Storage = GetTestStorage()
	Storage:SetAtPath( false, "MoreCake", "More", "More", "More", "SugarOverload" )

	Storage:BeginTransaction()
	Storage:SetAtPath( true, "MoreCake", "More", "More", "More", "SugarOverload" )

	-- Transaction returns true with GetAtPath, but the underlying data should not have changed.
	Assert:True( Storage:GetInTransaction( "MoreCake", "More", "More", "More", "SugarOverload" ) )
	Assert:True( Storage:GetAtPath( "MoreCake", "More", "More", "More", "SugarOverload" ) )
	Assert:False( Storage.Data.MoreCake.More.More.More.SugarOverload )

	Storage:Commit()

	Assert:True( Storage:GetAtPath( "MoreCake", "More", "More", "More", "SugarOverload" ) )
	Assert:True( Storage.Data.MoreCake.More.More.More.SugarOverload )

	-- Should have persisted after the Commit() call.
	Storage = GetTestStorage()
	Assert:True( Storage:GetAtPath( "MoreCake", "More", "More", "More", "SugarOverload" ) )
	Assert:True( Storage.Data.MoreCake.More.More.More.SugarOverload )
end )

UnitTest:Test( "Transaction rollback", function( Assert )
	local Storage = GetTestStorage()
	Storage:SetAtPath( false, "MoreCake", "More", "More", "More", "SugarOverload" )

	Storage:BeginTransaction()
	Storage:SetAtPath( true, "MoreCake", "More", "More", "More", "SugarOverload" )

	Assert:True( Storage:GetAtPath( "MoreCake", "More", "More", "More", "SugarOverload" ) )
	Assert:False( Storage.Data.MoreCake.More.More.More.SugarOverload )

	-- Rollback should not have committed anything.
	Storage:Rollback()
	Assert:False( Storage:GetAtPath( "MoreCake", "More", "More", "More", "SugarOverload" ) )
	Assert:False( Storage.Data.MoreCake.More.More.More.SugarOverload )
end )
