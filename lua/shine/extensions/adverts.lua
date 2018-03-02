--[[
	Shine adverts system.
]]

local Shine = Shine

local IsType = Shine.IsType
local setmetatable = setmetatable
local StringFormat = string.format
local StringUpper = string.upper
local TableQuickCopy = table.QuickCopy
local TableQuickShuffle = table.QuickShuffle
local TableRemove = table.remove
local tonumber = tonumber

local Plugin = {}
Plugin.Version = "1.2"
Plugin.PrintName = "Adverts"

Plugin.HasConfig = true
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.ConfigName = "Adverts.json"

Plugin.AdvertTrigger = table.AsEnum{
	"COUNTDOWN", "START_OF_ROUND", "END_OF_ROUND",
	"MARINE_VICTORY", "ALIEN_VICTORY", "DRAW"
}

Plugin.DefaultConfig = {
	Templates = {
		-- Defines named template adverts, allowing many adverts to share the
		-- same type/colour/prefix.
		ChatNotification = {
			Type = "chat",
			Colour = { 255, 255, 255 },
			Prefix = "[Info]",
			PrefixColour = { 0, 200, 255 }
		}
	},
	TriggeredAdverts = {
		--[[
		This would trigger a message at the start of a round (after the countdown).
		{
			Message = "Good luck and have fun!",
			Template = "ChatNotification",
			Trigger = "START_OF_ROUND"
		}
		]]
	},
	Adverts = {
		{
			Message = "Welcome to Natural Selection 2.",
			-- Template should match a key in the "Templates" table.
			Template = "ChatNotification"
		},
		{
			Message = "This server is running the Shine administration mod.",
			Template = "ChatNotification"
		}
	},
	Interval = 60,
	RandomiseOrder = false
}

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.2",
		Apply = function( Config )
			local Adverts = Config.Adverts
			if not IsType( Adverts, "table" ) then return end

			for i = 1, #Adverts do
				local Advert = Adverts[ i ]
				if IsType( Advert, "table" ) then
					Advert.Colour = { Advert.R or 255, Advert.G or 255, Advert.B or 255 }
					Advert.R = nil
					Advert.G = nil
					Advert.B = nil
				end
			end
		end
	}
}

Plugin.TimerName = "Adverts"

function Plugin:Initialise()
	-- If this is the first time loading, the map may not be available yet.
	if not self:IsFirstTimeLoaded() then
		self:ParseAdverts()
		self:SetupTimer()
	end

	self.Enabled = true

	return true
end

function Plugin:OnWebConfigReloaded()
	self:ParseAdverts()
	self:SetupTimer()
end

-- Wait for the map to be loaded before parsing to ensure we know what it is.
function Plugin:OnFirstThink()
	self:ParseAdverts()
	self:SetupTimer()
end

