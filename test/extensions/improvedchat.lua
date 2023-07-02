--[[
	Improved chat plugin tests.
]]

local UnitTest = Shine.UnitTest
local Plugin = UnitTest:LoadExtension( "improvedchat" )
if not Plugin then return end

local ChatAPI = require "shine/core/shared/chat/chat_api"

local ColourElement = require "shine/lib/gui/richtext/elements/colour"
local ImageElement = require "shine/lib/gui/richtext/elements/image"
local TextElement = require "shine/lib/gui/richtext/elements/text"

Plugin = UnitTest.MockOf( Plugin )

local SentNetworkMessages = {}
function Plugin:SendNetworkMessage( Targets, Name, Data, Reliable )
	SentNetworkMessages[ #SentNetworkMessages + 1 ] = {
		Name = Name,
		Data = Data,
		Targets = Targets
	}
end

UnitTest:Before( function()
	Plugin.NextMessageID = 0
	Plugin.ChatTagIndex = 0
	SentNetworkMessages = {}
end )

local RichTextMessages = {
	{
		Input = {
			Message = {
				ColourElement( Colour( 1, 1, 1 ) ),
				TextElement( "This text is smaller than the max size." ),
				ColourElement( Colour( 1, 0, 0 ) ),
				TextElement( " This text is red." ),
				ImageElement( {
					Texture = "ui/badges/wrench.dds"
				} )
			}
		},
		ExpectedMessages = {
			{
				Name = "RichTextChatMessage3",
				Data = {
					MessageID = 0,
					ChunkIndex = 1,
					NumChunks = 1,
					SourceType = ChatAPI.SourceType.SYSTEM,
					SourceID = "",
					SuppressSound = false,

					Colour1 = 0xFFFFFF,
					Value1 = "t:This text is smaller than the max size.",

					Colour2 = 0xFF0000,
					Value2 = "t: This text is red.",

					Colour3 = -1,
					Value3 = "i:ui/badges/wrench.dds"
				}
			}
		}
	},
	{
		Input = {
			Message = {
				Colour( 1, 1, 1 ),
				string.rep( "é", 126 )
			},
			Source = {
				Type = ChatAPI.SourceTypeName.PLUGIN,
				ID = "test"
			}
		},
		ExpectedMessages = {
			{
				Name = "RichTextChatMessage1",
				Data = {
					MessageID = 0,
					ChunkIndex = 1,
					NumChunks = 1,
					SourceType = ChatAPI.SourceType.PLUGIN,
					SourceID = "test",
					SuppressSound = false,

					Colour1 = 0xFFFFFF,
					Value1 = "t:"..string.rep( "é", 126 )
				}
			}
		}
	},
	{
		Input = {
			Message = {
				Colour( 1, 1, 1 ),
				string.rep( "é", 125 ).."e"
			},
			Source = {
				Type = ChatAPI.SourceTypeName.PLUGIN,
				ID = "test"
			}
		},
		ExpectedMessages = {
			{
				Name = "RichTextChatMessage1",
				Data = {
					MessageID = 0,
					ChunkIndex = 1,
					NumChunks = 1,
					SourceType = ChatAPI.SourceType.PLUGIN,
					SourceID = "test",
					SuppressSound = false,

					Colour1 = 0xFFFFFF,
					Value1 = "t:"..string.rep( "é", 125 ).."e"
				}
			}
		}
	},
	{
		Input = {
			Message = {
				Colour( 1, 1, 1 ),
				string.rep( "é", 126 ).."e"
			},
			Source = {
				Type = ChatAPI.SourceTypeName.PLUGIN,
				ID = "test"
			}
		},
		ExpectedMessages = {
			{
				Name = "RichTextChatMessage2",
				Data = {
					MessageID = 0,
					ChunkIndex = 1,
					NumChunks = 1,
					SourceType = ChatAPI.SourceType.PLUGIN,
					SourceID = "test",
					SuppressSound = false,

					Colour1 = 0xFFFFFF,
					Value1 = "t:"..string.rep( "é", 126 ),

					Colour2 = -1,
					Value2 = "t:e"
				}
			}
		}
	},
	{
		Input = {
			Message = {
				Colour( 1, 1, 1 ),
				"This text is smaller than the max size.",
				string.rep( "é", 128 )
			},
			Source = {
				Type = ChatAPI.SourceTypeName.PLAYER,
				ID = 123
			}
		},
		ExpectedMessages = {
			{
				Name = "RichTextChatMessage2",
				Data = {
					MessageID = 0,
					ChunkIndex = 1,
					NumChunks = 1,
					SourceType = ChatAPI.SourceType.PLAYER,
					SourceID = "123",
					SuppressSound = false,

					-- Should split once when text overflows but the overflow is not larger than the max.
					Colour1 = 0xFFFFFF,
					Value1 = "t:This text is smaller than the max size."..string.rep( "é", 106 ),

					Colour2 = -1,
					Value2 = "t:"..string.rep( "é", 22 )
				}
			}
		}
	},
	{
		Input = {
			Message = {
				Colour( 1, 1, 1 ),
				"This text is smaller than the max size.",
				string.rep( "é", 300 )
			}
		},
		ExpectedMessages = {
			{
				Name = "RichTextChatMessage3",
				Data = {
					MessageID = 0,
					ChunkIndex = 1,
					NumChunks = 1,
					SourceType = ChatAPI.SourceType.SYSTEM,
					SourceID = "",
					SuppressSound = false,

					-- Should split n times to ensure no overflow.
					Colour1 = 0xFFFFFF,
					Value1 = "t:This text is smaller than the max size."..string.rep( "é", 106 ),

					Colour2 = -1,
					Value2 = "t:"..string.rep( "é", 126 ),

					Colour3 = -1,
					Value3 = "t:"..string.rep( "é", 68 )
				}
			}
		}
	},
	{
		Input = {
			Message = {
				Colour( 1, 1, 1 ),
				"This text is smaller than the max size.",
				string.rep( "e", 252 - 39 ),
				"This should be new text."
			}
		},
		ExpectedMessages = {
			{
				Name = "RichTextChatMessage2",
				Data = {
					MessageID = 0,
					ChunkIndex = 1,
					NumChunks = 1,
					SourceType = ChatAPI.SourceType.SYSTEM,
					SourceID = "",
					SuppressSound = false,

					-- Should correctly handle the case where text is exactly the max length.
					Colour1 = 0xFFFFFF,
					Value1 = "t:This text is smaller than the max size."..string.rep( "e", 252 - 39 ),

					Colour2 = -1,
					Value2 = "t:This should be new text."
				}
			}
		}
	},
	{
		Input = {
			Message = {
				Colour( 1, 1, 1 ),
				"This text is white.",
				Colour( 1, 0, 0 ),
				"This text is red.",
				Colour( 0, 1, 0 ),
				"This text is green.",
				Colour( 0, 0, 1 ),
				"This text is blue.",
				Colour( 1, 1, 0 ),
				"This text is yellow.",
				Colour( 0, 1, 1 ),
				"This text is light blue.",
				Colour( 0, 0, 0 ),
				"This text is black."
			}
		},
		ExpectedMessages = {
			{
				Name = "RichTextChatMessage6",
				Data = {
					MessageID = 0,
					ChunkIndex = 1,
					NumChunks = 2,
					SourceType = ChatAPI.SourceType.SYSTEM,
					SourceID = "",
					SuppressSound = false,

					Colour1 = 0xFFFFFF,
					Value1 = "t:This text is white.",

					Colour2 = 0xFF0000,
					Value2 = "t:This text is red.",

					Colour3 = 0x00FF00,
					Value3 = "t:This text is green.",

					Colour4 = 0x0000FF,
					Value4 = "t:This text is blue.",

					Colour5 = 0xFFFF00,
					Value5 = "t:This text is yellow.",

					Colour6 = 0x00FFFF,
					Value6 = "t:This text is light blue."
				}
			},
			{
				Name = "RichTextChatMessage1",
				Data = {
					MessageID = 0,
					ChunkIndex = 2,
					NumChunks = 2,
					SourceType = 1,
					SourceID = "",
					SuppressSound = false,

					Colour1 = 0,
					Value1 = "t:This text is black."
				}
			}
		}
	}
}

