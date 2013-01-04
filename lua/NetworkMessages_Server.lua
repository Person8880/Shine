// ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
//
// lua\NetworkMessages_Server.lua
//
//    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
//                  Max McGuire (max@unknownworlds.com)
//
// See the Messages section of the Networking docs in Spark Engine scripting docs for details.
//
// ========= For more information, visit us at http://www.unknownworlds.com =====================

function OnCommandCommMarqueeSelect(client, message)
	
	local player = client:GetControllingPlayer()
	if player:GetIsCommander() then
		player:MarqueeSelectEntities(ParseCommMarqueeSelectMessage(message))
	end
	
end

function OnCommandClearSelection(client, message)

	local player = client:GetControllingPlayer()
	local removeAll, removeId, ctrlPressed = ParseClearSelectionMessage(message)
	
	if player:GetIsCommander() then
		if removeAll then
			player:ClearSelection()
		else
			// TODO: remove entityId, if ctrl pressed remove all entities with same class name as well from selection
		end
	end
	
end

function OnCommandCommSelectId(client, message)

	local player = client:GetControllingPlayer()
	if player:GetIsCommander() then
		player:SelectEntityId(ParseSelectIdMessage(message))
	end

end

function OnCommandCommControlClickSelect(client, message)

	local player = client:GetControllingPlayer()
	if player:GetIsCommander() then
		player:ControlClickSelectEntities(ParseControlClickSelectMessage(message))
	end

end

function OnCommandParseSelectHotkeyGroup(client, message)

	local player = client:GetControllingPlayer()
	if player:GetIsCommander() then
		player:SelectHotkeyGroup(ParseSelectHotkeyGroupMessage(message))
	end
	
end

function OnCommandParseCreateHotkeyGroup(client, message)

	local player = client:GetControllingPlayer()
	if player:GetIsCommander() then
		player:CreateHotkeyGroup(message.groupNumber, player:GetSelection())
	end
	
end

function OnCommandCommAction(client, message)

	local techId = ParseCommActionMessage(message)
	
	local player = client:GetControllingPlayer()
	if player and player:GetIsCommander() then
		player:ProcessTechTreeAction(techId, nil, nil)
	else
		Shared.Message("CommAction message received with invalid player. TechID: " .. EnumToString(kTechId, techId))
	end
	
end

function OnCommandCommTargetedAction(client, message)

	local player = client:GetControllingPlayer()
	if player:GetIsCommander() then
	
		local techId, pickVec, orientation = ParseCommTargetedActionMessage(message)
		player:ProcessTechTreeAction(techId, pickVec, orientation)
	
	end
	
end

function OnCommandCommTargetedActionWorld(client, message)

	local player = client:GetControllingPlayer()
	if player:GetIsCommander() then
	
		local techId, pickVec, orientation = ParseCommTargetedActionMessage(message)
		player:ProcessTechTreeAction(techId, pickVec, orientation, true)
	
	end
	
end

function OnCommandGorgeBuildStructure(client, message)

	local player = client:GetControllingPlayer()
	local origin, direction, structureIndex = ParseGorgeBuildMessage(message)
	
	local dropStructureAbility = player:GetWeapon(DropStructureAbility.kMapName)
	// The player may not have an active weapon if the message is sent
	// after the player has gone back to the ready room for example.
	if dropStructureAbility then
		dropStructureAbility:OnDropStructure(origin, direction, structureIndex)
	end
	
end

function OnCommandMutePlayer(client, message)

	local player = client:GetControllingPlayer()
	local muteClientIndex, setMute = ParseMutePlayerMessage(message)
	player:SetClientMuted(muteClientIndex, setMute)
	
end

function OnCommandCommClickSelect(client, message)

	local player = client:GetControllingPlayer()
	if player:GetIsCommander() then
		player:ClickSelectEntities(ParseCommClickSelectMessage(message))
	end
	
end

local kChatsPerSecondAdded = 1
local kMaxChatsInBucket = 5
local function CheckChatAllowed(client)

	client.chatTokenBucket = client.chatTokenBucket or CreateTokenBucket(kChatsPerSecondAdded, kMaxChatsInBucket)
	// Returns true if there was a token to remove.
	return client.chatTokenBucket:RemoveTokens(1)
	
end

local function GetChatPlayerData(client)

	local playerName = "Admin"
	local playerLocationId = -1
	local playerTeamNumber = kTeamReadyRoom
	local playerTeamType = kNeutralTeamType
	
	if client then
	
		local player = client:GetControllingPlayer()
		if not player then
			return
		end
		playerName = player:GetName()
		playerLocationId = player.locationId
		playerTeamNumber = player:GetTeamNumber()
		playerTeamType = player:GetTeamType()
		
	end
	
	return playerName, playerLocationId, playerTeamNumber, playerTeamType
	
end

