--[[
	Handles external API endpoints, such as the Steam API.
]]

local Shine = Shine

local OSTime = os.time
local StringFormat = string.format
local tostring = tostring

local APIs = {
	Steam = {
		URL = "http://api.steampowered.com/",
		Params = {
			APIKey = tostring
		},
		GlobalRequestParams = {},
		EndPoints = {
			-- Determines if a player is playing with a family shared account.
			-- Callback returns the NS2ID of the player sharing the game, or false if the player owns the game.
			IsPlayingSharedGame = {
				Protocol = "GET",
				URL = "IPlayerService/IsPlayingSharedGame/v0001/?key={APIKey}&steamid={SteamID}&appid_playing=4920&format=json",
				Params = {
					SteamID = Shine.NS2IDTo64
				},
				GetCacheKey = function( Params ) return tostring( Params.SteamID ) end,
				ResponseTransformer = function( Response )
					-- Do not cache on invalid JSON.
					if not Response then return nil end

					local Lender = Response.lender_steamid
					if not Lender or Lender == "0" then return false end

					return Shine.SteamID64ToNS2ID( Lender )
				end
			}
		}
	}
}

local APICallers = {}

--[[
	Registers an external API.

	Data should contain the following fields:
	- GlobalRequestParams: If provided, a table of parameters to use as defaults for all requests
	  under this API. Useful for a single global API key.
	- Params: If provided, a list of parameters that are always required, e.g. an API key.
	- URL: The base URL all endpoints start with.
]]
function Shine.RegisterExternalAPI( APIName, Data )
	APIs[ APIName ] = Data
end

do
	local Decode = json.decode
	local setmetatable = setmetatable
	local StringGSub = string.gsub

	--[[
		Registers an endpoint under the given API.

		Data should contain the following fields:
		- GetCacheKey: If provided, should be a function that returns a single string that
		  uniquely identifies the given request parameters.

		- Params: A table of functions which receive a single value, and return a string.
		  These will be used to convert the provided request parameters.

		- Protocol: The protocol the API requires, e.g. "GET" or "POST".

		- ResponseTransformer: A function that receives the JSON object from the response,
		  and should return a value representing the response.

		- URL: The path to append to the API's primary URL. Request parameters should be
		  placed using {Param}.
	]]
	local function RegisterEndPoint( APIName, EndPointName, Data )
		local APIData = APIs[ APIName ]
		if not APIData then
			error( "Attempted to register an endpoint before its API", 2 )
		end

		APIData[ EndPointName ] = Data
		APICallers[ APIName ] = APICallers[ APIName ] or {}

		local URL = APIData.URL..Data.URL
		local IsPOST = Data.Protocol == "POST"

		-- Inherit the base API definition's parameters automatically.
		setmetatable( Data.Params, { __index = APIData.Params } )

		APICallers[ APIName ][ EndPointName ] = function( RequestParams, Callbacks, Attempts )
			Attempts = Attempts or 1

			-- Inherit the base API definition's global request parameters (e.g. for an API key).
			setmetatable( RequestParams, { __index = APIData.GlobalRequestParams } )

			-- Parse the request parameters using the set converters.
			local RequestURL = StringGSub( URL, "{([^}]+)}", function( Match )
				if not RequestParams[ Match ] then
					error( StringFormat( "Missing request parameter: '%s'", Match ), 3 )
				end
				return Data.Params[ Match ]( RequestParams[ Match ] )
			end )

			-- Pass the transformed JSON response through to the OnSuccess callback.
			local OldOnSuccess = Callbacks.OnSuccess
			Callbacks.OnSuccess = function( Response )
				OldOnSuccess( Data.ResponseTransformer( Decode( Response ) ) )
			end

			if IsPOST then
				Shine.HTTPRequestWithRetry( RequestURL, Data.Protocol, RequestParams.POST, Callbacks, Attempts )
			else
				Shine.HTTPRequestWithRetry( RequestURL, Data.Protocol, Callbacks, Attempts )
			end
		end
	end
	Shine.RegisterExternalAPIEndPoint = RegisterEndPoint

	for APIName, APIData in pairs( APIs ) do
		for EndPointName, Data in pairs( APIData.EndPoints ) do
			RegisterEndPoint( APIName, EndPointName, Data )
		end
	end
end

local ExternalAPIHandler = {
	Cache = {},
	Queue = Shine.Queue()
}
Shine.ExternalAPIHandler = ExternalAPIHandler

-- Only cache to disk on the server, not the client.
if Server then
	local APICacheFile = "config://shine/ExternalAPICache.json"

	ExternalAPIHandler.CacheLifeTime = 60 * 60 * 24

	function ExternalAPIHandler:SaveCache()
		Shine.SaveJSONFile( self.Cache, APICacheFile )
	end

	-- Delete any cached responses older than the cache life time.
	local function TrimCache( Cache )
		local Time = OSTime()

		-- Horrible nested loops, but it's only run once on startup.
		for APIName, EndPointCaches in pairs( Cache ) do
			for EndPointName, EndPointCache in pairs( EndPointCaches ) do
				for CacheKey, CacheEntry in pairs( EndPointCache ) do
					if CacheEntry.ExpiryTime < Time then
						EndPointCache[ CacheKey ] = nil
					end
				end

				if not next( EndPointCache ) then
					EndPointCaches[ EndPointName ] = nil
				end
			end

			if not next( EndPointCaches ) then
				Cache[ APIName ] = nil
			end
		end
	end

	Shine.Hook.Add( "PostloadConfig", "ExternalAPIHandlerCache", function()
		ExternalAPIHandler.Cache = Shine.LoadJSONFile( APICacheFile ) or ExternalAPIHandler.Cache
		TrimCache( ExternalAPIHandler.Cache )

		for Name, Key in pairs( Shine.Config.APIKeys ) do
			if Key ~= "" and APIs[ Name ] and APIs[ Name ].GlobalRequestParams then
				APIs[ Name ].GlobalRequestParams.APIKey = Key
			end
		end
	end )

	Shine.Hook.Add( "MapChange", "ExternalAPIHandlerCache", function()
		ExternalAPIHandler:SaveCache()
	end )
