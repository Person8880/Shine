--[[
	Provides a way to filter out player names.
]]

local Shine = Shine

local Clamp = math.Clamp
local Floor = math.floor
local GetOwner = Server.GetOwner
local Max = math.max
local pcall = pcall
local Random = math.random
local StringChar = string.char
local StringFind = string.find
local TableConcat = table.concat
local tostring = tostring

local Plugin = {}

Plugin.ConfigName = "NameFilter.json"
Plugin.HasConfig = true

Plugin.RENAME = 1
Plugin.KICK = 2
Plugin.BAN = 3

Plugin.DefaultConfig = {
	Filters = {},
	FilterAction = Plugin.RENAME,
	BanLength = 1440
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Config.BanLength = Max( 0, self.Config.BanLength )
	self.Config.FilterAction = Clamp( Floor( self.Config.FilterAction ), 1, 3 )

	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:CreateCommands()
	local RenameCommand = self:BindCommand( "sh_rename", "rename",
	function( Client, Target, NewName )
		local TargetPlayer = Target:GetControllingPlayer()

		if not TargetPlayer then return end
		
		local CallingInfo = Shine.GetClientInfo( Client )
		local TargetInfo = Shine.GetClientInfo( Target )

		TargetPlayer:SetName( NewName )

		Shine:Print( "%s was renamed to '%s' by %s.", true, TargetInfo, NewName, CallingInfo )
	end )
	RenameCommand:AddParam{ Type = "client" }
	RenameCommand:AddParam{ Type = "string", TakeRestOfLine = true }
	RenameCommand:Help( "<player> <new name> Renames the given player." )
end

Plugin.FilterActions = {
	function( self, Player, OldName ) --Rename them to a random string.
		local UserName = {}
		for i = 1, Random( 5, 10 ) do
			UserName[ i ] = StringChar( Random( 65, 122 ) )
		end
		
		local FinalUserName = TableConcat( UserName, "" )
		
		Player:SetName( FinalUserName )

		local Client = GetOwner( Player )

		if not Client then return end
	
		Shine:Print( "[NameFilter] Client %s[%s] was renamed from filtered name: %s", true,
			FinalUserName, Client:GetUserId(), OldName )
	end,

	function( self, Player, OldName ) --Kick them out.
		local Client = GetOwner( Player )

		if not Client then return end
		
		Shine:Print( "[NameFilter] Client %s[%s] was kicked for filtered name.", true,
			OldName, Client:GetUserId() )

		Server.DisconnectClient( Client )
	end,

	function( self, Player, OldName ) --Ban them.
		local Client = GetOwner( Player )

		if not Client then return end

		local ID = Client:GetUserId()

		local Enabled, BanPlugin = Shine:IsExtensionEnabled( "ban" )

		if Enabled then
			Shine:Print( "[NameFilter] Client %s[%s] was banned for filtered name.", true,
				OldName, ID )

			BanPlugin:AddBan( ID, OldName, self.Config.BanLength * 60, "NameFilter", 0,
				"Player used filtered name." )
		else
			Shine:Print( "[NameFilter] Client %s[%s] was kicked for filtered name (unable to ban, ban plugin not loaded).",
				true, OldName, ID )
		end

		Server.DisconnectClient( Client )
	end
}

--[[
	Checks a player's name for a match with the given pattern.

	Excluded should be an NS2ID which identifies the player who owns this name pattern.
]]
function Plugin:ProcessFilter( Player, Name, Pattern, Excluded )
	if not Pattern then return end

	local Client = GetOwner( Player )

	--This is the real player!
	if Client and tostring( Client:GetUserId() ) == tostring( Excluded ) then return end

	local LoweredName = Name:lower()
	Pattern = Pattern:lower()

	--If someone doesn't know about regex, they could pass an invalid pattern...
	local Success, Start = pcall( StringFind, LoweredName, Pattern )

	if not Success then return end

	if Start then
		self.FilterActions[ self.Config.FilterAction ]( self, Player, Name )
	
		return true
	end
end

--[[
	When a player's name changes, we check all set filters on their new name.
]]
function Plugin:PlayerNameChange( Player, Name, OldName )
	local Filters = self.Config.Filters

	for i = 1, #Filters do
		local Filter = Filters[ i ]
		local Pattern = Filter.Pattern
		local Excluded = Filter.Excluded

		if self:ProcessFilter( Player, Name, Pattern, Excluded ) then
			break
		end
	end
end

Shine:RegisterExtension( "namefilter", Plugin )
