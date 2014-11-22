--[[
	Vote menu client side stuff.
]]

Script.Load( "lua/shine/core/client/votemenu_gui.lua" )

local Clock = os.clock
local IsType = Shine.IsType
local StringFormat = string.format
local TableSort = table.sort

local ActivePlugins = {}
Shine.ActivePlugins = ActivePlugins

local WaitingForData = false

Client.HookNetworkMessage( "Shine_PluginData", function( Message ) 
	if #ActivePlugins > 0 then
		for i = 1, #ActivePlugins do
			ActivePlugins[ i ] = nil
		end
	end

	for Index, Data in pairs( Message ) do
		if Data then
			ActivePlugins[ #ActivePlugins + 1 ] = Index
		end
	end

	TableSort( ActivePlugins )

	if WaitingForData then
		Shine.OpenVoteMenu()

		WaitingForData = false
	end
end )

--[[
	Updates the binding data in case they changed it whilst connected.
]]
function Shine.CheckVoteMenuBind()
	local CustomBinds = io.open( "config://ConsoleBindings.json", "r" )

	if not CustomBinds then 
		Shine.VoteButtonBound = nil
		Shine.VoteButton = nil

		return 
	end

	local BindsFile = CustomBinds:read( "*all" )
	CustomBinds:close()

	local Binds = json.decode( BindsFile ) or {}

	if not IsType( Binds, "table" ) then
		Shine.VoteButtonBound = nil
		Shine.VoteButton = nil

		return
	end

	for Button, Data in pairs( Binds ) do
		if Data.command:find( "sh_votemenu" ) then
			Shine.VoteButtonBound = true
			Shine.VoteButton = Button
			return
		end
	end

	Shine.VoteButtonBound = nil
	Shine.VoteButton = nil
end

function Shine.OpenVoteMenu()
	local VoteMenu = Shine.VoteMenu

	if VoteMenu.Visible then
		VoteMenu:SetIsVisible( false )

		return
	end

	VoteMenu:SetIsVisible( true )

	Shine.SendNetworkMessage( "Shine_OpenedVoteMenu", {}, true )

	Shine.Hook.Call( "OnVoteMenuOpen" )
end

local NextPress = 0
Event.Hook( "Console_sh_votemenu", function()
	if #ActivePlugins == 0 then --Request addon list if our table is empty.
		if not WaitingForData then
			Shine.SendNetworkMessage( "Shine_RequestPluginData", {}, true )

			WaitingForData = true
		end

		return 
	end

	local Time = Clock()

	if Time >= NextPress or not Shine.VoteMenu.Visible then
		Shine.OpenVoteMenu()
	end

	NextPress = Time + 0.3
end )

local function CanBind( MenuBinds, Binds, Button )
	for i = 1, #MenuBinds do --Main menu binds.
		if MenuBinds[ i ].current == Button then
			return false
		end
	end

	if not Binds then return true end --No custom binds file.

	if not Binds[ Button ] then return true end

	if Binds[ Button ].command == "" then return true end

	return false
end

local KeysToTry = {
	"M", "N", "C"
}

local function BindVoteKey()
	local MenuBinds = BindingsUI_GetBindingsTable()

	local CustomBinds = io.open( "config://ConsoleBindings.json", "r" )

	local Binds

	if CustomBinds then
		local BindsFile = CustomBinds:read( "*all" )

		CustomBinds:close()

		Binds = json.decode( BindsFile ) or {}

		if IsType( Binds, "table" ) then
			for Button, Data in pairs( Binds ) do
				if Data.command and Data.command:find( "sh_votemenu" ) then
					Shine.VoteButtonBound = true
					Shine.VoteButton = Button
					return
				end
			end
		end
	end

	for i = 1, #KeysToTry do
		local Key = KeysToTry[ i ]

		if CanBind( MenuBinds, Binds, Key ) then
			Shared.ConsoleCommand( StringFormat( "bind %s sh_votemenu", Key ) )
			Shine.VoteButtonBound = true
			Shine.VoteButton = Key

			Shine.AddStartupMessage( StringFormat( "Shine has bound the %s key to the vote menu. If you would like to change this, enter \"bind <key> sh_votemenu\" into the console.", Key ) )

			return
		end
	end

	Shine.AddStartupMessage( "Shine was unable to bind a key to the vote menu. If you would like to use it, enter \"bind <key> sh_votemenu\" into the console." )
end
Shine.Hook.Add( "OnMapLoad", "BindVoteMenuKey", BindVoteKey )
