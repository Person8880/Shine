--[[
	Facilitates querying of gameserverdirectory.com for player info.

	There's no public API for game server querying that I can find, so this HTML page reading hack will have to do.
]]

local HTTPRequest = Shared.SendHTTPRequest
local StringFormat = string.format
local tonumber = tonumber

local BaseURL = "http://www.gameserverdirectory.com/server/"
local Match = [[<td class="infohead" nowrap>Players:</td>]]

function Shine.QueryServerPopulation( IP, Port, Callback )
	local URL = StringFormat( "%s%s:%s", BaseURL, IP, Port )

	HTTPRequest( URL, "GET", function( Body )
		if not Body or #Body == 0 then
			return Callback()
		end

		local Start, End = Body:find( Match )

		if not Start then return end

		Body = Body:sub( End )

		Start, End = Body:find( "(%d+)%s/%s(%d+)" )

		if not Start then
			return Callback()
		end

		local Data = Body:sub( Start, End )

		local Num = Data:sub( 1, 2 ):gsub( " ", "" )
		local Max = Data:sub( 3 ):gsub( "[^%d]", "" )
		
		return Callback( tonumber( Num ), tonumber( Max ) )
	end )
end
