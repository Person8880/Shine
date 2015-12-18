--[[
	Server-side commands tests.
]]

local UnitTest = Shine.UnitTest
local ParamTypes = Shine.CommandUtil.ParamTypes
local NotifyCommandError = Shine.NotifyCommandError

UnitTest:Test( "GetCommandArg", function( Assert )
	local Failed
	local Parsed
	local Arg = { Type = "test" }

	local TestClient = {}

	ParamTypes.test = {
		Parse = function( Client, String, CurArg )
			Parsed = true

			Assert:Equals( TestClient, Client )
			Assert:Equals( "", String )
			Assert:Equals( Arg, CurArg )

			return nil, true
		end,
		OnFailedMatch = function( Client, CurArg, Extra )
			Failed = true
			Assert:Equals( TestClient, Client )
			Assert:Equals( Arg, CurArg )
			Assert:True( Extra )
		end
	}

	Shine.NotifyCommandError = function() end

	-- Parse fails, should call OnFailedMatch
	local Success, Result = Shine.CommandUtil:GetCommandArg( TestClient, "sh_test", "", Arg )
	Assert:Falsy( Success )
	Assert:True( Failed )
	Assert:True( Parsed )

	Parsed = nil
	Failed = nil
	local Validated
	ParamTypes.test.Parse = function( Client, String, CurArg )
		Parsed = true

		Assert:Equals( TestClient, Client )
		Assert:Equals( "", String )
		Assert:Equals( Arg, CurArg )

		return true
	end
	ParamTypes.test.Validate = function( Client, CurArg, Result )
		Validated = true
		Assert:Equals( TestClient, Client )
		Assert:Equals( Arg, CurArg )
		Assert:True( Result )
		return false
	end

	-- Parse succeeds, but validation fails. Should return a non-successful result.
	Success, Result = Shine.CommandUtil:GetCommandArg( TestClient, "sh_test", "", Arg )
	Assert:Falsy( Success )
	Assert:Nil( Failed )
	Assert:True( Parsed )
	Assert:True( Validated )

	Parsed = nil
	Failed = nil
	Validated = nil
	ParamTypes.test.Validate = function( Client, CurArg, Result )
		Validated = true
		Assert:Equals( TestClient, Client )
		Assert:Equals( Arg, CurArg )
		Assert:True( Result )
		return true
	end

	-- Parse and validation succeed, so should return a success result and the parsed value.
	Success, Result = Shine.CommandUtil:GetCommandArg( TestClient, "sh_test", "", Arg )
	Assert:True( Success )
	Assert:True( Result )
	Assert:Nil( Failed )
	Assert:True( Parsed )
	Assert:True( Validated )
end, function()
	Shine.NotifyCommandError = NotifyCommandError
	ParamTypes.test = nil
end )