end

--[[
	Returns the requested API definition, if it exists.
]]
function ExternalAPIHandler:GetAPI( APIName )
	return APIs[ APIName ]
end

--[[
	Returns true if the given API has an "APIKey" global request parameter stored.
]]
function ExternalAPIHandler:HasAPIKey( APIName )
	local APIData = APIs[ APIName ]
	if not APIData then return false end

	return ( APIData.GlobalRequestParams and APIData.GlobalRequestParams.APIKey ) ~= nil
end

--[[
	Returns the requested endpoint definition, if it exists.
]]
function ExternalAPIHandler:GetEndPoint( APIName, EndPointName )
	return APIs[ APIName ] and APIs[ APIName ][ EndPointName ]
end

--[[
	Internal function, throws an error if the given API and endpoint do not exist.
]]
function ExternalAPIHandler:VerifyEndPoint( APIName, EndPointName )
	local EndPoint = self:GetEndPoint( APIName, EndPointName )
	if not EndPoint then
		error( StringFormat( "Attempted to use a non-existent API endpoint (%s.%s)", APIName, EndPointName ), 3 )
	end
	return EndPoint
end

--[[
	Returns the value cached for the given API, endpoint and request parameters.
	This will be nil if no value is stored.
]]
function ExternalAPIHandler:GetCachedValue( APIName, EndPointName, Params )
	local EndPoint = self:VerifyEndPoint( APIName, EndPointName )

	-- Endpoints decide how their parameters should map in the cache (if at all).
	local CacheKey = EndPoint.GetCacheKey and EndPoint.GetCacheKey( Params )
	local EndPointCache = self.Cache[ APIName ] and self.Cache[ APIName ][ EndPointName ]
	if not EndPointCache or CacheKey == nil then
		return nil
	end

	-- Refresh the expiry time on access.
	local CacheEntry = EndPointCache[ CacheKey ]
	if CacheEntry then
		CacheEntry.ExpiryTime = OSTime() + self.CacheLifeTime
	end

	return CacheEntry and CacheEntry.Value
end

do
	local OnError = Shine.BuildErrorHandler( "External API callback error" )
	local TableBuild = table.Build
	local unpack = unpack
	local xpcall = xpcall

	function ExternalAPIHandler:AddToCache( APIName, EndPointName, Params, Result )
		local EndPoint = self:GetEndPoint( APIName, EndPointName )
		local CacheKey = EndPoint.GetCacheKey and EndPoint.GetCacheKey( Params )
		if CacheKey == nil then return end

		local Cached = TableBuild( self.Cache, APIName, EndPointName )
		Cached[ CacheKey ] = {
			Value = Result,
			ExpiryTime = OSTime() + self.CacheLifeTime
		}
	end

	--[[
		Performs a request to a registered external API URL.

		Inputs:
			1. APIName - The name of the API.
			2. EndPointName - The name of the endpoint under the API.
			3. Params - The request parameters, endpoint dependent. If the endpoint uses the
			   "POST" protocol, then add a sub-table under Params.POST to set the POST request values.
			4. Callbacks - A table containing functions "OnSuccess", "OnFailure" and
			   optionally "OnTimeout". "OnSuccess" receives the response from the API (transformed by
			   the endpoint definition).
			5. Attempts - Optional maximum number of retry attempts, defaults to only 1 attempt.
	]]
	function ExternalAPIHandler:PerformRequest( APIName, EndPointName, Params, Callbacks, Attempts )
		local EndPoint = self:VerifyEndPoint( APIName, EndPointName )
		local Caller = APICallers[ APIName ][ EndPointName ]

		-- Cache the result and advance the queue on success.
		local OldOnSuccess = Callbacks.OnSuccess
		Callbacks.OnSuccess = function( Result )
			self:AddToCache( APIName, EndPointName, Params, Result )

			xpcall( OldOnSuccess, OnError, Result )

			self:ProcessQueue()
		end

		-- Advance the queue on failure.
		local OldOnFailure = Callbacks.OnFailure
		Callbacks.OnFailure = function()
			xpcall( OldOnFailure, OnError )

			self:ProcessQueue()
		end

		self.Queue:Add( {
			Caller = Caller,
			Args = { Params, Callbacks, Attempts }
		} )

		-- Waiting on previous request(s) to finish.
		if self.Queue:GetCount() > 1 then return end

		self:ProcessQueue()
	end

	local OnQueueError = Shine.BuildErrorHandler( "External API call error" )

	--[[
		Internal function, do not call. This is called automatically as requests
		are added and satisfied.

		Advances the request queue, if there are still requests pending.
	]]
	function ExternalAPIHandler:ProcessQueue()
		local Queued = self.Queue:Pop()
		if not Queued then return end

		-- If the function fails, skip it and go to the next entry.
		local Success = xpcall( Queued.Caller, OnQueueError, unpack( Queued.Args ) )
		if not Success then
			self:ProcessQueue()
		end
	end
end
