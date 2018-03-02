--[[
	Adverts plugin test.
]]

local UnitTest = Shine.UnitTest
local Adverts = UnitTest:LoadExtension( "adverts" )
if not Adverts then return end

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
	TriggeredAdverts = {
		{
			Message = "Get zem!",
			Template = "RoundStarted",
			Trigger = "START_OF_ROUND"
		},
		{
			Message = "",
			Trigger = "INVALID"
		},
		{
			Message = "I can't be used on any map",
			Maps = { [ "ns2_invalid" ] = true },
			Trigger = "START_OF_ROUND"
		},
		{
			Message = "I can't be used on the current map",
			ExcludedMaps = { [ Shared.GetMapName() ] = true },
			Trigger = "START_OF_ROUND"
		}
	}
}

UnitTest:Test( "ParseAdverts parses as expected", function( Assert )
	Adverts:ParseAdverts()

	Assert:Equals( 4, #Adverts.AdvertsList )
	local function AssertMatchesTemplate( Advert, Template )
		for Key, Value in pairs( Template ) do
			Assert.Equals( "Advert does not match template at key: "..Key, Value, Advert[ Key ] )
		end
	end
	for i = 1, 3 do
		local Advert = Adverts.AdvertsList[ i ]
		AssertMatchesTemplate( Advert, Adverts.Config.Templates[ Advert.Template ] )
	end
	Assert.Equals( "Expected final advert to be a string", "A string advert.", Adverts.AdvertsList[ 4 ] )

	Assert.DeepEquals( "Triggered advert multimap not mapped as expected", {
		START_OF_ROUND = {
			{
				Message = "Get zem!",
				Template = "RoundStarted",
				Trigger = "START_OF_ROUND"
			}
		}
	}, Adverts.TriggeredAdvertsByTrigger:AsTable() )
	AssertMatchesTemplate( Adverts.TriggeredAdvertsByTrigger:Get( "START_OF_ROUND" )[ 1 ], Adverts.Config.Templates.RoundStarted )
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

	local Filtered, HasListChanged = Adverts:FilterAdvertListForState( AdvertsList, AdvertsList, kGameState.Started )
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
	local Filtered, HasListChanged = Adverts:FilterAdvertListForState( AdvertsList, AdvertsList, kGameState.Started )
	Assert.False( "Expected list to not be marked as changed", HasListChanged )
	Assert.ArrayEquals( "Expected output to be identical to input", AdvertsList, Filtered )
end )

Adverts.RequiresGameStateFiltering = false
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

Adverts.RequiresGameStateFiltering = true
Adverts.AdvertsList = {
	{
		Message = "1"
	},
	{
		Message = "2"
	}
}
Adverts.CurrentAdvertsList = Adverts.AdvertsList
Adverts.CurrentMessageIndex = 2

function Adverts:FilterAdvertListForState()
	return self.AdvertsList, false
end

UnitTest:Test( "SetGameState - Does nothing if no triggers or filter change", function( Assert )
	Adverts:SetGameState( nil, kGameState.Countdown, kGameState.PreGame )
	Assert.Equals( "Advert list should not have changed", Adverts.AdvertsList, Adverts.CurrentAdvertsList )
	Assert.Equals( "Advert index should not have changed", 2, Adverts.CurrentMessageIndex )
end )

Adverts.CurrentAdvertsList = {}
function Adverts:FilterAdvertListForState()
	return self.AdvertsList, true
end

UnitTest:Test( "SetGameState - Updates current advert list on filter change", function( Assert )
	Adverts:SetGameState( nil, kGameState.Countdown, kGameState.PreGame )
	Assert.Equals( "Advert list should have changed", Adverts.AdvertsList, Adverts.CurrentAdvertsList )
	Assert.Equals( "Advert index should have reset", 1, Adverts.CurrentMessageIndex )
end )
