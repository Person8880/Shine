--[[
	Provides a basic means of tracking whether a given player ID has been processed across map changes.
]]

local Plugin = ... or _G.Plugin

local Module = {}

function Module:Initialise()
	self.RememberedPlayers = Shine.LoadJSONFile( self.PlayerMemoryFilePath ) or {}
	self.RememberedPlayersNeedSaving = false
end

function Module:GetRememberedPlayerIDs()
	return self.RememberedPlayers
end

function Module:IsPlayerIDRemembered( ID )
	return self:GetRememberedPlayerIDs()[ ID ]
end

function Module:RememberPlayerID( ID )
	local RememberedPlayers = self:GetRememberedPlayerIDs()
	if not RememberedPlayers[ ID ] then
		-- Remember the player but defer saving until later. It's less important if an action is repeated.
		RememberedPlayers[ ID ] = true
		self.RememberedPlayersNeedSaving = true
	end
end

function Module:ForgetPlayerID( ID )
	local RememberedPlayers = self:GetRememberedPlayerIDs()
	if RememberedPlayers[ ID ] then
		RememberedPlayers[ ID ] = nil
		-- Save the state on remove to ensure the associated action is performed again on next connect.
		self:SaveRememberedPlayers()
	end
end

function Module:SaveRememberedPlayers()
	Shine.SaveJSONFile( self.RememberedPlayers, self.PlayerMemoryFilePath )
	self.RememberedPlayersNeedSaving = false
end

function Module:MapChange()
	-- Clear out any players that never connected during this map.
	local ConnectedIDs = {}
	for Client in Shine.IterateClients() do
		ConnectedIDs[ tostring( Client:GetUserId() ) ] = true
	end

	local RememberedPlayers = self:GetRememberedPlayerIDs()
	for ID in pairs( RememberedPlayers ) do
		if not ConnectedIDs[ ID ] then
			self.RememberedPlayersNeedSaving = true
			RememberedPlayers[ ID ] = nil
		end
	end

	if self.RememberedPlayersNeedSaving then
		self:SaveRememberedPlayers()
	end
end

Plugin:AddModule( Module )
