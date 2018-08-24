--[[
	Shine adverts system.
]]

local Shine = Shine

local IsType = Shine.IsType
local Max = math.max
local OSDate = os.date
local OSTime = os.time
local StringFormat = string.format
local StringInterpolate = string.Interpolate
local StringMatch = string.match
local StringParseLocalDateTime = string.ParseLocalDateTime
local StringUpper = string.upper
local TableAdd = table.Add
local TableAsSet = table.AsSet
local TableRemove = table.remove
local TableShallowCopy = table.ShallowCopy
local TableShallowMerge = table.ShallowMerge
local tonumber = tonumber

local Plugin = {}
Plugin.Version = "2.2"
Plugin.PrintName = "Adverts"

Plugin.HasConfig = true
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.ConfigName = "Adverts.json"

Plugin.AdvertTrigger = table.AsEnum{
	-- Game state events
	"COUNTDOWN",
	"START_OF_ROUND",
	"END_OF_ROUND",
	"MARINE_VICTORY",
	"ALIEN_VICTORY",
	"DRAW",

	-- Commander events
	"COMMANDER_LOGGED_IN",
	"MARINE_COMMANDER_LOGGED_IN",
	"ALIEN_COMMANDER_LOGGED_IN",
	"COMMANDER_LOGGED_OUT",
	"MARINE_COMMANDER_LOGGED_OUT",
	"ALIEN_COMMANDER_LOGGED_OUT",
	"COMMANDER_EJECTED",
	"MARINE_COMMANDER_EJECTED",
	"ALIEN_COMMANDER_EJECTED",

	-- Misc. events
	"STARTUP",
	"SYSTEM_TIME"
}
Plugin.TeamType = table.AsEnum{
	"MARINE", "ALIEN", "READY_ROOM", "SPECTATOR"
}
Plugin.TeamTypeToTeamNumber = {
	[ Plugin.TeamType.MARINE ] = kTeam1Index,
	[ Plugin.TeamType.ALIEN ] = kTeam2Index,
	[ Plugin.TeamType.READY_ROOM ] = kTeamReadyRoom,
	[ Plugin.TeamType.SPECTATOR ] = kSpectatorIndex
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
		START_OF_ROUND = {
			{
				Message = "Good luck and have fun!",
				Template = "ChatNotification"
			}
		}
		Multiple triggered adverts for the same trigger will display at the same time in the
		order specified in this list.
		]]
	},
	-- A list of advert "streams". Each stream has its own internal timing and ordering,
	-- and can run concurrently with other streams.
	-- This allows setting up various adverts on different intervals or for different teams.
	Adverts = {
		{
			Messages = {
				{
					Message = "Welcome to Natural Selection 2."
				},
				{
					Message = "This server is running the Shine administration mod."
				}
			},
			-- Default delay for messages. Each message may specify DelayInSeconds to change this.
			IntervalInSeconds = 60,
			RandomiseOrder = false,
			-- Templates should match a key in the "Templates" table.
			-- This sets the default for all messages in the stream, but individual messages
			-- may use their own templates too.
			DefaultTemplate = "ChatNotification"
		}
	}
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
	},
	{
		VersionTo = "2.0",
		Apply = function( Config )
			local Adverts = Config.Adverts
			if not IsType( Adverts, "table" ) then return end

			if IsType( Config.TriggeredAdverts, "table" ) then
				local TriggersByName = Shine.Multimap()
				for i = 1, #Config.TriggeredAdverts do
					local Advert = Config.TriggeredAdverts[ i ]

					if IsType( Advert, "table" ) and IsType( Advert.Trigger, "string" ) then
						TriggersByName:Add( Advert.Trigger, Advert )
						Advert.Trigger = nil
					end
				end
				Config.TriggeredAdverts = TriggersByName:AsTable()
			end

			local NewAdvertsList = {
				{
					Messages = Adverts,
					IntervalInSeconds = tonumber( Config.Interval ) or 60,
					RandomiseOrder = Config.RandomiseOrder
				}
			}
			Config.Adverts = NewAdvertsList
			Config.Interval = nil
			Config.RandomiseOrder = nil
		end
	}
}

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	-- If this is the first time loading, the map may not be available yet.
	if not self:IsFirstTimeLoaded() then
		self:ParseAndStartAdverts()
	end

	self.Enabled = true

	return true
end

function Plugin:ParseAndStartAdverts()
	self:ParseAdverts()
	self:StartStreams()
