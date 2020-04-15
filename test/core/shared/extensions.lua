--[[
	Extension system tests.
]]

local UnitTest = Shine.UnitTest
local IsType = Shine.IsType
local Hook = Shine.Hook

local OldDebugPrint = Shine.DebugPrint
local OldAddErrorReport = Shine.AddErrorReport
local OldAddNotification = Shine.SystemNotifications.AddNotification

function Shine:DebugPrint() end
function Shine:AddErrorReport() end
function Shine.SystemNotifications:AddNotification() end

-- Forget the hook to ensure it's not added immediately.
Hook.Clear( "OnTestEvent" )

local TestPlugin = Shine.Plugin( "test" )
Shine:RegisterExtension( "test", TestPlugin )
Shine.AllPluginsArray[ #Shine.AllPluginsArray + 1 ] = "test"

TestPlugin.HasConfig = true
TestPlugin.LoadConfig = UnitTest.MockFunction()

local OnTestEvent = UnitTest.MockFunction()
function TestPlugin:OnTestEvent( Arg1, Arg2, Arg3 )
	return OnTestEvent( self, Arg1, Arg2, Arg3 )
end

function TestPlugin:ClientConnect( Client )

end

UnitTest:Before( function()
	OnTestEvent:Reset()

	TestPlugin.LoadConfig:Reset()
	TestPlugin.LoadConfig:SetImplementation( nil )
	TestPlugin.Initialise = nil

	TestPlugin.Conflicts = nil
	TestPlugin.DependsOnPlugins = nil
end )

UnitTest:Test( "EnableExtension - Fails if the given plugin does not exist", function( Assert )
	local Loaded, Err = Shine:EnableExtension( "test2" )
	Assert.False( "Should not have loaded a non-existent plugin", Loaded )
	Assert.Equals( "Error should be due to the plugin not existing", "plugin does not exist", Err )
end )

UnitTest:Test( "EnableExtension - Fails if the plugin has a conflict", function( Assert )
	TestPlugin.Conflicts = {
		DisableUs = { "basecommands" }
	}

	local Loaded, Err = Shine:EnableExtension( "test" )
	Assert.False( "Should not have loaded due to a conflict", Loaded )
	Assert.Equals( "Error should be due to the conflict", "unable to load alongside 'basecommands'.", Err )
	Assert.Nil( "Should not be marked as enabled", TestPlugin.Enabled )
end )

UnitTest:Test( "EnableExtension - Fails if the plugin is missing a dependency", function( Assert )
	TestPlugin.DependsOnPlugins = { "test2" }

	local Loaded, Err = Shine:EnableExtension( "test" )
	Assert.False( "Should not have loaded due to a missing dependency", Loaded )
	Assert.Equals( "Error should be due to the missing dependency", "plugin depends on 'test2'", Err )
	Assert.Nil( "Should not be marked as enabled", TestPlugin.Enabled )
end )

UnitTest:Test( "EnableExtension - Fails if loading the config fails", function( Assert )
	TestPlugin.LoadConfig:SetImplementation( function() error( "failed to load config", 0 ) end )

	local Loaded, Err = Shine:EnableExtension( "test" )
	Assert.False( "Should not have loaded due to an error loading config", Loaded )
	Assert.Equals( "Error should be due to the thrown error", "Error while loading config: failed to load config", Err )
	Assert.Nil( "Should not be marked as enabled", TestPlugin.Enabled )
end )

UnitTest:Test( "EnableExtension - Fails if initialising throws an error", function( Assert )
	TestPlugin.Initialise = function()
		error( "failed to initialise", 0 )
	end

	local Loaded, Err = Shine:EnableExtension( "test" )
	Assert.False( "Should not have loaded due to an error in Initialise", Loaded )
	Assert.Equals( "Error should be due to the thrown error", "Lua error: failed to initialise", Err )
	Assert.Nil( "Should not be marked as enabled", TestPlugin.Enabled )
end )

UnitTest:Test( "EnableExtension - Fails if Initialise returns false", function( Assert )
	TestPlugin.Initialise = function()
		return false, "unable to load"
	end

	local Loaded, Err = Shine:EnableExtension( "test" )
	Assert.False( "Should not have loaded due to Initialise returning false", Loaded )
	Assert.Equals( "Error should be the returned failure message", "unable to load", Err )
	Assert.Nil( "Should not be marked as enabled", TestPlugin.Enabled )
end )

local function HasPluginHook( Hooks )
	local Found
	for Key, Callback in pairs( Hooks ) do
		if
			IsType( Key, "table" ) and Key.Plugin == TestPlugin and
			IsType( Callback, "table" ) and Callback.Plugin == TestPlugin
		then
			return true
		end
	end
	return false
end

UnitTest:Test( "EnableExtension - Adds hooks as expected", function( Assert )
	local Loaded, Err = Shine:EnableExtension( "test" )
	Assert.True( Err, Loaded )
	Assert.True( "Plugin should be marked as enabled", TestPlugin.Enabled )
	Assert.CalledTimes( "Should have called LoadConfig on the plugin", TestPlugin.LoadConfig, 1 )

	local Hooks = Hook.GetTable()
	Assert.Nil( "Should not have any hooks for OnTestEvent yet", Hooks.OnTestEvent )
	Assert.IsType( "Should have ClientConnect hooks", Hooks.ClientConnect, "table" )
	Assert.True( "Expected ClientConnect hook callback for enabled plugin", HasPluginHook( Hooks.ClientConnect ) )
end )

UnitTest:Test( "SetupExtensionEvents - Adds hooks as expected", function( Assert )
	Hook.Broadcast( "OnTestEvent", 1, 2, 3 )

	local Hooks = Hook.GetTable()
	Assert.IsType( "Should have OnTestEvent hooks", Hooks.OnTestEvent, "table" )
	Assert.True( "Expected OnTestEvent hook callback for enabled plugin", HasPluginHook( Hooks.OnTestEvent ) )
	Assert.Called( "Should have invoked the plugin method with expected args", OnTestEvent, TestPlugin, 1, 2, 3 )
end )

UnitTest:Test( "UnloadExtension - Removes hooks as expected", function( Assert )
	local Unloaded = Shine:UnloadExtension( "test" )
	Assert.True( "Should have successfully unloaded the plugin", Unloaded )
	Assert.False( "Plugin should be marked as disabled", TestPlugin.Enabled )

	Unloaded = Shine:UnloadExtension( "test" )
	Assert.False( "Should not be able to unload a plugin twice", Unloaded )

	local Hooks = Hook.GetTable()
	Assert.IsType( "Should have ClientConnect hooks", Hooks.ClientConnect, "table" )
	Assert.False( "Expected ClientConnect hook callback to be removed", HasPluginHook( Hooks.ClientConnect ) )

	Assert.IsType( "Should have OnTestEvent hooks", Hooks.OnTestEvent, "table" )
	Assert.False( "Expected OnTestEvent hook callback to be removed", HasPluginHook( Hooks.OnTestEvent ) )

	Hook.Broadcast( "OnTestEvent", 1, 2, 3 )
	Assert.CalledTimes( "Should not have invoked the plugin method after it is disabled", OnTestEvent, 0 )
end )

Shine:UnloadExtension( "test" )
Shine.Plugins.test = nil
Shine.AllPluginsArray[ #Shine.AllPluginsArray ] = nil

Shine.DebugPrint = OldDebugPrint
Shine.AddErrorReport = OldAddErrorReport
Shine.SystemNotifications.AddNotification = OldAddNotification
