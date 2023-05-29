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

local Floor = math.floor
local IsType = Shine.IsType
local Min = math.min
local StringFormat = string.format
local StringGSub = string.gsub
local StringLower = string.lower
local StringMatch = string.match
local StringSub = string.sub
local TableEmpty = table.Empty
local TableSort = table.sort
local type = type

local EmojiRepository = {
	Logger = Shine.Objects.Logger( Shine.Objects.Logger.LogLevel.INFO, Shared.Message )
}
local EmojiByName = {}
local EmojiIndex = Shine.Multimap()

do
	local StringExplode = string.Explode
	local TableConcat = table.concat

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
		),
		Validator.IfFieldPresent( "Folder",
			Validator.ValidateField(
				"Exclude", Validator.IsAnyType( { "table", "nil" }, DeleteIfFieldInvalid )
			),
			Validator.ValidateField(
				"Exclude", Validator.IfType( "table",
					Validator.AllValuesSatisfy( Validator.IsType( "string" ) )
				)
			)
		)
	) )

	local function AddEmojiToIndex( Name )
		local Segments = StringExplode( Name, "_", true )
		local NumSegments = #Segments

		for i = 1, NumSegments do
			for j = i, NumSegments do
				local Key = TableConcat( Segments, "_", i, j )
				if not EmojiIndex:HasKeyValue( Key, Name ) then
					local StartIndex = 1
					for k = 1, i - 1 do
						StartIndex = StartIndex + #Segments[ k ]
					end
					-- Add extra characters for each '_' separator.
					StartIndex = StartIndex + i - 1

					-- Store this emoji under the given segment key, tracking where in the full name the segment starts.
					EmojiIndex:AddPair( Key, Name, StartIndex )
				end
			end
		end
	end

	local function AddEmoji( Name, Entry )
		Name = StringGSub( StringLower( Name ), "[^%w]", "_" )

		if EmojiByName[ Name ] then
			EmojiRepository.Logger:Warn(
				"Emoji '%s' was defined more than once! Only the first definition will be used.",
				Name
			)
			return
		end

		EmojiByName[ #EmojiByName + 1 ] = Entry
		EmojiByName[ Name ] = Entry
		Entry.Name = Name

		AddEmojiToIndex( Name )
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

				local Exclusions
				if Entry.Exclude then
					Exclusions = {}

					for j = 1, #Entry.Exclude do
						local ExcludedFiles = {}
						Shared.GetMatchingFileNames( Entry.Exclude[ j ], true, ExcludedFiles )
						for k = 1, #ExcludedFiles do
							Exclusions[ ExcludedFiles[ k ] ] = true
						end
					end
				end

				for j = 1, #Textures do
					local Texture = Textures[ j ]
					if not ( Exclusions and Exclusions[ Texture ] ) then
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

	EmojiIndex:SortKeys()
end

local Results = {}
local function SortEmoji( A, B )
	local LeftStartIndex = Results[ A ]
	local RightStartIndex = Results[ B ]

	-- Prefer matches that occur earlier in the emoji name.
	if LeftStartIndex ~= RightStartIndex then
		return LeftStartIndex < RightStartIndex
	end

	-- If both match at the same index, prefer smaller emoji names as more of the name is matched.
	if #A ~= #B then
		return #A < #B
	end

	return A < B
end

function EmojiRepository.FindMatchingEmoji( EmojiName )
	local PrefixLength = #EmojiName
	local Keys = EmojiIndex.Keys
	local NumKeys = #Keys

	-- First do a binary search to find the earliest key that starts with the given search term.
	local Start, Mid, End = 1, 0, NumKeys
	while Start <= End do
		Mid = Floor( ( Start + End ) * 0.5 )

		local Key = Keys[ Mid ]
		local KeyPrefix = StringSub( Key, 1, PrefixLength )
		if KeyPrefix < EmojiName then
			Start = Mid + 1
		else
			if KeyPrefix == EmojiName then
				-- Check the key right behind this one, if it's not a match, stop here.
				local Previous = Keys[ Mid - 1 ]
				if not Previous or StringSub( Previous, 1, PrefixLength ) ~= EmojiName then
					break
				end
			end

			End = Mid - 1
		end
	end

	-- Next, iterate starting at the first key that starts with the given search term, and collect all emoji until the
	-- indexed key no longer matches.
	TableEmpty( Results )
	local Count = 0
	for i = Mid, NumKeys do
		local Key = Keys[ i ]
		local KeyPrefix = StringSub( Key, 1, PrefixLength )
		if KeyPrefix ~= EmojiName then
			break
		end

		local EmojiForKey = EmojiIndex:GetPairs( Key )
		for Emoji, StartIndex in EmojiForKey:Iterate() do
			if not Results[ Emoji ] then
				Count = Count + 1
				Results[ Count ] = Emoji
				Results[ Emoji ] = StartIndex
			else
				Results[ Emoji ] = Min( StartIndex, Results[ Emoji ] )
			end
		end
	end

	-- Finally, sort the results to favour closer matches, and return the emoji data for each name.
	TableSort( Results, SortEmoji )

	local Output = {}
	for i = 1, Count do
		Output[ i ] = EmojiByName[ Results[ i ] ]
	end

	TableEmpty( Results )

	return Output
end

function EmojiRepository.GetAllEmoji()
	return EmojiByName
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
