--[[
	Adverts plugin test.
]]

local UnitTest = Shine.UnitTest
local Adverts = UnitTest:LoadExtension( "adverts" )
if not Adverts then return end

local AdvertStream = require "shine/extensions/adverts/advert_stream"

Adverts = UnitTest.MockOf( Adverts )

Adverts.Config = {
	Templates = {
		ChatNotification = {
			Type = "chat",
			Colour = { 255, 255, 255 },
			Prefix = "[Info]",
			PrefixColour = { 0, 200, 255 }
		},
		RoundStarted = {
			Type = "chat",
			Colour = { 255, 255, 255 },
			Prefix = "[Hint]",
			PrefixColour = { 0, 200, 255 },
			GameState = "Started"
		},
		PreGame = {
			Type = "chat",
			Colour = { 255, 255, 255 },
			Prefix = "[Hint]",
			PrefixColour = { 0, 200, 255 },
			GameState = { "NotStarted", "WarmUp" }
		}
	},
	Adverts = {
		{
			Messages = {
				{
					Message = "This server is running the Shine administration mod.",
					Template = "ChatNotification"
				},
				{
					Message = "Did you know that Aliens bite things?",
					Template = "RoundStarted",
					Team = "ALIEN"
				},
				{
					Message = "Get ready to shoot/bite!",
					Template = "PreGame",
					Team = { "MARINE", "ALIEN" }
				},
				"A string advert.",
				{
					-- This is invalid
					Message = 1
				},
				{
					Message = "I can't be used on any map",
					Maps = { [ "ns2_invalid" ] = true }
				},
				{
					Message = "I can't be used on the current map",
					ExcludedMaps = { [ Shared.GetMapName() ] = true }
				},
				{
					Message = "Invalid team",
					Team = 1
				},
				{
					Message = "Another invalid team",
					Team = "NOPE"
				},
				{
					Message = "Another invalid team",
					Team = { "NOPE" }
				}
			},
			IntervalInSeconds = 60,
			RandomiseOrder = false,
			DefaultTemplate = "ChatNotification"
		},
		{
			-- Should correct this value when validating.
			IntervalInSeconds = "60",
			RandomiseOrder = false,
			DefaultTemplate = "ChatNotification",
			StartedBy = { Adverts.AdvertTrigger.START_OF_ROUND },
			StoppedBy = { Adverts.AdvertTrigger.END_OF_ROUND },
			Messages = {
				{
					Message = "This message displays during a round only."
				}
			}
		},
		-- This stream should be rejected as all messages have a 0 delay.
		{
			IntervalInSeconds = 0,
			Messages = {
				{
					Message = "This stream"
				},
				{
					Message = "will infinite loop"
				},
				{
					Message = "so it should be disabled"
				}
			}
		},
		-- This stream is invalid as it can infinite loop in the PreGame state.
		{
			IntervalInSeconds = 10,
			Messages = {
				{
					Message = "This will infinite loop.",
					GameState = "PreGame",
					DelayInSeconds = 0
				},
				{
					Message = "In PreGame",
					GameState = { "PreGame", "WarmUp" },
					DelayInSeconds = 0
				},
				{
					Message = "But not in WarmUp",
					GameState = "WarmUp"
				}
			}
		}
	},
	TriggeredAdverts = {
		[ Adverts.AdvertTrigger.START_OF_ROUND ] = {
			{
				Message = "Get zem!",
				Template = "RoundStarted"
			},
			{
				Message = "I can't be used on any map",
				Maps = { [ "ns2_invalid" ] = true }
			},
			{
				Message = "I can't be used on the current map",
				ExcludedMaps = { [ Shared.GetMapName() ] = true }
			}
		},
		INVALID = {
			{
				Message = ""
			}
		}
	}
}

