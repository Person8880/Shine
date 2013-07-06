--[[
	Base commands shared.
]]

local Plugin = {}

function Plugin:SetupDataTable()
	self:AddDTVar( "integer (1 to 10)", "Gamestate", 1 )
	self:AddDTVar( "boolean", "AllTalk", false )
end

function Plugin:NetworkUpdate( Key, Old, New )
	if Server then return end

	if Key == "Gamestate" then
		if Old == 2 and New == 1 then
			--The game state changes back to 1, then to 3 to start. This is VERY annoying...
			Shine.Timer.Simple( 1, function()
				if not self.Enabled then return end
				
				if self.dt.Gamestate == 1 then
					self:UpdateAllTalk( self.dt.Gamestate )
				end
			end )

			return
		end

		self:UpdateAllTalk( New )
	elseif Key == "AllTalk" then
		if not New then
			self:RemoveAllTalkText()
		else
			self:UpdateAllTalk( self.dt.Gamestate )
		end
	end
end

Shine:RegisterExtension( "basecommands", Plugin )

if Server then return end

local StringFormat = string.format

local NOT_STARTED = 1
local PREGAME = 2
local COUNTDOWN = 3

function Plugin:Initialise()
	if self.dt.AllTalk then
		self:UpdateAllTalk( self.dt.Gamestate )
	end

	self.Enabled = true

	return true
end

function Plugin:UpdateAllTalk( State )
	if not self.dt.AllTalk then return end
	
	if State >= COUNTDOWN then
		if not self.TextObj then return end
		
		self:RemoveAllTalkText()

		return	
	end

	local Enabled = State > NOT_STARTED and "disabled." or "enabled."

	if not self.TextObj then
		local GB = State > NOT_STARTED and 0 or 255

		--A bit of a hack, but the whole screen text stuff is in dire need of a replacement...
		self.TextObj = Shine:AddMessageToQueue( -1, 0.5, 0.95, 
			StringFormat( "All talk is %s", Enabled ), -2, 255, GB, GB, 1, 2, 1, true )

		return
	end

	self.TextObj.Text = StringFormat( "All talk is %s", Enabled )

	local Col = State > NOT_STARTED and Color( 255, 0, 0 ) or Color( 255, 255, 255 )

	self.TextObj.Colour = Col
	self.TextObj.Obj:SetColor( Col )
end

function Plugin:RemoveAllTalkText()
	if not self.TextObj then return end
	
	self.TextObj.LastUpdate = Shared.GetTime() - 1
	self.TextObj.Duration = 1

	self.TextObj = nil
end
