--[[
	A file for hotfixing issues that annoy me.
]]

local Shine = Shine
local Hotfixes

if Server then
	-- Server hotfixes
	Hotfixes = {
		[ "lua/bots/Bot.lua" ] = {
			Hotfix = function()
				local function ValidClientFilter( Bot )
					return Shine:IsValidClient( Bot.client )
				end

				local OldDisconnect
				OldDisconnect = Shine.ReplaceClassMethod( "Bot", "Disconnect", function( self )
					-- Get rid of bots whose client has disconnected so it doesn't script error
					-- getting their ID and break team swapping...
					Shine.Stream( gServerBots ):Filter( ValidClientFilter )

					-- Make sure this bot has a valid client too.
					if not Shine:IsValidClient( self.client ) then return end

					return OldDisconnect( self )
				end )
			end,
			ShouldApply = function() return gServerBots ~= nil end
		}
	}
else
	-- Client hotfixes
end

if not Hotfixes then return end

for Name, HotfixData in pairs( Hotfixes ) do
	if HotfixData:ShouldApply() then
		HotfixData:Hotfix()
		Hotfixes[ Name ] = nil
	end
end

Shine.Hook.Add( "PostLoadScript", "HotfixNS2Bugs", function( ScriptName )
	local HotfixData = Hotfixes[ ScriptName ]
	if HotfixData and HotfixData:ShouldApply() then
		HotfixData:Hotfix()
	end
end )
