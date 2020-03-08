--[[
	Parses emoji definition files and provides helpers to produce rich text elements for a given emoji.

	Emoji definitions are searched for under ui/shine/emoji/*.json, and expect the following structure:
	{
		Emoji = {
			{
				-- A single-texture emoji (no texture co-ordinates).
				Name = "some_emoji",
				Texture = "ui/some_emoji.dds"
			},
			{
				-- An emoji taken from a section of a texture.
				Name = "some_emoji_from_atlas",
				Texture = "ui/some_emoji_atlas.dds",
				-- Texture co-ordinates in UV space.
				TextureCoordinates = {
					0, 0, 0.1, 0.1
				}
			},
			{
				Name = "another_emoji_from_atlas",
				Texture = "ui/some_emoji_atlas.dds",
				-- Texture co-ordinates in pixel space.
				TexturePixelCoordinates = {
					0, 0, 32, 32
				}
			},
			{
				-- A folder of emoji. Each matching file will be used as a single emoji, using the file name as the
				-- emoji name.
				Folder = "ui/emoji/*.dds"
			}
		}
	}
]]

local ImageElement = require "shine/lib/gui/richtext/elements/image"

local IsType = Shine.IsType
local StringFormat = string.format
local StringLower = string.lower
local StringMatch = string.match
local StringStartsWith = string.StartsWith
local type = type

local EmojiRepository = {
	Logger = Shine.Objects.Logger( Shine.Objects.Logger.LogLevel.INFO, Shared.Message )
}
local EmojiByName = {}
local SortedEmojiNames = {}

do
	local Files = {}
	Shared.GetMatchingFileNames( "ui/shine/emoji/*.json", false, Files )

	local DeleteIfFieldInvalid = { DeleteIfFieldInvalid = true }
	local Validator = Shine.Validator( "Emoji file validation error: " )
	Validator:AddFieldRule( "Emoji", Validator.IsType( "table", {} ) )
	Validator:AddFieldRule( "Emoji", Validator.AllValuesSatisfy(
		Validator.Exclusive( "Name", "Folder", { DeleteIfInvalid = true, FailIfBothMissing = true } ),
		Validator.ValidateField( "Name", Validator.IsAnyType( { "string", "nil" } ), DeleteIfFieldInvalid ),
		Validator.ValidateField( "Folder", Validator.IsAnyType( { "string", "nil" } ), DeleteIfFieldInvalid ),
		Validator.IfFieldPresent( "Name",
			Validator.ValidateField( "Texture", Validator.IsType( "string" ), DeleteIfFieldInvalid ),
			Validator.ValidateField(
				"TexturePixelCoordinates", Validator.IsAnyType( { "table", "nil" }, DeleteIfFieldInvalid )
			),
			Validator.ValidateField(
				"TexturePixelCoordinates", Validator.IfType( "table", Validator.HasLength( 4, 0 ) )
			),
			Validator.ValidateField(
				"TexturePixelCoordinates", Validator.IfType( "table",
					Validator.AllValuesSatisfy( Validator.IsType( "number", 0 ) )
				)
			),
			Validator.ValidateField(
				"TextureCoordinates", Validator.IsAnyType( { "table", "nil" }, DeleteIfFieldInvalid )
			),
			Validator.ValidateField(
				"TextureCoordinates", Validator.IfType( "table", Validator.HasLength( 4, 0 ) )
			),
			Validator.ValidateField(
				"TextureCoordinates", Validator.IfType( "table",
					Validator.AllValuesSatisfy( Validator.IsType( "number", 0 ) )
				)
			)
		)
	) )

	local function AddEmoji( Name, Entry )
		Name = StringLower( Name )

		EmojiByName[ Name ] = Entry
		Entry.Name = Name

		if not SortedEmojiNames[ Name ] then
			SortedEmojiNames[ Name ] = true
			SortedEmojiNames[ #SortedEmojiNames + 1 ] = Name
		end
	end

	local SupportedFileExtensions = {
		dds = true,
		tga = true,
		jpg = true
	}
	local function ParseEmojiFile( EmojiDef )
		Validator:Validate( EmojiDef )

		local Emoji = EmojiDef.Emoji
		for i = 1, #Emoji do
			local Entry = Emoji[ i ]
			if Entry.Name then
				AddEmoji( Entry.Name, Entry )
			elseif Entry.Folder then
				local Textures = {}
				Shared.GetMatchingFileNames( Entry.Folder, true, Textures )
				for j = 1, #Textures do
					local Texture = Textures[ j ]
					local FileName, FileExtension = StringMatch( Texture, "([^/%.]+)%.(%w+)$" )
					if FileName and SupportedFileExtensions[ FileExtension ] then
						AddEmoji( FileName, {
							Name = FileName,
							Texture = Texture
						} )
					end
				end
			end
		end
	end

	for i = 1, #Files do
		local Contents, Pos, Err = Shine.LoadJSONFile( Files[ i ] )
		if Contents then
			Validator.MessagePrefix = StringFormat( "Emoji definition file %s validation error:", Files[ i ] )
			ParseEmojiFile( Contents )
		else
			EmojiRepository.Logger:Error( "Invalid emoji definition file %s: %s", Files[ i ], Err )
		end
	end

	table.sort( SortedEmojiNames )
end

function EmojiRepository.FindMatchingEmoji( EmojiName )
	local Count = 0
	local Results = {}

	local Found = false
	for i = 1, #SortedEmojiNames do
		if StringStartsWith( SortedEmojiNames[ i ], EmojiName ) then
			Found = true
			Count = Count + 1
			Results[ Count ] = EmojiByName[ SortedEmojiNames[ i ] ]
		elseif Found then
			break
		end
	end

	return Results
end

function EmojiRepository.MakeEmojiElement( EmojiName )
	local EmojiDef = EmojiByName[ EmojiName ]
	if not EmojiDef then return nil end

	return ImageElement( {
		Texture = EmojiDef.Texture,
		TextureCoordinates = EmojiDef.TextureCoordinates,
		TexturePixelCoordinates = EmojiDef.TexturePixelCoordinates,
		Tooltip = StringFormat( ":%s:", EmojiName )
	} )
end

function EmojiRepository.GetEmojiDefinition( EmojiName )
	return EmojiByName[ EmojiName ]
end

return EmojiRepository
