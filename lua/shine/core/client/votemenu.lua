--[[
	Vote menu client side stuff.
]]

Script.Load( "lua/shine/core/client/votemenu_gui.lua" )

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
local function CheckForBind()
	local CustomBinds = io.open( "config://ConsoleBindings.json", "r" )

	if not CustomBinds then 
		Shine.VoteButtonBound = nil
		Shine.VoteButton = nil

		return 
	end

	local Binds = json.decode( CustomBinds:read( "*all" ) ) or {}

	CustomBinds:close()

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
Shine.CheckVoteMenuBind = CheckForBind

function Shine.OpenVoteMenu()
	local VoteMenu = Shine.VoteMenu

	if VoteMenu.Visible then
		VoteMenu:SetIsVisible( false )

		return
	end

	VoteMenu:SetIsVisible( true )

	Client.SendNetworkMessage( "Shine_OpenedVoteMenu", {}, true )
	
	Shine.Hook.Call( "OnVoteMenuOpen" )
end

Event.Hook( "Console_sh_votemenu", function()
	if #ActivePlugins == 0 then --Request addon list if our table is empty.
		Client.SendNetworkMessage( "Shine_RequestPluginData", {}, true )

		WaitingForData = true

		return 
	end
	
	Shine.OpenVoteMenu()
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

local function BindVoteKey()
	local MenuBinds = BindingsUI_GetBindingsTable()

	local CustomBinds = io.open( "config://ConsoleBindings.json", "r" )

	local Binds

	if CustomBinds then
		Binds = json.decode( CustomBinds:read( "*all" ) ) or {}

		CustomBinds:close()

		for Button, Data in pairs( Binds ) do
			if Data.command and Data.command:find( "sh_votemenu" ) then
				Shine.VoteButtonBound = true
				Shine.VoteButton = Button
				return
			end
		end
	end

	if CanBind( MenuBinds, Binds, "M" ) then --This is now the default map button...
		Shared.ConsoleCommand( "bind M sh_votemenu" )
		Shine.VoteButtonBound = true

		Shared.Message( "Shine has bound the M key to the vote menu. If you would like to change this, type bind <key> sh_votemenu" )

		return
	elseif CanBind( MenuBinds, Binds, "N" ) then
		Shared.ConsoleCommand( "bind N sh_votemenu" )
		
		Shine.VoteButton = "N"
		Shine.VoteButtonBound = true

		Shared.Message( "Shine has bound the N key to the vote menu. If you would like to change this, type bind <key> sh_votemenu" )

		return
	elseif CanBind( MenuBinds, Binds, "C" ) then --Try the old default map button!
		Shared.ConsoleCommand( "bind C sh_votemenu" )
		
		Shine.VoteButton = "C"
		Shine.VoteButtonBound = true

		Shared.Message( "Shine has bound the C key to the vote menu. If you would like to change this, type bind <key> sh_votemenu" )

		return
	end

	Shared.Message( "Shine was unable to bind a key to the vote menu. If you would like to use it, type bind <key> sh_votemenu" )
end
Event.Hook( "LoadComplete", BindVoteKey )
