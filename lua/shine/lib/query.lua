--[[
	Queries my PHP script for server info.
]]

local Encode, Decode = json.encode, json.decode
local HTTPRequest = Shared.SendHTTPRequest
local StringFormat = string.format
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