for i = 1, #RichTextMessages do
	UnitTest:Test( "AddRichTextMessage - Test case "..i, function( Assert )
		Plugin:AddRichTextMessage( RichTextMessages[ i ].Input )
		Assert:DeepEquals( RichTextMessages[ i ].ExpectedMessages, SentNetworkMessages )
	end )
end

UnitTest:Test( "SetChatTag", function( Assert )
	local Client1 = UnitTest.MakeMockClient( 1 )
	local Client2 = UnitTest.MakeMockClient( 2 )

	Plugin:SetChatTag( Client1, {
		Text = "[Test]",
		Colour = { 255, 0, 0 },
		Image = "ui/badges/wrench.dds"
	}, "Group:TestGroup" )

	local ExpectedChatTag = {
		Text = "[Test]",
		Image = "ui/badges/wrench.dds",
		Colour = 0xFF0000,
		Index = 0,
		ReferenceCount = 1
	}

	Assert.DeepEquals( "Should have stored the chat tag definition",
		ExpectedChatTag, Plugin.ChatTagDefinitions:Get( "Group:TestGroup" ) )

	local ExpectedAssignment = {
		SteamID = 1,
		Index = 0,
		Key = "Group:TestGroup"
	}
	Assert.DeepEquals( "Should have assigned the chat tag to the client",
		ExpectedAssignment, Plugin.ClientsWithTags:Get( Client1 ) )

	Assert.DeepEquals( "Should have sent the new definition and assignment to all clients", {
		{
			Name = "CreateChatTagDefinition",
			Data = ExpectedChatTag
		},
		{
			Name = "AssignChatTag",
			Data = ExpectedAssignment
		}
	}, SentNetworkMessages )

	SentNetworkMessages = {}

	Plugin:SetChatTag( Client2, {
		Text = "[Test]",
		Colour = { 255, 0, 0 },
		Image = "ui/badges/wrench.dds"
	}, "Group:TestGroup" )

	ExpectedChatTag.ReferenceCount = 2

	Assert.DeepEquals( "Should have incremented the reference count on the chat tag definition",
		ExpectedChatTag, Plugin.ChatTagDefinitions:Get( "Group:TestGroup" ) )

	ExpectedAssignment = {
		SteamID = 2,
		Index = 0,
		Key = "Group:TestGroup"
	}
	Assert.DeepEquals( "Should have assigned the chat tag to the client",
		ExpectedAssignment, Plugin.ClientsWithTags:Get( Client2 ) )

	Assert.DeepEquals( "Should have sent the new assignment, but not definition, to all clients", {
		{
			Name = "AssignChatTag",
			Data = ExpectedAssignment
		}
	}, SentNetworkMessages )

	SentNetworkMessages = {}

	Plugin:SetChatTag( Client2, nil )
	ExpectedChatTag.ReferenceCount = 1

	Assert.Nil( "Should have removed client 2's assignment", Plugin.ClientsWithTags:Get( Client2 ) )
	Assert.DeepEquals( "Should have decremented the chat tag's reference count",
		ExpectedChatTag, Plugin.ChatTagDefinitions:Get( "Group:TestGroup" ) )

	Assert.DeepEquals( "Should have sent a reset message to all clients for client 2", {
		{
			Name = "ResetChatTag",
			Data = {
				SteamID = 2
			}
		}
	}, SentNetworkMessages )

	SentNetworkMessages = {}

	Plugin:SetChatTag( Client1, nil )
	Assert.Nil( "Should have removed client 1's assignment", Plugin.ClientsWithTags:Get( Client1 ) )
	Assert.Nil( "Should have removed the chat tag definition", Plugin.ChatTagDefinitions:Get( "Group:TestGroup" ) )

	Assert.DeepEquals( "Should have sent a reset message to all clients for client 1", {
		{
			Name = "DeleteChatTagDefinition",
			Data = {
				Index = 0
			}
		},
		{
			Name = "ResetChatTag",
			Data = {
				SteamID = 1
			}
		}
	}, SentNetworkMessages )
end )

