--[[
	The default chat provider, providing 2-colour text using the vanilla chat system.
]]

local TableConcat = table.concat
local type = type

local DefaultColour = Color( 1, 1, 1 )
local DefaultProvider = {}

function DefaultProvider:SupportsRichText()
	return false
end

-- Converts a rich-text message into a 2-colour message.
-- Ideally clients of the API should use AddMessage instead when they know rich text is not supported.
function DefaultProvider:AddRichTextMessage( MessageData )
	if MessageData.FallbackMessage then
		local Message = MessageData.FallbackMessage
		if Message.Prefix then
			return self:AddDualColourMessage(
				Message.PrefixColour, Message.Prefix, Message.MessageColour, Message.Message
			)
		end
		return self:AddMessage( Message.MessageColour, Message.Message )
	end

	local MessageParts = {}
	local CurrentText = {}

	local NumColours = 0
	local Contents = MessageData.Message

	for i = 1, #Contents do
		local Entry = Contents[ i ]
		local Type = type( Entry )

		if Type == "table" then
			if Entry.Type == "Text" then
				Type = "string"
				Entry = Entry.Value
			elseif Entry.Type == "Colour" then
				Type = "cdata"
				Entry = Entry.Value
			end
		end

		if Type == "string" then
			if #MessageParts == 0 then
				NumColours = NumColours + 1
				MessageParts[ #MessageParts + 1 ] = DefaultColour
			end
			CurrentText[ #CurrentText + 1 ] = Entry
		elseif Type == "cdata" then
			if NumColours < 2 then
				if #CurrentText > 0 then
					MessageParts[ #MessageParts + 1 ] = TableConcat( CurrentText )
					CurrentText = {}
				end

				if type( MessageParts[ #MessageParts ] ) == "cdata" then
					MessageParts[ #MessageParts ] = Entry
				else
					NumColours = NumColours + 1
					MessageParts[ #MessageParts + 1 ] = Entry
				end
			end
		end
	end

	if #MessageParts == 0 then return end

	MessageParts[ #MessageParts + 1 ] = TableConcat( CurrentText )

	if #MessageParts == 2 then
		-- Only a single colour, use the message component to display it.
		return self:AddMessage( MessageParts[ 1 ], MessageParts[ 2 ], MessageData.Targets )
	end

	return self:AddDualColourMessage(
		MessageParts[ 1 ], MessageParts[ 2 ], MessageParts[ 3 ], MessageParts[ 4 ], MessageData.Targets
	)
end

if Client then
	function DefaultProvider:AddDualColourMessage( PrefixColour, Prefix, MessageColour, Message )
		Shine.AddChatText(
			PrefixColour.r * 255,
			PrefixColour.g * 255,
			PrefixColour.b * 255,
			Prefix,
			MessageColour.r,
			MessageColour.g,
			MessageColour.b,
			Message
		)
	end
else
	function DefaultProvider:AddDualColourMessage( PrefixColour, Prefix, MessageColour, Message, Targets )
		Shine:NotifyDualColour(
			Targets,
			PrefixColour.r * 255,
			PrefixColour.g * 255,
			PrefixColour.b * 255,
			Prefix,
			MessageColour.r * 255,
			MessageColour.g * 255,
			MessageColour.b * 255,
			Message
		)
	end
end

function DefaultProvider:AddMessage( MessageColour, Message, Targets )
	return self:AddDualColourMessage( DefaultColour, "", MessageColour, Message, Targets )
end

return DefaultProvider