function Plugin:ParseAdverts()
	local CurrentMapName = Shared.GetMapName()

	local AdvertList = "Adverts"
	local function IsValidAdvert( Advert, Index )
		if not IsType( Advert, "string" ) and not IsType( Advert, "table" ) then
			self:Print( "%s[ %d ] is neither a string or a table.", true, AdvertList, Index )
			return false
		end

		if IsType( Advert, "table" ) and not IsType( Advert.Message, "string" ) then
			self:Print( "%s[ %d ] has a missing or non-string message.", true, AdvertList, Index )
			return false
		end

		return true
	end

	local function AssignTemplate( Advert )
		if not IsType( Advert, "table" ) then return Advert end

		local Template = self.Config.Templates[ Advert.Template ]

		if IsType( Template, "table" ) then
			-- Inherit values from the template.
			return setmetatable( Advert, { __index = Template } )
		end

		return Advert
	end

	self.RequiresGameStateFiltering = false

	local function IsValidForMap( Advert )
		if Advert.Maps then
			return Advert.Maps[ CurrentMapName ]
		end
		if Advert.ExcludedMaps then
			return not Advert.ExcludedMaps[ CurrentMapName ]
		end

		return true
	end

	-- Parse the list of cycling adverts, filtering out any that are invalid or not enabled
	-- for the current map.
	self.AdvertsList = Shine.Stream.Of( self.Config.Adverts )
		:Map( AssignTemplate )
		:Filter( IsValidAdvert )
		:Filter( function( Advert )
			if not IsType( Advert, "table" ) then return true end

			if Advert.GameState then
				self.RequiresGameStateFiltering = true
			end

			return IsValidForMap( Advert )
		end )
		:AsTable()

	-- Collect all adverts set to run on a given trigger.
	local TriggeredAdverts = self.Config.TriggeredAdverts
	local TriggeredAdvertsByTrigger = Shine.Multimap()

	AdvertList = "TriggeredAdverts"
	local function IsValidTriggerAdvert( Advert, Index )
		if not IsValidAdvert( Advert, Index ) then return false end

		if not IsType( Advert, "table" ) or not IsType( Advert.Trigger, "string" ) then
			self:Print( "%s[ %d ] must have a trigger defined.", true, AdvertList, Index )
			return false
		end

		return true
	end

	Shine.Stream.Of( self.Config.TriggeredAdverts )
		:Map( AssignTemplate )
		:Filter( IsValidTriggerAdvert )
		:Filter( IsValidForMap )
		:ForEach( function( Advert, Index )
			local TriggerName = StringUpper( Advert.Trigger )

			if self.AdvertTrigger[ TriggerName ] then
				TriggeredAdvertsByTrigger:Add( TriggerName, Advert )
			else
				self:Print( "%s[ %d ] has invalid trigger: %s",
					true, AdvertList, Index, TriggerName )
			end
		end )

	self.TriggeredAdvertsByTrigger = TriggeredAdvertsByTrigger
end

local function UnpackColour( Colour )
	if not Colour then return 255, 255, 255 end

	return tonumber( Colour[ 1 ] ) or 255,
		tonumber( Colour[ 2 ] ) or 255,
		tonumber( Colour[ 3 ] ) or 255
end

function Plugin:DisplayAdvert( Advert )
	if IsType( Advert, "string" ) then
		Shine:NotifyColour( nil, 255, 255, 255, Advert )
		return
	end

	local Message = Advert.Message
	local R, G, B = UnpackColour( Advert.Colour )
	local Type = Advert.Type

	if not Type or Type == "chat" then
		if IsType( Advert.Prefix, "string" ) then
			-- Send the advert with a coloured prefix.
			local PR, PG, PB = UnpackColour( Advert.PrefixColour or { 255, 255, 255 } )

 			Shine:NotifyDualColour( nil, PR, PG, PB, Advert.Prefix, R, G, B, Message )

 			return
		end

		Shine:NotifyColour( nil, R, G, B, Message )
	else
		local Position = ( Advert.Position or "top" ):lower()

		local X, Y = 0.5, 0.2
		local Align = 1

		if Position == "bottom" then
			X, Y = 0.5, 0.8
		end

		Shine.ScreenText.Add( 20, {
			X = X, Y = Y,
			Text = Message,
			Duration = 7,
			R = R, G = G, B = B,
			Alignment = Align,
			Size = 2, FadeIn = 1
		} )
	end
end

-- Enums error when accessing a field that is not present...
local SafeGameStateLookup = {}
for i = 1, #kGameState do
	SafeGameStateLookup[ kGameState[ i ] ] = i
end

