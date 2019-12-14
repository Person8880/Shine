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
			GameState = "Started",
			MinPlayers = 8
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
				},
				{
					Message = "Invalid delay type",
					DelayInSeconds = "Not a number"
				},
				{
					Message = "Invalid delay value",
					DelayInSeconds = -1
				},
				{
					Message = "Invalid min players",
					MinPlayers = "Not a number"
				},
				{
					Message = "Invalid max players type",
					MaxPlayers = {}
				},
				{
					Message = "Invalid max players value",
					MaxPlayers = 0
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
			MinPlayers = 16,
			MaxPlayers = 24,
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
		},
		-- This stream is invalid as it can infinite loop when the player count is 8
		{
			IntervalInSeconds = 10,
			MinPlayers = 8,
			Messages = {
				{
					Message = "This will infinite loop.",
					MinPlayers = 8,
					DelayInSeconds = 0
				},
				{
					Message = "at 8 players",
					MinPlayers = 9
				}
			}
		},
		-- This stream is invalid as it can infinite loop at many player counts.
		{
			IntervalInSeconds = 10,
			MaxPlayers = 15,
			Messages = {
				{
					Message = "This will infinite loop.",
					MinPlayers = 8,
					DelayInSeconds = 0
				},
				{
					Message = "at < 8 players",
					MinPlayers = 8
				}
			}
		},
		-- This stream is invalid as it can infinite loop at many player counts.
		{
			IntervalInSeconds = 10,
			Messages = {
				{
					Message = "This will infinite loop.",
					MaxPlayers = 8,
					DelayInSeconds = 0
				},
				{
					Message = "at > 8 players",
					MaxPlayers = 8
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
			},
			{
				Message = "I can't be used in the current gamestate.",
				GameState = { "Started" }
			}
		},
		INVALID = {
			{
				Message = ""
			}
		}
	}
}

function Adverts:GetGameState()
	return kGameState.NotStarted
end

function Adverts:GetPlayerCount()
	return 8
end

function Adverts:GetMaxPlayerCount()
	return 24
end