UnitTest:Test( "ParseAdverts parses as expected", function( Assert )
	Adverts:ParseAdverts()

	Assert.Equals( "Expected 2 valid advert streams", 2, #Adverts.AdvertStreams )

	local Stream = Adverts.AdvertStreams[ 1 ]

	Assert.Equals( "Expected one filtered stream in list",
		1, #Adverts.GameStateFilteredStreams )
	Assert.Equals( "Expected the first stream to be stored in filtered list",
		Stream, Adverts.GameStateFilteredStreams[ 1 ] )
	Assert.True( "Expected the first stream to be marked as requiring filtering",
		Stream.RequiresGameStateFiltering )
	Assert.False( "Expected first stream to not be started by trigger",
		Stream:IsStartedByTrigger() )

	Assert.Equals( "Expected 4 adverts in first stream", 4, #Stream.AdvertsList )
	local function AssertMatchesTemplate( Advert, Template )
		Assert.IsType( "Advert is not a table!", Advert, "table" )
		for Key, Value in pairs( Template ) do
			Assert.Equals( "Advert does not match template at key: "..Key, Value, Advert[ Key ] )
		end
	end
	for i = 1, 4 do
		local Advert = Stream.AdvertsList[ i ]
		AssertMatchesTemplate( Advert, Adverts.Config.Templates[ Advert.Template ] )
		Assert.Equals( "Advert does not have delay set", 60, Advert.DelayInSeconds )
	end

	local InGameStream = Adverts.AdvertStreams[ 2 ]
	Assert.True( "Expected second stream to be started by trigger",
		InGameStream:IsStartedByTrigger() )
	Assert.False( "Expected second stream to not require filtering",
		InGameStream.RequiresGameStateFiltering )
	Assert.Equals( "Expected 1 advert in second stream",
		1, #InGameStream.AdvertsList )
	Assert.True( "Expected stream to start on START_OF_ROUND",
		InGameStream:WillStartOnTrigger( Adverts.AdvertTrigger.START_OF_ROUND ) )
	Assert.Equals( "Expected stream to be in START_OF_ROUND triggers",
		InGameStream, Adverts.TriggeredAdvertStreams:Get( Adverts.AdvertTrigger.START_OF_ROUND )[ 1 ] )
	Assert.Equals( "Expected stream to be in END_OF_ROUND triggers",
		InGameStream, Adverts.TriggeredAdvertStreams:Get( Adverts.AdvertTrigger.END_OF_ROUND )[ 1 ] )

	Assert.DeepEquals( "Triggered advert multimap not mapped as expected", {
		[ Adverts.AdvertTrigger.START_OF_ROUND ] = {
			{
				Message = "Get zem!",
				Template = "RoundStarted",
				Type = "chat",
				Colour = { 255, 255, 255 },
				Prefix = "[Hint]",
				PrefixColour = { 0, 200, 255 },
				GameState = "Started"
			}
		}
	}, Adverts.TriggeredAdvertsByTrigger:AsTable() )
	AssertMatchesTemplate( Adverts.TriggeredAdvertsByTrigger:Get( Adverts.AdvertTrigger.START_OF_ROUND )[ 1 ],
		Adverts.Config.Templates.RoundStarted )
end )

UnitTest:Test( "FilterAdvertListForState filters when adverts should be", function( Assert )
	local AdvertsList = {
		{
			Message = "This server is running the Shine administration mod.",
		},
		{
			Message = "Did you know that Aliens bite things?",
			GameState = "Started"
		},
		{
			Message = "Get ready to shoot/bite!",
			GameState = { "NotStarted", "WarmUp" }
		}
	}

	local Filtered, HasListChanged = AdvertStream.FilterAdvertListForState( AdvertsList, AdvertsList, kGameState.Started )
	Assert.True( "Expected list to be marked as changed", HasListChanged )
	Assert.ArrayEquals( "Expected only adverts valid for gamestate",
		{ AdvertsList[ 1 ], AdvertsList[ 2 ] }, Filtered )
end )

UnitTest:Test( "FilterAdvertListForState produces same list when all match", function( Assert )
	local AdvertsList = {
		{
			Message = "This server is running the Shine administration mod.",
		},
		{
			Message = "Did you know that Aliens bite things?",
			GameState = "Started"
		},
		{
			Message = "Get ready to shoot/bite!"
		}
	}
	local Filtered, HasListChanged = AdvertStream.FilterAdvertListForState( AdvertsList, AdvertsList, kGameState.Started )
	Assert.False( "Expected list to not be marked as changed", HasListChanged )
	Assert.ArrayEquals( "Expected output to be identical to input", AdvertsList, Filtered )
end )

Adverts.GameStateFilteredStreams = {}

local Displayed = {}
function Adverts:DisplayAdvert( Advert )
	Displayed[ Advert ] = true
end

Adverts.TriggeredAdvertsByTrigger = Shine.Multimap( {
	[ Adverts.AdvertTrigger.START_OF_ROUND ] = {
		{
			Message = "1"
		},
		{
			Message = "2"
		}
	}
} )

UnitTest:Test( "SetGameState - Displays adverts for triggers", function( Assert )
	Adverts:SetGameState( nil, kGameState.Started, kGameState.Countdown )

	local AdvertsTriggered = Adverts.TriggeredAdvertsByTrigger:Get( Adverts.AdvertTrigger.START_OF_ROUND )
	for i = 1, #AdvertsTriggered do
		Assert.True( "Advert should have been triggered", Displayed[ AdvertsTriggered[ i ] ] )
	end
end )

local Timers = {}
function Adverts:SimpleTimer( Delay, Callback )
	local Timer = {
		Destroy = function() end,
		Delay = Delay,
		Callback = Callback
	}
	Timers[ #Timers + 1 ] = Timer
	return Timer
end

local Stream = AdvertStream( Adverts, {}, {} )
Stream.RequiresGameStateFiltering = true
Stream.AdvertsList = {
	{
		Message = "1",
		DelayInSeconds = 10
	},
	{
		Message = "2",
		DelayInSeconds = 10
	}
}
Stream.CurrentAdvertsList = Stream.AdvertsList
Stream.CurrentMessageIndex = 2

function Stream.FilterAdvertListForState()
	return Stream.AdvertsList, false
end

UnitTest:Test( "SetGameState - Does nothing if no triggers or filter change", function( Assert )
	Stream:OnGameStateChanged( kGameState.Countdown )
	Assert.Equals( "Advert list should not have changed", Stream.AdvertsList, Stream.CurrentAdvertsList )
	Assert.Equals( "Advert index should not have changed", 2, Stream.CurrentMessageIndex )
end )

Stream.CurrentAdvertsList = {}
function Stream.FilterAdvertListForState()
	return Stream.AdvertsList, true
end

UnitTest:Test( "SetGameState - Updates current advert list on filter change", function( Assert )
	Stream:OnGameStateChanged( kGameState.Countdown )
	Assert.Equals( "Advert list should have changed", Stream.AdvertsList, Stream.CurrentAdvertsList )
	Assert.Equals( "Advert index should have reset", 1, Stream.CurrentMessageIndex )

	Assert.Equals( "Should have queued the first advert", 1, #Timers )
	Assert.Equals( "The timer should have a 10 second delay", 10, Timers[ 1 ].Delay )
end )
