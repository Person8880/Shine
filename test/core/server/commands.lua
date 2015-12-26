--[[
	Server-side commands tests.
]]

local UnitTest = Shine.UnitTest
local ParamTypes = Shine.CommandUtil.ParamTypes
local NotifyCommandError = Shine.NotifyCommandError

Shine.NotifyCommandError = function() end

UnitTest:Test( "AdjustArguments", function( Assert )
	local Args = {
		"sh_test", "\"this", "is", "a", "single", "argument\"", "this", "isn't",
		"\"this", "is", "\\\"and", "this", "is", "escaped\\\"", "end\"",
		"\"this came from the console\"",
		"\"this", "is", "an", "unfinished", "quote", "at", "the", "end"
	}

	local CommandArguments = Shine.CommandUtil.AdjustArguments( Args )
	Assert:ArrayEquals( {
		"sh_test", "this is a single argument", "this", "isn't",
		"this is \"and this is escaped\" end",
		"this came from the console",
		"this is an unfinished quote at the end"
	}, CommandArguments )
end )

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
	ParamTypes.test = nil
end )

local GetPermission = Shine.GetPermission

UnitTest:Test( "Validate", function( Assert )
	local Client = {}
	local ConCommand = "sh_test"
	local Result = "cake"
	local MatchedType = "string"
	local i = 1
	local CurArg = { Type = "string" }

	Shine.GetPermission = function()
		return true
	end

	local Success, NewResult = Shine.CommandUtil:Validate( Client, ConCommand, Result, MatchedType, CurArg, i )
	Assert:True( Success )
	Assert:Nil( NewResult )

	Shine.GetPermission = function()
		return true, {
			[ "1" ] = "cake"
		}
	end

	Success, NewResult = Shine.CommandUtil:Validate( Client, ConCommand, Result, MatchedType, CurArg, i )
	Assert:True( Success )
	Assert:Equals( Result, NewResult )

	Result = "not cake"

	Success, NewResult = Shine.CommandUtil:Validate( Client, ConCommand, Result, MatchedType, CurArg, i )
	Assert:False( Success )
	Assert:Nil( NewResult )
end )

local GetAllClients = Shine.GetAllClients
local ClientsParamType = Shine.CommandUtil.ParamTypes.clients
local ControlCharacters = ClientsParamType.ControlCharacters

UnitTest:Test( "ClientsParse", function( Assert )
	ControlCharacters[ "&" ] = {
		Parse = function( Client, Context )
			local Value = tonumber( Context.Value )
			Assert:NotNil( Value )

			if Value > 0 and Value <= Context.NumClients then
				return { Value }
			end
			return nil
		end
	}

	function Shine.GetAllClients()
		return { 1, 2, 3, 4 }, 4
	end

	local Arg = { Type = "clients" }

	local function ParseString( Client, String, Table )
		local Results = ClientsParamType.Parse( Client, String, Table )
		table.sort( Results )
		return Results
	end

	Assert:ArrayEquals( { 1, 3, 4 }, ParseString( 2, "!^", Arg ) )
	Assert:ArrayEquals( { 1, 4 }, ParseString( 2, "!^,!&3", Arg ) )
	Assert:ArrayEquals( { 1, 2, 3, 4 }, ParseString( 2, "*,!&24", Arg ) )

	Assert:ArrayEquals( { 1, 2, 3, 4 }, ParseString( 2, "*", Arg ) )
	Assert:ArrayEquals( {}, ParseString( 2, "*blah", Arg ) )
	Assert:ArrayEquals( { 2, 3, 4 }, ParseString( 2, "&3,&4,^", Arg ) )
	Assert:ArrayEquals( { 3, 4 }, ParseString( 2, "&3,&4,&24", Arg ) )
end, function()
	ControlCharacters[ "&" ] = nil
end )

Shine.GetAllClients = GetAllClients
Shine.GetPermission = GetPermission
Shine.NotifyCommandError = NotifyCommandError