end

function Plugin:OnWebConfigReloaded()
	self:ParseAndStartAdverts()
end

-- Wait for the map to be loaded before parsing to ensure we know what it is.
function Plugin:OnFirstThink()
	self:ParseAndStartAdverts()
end

local AdvertStream = require "shine/extensions/adverts/advert_stream"
local ONE_DAY = 60 * 60 * 24
local TRIGGER_CHECK_INTERVAL = 60

function Plugin:SetupSystemTimeTriggerCheck()
	local PendingTriggers = self.PendingTriggers
	if PendingTriggers then return PendingTriggers end

	local PendingTriggers = {}
	self.PendingTriggers = PendingTriggers

	self:CreateTimer( "PendingTriggerCheck", TRIGGER_CHECK_INTERVAL, -1, function()
		local Now = OSTime()

		for i = #PendingTriggers, 1, -1 do
			local Trigger = PendingTriggers[ i ]
			local TimeTillTrigger = Max( Trigger.Timestamp - Now, 0 )

			if TimeTillTrigger <= TRIGGER_CHECK_INTERVAL then
				self.Logger:Debug( "Setting up timer for %s with delay of %d seconds",
					Trigger.Source, TimeTillTrigger )

				self:SimpleTimer( TimeTillTrigger, function()
					Trigger.Action()

					if not Trigger.IsDateTime then
						-- If it's supposed to trigger every day, queue it up again.
						Trigger.Timestamp = Trigger.Timestamp + ONE_DAY
						PendingTriggers[ #PendingTriggers + 1 ] = Trigger
						self.Logger:Debug( "Queued %s to next trigger tomorrow.",
							Trigger.Source )
					end
				end )

				TableRemove( PendingTriggers, i )
			end
		end
	end )

	return PendingTriggers
end

Plugin.TriggerHandlers = {
	[ Plugin.AdvertTrigger.SYSTEM_TIME ] = function( self, Source, Config, Action )
		if not IsType( Config, "table" ) or not IsType( Config.TriggerTimes, "table" ) then
			self:Print( "Misconfigured system time trigger for %s, expected TriggerTimes list.", true, Source )
			return
		end

		local PendingTriggers = self:SetupSystemTimeTriggerCheck()
		local Now = OSTime()

		local function ParseTriggerTime( Time )
			-- Expect dates formatted as 'YYYY-MM-ddTHH:mm:ss' and times as 'HH:mm:ss'
			local Timestamp, IsDateTime = StringParseLocalDateTime( Time )
			if not Timestamp then
				self:Print( "'%s' is not a valid time expression.", true, Time )
				return
			end

			if Timestamp < Now then
				if IsDateTime then
					self.Logger:Debug( "%s (%s) is in the past, skipping.", Time, Source )
					return
				end

				-- Move forward by one day if we've missed today's execution.
				Timestamp = Timestamp + ONE_DAY
			end

			local TimeTillTrigger = Timestamp - Now
			self.Logger:Debug( "%s will trigger in %d seconds (%s)", Source, TimeTillTrigger, Time )

			if TimeTillTrigger > TRIGGER_CHECK_INTERVAL then
				self.Logger:Debug( "Adding %s to pending triggers list.", Source )
				-- If the trigger time is too far away, don't add a timer yet.
				PendingTriggers[ #PendingTriggers + 1 ] = {
					Timestamp = Timestamp,
					Action = Action,
					Source = Source,
					IsDateTime = IsDateTime
				}
			else
				self.Logger:Debug( "Starting timer for %s with delay of %d seconds.",
					Source, TimeTillTrigger )
				-- Run the next time the given time is hit.
				self:SimpleTimer( TimeTillTrigger, Action )
			end
		end

		for i = 1, #Config.TriggerTimes do
			ParseTriggerTime( Config.TriggerTimes[ i ] )
		end
	end
}

function Plugin:ParseAdverts()
	local CurrentMapName = Shared.GetMapName()

	local AdvertList
	local function IsValidAdvert( Advert, Index )
		if not IsType( Advert, "string" ) and not IsType( Advert, "table" ) then
			self:Print( "%s[ %d ] is neither a string or a table.", true, AdvertList, Index )
			return false
		end

		if IsType( Advert, "table" ) then
			if not IsType( Advert.Message, "string" ) then
				self:Print( "%s[ %d ] has a missing or non-string message.", true, AdvertList, Index )
				return false
			end

			if Advert.Team ~= nil then
				local TeamType = type( Advert.Team )
				if TeamType ~= "string" and TeamType ~= "table" then
					self:Print( "%s[ %d ] has an invalid team filter. Must be a single team or list of teams.",
						true, AdvertList, Index )
					return false
				end

				if TeamType == "string" then
					Advert.Team = StringUpper( Advert.Team )
					if not self.TeamType[ Advert.Team ] then
						self:Print( "%s[ %d ] has an invalid team filter.",
							true, AdvertList, Index )
						return false
					end
				else
					for i = 1, #Advert.Team do
						if not IsType( Advert.Team[ i ], "string" ) then
							self:Print( "%s[ %d ] has an invalid team filter at index %d.",
								true, AdvertList, Index, i )
							return false
						end

						Advert.Team[ i ] = StringUpper( Advert.Team[ i ] )
						if not self.TeamType[ Advert.Team[ i ] ] then
							self:Print( "%s[ %d ] has an invalid team filter at index %d.",
								true, AdvertList, Index, i )
							return false
						end
					end
				end
			end
		end

		if Advert.DelayInSeconds ~= nil then
			if not IsType( Advert.DelayInSeconds, "number" ) or Advert.DelayInSeconds < 0 then
				self:Print( "%s[ %d ] has an invalid delay. Must be a non-negative number.",
					true, AdvertList, Index )
				return false
			end
		end

		return true
	end

	local function AssignTemplate( Advert )
		if not IsType( Advert, "table" ) then return Advert end

		local Templates = Advert.Template
		if IsType( Templates, "string" ) then
			Templates = { Templates }
		elseif not IsType( Templates, "table" ) then
			return Advert
		end

		local TemplatedAdvert = TableShallowCopy( Advert )

		for i = 1, #Templates do
			local Template = self.Config.Templates[ Templates[ i ] ]

			if IsType( Template, "table" ) then
				-- Inherit values from the template.
				TableShallowMerge( Template, TemplatedAdvert )
			end
		end

		return TemplatedAdvert
	end

	local function IsValidForMap( Advert )
		if Advert.Maps then
			return Advert.Maps[ CurrentMapName ]
		end
		if Advert.ExcludedMaps then
			return not Advert.ExcludedMaps[ CurrentMapName ]
		end

		return true
	end

	local AdvertStreams = {}

	-- Collect streams that are triggered, and those that need game state filtering.
	local TriggeredAdvertStreams = Shine.Multimap()
	local GameStateFilteredStreams = {}
	local function AddTriggeredStream( Triggers, Stream, Source, TriggerConfig, Action )
		if not Triggers then return end
		for i = 1, #Triggers do
			local Trigger = Triggers[ i ]

			-- Apply special trigger handling if necessary, otherwise just store it.
			if self.TriggerHandlers[ Trigger ] then
				self.TriggerHandlers[ Trigger ]( self, Source,
					TriggerConfig and TriggerConfig[ Trigger ], Action )
			else
				TriggeredAdvertStreams:Add( Triggers[ i ], Stream )
			end
		end
	end

	local function AdvertHasNonZeroDelay( Advert )
		return Advert.DelayInSeconds > 0
	end

	-- Checks the given advert list against every possible game state to see
	-- if any of them result in a list with no delays.
	local function HasGameStateWithNoDelays( AdvertsList )
		for i = 1, #kGameState do
			local Adverts = AdvertStream.FilterAdvertListForState( AdvertsList, AdvertsList, i )
			if #Adverts > 0 then
				local NumWithDelay = Shine.Stream( Adverts ):Filter( AdvertHasNonZeroDelay ):GetCount()
				if NumWithDelay == 0 then
					self:Print( "Game state %s in %s has no messages with a delay, which will cause an infinite loop. This stream has been disabled.",
						true, kGameState[ i ], AdvertList )
					return true
				end
			end
		end

		return false
	end

	-- Each entry in the Adverts table represents a stream of adverts.
	for i = 1, #self.Config.Adverts do
		local StreamConfig = self.Config.Adverts[ i ]
		local RequiresGameStateFiltering = false

		local Validator = Shine.Validator()
		local AdvertListField = StringFormat( "Adverts[ %d ]", i )

		Validator:AddFieldRule( {
			"IntervalInSeconds", AdvertListField..".IntervalInSeconds"
		}, Validator.IsType( "number", 60 ) )
		Validator:AddFieldRule( {
			"Messages", AdvertListField..".Messages"
		}, Validator.IsType( "table", {} ) )

		if StreamConfig.InitialDelayInSeconds ~= nil then
			Validator:AddFieldRule( {
				"InitialDelayInSeconds", AdvertListField..".InitialDelayInSeconds"
			}, Validator.IsType( "number", StreamConfig.IntervalInSeconds ) )
		end

		if StreamConfig.StartedBy ~= nil then
			if IsType( StreamConfig.StartedBy, "string" ) then
				StreamConfig.StartedBy = { StreamConfig.StartedBy }
			end
			local Field = { "StartedBy", AdvertListField..".StartedBy" }
			Validator:AddFieldRule( Field, Validator.IsType( "table", {} ) )
			Validator:AddFieldRule( Field, Validator.Each( Validator.InEnum( Plugin.AdvertTrigger ) ) )
		end
		if StreamConfig.StoppedBy ~= nil then
			if IsType( StreamConfig.StoppedBy, "string" ) then
				StreamConfig.StoppedBy = { StreamConfig.StoppedBy }
			end
			local Field = { "StoppedBy", AdvertListField..".StoppedBy" }
			Validator:AddFieldRule( Field, Validator.IsType( "table", {} ) )
			Validator:AddFieldRule( Field, Validator.Each( Validator.InEnum( Plugin.AdvertTrigger ) ) )
		end
		if StreamConfig.DefaultTemplate ~= nil then
			Validator:AddFieldRule( {
				"DefaultTemplate", AdvertListField..".DefaultTemplate"
			}, Validator.IsType( "string", nil ) )
		end

		Validator:Validate( StreamConfig )

		AdvertList = AdvertListField..".Messages"

		local HasNonZeroDelay = false
		-- Parse the list of cycling adverts, filtering out any that are invalid or not enabled
		-- for the current map.
		local AdvertsList = Shine.Stream.Of( StreamConfig.Messages )
			:Map( function( Advert )
				if IsType( Advert, "string" ) then
					-- All adverts in a stream must be a table.
					-- However, we still tolerate string values in the config.
					Advert = {
						Message = Advert
					}
				else
					Advert = TableShallowCopy( Advert )
				end

				if not Advert.Template then
					-- Assign the default template, if it's provided.
					Advert.Template = StreamConfig.DefaultTemplate
				end

				return Advert
			end )
			:Map( AssignTemplate )
			:Map( function( Advert )
				if not Advert.DelayInSeconds then
					-- Assign the default delay if not overridden.
					Advert.DelayInSeconds = StreamConfig.IntervalInSeconds
				end
				return Advert
			end )
			:Filter( IsValidAdvert )
			:Filter( function( Advert )
				if not IsType( Advert, "table" ) then return true end

				if Advert.GameState then
					RequiresGameStateFiltering = true
				elseif AdvertHasNonZeroDelay( Advert ) then
					HasNonZeroDelay = true
				end

				return IsValidForMap( Advert )
			end )
			:AsTable()

		local WillLoop = StreamConfig.Loop == nil or StreamConfig.Loop
		if WillLoop then
			if RequiresGameStateFiltering then
				-- Check every possible game state to ensure each list has at least one advert with a delay.
				HasNonZeroDelay = not HasGameStateWithNoDelays( AdvertsList )
			elseif not HasNonZeroDelay then
				-- Otherwise ensure that there is at least one message with a delay.
				self:Print( "None of the messages in %s have a delay, which will cause an infinite loop. This stream has been disabled.",
					true, AdvertList )
			end
		end

		if #AdvertsList > 0 and ( HasNonZeroDelay or not WillLoop ) then
			-- If there are adverts to display on this map, then setup the stream.
			-- Otherwise it would be pointless to setup as it would never display anything.
			local StartingTriggers = StreamConfig.StartedBy
			local StoppingTriggers = StreamConfig.StoppedBy

			local Stream = AdvertStream( self, AdvertsList, {
				InitialDelayInSeconds = StreamConfig.InitialDelayInSeconds,
				RequiresGameStateFiltering = RequiresGameStateFiltering,
				RandomiseOrder = StreamConfig.RandomiseOrder,
				StartingTriggers = StartingTriggers and TableAsSet( StartingTriggers ),
				StoppingTriggers = StoppingTriggers and TableAsSet( StoppingTriggers ),
				Loop = WillLoop
			} )

			if RequiresGameStateFiltering then
				GameStateFilteredStreams[ #GameStateFilteredStreams + 1 ] = Stream
			end

			-- Setup the stream to be triggered to start/stop if necessary.
			if StartingTriggers then
				local function Start()
					Stream:Start()
				end
				AddTriggeredStream( StartingTriggers, Stream, AdvertListField,
					StreamConfig.StartTriggerConfig, Start )
			end
			if StoppingTriggers then
				local function Stop()
					Stream:Stop()
				end
				AddTriggeredStream( StoppingTriggers, Stream, AdvertListField,
					StreamConfig.StopTriggerConfig, Stop )
			end

			AdvertStreams[ #AdvertStreams + 1 ] = Stream
		end
	end

	self.AdvertStreams = AdvertStreams
	self.TriggeredAdvertStreams = TriggeredAdvertStreams
	self.GameStateFilteredStreams = GameStateFilteredStreams

	-- Collect all adverts set to run on a given trigger.
	local TriggeredAdverts = self.Config.TriggeredAdverts
	local TriggeredAdvertsByTrigger = Shine.Multimap()

	for Trigger, Adverts in pairs( self.Config.TriggeredAdverts ) do
		if not IsType( Trigger, "string" ) then
			self:Print( "Triggered adverts must be mapped by name." )
			break
		end

		local TriggerName = StringUpper( Trigger )
		if not self.AdvertTrigger[ TriggerName ] then
			self:Print( "Invalid trigger: %s",
					true, TriggerName )
		else
			AdvertList = "TriggeredAdverts[ \""..Trigger.."\" ]"
			Shine.Stream.Of( Adverts )
				:Map( AssignTemplate )
				:Filter( IsValidAdvert )
				:Filter( IsValidForMap )
				:ForEach( function( Advert, Index )
					if self.TriggerHandlers[ TriggerName ] then
						local Source = StringFormat( "%s[ %d ]", AdvertList, Index )
						self.TriggerHandlers[ TriggerName ]( self, Source, Advert, function()
							self:TriggerAdvert( Advert, nil, self:GetGameState() )
						end )
					else
						TriggeredAdvertsByTrigger:Add( TriggerName, Advert )
					end
				end )
		end
	end

	self.TriggeredAdvertsByTrigger = TriggeredAdvertsByTrigger
end

function Plugin:GetGameState()
	local Gamerules = GetGamerules()
	return Gamerules and Gamerules:GetGameState()
end

function Plugin:StartStreams()
	for i = 1, #self.AdvertStreams do
		local Stream = self.AdvertStreams[ i ]
		if not Stream:IsStartedByTrigger()
		or Stream:WillStartOnTrigger( self.AdvertTrigger.STARTUP ) then
			-- Force a restart, assume we've just parsed the config.
			Stream:Restart()
		end
	end
end

local function UnpackColour( Colour )
	if not Colour then return 255, 255, 255 end

	return tonumber( Colour[ 1 ] ) or 255,
		tonumber( Colour[ 2 ] ) or 255,
		tonumber( Colour[ 3 ] ) or 255
end

function Plugin:GetClientsForAdvert( Advert )
	-- By default, show adverts to everyone.
	local Targets = nil

	if Advert.Team then
		-- If a team is specified, filter down to just the clients on the team(s)
		if IsType( Advert.Team, "string" ) then
			Targets = Shine.GetTeamClients( self.TeamTypeToTeamNumber[ Advert.Team ] )
		else
			Targets = {}
			for i = 1, #Advert.Team do
				TableAdd( Targets, Shine.GetTeamClients( self.TeamTypeToTeamNumber[ Advert.Team[ i ] ] ) )
			end
		end
	end

	return Targets
end

local function WithInterpolation( Text, EventData )
	if not EventData then return Text end

	return StringInterpolate( Text, EventData )
end

function Plugin:DisplayAdvert( Advert, EventData )
	if IsType( Advert, "string" ) then
		Shine:NotifyColour( nil, 255, 255, 255, WithInterpolation( Advert, EventData ) )
		return
	end

	local Message = WithInterpolation( Advert.Message, EventData )
	local R, G, B = UnpackColour( Advert.Colour )
	local Type = Advert.Type

	local Targets = self:GetClientsForAdvert( Advert )
	-- Don't send anything if there's no one to send to.
	if Targets and #Targets == 0 then return end

	if not Type or Type == "chat" then
		if IsType( Advert.Prefix, "string" ) then
			-- Send the advert with a coloured prefix.
			local PR, PG, PB = UnpackColour( Advert.PrefixColour or { 255, 255, 255 } )
			local PrefixText = WithInterpolation( Advert.Prefix, EventData )

 			Shine:NotifyDualColour( Targets, PR, PG, PB, PrefixText, R, G, B, Message )

 			return
		end

		Shine:NotifyColour( Targets, R, G, B, Message )
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
		}, Targets )
	end
end

function Plugin:TriggerAdvert( Advert, EventData, GameState )
	if GameState and not AdvertStream.IsValidForGameState( Advert, GameState ) then
		return
	end

	-- Only trigger adverts that are valid for the current gamestate.
	self:DisplayAdvert( Advert, EventData )
end

--[[
	Triggers all adverts for the given trigger name with the given data.
]]
function Plugin:TriggerAdverts( TriggerName, EventData )
	local TriggeredStreams = self.TriggeredAdvertStreams:Get( TriggerName )
	if TriggeredStreams then
		-- Trigger streams to start/stop
		for j = 1, #TriggeredStreams do
			TriggeredStreams[ j ]:OnTrigger( TriggerName )
		end
	end

	local Adverts = self.TriggeredAdvertsByTrigger:Get( TriggerName )
	if Adverts then
		local GameState = self:GetGameState()
		-- Trigger individual adverts.
		for j = 1, #Adverts do
			self:TriggerAdvert( Adverts[ j ], EventData, GameState )
		end
	end
end

function Plugin:TriggerTeamAdvert( TeamTriggerNames, Team, EventData )
	local TeamSpecificTrigger = TeamTriggerNames[ Team ]
	if not TeamSpecificTrigger then return end

	self:TriggerAdverts( TeamSpecificTrigger, EventData )
end

local function CommanderEvent( Commander )
	return {
		CommanderName = Commander:GetName()
	}
end

do
	local CommanderLoginTriggers = {
		Plugin.AdvertTrigger.MARINE_COMMANDER_LOGGED_IN,
		Plugin.AdvertTrigger.ALIEN_COMMANDER_LOGGED_IN
	}

	function Plugin:CommLoginPlayer( Chair, Commander )
		local EventData = CommanderEvent( Commander )

		self:TriggerAdverts( self.AdvertTrigger.COMMANDER_LOGGED_IN, EventData )
		self:TriggerTeamAdvert( CommanderLoginTriggers, Commander:GetTeamNumber(), EventData )
	end
end

do
	local CommanderEjectTeamTriggers = {
		Plugin.AdvertTrigger.MARINE_COMMANDER_EJECTED,
		Plugin.AdvertTrigger.ALIEN_COMMANDER_EJECTED
	}

	function Plugin:OnCommanderEjected( Commander )
		Commander.__IsEjected = true

		local EventData = CommanderEvent( Commander )

		self:TriggerAdverts( self.AdvertTrigger.COMMANDER_EJECTED, EventData )
		self:TriggerTeamAdvert( CommanderEjectTeamTriggers, Commander:GetTeamNumber(), EventData )
	end
end

do
	local CommanderLogoutTriggers = {
		Plugin.AdvertTrigger.MARINE_COMMANDER_LOGGED_OUT,
		Plugin.AdvertTrigger.ALIEN_COMMANDER_LOGGED_OUT
	}

	function Plugin:CommLogout( Chair )
		local Commander = Chair:GetCommander()
		if not Commander or Commander.__IsEjected then return end

		local EventData = CommanderEvent( Commander )

		self:TriggerAdverts( self.AdvertTrigger.COMMANDER_LOGGED_OUT, EventData )
		self:TriggerTeamAdvert( CommanderLogoutTriggers, Commander:GetTeamNumber(), EventData )
	end
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
	-- Ensure filtered streams re-compute the adverts they can display.
	for i = 1, #self.GameStateFilteredStreams do
		local Stream = self.GameStateFilteredStreams[ i ]
		Stream:OnGameStateChanged( NewState )
	end

	local Triggers = self:GetTriggerNamesForGameState( NewState )
	if not Triggers then return end

	for i = 1, #Triggers do
		self:TriggerAdverts( Triggers[ i ] )
	end
end

Shine:RegisterExtension( "adverts", Plugin )
Shine.LoadPluginModule( "logger.lua", Plugin )
