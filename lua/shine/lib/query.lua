--[[
	Handles various useful HTTP queries.
]]

local HTTPRequest = Shared.SendHTTPRequest
local IsType = Shine.IsType
local Time = Shared.GetSystemTimeReal
local Timer = Shine.Timer
local xpcall = xpcall

do
	local Encode, Decode = json.encode, json.decode
	local StringFormat = string.format
	local tostring = tostring

	local OnError = Shine.BuildErrorHandler( "Server query callback error" )

	local BaseURL = "http://51.68.206.223/shine/serverquery.php"

	local QueryCache = {}
	local function CallbackFailed( CacheKey, Callbacks )
		QueryCache[ CacheKey ] = { ExpireTime = Time() + 10 }

		for i = 1, #Callbacks do
			xpcall( Callbacks[ i ][ 1 ], OnError )
		end
	end

	local function CacheResult( CacheKey, Data )
		QueryCache[ CacheKey ] = { Data = Data, ExpireTime = Time() + 10 }
	end

	local function PopulationWrapper( Data, Callback )
		xpcall( Callback, OnError, Data[ 1 ].numberOfPlayers, Data[ 1 ].maxPlayers )
	end

	local function FullDataWrapper( Data, Callback )
		xpcall( Callback, OnError, Data[ 1 ] )
	end

	local function QueryServer( IP, Port, Callback, Wrapper )
		local CacheKey = StringFormat( "%s:%s", IP, Port )
		local Cache = QueryCache[ CacheKey ]

		if Cache and Cache.ExpireTime > Time() then
			local Data = Cache.Data
			-- Delay by a tick/frame to retain the asynchronous nature of the callback (avoids logic running before the
			-- function returns here).
			Timer.Simple( 0, function()
				if not Data then
					xpcall( Callback, OnError )
				else
					Wrapper( Data, Callback )
				end
			end )

			return true
		end

		if not Cache then
			Cache = { ExpireTime = 0 }
			QueryCache[ CacheKey ] = Cache
		end

		-- De-duplicate all attempts to query this IP + port until a response is received.
		Cache.Callbacks = Cache.Callbacks or {}
		Cache.Callbacks[ #Cache.Callbacks + 1 ] = { Callback, Wrapper }

		if #Cache.Callbacks == 1 then
			local Params = {
				servers = Encode( {
					{ ip = IP, port = tostring( Port ) }
				} )
			}

			local function OnFailure()
				CallbackFailed( CacheKey, Cache.Callbacks )
			end

			Shine.TimedHTTPRequest( BaseURL, "POST", Params, function( Body )
				local Data = Body and Decode( Body )
				if not IsType( Data, "table" ) or #Data == 0 then
					OnFailure()
					return
				end

				CacheResult( CacheKey, Data )

				for i = 1, #Cache.Callbacks do
					local CallbackData = Cache.Callbacks[ i ]
					local QueuedCallback = CallbackData[ 1 ]
					local Wrapper = CallbackData[ 2 ]
					Wrapper( Data, QueuedCallback )
				end
			end, OnFailure )
		end

		return false
	end

	--[[
		Query the state of a single server.

		Callback should have the following signature:
		function( NumPlayers, MaxPlayers )
			-- NumPlayers is the number of players on the server.
			-- MaxPlayers is the maximum number of players on the server (not accounting for reserved slots).
		end

		If the server status cannot be retrieved, the callback will be invoked with no arguments.

		Returns true if data has been previously retrieved and not yet expired, false if a new request was made.
	]]
	function Shine.QueryServerPopulation( IP, Port, Callback )
		Shine.TypeCheck( IP, "string", 1, "QueryServerPopulation" )
		Shine.TypeCheck( Port, { "number", "string" }, 2, "QueryServerPopulation" )
		Shine.AssertAtLevel( Shine.IsCallable( Callback ), "Callback must be callable!", 3 )

		return QueryServer( IP, Port, Callback, PopulationWrapper )
	end

	--[[
		Queries for the entire server data of a single server.

		Callback should have the following signature:
		function( Data )
			-- Data is a table with the following fields:
			-- "numberOfPlayers" - number of players on the server.
			-- "maxPlayers" - max players on the server (not accounting for reserved slots).
			-- "serverTags" - a "|" delimited string containing the tags for the server.
			-- Additional fields may be present, but should not be relied upon.
		end

		If the server status cannot be retrieved, the callback will be invoked with no arguments.

		Returns true if data has been previously retrieved and not yet expired, false if a new request was made.
	]]
	function Shine.QueryServer( IP, Port, Callback )
		Shine.TypeCheck( IP, "string", 1, "QueryServer" )
		Shine.TypeCheck( Port, { "number", "string" }, 2, "QueryServer" )
		Shine.AssertAtLevel( Shine.IsCallable( Callback ), "Callback must be callable!", 3 )

		return QueryServer( IP, Port, Callback, FullDataWrapper )
	end
end

local OnError = Shine.BuildErrorHandler( "HTTP request callback error" )
local DefaultTimeout = 5

--[[
	Performs a HTTP request that will call a timeout function if it takes too long to respond.

	Inputs:
		1. URL.
		2. Protocol, i.e "GET" or "POST".
		3. Params table for "POST".
		4. OnResponse callback to run (called on success, or if a network error occurs).
		5. OnTimeout callback to run (called if no response or error is returned within the given timeout).
		6. Optional timeout time, otherwise the timeout time is 5 seconds.
]]
function Shine.TimedHTTPRequest( URL, Protocol, Params, OnResponse, OnTimeout, Timeout )
	Shine.TypeCheck( URL, "string", 1, "TimedHTTPRequest" )
	Shine.TypeCheck( Protocol, "string", 2, "TimedHTTPRequest" )

	local NumParams = 6

	if Protocol ~= "POST" and not IsType( Params, "table" ) then
		Timeout = OnTimeout
		OnTimeout = OnResponse
		OnResponse = Params
		Params = nil
		NumParams = 5
	else
		Shine.TypeCheck( Params, "table", 3, "TimedHTTPRequest" )
	end

	Timeout = Timeout or DefaultTimeout

	Shine.AssertAtLevel( Shine.IsCallable( OnResponse ), "Response callback must be callable!", 3 )
	Shine.AssertAtLevel( Shine.IsCallable( OnTimeout ), "Timeout callback must be callable!", 3 )
	Shine.TypeCheck( Timeout, "number", NumParams, "TimedHTTPRequest" )

	local Succeeded
	local TimeoutTimer

	local function Callback( Data, ... )
		if Succeeded ~= nil then return end

		Succeeded = true

		if TimeoutTimer then
			TimeoutTimer:Destroy()
			TimeoutTimer = nil
		end

		xpcall( OnResponse, OnError, Data, ... )
	end

	if Params then
		HTTPRequest( URL, Protocol, Params, Callback )
	else
		HTTPRequest( URL, Protocol, Callback )
	end

	TimeoutTimer = Timer.Simple( Timeout, function()
		if Succeeded ~= nil then return end

		Succeeded = false

		xpcall( OnTimeout, OnError )
	end )
end

--[[
	Sends a request to a given URL, accounting for timeouts and retrying up to the given number of max attempts.

	Callbacks should be a table (or other indexable object) providing the following functions:
	{
		OnSuccess = function( Body, Err, ErrCode )
			-- Called when the request is completed, passed the response body. If the request fails due to a network
			-- error, the body will be an empty string, and a network error message and network error code will be
			-- provided. This is not ideal, but is maintained for backwards compatibility.
		end,
		OnTimeout = function( AttemptNumber )
			-- Called when the request times out on a given attempt (optional).
		end,
		OnFailure = function()
			-- Called when all attempts have failed due to timeouts (optional).
		end
	}
]]
function Shine.HTTPRequestWithRetry( URL, Protocol, Params, Callbacks, MaxAttempts, Timeout )
	Shine.TypeCheck( URL, "string", 1, "HTTPRequestWithRetry" )
	Shine.TypeCheck( Protocol, "string", 2, "HTTPRequestWithRetry" )

	local NumParams = 6

	if Protocol ~= "POST" and not IsType( Callbacks, "table" ) then
		Timeout = MaxAttempts
		MaxAttempts = Callbacks
		Callbacks = Params
		Params = nil
		NumParams = 5
	else
		Shine.TypeCheck( Params, "table", 3, "HTTPRequestWithRetry" )
	end

	MaxAttempts = MaxAttempts or 3

	Shine.TypeCheck( MaxAttempts, "number", NumParams - 1, "HTTPRequestWithRetry" )
	if Timeout then Shine.TypeCheck( Timeout, "number", NumParams, "HTTPRequestWithRetry" ) end

	local OnTimeoutCallback = Callbacks.OnTimeout
	local OnFailureCallback = Callbacks.OnFailure
	local OnSuccessCallback = Callbacks.OnSuccess

	Shine.AssertAtLevel( Shine.IsCallable( OnSuccessCallback ), "OnSuccess callback must be callable!", 3 )

	local Attempts = 0
	local Submit

	local function OnTimeout()
		Attempts = Attempts + 1

		if Shine.IsCallable( OnTimeoutCallback ) then
			OnTimeoutCallback( Attempts )
		end

		if Attempts >= MaxAttempts then
			if Shine.IsCallable( OnFailureCallback ) then
				OnFailureCallback()
			end
			return
		end

		Submit()
	end

	Submit = function()
		if Params then
			return Shine.TimedHTTPRequest( URL, Protocol, Params, OnSuccessCallback, OnTimeout, Timeout )
		end
		return Shine.TimedHTTPRequest( URL, Protocol, OnSuccessCallback, OnTimeout, Timeout )
	end

	return Submit()
end

Script.Load( "lua/shine/lib/external_apis.lua" )