local EmojiRepository = require "shine/extensions/improvedchat/emoji_repository"

UnitTest:ResetState()
UnitTest:Before( function()
	Shine.UserData.Groups.EmojiTestGroup = {
		AllowedEmoji = {
			-- Remove an emoji from the parent's allowed set.
			"!grinning_face",
			-- Add another single emoji.
			"alien",
			-- Add a category of emoji (case shouldn't matter).
			"c:Emoticons"
		},
		InheritsFrom = { "EmojiTestParentGroup" }
	}
	Shine.UserData.Groups.EmojiTestParentGroup = {
		AllowedEmoji = {
			"*_face"
		}
	}
end )

UnitTest:Test( "GetAvailableEmoji - Returns false if no whitelist is set", function( Assert )
	Shine.UserData.Groups.EmojiTestParentGroup.AllowedEmoji = nil

	local AllowedEmoji = Plugin:GetAvailableEmoji( "EmojiTestParentGroup" )
	Assert:False( AllowedEmoji )
end )

UnitTest:Test( "GetAvailableEmoji - Returns a bitset of emoji indices if restrictions exist", function( Assert )
	local AllowedEmoji = Plugin:GetAvailableEmoji( "EmojiTestGroup" )
	Assert:True( Shine.Implements( AllowedEmoji, Shine.BitSet ) )
	Assert:True( AllowedEmoji:GetCount() > 0 )

	local AllEmoji = EmojiRepository.GetAllEmoji()
	for Index in AllowedEmoji:Iterate() do
		local EmojiDef = AllEmoji[ Index ]
		local EmojiName = EmojiDef.Name
		Assert.True(
			"Unexpected allowed emoji: "..EmojiName,
			( EmojiName == "alien" or EmojiName:EndsWith( "_face" ) or EmojiDef.Category.Name == "Emoticons" ) and
			EmojiName ~= "grinning_face"
		)
	end

	local EncodedBitSet = Plugin:EncodeBitsetToMessage( 1, 1, AllowedEmoji )
	local ChunkIndex, NumChunks = Plugin.DecodeMessageChunkData( EncodedBitSet )
	Assert:Equals( 1, ChunkIndex )
	Assert:Equals( 1, NumChunks )

	local DecodedBitSet = Plugin:DecodeBitSetFromChunks( { EncodedBitSet } )
	Assert.Equals( "Encoding and decoding allowed emoji should result in the same bitset", AllowedEmoji, DecodedBitSet )
	Assert.Equals(
		"Should not have stored more data than necessary when decoding",
		AllowedEmoji.MaxArrayIndex,
		DecodedBitSet.MaxArrayIndex
	)
end )

UnitTest:Test( "GetAvailableEmoji - Returns false if all emoji are allowed", function( Assert )
	Shine.UserData.Groups.EmojiTestParentGroup.AllowedEmoji = { "*" }

	local AllowedEmoji = Plugin:GetAvailableEmoji( "EmojiTestParentGroup" )
	Assert:False( AllowedEmoji )
end )

UnitTest:ResetState()
Shine.UserData.Groups.EmojiTestGroup = nil
Shine.UserData.Groups.EmojiTestParentGroup = nil

local MockFilter = Shine.BitSet()
MockFilter:Add( EmojiRepository.GetEmojiDefinition( "grinning_face" ).Index )

UnitTest:Test( "ApplyEmojiFilters - Returns text as-is if it contains no emoji", function( Assert )
	local Message = "This is a test message."
	local Text = Plugin.ApplyEmojiFilters( Message, MockFilter )
	Assert:Equals( Message, Text )
end )

UnitTest:Test( "ApplyEmojiFilters - Returns text without emoji that are not allowed", function( Assert )
	local Message = "This is a :zzz:zzz:test: :zzz::message:zzz:."
	local Text = Plugin.ApplyEmojiFilters( Message, MockFilter )
	Assert:Equals( "This is a zzz:test: :message.", Text )
end )

UnitTest:Test( "ApplyEmojiFilters - Returns an empty string if all emoji are filtered out and only whitespace remains", function( Assert )
	local Message = ":zzz: :zzz: :zzz:"
	local Text = Plugin.ApplyEmojiFilters( Message, MockFilter )
	Assert:Equals( "", Text )
end )

UnitTest:Test( "ApplyEmojiFilters - Returns whitespace as-is if it was provided originally", function( Assert )
	local Message = "    "
	local Text = Plugin.ApplyEmojiFilters( Message, MockFilter )
	Assert:Equals( Message, Text )
end )