--[[
	Filters the current advert list to those that are valid for the given
	game state.

	Returns the filtered list, and a boolean to indicate if any have been filtered
	out.
]]
function Plugin:FilterAdvertListForState( Adverts, CurrentAdverts, GameState )
	local function IsGameState( GameStateName )
		return SafeGameStateLookup[ GameStateName ] == GameState
	end

	local function IsValidForGameState( Advert )
		if not Advert.GameState then return true end

		if IsType( Advert.GameState, "table" ) then
			for i = 1, #Advert.GameState do
				if IsGameState( Advert.GameState[ i ] ) then
					return true
				end
			end
		end

		return IsGameState( Advert.GameState )
	end

	local OutputAdverts = {}
	local HasChanged = false
	for i = 1, #Adverts do
		if IsValidForGameState( Adverts[ i ] ) then
			local Index = #OutputAdverts + 1
			OutputAdverts[ Index ] = Adverts[ i ]
			if OutputAdverts[ Index ] ~= CurrentAdverts[ Index ] then
				HasChanged = true
			end
		end
	end

	if #OutputAdverts ~= #CurrentAdverts then
		HasChanged = true
	end

	return OutputAdverts, HasChanged
end

local StateToTrigger = Shine.Multimap( {
	[ kGameState.Countdown ] = { Plugin.AdvertTrigger.COUNTDOWN },
	[ kGameState.Started ] = { Plugin.AdvertTrigger.START_OF_ROUND },
	[ kGameState.Team1Won ] = {
		Plugin.AdvertTrigger.END_OF_ROUND,
		Plugin.AdvertTrigger.MARINE_VICTORY
	},
	[ kGameState.Team2Won ] = {
		Plugin.AdvertTrigger.END_OF_ROUND,
		Plugin.AdvertTrigger.ALIEN_VICTORY
	},
	[ kGameState.Draw ] = {
		Plugin.AdvertTrigger.END_OF_ROUND,
		Plugin.AdvertTrigger.DRAW
	}
} )
--[[
	Gets the apprioriate trigger name for the given game state.
]]
function Plugin:GetTriggerNamesForGameState( GameState )
	return StateToTrigger:Get( GameState )
end

--[[
	Changes the current advert list based on the new game state, and triggers any
	triggered adverts.
]]
function Plugin:SetGameState( Gamerules, NewState, OldState )
	if self.RequiresGameStateFiltering then
		local NewAdverts, HasListChanged = self:FilterAdvertListForState( self.AdvertsList,
			self.CurrentAdvertsList or self.AdvertsList, NewState )
		if HasListChanged then
			-- Reset the advert list to the newly filtered version.
			self.CurrentMessageIndex = 1
			self.CurrentAdvertsList = NewAdverts
		end
	end

	local Triggers = self:GetTriggerNamesForGameState( NewState )
	if not Triggers then return end

	for i = 1, #Triggers do
		local Adverts = self.TriggeredAdvertsByTrigger:Get( Triggers[ i ] )
		if Adverts then
			for j = 1, #Adverts do
				self:DisplayAdvert( Adverts[ j ] )
			end
		end
	end
end

function Plugin:SetupTimer()
	if self:TimerExists( self.TimerName ) then
		self:DestroyTimer( self.TimerName )
	end

	if #self.AdvertsList == 0 then return end

	self.CurrentMessageIndex = 1
	if self.RequiresGameStateFiltering then
		local Gamerules = GetGamerules()
		local GameState = Gamerules and Gamerules:GetGameState() or kGameState.NotStarted
		-- Make sure to filter down to the right list of adverts now.
		self.CurrentAdvertsList = self:FilterAdvertListForState( self.AdvertsList,
			self.AdvertsList, GameState )
	else
		self.CurrentAdvertsList = self.AdvertsList
	end

	self:CreateTimer( self.TimerName, self.Config.Interval, -1, function()
		local Message = self.CurrentMessageIndex
		-- Back to the start, randomise the order again.
		if Message == 1 and self.Config.RandomiseOrder then
			TableQuickShuffle( self.CurrentAdvertsList )
		end

		self:DisplayAdvert( self.CurrentAdvertsList[ Message ] )
		self.CurrentMessageIndex = ( Message % #self.CurrentAdvertsList ) + 1
	end )
end

Shine:RegisterExtension( "adverts", Plugin )
