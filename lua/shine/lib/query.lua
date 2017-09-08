--[[
	Handles various useful HTTP queries.
]]

local HTTPRequest = Shared.SendHTTPRequest
local IsType = Shine.IsType
local Time = os.clock

do
	local Encode, Decode = json.encode, json.decode
	local StringFormat = string.format
	local tostring = tostring

	local BaseURL = "http://5.39.89.152/shine/serverquery.php"

	local QueryCache = {}
	local function CallbackFailed( CacheKey, Callback )
		QueryCache[ CacheKey ] = { Data = {}, ExpireTime = Time() + 10 }

		Callback()
	end

	local function CacheResult( CacheKey, Data )
		QueryCache[ CacheKey ] = { Data = Data, ExpireTime = Time() + 10 }
	end

	local function PopulationWrapper( Data, Callback )
		Callback( Data[ 1 ].numberOfPlayers, Data[ 1 ].maxPlayers )
	end

	local function FullDataWrapper( Data, Callback )
		Callback( Data[ 1 ] )
	end

	local function QueryServer( IP, Port, Callback, Wrapper )
		local CacheKey = StringFormat( "%s:%s", IP, Port )
		local Cache = QueryCache[ CacheKey ]

		if Cache and Cache.ExpireTime > Time() then
			local Data = Cache.Data

			if not Data[ 1 ] then
				Callback()

				return
			end

			Wrapper( Data, Callback )

			return
		end

		local Params = {
			servers = Encode( {
				{ ip = IP, port = tostring( Port ) }
			} )
		}

		HTTPRequest( BaseURL, "POST", Params, function( Body )
			if not Body or #Body == 0 then
				CallbackFailed( CacheKey, Callback )

				return
			end

			local Data = Decode( Body )

			if not IsType( Data, "table" ) or #Data == 0 then
				CallbackFailed( CacheKey, Callback )

				return
			end

			CacheResult( CacheKey, Data )

			Wrapper( Data, Callback )
		end )
	end

	--[[
		Query the state of a single server.
	]]
	function Shine.QueryServerPopulation( IP, Port, Callback )
		QueryServer( IP, Port, Callback, PopulationWrapper )
	end

	--[[
		Queries for the entire server data of a single server.
	]]
	function Shine.QueryServer( IP, Port, Callback )
		QueryServer( IP, Port, Callback, FullDataWrapper )
	end
end

local Timer = Shine.Timer

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

	if Protocol ~= "POST" and not IsType( Params, "table" ) then
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

--[[
	Sends a request to a given URL, accounting for timeouts and retrying up to the given
	number of max attempts.
]]
function Shine.HTTPRequestWithRetry( URL, Protocol, Params, Callbacks, MaxAttempts, Timeout )
	local NeedParams = true
	if Protocol ~= "POST" and not IsType( Callbacks, "table" ) then
		Timeout = MaxAttempts
		MaxAttempts = Callbacks
		Callbacks = Params
		NeedParams = false
	end

	MaxAttempts = MaxAttempts or 3

	local Attempts = 0
	local Submit

	local function OnTimeout()
		Attempts = Attempts + 1

		if Callbacks.OnTimeout then
			Callbacks.OnTimeout( Attempts )
		end

		if Attempts >= MaxAttempts then
			Callbacks.OnFailure()
			return
		end

		Submit()
	end

	Submit = function()
		if NeedParams then
			Shine.TimedHTTPRequest( URL, Protocol, Params, Callbacks.OnSuccess, OnTimeout, Timeout )
		else
			Shine.TimedHTTPRequest( URL, Protocol, Callbacks.OnSuccess, OnTimeout, Timeout )
		end
	end

	Submit()
end

Script.Load( "lua/shine/lib/external_apis.lua" )