local function OnChatReceived(client, message)

	if not CheckChatAllowed(client) then
		return
	end

	chatMessage = string.sub(message.message, 1, kMaxChatLength)

	if chatMessage and string.len(chatMessage) > 0 then
		--Begin modification to hook directly into the chat.
		local Result = Shine.Hook.Call( "PlayerSay", client, message )
		if Result then
			if Result[ 1 ] == "" then return end
			chatMessage = Result[ 1 ]:sub( 1, kMaxChatLength )
		end
	
		local playerName, playerLocationId, playerTeamNumber, playerTeamType = GetChatPlayerData(client)
		
		if playerName then
		
			if message.teamOnly then
			
				local players = GetEntitiesForTeam("Player", playerTeamNumber)
				for index, player in ipairs(players) do
					Server.SendNetworkMessage(player, "Chat", BuildChatMessage(true, playerName, playerLocationId, playerTeamNumber, playerTeamType, chatMessage), true)
				end
				
			else
				Server.SendNetworkMessage("Chat", BuildChatMessage(false, playerName, playerLocationId, playerTeamNumber, playerTeamType, chatMessage), true)
			end
			
			Shared.Message("Chat " .. (message.teamOnly and "Team - " or "All - ") .. playerName .. ": " .. chatMessage)
			
			// We save a history of chat messages received on the Server.
			Server.AddChatToHistory(chatMessage, playerName, client:GetUserId(), playerTeamNumber, message.teamOnly)
			
		end
		
	end
	
end

local function OnCommandCommPing(client, message)

	if Server then
	
		local player = client:GetControllingPlayer()
		if player then
			local team = player:GetTeam()
			team:SetCommanderPing(message.position)
		end
	
	end

end

local function OnCommandSetRookieMode(client, networkMessage)

	if client ~= nil then
	
		local player = client:GetControllingPlayer()
		if player then 
		
			local rookieMode = ParseRookieMessage(networkMessage)
			player:SetRookieMode(rookieMode)
			
		end
		
	end

end

local function OnCommandSetCommStatus(client, networkMessage)

	if client ~= nil then
	
		local player = client:GetControllingPlayer()
		if player then 
		
			local commStatus = ParseCommunicationStatus(networkMessage)
			player:SetCommunicationStatus(commStatus)
			
		end
		
	end

end

local function OnMessageBuy(client, buyMessage)

	local player = client:GetControllingPlayer()
	
	if player and player:GetIsAllowedToBuy() then
	
		local purchaseTechIds = ParseBuyMessage(buyMessage)
		player:ProcessBuyAction(purchaseTechIds)
		
	end
	
end


local function OnVoiceMessage(client, message)

	local voiceId = ParseVoiceMessage(message)
	local player = client:GetControllingPlayer()
	
	if player then
	
		local soundData = GetVoiceSoundData(voiceId)
		if soundData then
		
			local soundName = soundData.Sound
			
			if soundData.Function then            
				soundName = soundData.Function(player) or soundName    
			end
			
			// the request sounds always play for everyone since its something the player is doing actively
			// the auto voice overs are triggered somewhere else server side and play for team only
			if soundName then
				StartSoundEffectOnEntity(soundName, player)
			end
			
			local team = player:GetTeam()
			if team then

				// send alert so a marine commander for example gets notified about players who need a medpack / ammo etc.
				if soundData.AlertTechId and soundData.AlertTechId ~= kTechId.None then
					team:TriggerAlert(soundData.AlertTechId, player)
				end
				
			end
		
		end
	
	end

end

local function OnConnectMessage(client, message)

	local armorType = ParseConnectMessage(message)
	if client then
	
		local allowed = armorType == kArmorType.Green or
					   (armorType == kArmorType.Black and GetHasBlackArmor(client)) or
					   (armorType == kArmorType.Deluxe and GetHasDeluxeEdition(client))
						
		if allowed then
			client.armorType = armorType
		end
		
		local player = client:GetControllingPlayer()
		if player then
			player:OnClientUpdated(client)
		end
	
	end

end

Server.HookNetworkMessage("MarqueeSelect", OnCommandCommMarqueeSelect)
Server.HookNetworkMessage("ClickSelect", OnCommandCommClickSelect)
Server.HookNetworkMessage("ClearSelection", OnCommandClearSelection)
Server.HookNetworkMessage("ControlClickSelect", OnCommandCommControlClickSelect)
Server.HookNetworkMessage("SelectHotkeyGroup", OnCommandParseSelectHotkeyGroup)
Server.HookNetworkMessage("CreateHotKeyGroup", OnCommandParseCreateHotkeyGroup)
Server.HookNetworkMessage("CommAction", OnCommandCommAction)
Server.HookNetworkMessage("CommTargetedAction", OnCommandCommTargetedAction)
Server.HookNetworkMessage("CommTargetedActionWorld", OnCommandCommTargetedActionWorld)
Server.HookNetworkMessage("GorgeBuildStructure", OnCommandGorgeBuildStructure)
Server.HookNetworkMessage("MutePlayer", OnCommandMutePlayer)
Server.HookNetworkMessage("SelectId", OnCommandCommSelectId)
Server.HookNetworkMessage("ChatClient", OnChatReceived)
Server.HookNetworkMessage("CommanderPing", OnCommandCommPing)
Server.HookNetworkMessage("SetRookieMode", OnCommandSetRookieMode)
Server.HookNetworkMessage("SetCommunicationStatus", OnCommandSetCommStatus)
Server.HookNetworkMessage("Buy", OnMessageBuy)
Server.HookNetworkMessage("VoiceMessage", OnVoiceMessage)
Server.HookNetworkMessage("ConnectMessage", OnConnectMessage)