UnitTest:Test( "ParseAdverts parses as expected", function( Assert )
	Adverts:ParseAdverts()

	Assert.Equals( "Expected 2 valid advert streams", 2, #Adverts.AdvertStreams )

	local Stream = Adverts.AdvertStreams[ 1 ]

	Assert.Equals( "Expected one game state filtered stream in list",
		1, #Adverts.GameStateFilteredStreams )
	Assert.Equals( "Expected the first stream to be stored in game state filtered list",
		Stream, Adverts.GameStateFilteredStreams[ 1 ] )
	Assert.True( "Expected the first stream to be marked as requiring filtering",
		Stream.RequiresGameStateFiltering )
	Assert.False( "Expected first stream to not be started by trigger",
		Stream:IsStartedByTrigger() )
	Assert.Nil( "Expected MinPlayers to not be set on first stream", Stream.MinPlayers )
	Assert.Nil( "Expected MaxPlayers to not be set on first stream", Stream.MaxPlayers )

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

	Assert.ArrayEquals(
		"Expected player count filtered list to hold both valid streams",
		{ Stream, InGameStream },
		Adverts.PlayerCountFilteredStreams
	)
	Assert.Equals( "Expected MinPlayers to be set on second stream", 16, InGameStream.MinPlayers )
	Assert.Equals( "Expected MaxPlayers to be set on second stream", 24, InGameStream.MaxPlayers )

	Assert.DeepEquals( "Triggered advert multimap not mapped as expected", {
		[ Adverts.AdvertTrigger.START_OF_ROUND ] = {
			{
				Message = "Get zem!",
				Template = "RoundStarted",
				Type = "chat",
				Colour = { 255, 255, 255 },
				Prefix = "[Hint]",
				PrefixColour = { 0, 200, 255 },
				GameState = "Started",
				MinPlayers = 8
			},
			{
				Message = "I can't be used in the current gamestate.",
				GameState = { "Started" }
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
function Adverts:DisplayAdvert( Advert, EventData )
	Displayed[ Advert ] = EventData or true
end

Adverts.TriggeredAdvertsByTrigger = Shine.Multimap( {
	[ Adverts.AdvertTrigger.START_OF_ROUND ] = {
		{
			Message = "1"
		},
		{
			Message = "2"
		}
	},
	[ Adverts.AdvertTrigger.COMMANDER_LOGGED_IN ] = {
		{
			Message = "Commander {CommanderName} logged in.",
			MaxPlayers = 10
		},
		{
			Message = "Another message.",
			GameState = { "PreGame", "WarmUp", "NotStarted" },
			MinPlayers = 8
		},
		{
			Message = "Only show this when started",
			GameState = "Started"
		},
		{
			Message = "Only show this at > 8 players",
			MinPlayers = 9
		},
		{
			Message = "Only show this at < 8 players",
			MaxPlayers = 7
		}
	},
	[ Adverts.AdvertTrigger.COMMANDER_LOGGED_OUT ] = {
		{
			Message = "Commander {CommanderName} logged out."
		}
	},
	[ Adverts.AdvertTrigger.COMMANDER_EJECTED ] = {
		{
			Message = "Commander {CommanderName} was ejected."
		}
	}
} )

UnitTest:Test( "TriggerAdverts - Displays adverts for given trigger", function( Assert )
	local Data = {
		CommanderName = "Test"
	}
	Adverts:TriggerAdverts( Adverts.AdvertTrigger.COMMANDER_LOGGED_IN, Data )

	local AdvertsTriggered = Adverts.TriggeredAdvertsByTrigger:Get( Adverts.AdvertTrigger.COMMANDER_LOGGED_IN )
	for i = 1, 2 do
		Assert.Equals( "Adverts should have been triggered with the given data",
			Data, Displayed[ AdvertsTriggered[ i ] ] )
	end

	Assert.Nil( "Third advert should not be displayed due to gamestate filter.",
		Displayed[ AdvertsTriggered[ 3 ] ] )
	Assert.Nil( "Fourth advert should not be displayed due to min players filter.",
		Displayed[ AdvertsTriggered[ 4 ] ] )
	Assert.Nil( "Fifth advert should not be displayed due to max players filter.",
		Displayed[ AdvertsTriggered[ 5 ] ] )
end )

Displayed = {}

UnitTest:Test( "OnCommanderEjected - Does not trigger logged out messages", function( Assert )
	local Commander = {
		GetName = function() return "Test" end,
		GetTeamNumber = function() return 1 end
	}

	Adverts:OnCommanderEjected( Commander )
	Adverts:CommLogout( { GetCommander = function() return Commander end } )

	Assert.DeepEquals( "Only the ejection adverts should have been triggered", {
		[ Adverts.TriggeredAdvertsByTrigger:Get( Adverts.AdvertTrigger.COMMANDER_EJECTED )[ 1 ] ] = {
			CommanderName = "Test"
		}
	}, Displayed )
end )

Displayed = {}

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
		Destroy = function( self ) self.Destroyed = true end,
		Delay = Delay,
		Callback = Callback
	}
	Timers[ #Timers + 1 ] = Timer
	return Timer
end

local Stream
UnitTest:Before( function()
	Stream = AdvertStream( Adverts, {}, {} )
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
	Stream.MinPlayers = 8
	Stream.MaxPlayers = 24

	Timers = {}
end )

UnitTest:Test( "AdvertStream:OnGameStateChanged - Does nothing if no triggers or filter change", function( Assert )
	function Stream.FilterAdvertListForState()
		return Stream.AdvertsList, false
	end

	Stream:OnGameStateChanged( kGameState.Countdown )
	Assert.Equals( "Advert list should not have changed", Stream.AdvertsList, Stream.CurrentAdvertsList )
	Assert.Equals( "Advert index should not have changed", 2, Stream.CurrentMessageIndex )
end )

UnitTest:Test( "AdvertStream:OnGameStateChanged - Updates current advert list on filter change", function( Assert )
	function Stream.FilterAdvertListForState()
		return Stream.AdvertsList, true
	end

	Stream.CurrentAdvertsList = {}

	Stream:OnGameStateChanged( kGameState.Countdown )
	Assert.Equals( "Advert list should have changed", Stream.AdvertsList, Stream.CurrentAdvertsList )
	Assert.Equals( "Advert index should have reset", 1, Stream.CurrentMessageIndex )

	Assert.Equals( "Should have queued the first advert", 1, #Timers )
	Assert.Equals( "The timer should have a 10 second delay", 10, Timers[ 1 ].Delay )
end )

UnitTest:Test( "AdvertStream:CanStart - Returns false when < min players", function( Assert )
	Assert.False( "Stream should not be able to start when player count < min", Stream:CanStart( 7 ) )
end )

UnitTest:Test( "AdvertStream:CanStart - Returns false when > max players", function( Assert )
	Assert.False( "Stream should not be able to start when player count > max", Stream:CanStart( 25 ) )
end )

UnitTest:Test( "AdvertStream:CanStart - Returns true when player count in range", function( Assert )
	for i = 8, 24 do
		Assert.True( "Stream should be able to start when player count in range", Stream:CanStart( i ) )
	end
end )

UnitTest:Test( "AdvertStream:CanStart - Returns true when no player count restrictions are set", function( Assert )
	Stream.MinPlayers = nil
	Stream.MaxPlayers = nil
	for i = 0, 24 do
		Assert.True( "Stream should be able to start when player count in range", Stream:CanStart( i ) )
	end
end )

UnitTest:Test( "AdvertStream:OnTrigger - Does not start stream if player count is out of range", function( Assert )
	Stream.StartingTriggers = {
		[ Adverts.AdvertTrigger.STARTUP ] = true
	}
	Stream.PlayerCount = 0

	Assert.False( "Stream should not have started yet", Stream.Started )

	Stream:OnTrigger( Adverts.AdvertTrigger.STARTUP )

	Assert.False( "Stream should not start on trigger when player count is out of range", Stream.Started )
	Assert.Equals( "Should not have queued the first advert", 0, #Timers )
end )

UnitTest:Test( "AdvertStream:OnTrigger - Starts stream if player count is in range", function( Assert )
	Stream.StartingTriggers = {
		[ Adverts.AdvertTrigger.STARTUP ] = true
	}
	Stream.PlayerCount = 8

	Assert.False( "Stream should not have started yet", Stream.Started )

	Stream:OnTrigger( Adverts.AdvertTrigger.STARTUP )

	Assert.True( "Stream should start on trigger when player count is in range", Stream.Started )
	Assert.Equals( "Should have queued the first advert", 1, #Timers )
	Assert.Equals( "The timer should have a 10 second delay", 10, Timers[ 1 ].Delay )
end )

UnitTest:Test( "AdvertStream:OnTrigger - Stops stream on stop trigger", function( Assert )
	Stream.StoppingTriggers = {
		[ Adverts.AdvertTrigger.COUNTDOWN ] = true
	}

	Stream:Start()
	Assert.True( "Stream should have started", Stream.Started )

	Stream:OnTrigger( Adverts.AdvertTrigger.COUNTDOWN )

	Assert.False( "Stream should stop on trigger", Stream.Started )
	Assert.True( "The existing advert timer should have been destroyed", Timers[ 1 ].Destroyed )
end )

UnitTest:Test( "AdvertStream:OnPlayerCountChanged - Does nothing when player count is in range if using triggers", function( Assert )
	Stream.StartingTriggers = {
		[ Adverts.AdvertTrigger.STARTUP ] = true
	}

	Assert.False( "Stream should not have started yet", Stream.Started )

	Stream:OnPlayerCountChanged( 8 )

	Assert.False( "Stream should not start when configured with a trigger and player count is in range", Stream.Started )
	Assert.Equals( "Should not have queued the first advert", 0, #Timers )
end )

UnitTest:Test( "AdvertStream:OnPlayerCountChanged - Starts stream is player count is in range and not using triggers", function( Assert )
	Assert.False( "Stream should not have started yet", Stream.Started )

	Stream:OnPlayerCountChanged( 8 )

	Assert.True( "Stream should start when not configured with a trigger and player count is in range", Stream.Started )
	Assert.Equals( "Should have queued the first advert", 1, #Timers )
	Assert.Equals( "The timer should have a 10 second delay", 10, Timers[ 1 ].Delay )
end )

UnitTest:Test( "AdvertStream:OnPlayerCountChanged - Stops stream is player count is out of range", function( Assert )
	Stream:Start()
	Assert.True( "Stream should have started", Stream.Started )

	Stream:OnPlayerCountChanged( 7 )

	Assert.False( "Stream should stop when player count is out of range", Stream.Started )
	Assert.True( "The existing advert timer should have been destroyed", Timers[ 1 ].Destroyed )
end )

UnitTest:Test( "AdvertStream:GetNextAdvert - Returns next advert in the list", function( Assert )
	Stream.CurrentMessageIndex = 1

	local Advert, MessageIndex = Stream:GetNextAdvert()
	Assert.Equals( "Should return the first advert", Stream.AdvertsList[ 1 ], Advert )
	Assert.Equals( "Index should be 1", 1, MessageIndex )
end )

UnitTest:Test( "AdvertStream:GetNextAdvert - Skips adverts with player count out of range", function( Assert )
	Stream.CurrentAdvertsList = {
		{
			Message = "1",
			DelayInSeconds = 10,
			MinPlayers = 8
		},
		{
			Message = "2",
			DelayInSeconds = 10,
			MaxPlayers = 1
		}
	}
	Stream.PlayerCount = 1

	local Advert, MessageIndex = Stream:GetNextAdvert()
	Assert.Equals( "Should return the second advert", Stream.CurrentAdvertsList[ 2 ], Advert )
	Assert.Equals( "Index should be 2", 2, MessageIndex )
end )

UnitTest:Test( "AdvertStream:GetNextAdvert - Handles case where no advert is valid", function( Assert )
	Stream.CurrentAdvertsList = {
		{
			Message = "1",
			DelayInSeconds = 10,
			MinPlayers = 8
		},
		{
			Message = "2",
			DelayInSeconds = 10,
			MaxPlayers = 1
		}
	}
	Stream.PlayerCount = 2

	local Advert, MessageIndex = Stream:GetNextAdvert()
	Assert.Nil( "Should return nil for the advert as none are valid", Advert )
end )

UnitTest:Test( "AdvertStream.IsValidForPlayerCount - Returns false if player count < min", function( Assert )
	Assert.False(
		"Should return false if player count < min",
		AdvertStream.IsValidForPlayerCount( {
			MinPlayers = 8
		}, 7 )
	)
end )

UnitTest:Test( "AdvertStream.IsValidForPlayerCount - Returns false if player count > max", function( Assert )
	Assert.False(
		"Should return false if player count > max",
		AdvertStream.IsValidForPlayerCount( {
			MaxPlayers = 16
		}, 17 )
	)
end )

UnitTest:Test( "AdvertStream.IsValidForPlayerCount - Returns true if player count in range", function( Assert )
	local Advert = {
		MinPlayers = 8,
		MaxPlayers = 16
	}
	for i = 8, 16 do
		Assert.True( "Should return false if player count > max", AdvertStream.IsValidForPlayerCount( Advert, i ) )
	end
end )
