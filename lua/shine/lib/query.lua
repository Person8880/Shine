--[[
	Queries my PHP script for server info.
]]

local Encode, Decode = json.encode, json.decode
local HTTPRequest = Shared.SendHTTPRequest
local StringFormat = string.format
local Time = os.clock
local Timer = Shine.Timer
local tonumber = tonumber
local tostring = tostring

local BaseURL = "http://5.39.89.152/shine/serverquery.php"

--[[
	Query the state of a single server.
]]
function Shine.QueryServerPopulation( IP, Port, Callback )
	local Params = {
		servers = Encode( {
			{ ip = IP, port = tostring( Port ) }
		} )
	}
	HTTPRequest( BaseURL, "POST", Params, function( Body )
		if not Body or #Body == 0 then
			return Callback()
		end

		local Data = Decode( Body )

		if not Data or #Data == 0 then
			return Callback()
		end
		
		return Callback( Data[ 1 ].numberOfPlayers, Data[ 1 ].maxPlayers )
	end )
end

--[[
	Query the state of multiple servers.
]]
function Shine.QueryServers( Servers, Callback )
	local Params = {
		servers = Encode( Servers )
	}

	HTTPRequest( BaseURL, "POST", Params, function( Body )
		if not Body or #Body == 0 then
			return Callback()
		end

		local Data = Decode( Body )

		if not Data or #Data == 0 then
			return Callback()
		end

		return Callback( Data )
	end )
end

local DefaultTimeout = 5

--[[
	Performs a HTTP request that will call a timeout function
	if it takes too long to respond.

	Inputs:
		1. URL.
		2. Protocol, i.e "GET" or "POST".
		3. Params table for "POST".
		4. OnSuccess callback to run.
		5. OnTimeout callback to run.
		6. Optional timeout time, otherwise the timeout time is 5 seconds.
]]
function Shine.TimedHTTPRequest( URL, Protocol, Params, OnSuccess, OnTimeout, Timeout )
	local NeedParams = true

	if not OnTimeout then
		Timeout = OnTimeout
		OnTimeout = OnSuccess
		OnSuccess = Params
		NeedParams = false
	end

	Timeout = Timeout or DefaultTimeout
	
	local TimeoutTime = Time() + Timeout
	local Succeeded

	local function Callback( Data )
		if Time() > TimeoutTime then
			return
		end
		
		Succeeded = true

		OnSuccess( Data )
	end

	if NeedParams then
		HTTPRequest( URL, Protocol, Params, Callback )	
	else
		HTTPRequest( URL, Protocol, Callback )
	end
	
	Timer.Simple( Timeout, function()
		if not Succeeded then
			OnTimeout()
		end
	end )
end
