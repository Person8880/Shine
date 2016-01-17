--[[
	Vote menu client side stuff.
]]

Script.Load( "lua/shine/core/client/votemenu_gui.lua" )

local IsType = Shine.IsType
local StringFormat = string.format
local TableFindByField = table.FindByField
local TableSort = table.sort

local ActivePlugins = {}
Shine.ActivePlugins = ActivePlugins

local WaitingForData = false

Client.HookNetworkMessage( "Shine_PluginData", function( Message )
	for i = 1, #ActivePlugins do
		ActivePlugins[ i ] = nil
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

do
	local ConsoleBindingsFile = "config://ConsoleBindings.json"
	local function FindBind( Binds, Command )
		for Button, Data in pairs( Binds ) do
			if IsType( Data, "table" ) and IsType( Data.command, "string" )
			and Data.command:find( Command ) then
				return Button
			end
		end

		return nil
	end

	--[[
		Updates the binding data in case they changed it whilst connected.
	]]
	function Shine.CheckVoteMenuBind()
		local CustomBinds = Shine.LoadJSONFile( ConsoleBindingsFile )
		if not IsType( CustomBinds, "table" ) then
			Shine.VoteButtonBound = nil
			Shine.VoteButton = nil

			return false, CustomBinds
		end

		local Button = FindBind( CustomBinds, "sh_votemenu" )
		if Button then
			Shine.VoteButtonBound = true
			Shine.VoteButton = Button
			return true, CustomBinds
		end

		Shine.VoteButtonBound = nil
		Shine.VoteButton = nil

		return false, CustomBinds
	end
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

do
	local Clock = os.clock
	local NextPress = 0

	Shine:RegisterClientCommand( "sh_votemenu", function()
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
end

local function CanBind( MenuBinds, Binds, Button )
	-- Search main menu binds first, then custom binds file.
	if TableFindByField( MenuBinds, "current", Button ) then
		return false
	end

	if not IsType( Binds, "table" ) then return true end
	if not IsType( Binds[ Button ], "table" ) then return true end
	if Binds[ Button ].command == "" then return true end

	return false
end

local function BindVoteKey()
	local Found, CustomBinds = Shine.CheckVoteMenuBind()
	if Found then return end

	local MenuBinds = BindingsUI_GetBindingsTable()
	local KeysToTry = {
		"M", "N", "C"
	}

	for i = 1, #KeysToTry do
		local Key = KeysToTry[ i ]

		if CanBind( MenuBinds, CustomBinds, Key ) then
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
