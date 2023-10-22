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

local Floor = math.floor
local IsType = Shine.IsType
local Min = math.min
local StringExplode = string.Explode
local StringFormat = string.format
local StringGSub = string.gsub
local StringLower = string.lower
local StringMatch = string.match
local StringSub = string.sub
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableSort = table.sort
local type = type

local EmojiRepository = {
	Logger = Shine.Objects.Logger( Shine.Objects.Logger.LogLevel.INFO, Shared.Message )
}
local EmojiByName = {
	[ 0 ] = 0
}
local EmojiIndex = Shine.Multimap()
local EmojiByCategory = Shine.Multimap()
local EmojiCategories = {}

do
	local TableShallowMerge = table.ShallowMerge

	local DEFAULT_CATEGORY = "Uncategorised"
	local EMOJI_DEFINITION_PATH = "ui/shine/emoji/*.json"

	if Server then
		-- To ensure that emoji indices are identical on the client and the server, emoji definitions must match.
		Server.AddRestrictedFileHashes( EMOJI_DEFINITION_PATH )
	end

	local function GetSortedFiles( Path )
		local Files = {}
		Shared.GetMatchingFileNames( Path, true, Files )
		-- To ensure consistent loading order (and thus consistent indices), sort the files.
		-- This ought to be done by GetMatchingFileNames, but it doesn't hurt to enforce it again here.
		TableSort( Files )
		return Files
	end

	local Files = GetSortedFiles( EMOJI_DEFINITION_PATH )

	local DeleteIfFieldInvalid = { DeleteIfFieldInvalid = true }
	local Validator = Shine.Validator( "Emoji file validation error: " )

	-- Validate category definitions, if they're provided.
	Validator:AddFieldRule( "Categories", Validator.IsAnyType( { "table", "nil" } ) )
	Validator:AddFieldRule( "Categories", Validator.IfType( "table", Validator.AllValuesSatisfy(
		Validator.ValidateField( "Name", Validator.IsType( "string" ), DeleteIfFieldInvalid ),
		Validator.ValidateField( "Translations", Validator.IsType( "table" ), DeleteIfFieldInvalid ),
		Validator.ValidateField( "Translations", Validator.AllKeyValuesSatisfy( Validator.IsType( "string" ) ) )
	) ) )

	-- Ensure there's a valid list of emoji.
	Validator:AddFieldRule( "Emoji", Validator.IsAnyType( { "table", "nil" } ) )
	Validator:AddFieldRule( "Emoji", Validator.IfType( "table", Validator.AllValuesSatisfy(
		Validator.Exclusive( "Name", "Folder", { DeleteIfInvalid = true, FailIfBothMissing = true } ),
		Validator.ValidateField( "Name", Validator.IsAnyType( { "string", "nil" } ), DeleteIfFieldInvalid ),
		Validator.ValidateField( "Category", Validator.IsAnyType( { "string", "nil" } ), DeleteIfFieldInvalid ),
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
	) ) )

	local function AddCategory( CategoryDefinition )
		local ExistingCategory = EmojiCategories[ CategoryDefinition.Name ]
		if not ExistingCategory then
			EmojiCategories[ CategoryDefinition.Name ] = CategoryDefinition
			return
		end

		-- If the category has already been defined, merge any additional language translations into it.
		TableShallowMerge( CategoryDefinition.Translations, ExistingCategory.Translations )
	end

	local function GetCategory( CategoryName )
		local CategoryDefinition = EmojiCategories[ CategoryName ]
		if not CategoryDefinition then
			CategoryDefinition = {
				Name = CategoryName,
				Translations = {}
			}
			EmojiCategories[ CategoryName ] = CategoryDefinition
		end
		return CategoryDefinition
	end

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

		-- Make sure the name won't clash with generated short names.
		if StringMatch( Name, "^e%d+$" ) then
			EmojiRepository.Logger:Warn( "Emoji '%s' uses reserved name and will be ignored.", Name )
			return
		end

		if EmojiByName[ Name ] then
			EmojiRepository.Logger:Warn(
				"Emoji '%s' was defined more than once! Only the first definition will be used.",
				Name
			)
			return
		end

		local Index = EmojiByName[ 0 ] + 1
		EmojiByName[ Index ] = Entry
		EmojiByName[ Name ] = Entry
		EmojiByName[ 0 ] = Index
		Entry.Index = Index
		Entry.Name = Name
		Entry.Category = GetCategory( Entry.Category or DEFAULT_CATEGORY )

		AddEmojiToIndex( Name )

		EmojiByCategory:Add( StringLower( Entry.Category.Name ), Entry )
	end

	local SupportedFileExtensions = {
		dds = true,
		tga = true,
		jpg = true
	}
	local function ParseEmojiFile( EmojiDef )
		Validator:Validate( EmojiDef )

		local Categories = EmojiDef.Categories
		if Categories then
			for i = 1, #Categories do
				AddCategory( Categories[ i ] )
			end
		end

		local Emoji = EmojiDef.Emoji
		if not Emoji then return end

		for i = 1, #Emoji do
			local Entry = Emoji[ i ]
			if Entry.Name then
				AddEmoji( Entry.Name, Entry )
			elseif Entry.Folder then
				if Server then
					-- Again, to ensure consistent emoji indices, if a folder is included, its contents must be
					-- identical on the client and the server. This has the side effect of blocking local modifications
					-- to emoji images, but that's unfortunately unavoidable here.
					Server.AddRestrictedFileHashes( Entry.Folder )
				end

				local Textures = GetSortedFiles( Entry.Folder )
				local Exclusions
				if Entry.Exclude then
					Exclusions = {}

					for j = 1, #Entry.Exclude do
						-- Exclusions don't need to be in any order, and they don't need to be consistency checked
						-- (it only makes sense for these to be a subset of the files defined by Entry.Folder).
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
								Texture = Texture,
								Category = Entry.Category
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
			Validator.MessagePrefix = StringFormat( "Emoji definition file '%s' validation error: ", Files[ i ] )
			ParseEmojiFile( Contents )
		else
			EmojiRepository.Logger:Error( "Invalid emoji definition file '%s': %s", Files[ i ], Err )
		end
	end

	EmojiIndex:SortKeys()

	EmojiRepository.TotalEmojiCount = EmojiByName[ 0 ]

	-- Note: math.log10 is more precise than math.log( x, 10 ).
	local ShortNamePaddingSize = math.floor( math.log10( EmojiByName[ 0 ] ) ) + 1

	-- For each emoji, assign a short name of the form "e{Index}", e.g. "e100" or "e010". This is left-padded to ensure
	-- every emoji takes up the exact same number of characters. These short names can then be used internally when
	-- submitting chat messages to normalise the space taken up by each emoji, rather than punishing those that have
	-- longer human-readable names.
	for i = 1, EmojiByName[ 0 ] do
		local EmojiDef = EmojiByName[ i ]
		local ShortName = StringFormat( "e%."..ShortNamePaddingSize.."d", i )
		EmojiDef.ShortName = ShortName
		-- Only need to add the short name to the lookup table, don't want to show these names in search results.
		EmojiByName[ ShortName ] = EmojiDef
	end
end

if Client then
	local FREQUENTLY_USED_EMOJI_FILE_PATH = "config://shine/temp/cl_frequently_used_emoji.json"
	local FrequentlyUsedEmoji
	local function CompareEmoji( Left, Right )
		local LeftCount = FrequentlyUsedEmoji:Get( Left )
		local RightCount = FrequentlyUsedEmoji:Get( Right )

		if LeftCount > RightCount then return true end
		if LeftCount < RightCount then return false end

		local LeftIndex = EmojiByName[ Left ] and EmojiByName[ Left ].Index
		local RightIndex = EmojiByName[ Right ] and EmojiByName[ Right ].Index

		if LeftIndex and RightIndex then
			return LeftIndex < RightIndex
		end

		if LeftIndex then return true end
		if RightIndex then return false end

		return Left < Right
	end

	do
		local SavedFrequentlyUsedEmoji = Shine.LoadJSONFile( FREQUENTLY_USED_EMOJI_FILE_PATH )
		if IsType( SavedFrequentlyUsedEmoji, "table" ) then
			FrequentlyUsedEmoji = Shine.Map( SavedFrequentlyUsedEmoji )
		else
			FrequentlyUsedEmoji = Shine.Map()
		end

		FrequentlyUsedEmoji:SortKeys( CompareEmoji )
	end

	local SortRequired = false
	local SaveTimer
	local function SaveFrequentlyUsedEmoji()
		Shine.SaveJSONFile( FrequentlyUsedEmoji:AsTable(), FREQUENTLY_USED_EMOJI_FILE_PATH, {
			indent = false
		} )
		SaveTimer = nil
	end

	function EmojiRepository.IncrementEmojiUsageCounter( EmojiName )
		SortRequired = true
		FrequentlyUsedEmoji:Add( EmojiName, ( FrequentlyUsedEmoji:Get( EmojiName ) or 0 ) + 1 )

		if not SaveTimer then
			SaveTimer = Shine.Timer.Create( "EmojiRepository_SaveFrequentlyUsed", 5, 1, SaveFrequentlyUsedEmoji )
		end
		SaveTimer:Debounce()
	end

	local function EmojiExists( Key ) return EmojiByName[ Key ] ~= nil end

	function EmojiRepository.GetFrequentlyUsedEmoji()
		if SortRequired then
			SortRequired = false
			FrequentlyUsedEmoji:SortKeys( CompareEmoji )
		end
		return Shine.Map( FrequentlyUsedEmoji ):Filter( EmojiExists )
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

	local ImageElement = require "shine/lib/gui/richtext/elements/image"

	function EmojiRepository.MakeEmojiElement( EmojiName )
		local EmojiDef = EmojiByName[ EmojiName ]
		if not EmojiDef then return nil end

		return ImageElement( {
			Texture = EmojiDef.Texture,
			TextureCoordinates = EmojiDef.TextureCoordinates,
			TexturePixelCoordinates = EmojiDef.TexturePixelCoordinates,
			Tooltip = StringFormat( ":%s:", EmojiDef.Name )
		} )
	end

	function EmojiRepository.GetCategoryDefinition( CategoryName )
		return EmojiCategories[ CategoryName ]
	end
elseif Server then
	local BitSet = Shine.BitSet
	local rawset = rawset
	local Stream = Shine.Stream
	local StringFind = string.find
	local StringPatternSafe = string.PatternSafe

	local PatternMatchCache = setmetatable( {}, {
		__index = function( self, Pattern )
			if not StringFind( Pattern, "*", 1, true ) then
				if StringSub( Pattern, 1, 2 ) == "c:" then
					-- Matching an entire category.
					local CategoryName = StringSub( Pattern, 3 )
					local EmojiForCategory = EmojiByCategory:Get( CategoryName )
					if EmojiForCategory then
						local Matches = BitSet()
						for i = 1, #EmojiForCategory do
							Matches:Add( EmojiForCategory[ i ].Index )
						end

						rawset( self, Pattern, Matches )

						return Matches
					end

					return nil
				end

				-- No need to cache this, just return the index if the emoji exists.
				local EmojiDef = EmojiByName[ Pattern ]
				return EmojiDef and EmojiDef.Index
			end

			-- Pattern has wildcards, convert to a Lua pattern then search the emoji list for matches.
			local Matches = BitSet()
			if Pattern == "*" then
				-- Pure wildcard can just add every emoji index.
				Matches:AddRange( 1, EmojiByName[ 0 ] )
			else
				-- This isn't the fastest way of doing this, but given it's cached and that the number of emoji is
				-- unlikely to be large enough to cause a noticeable slowdown, it's sufficient.
				local PlaintextSegments = Stream(
					StringExplode( Pattern, "*", true )
				):Map( StringPatternSafe ):AsTable()
				local SearchPattern = "^"..TableConcat( PlaintextSegments, ".*" ).."$"

				-- Collect the emoji indices that match the pattern rather than names, as it's the indices that are
				-- networked to players.
				for i = 1, EmojiByName[ 0 ] do
					local EmojiName = EmojiByName[ i ].Name
					if StringFind( EmojiName, SearchPattern ) then
						Matches:Add( i )
					end
				end
			end

			rawset( self, Pattern, Matches )

			return Matches
		end
	} )

	--[[
		Returns either an emoji index or a bitset of emoji indices that match the given pattern.

		Patterns are expected to be either exact emoji names, or names with wildcards ("*" to match 0 or more
		characters).

		For example:
		* "example_emoji" - matches the exact emoji named "example_emoji".
		* "example_*" - matches any emoji name that starts with "example_".
		* "*_emoji" - matches any emoji name that ends with "_emoji".
	]]
	function EmojiRepository.FindByPattern( Pattern )
		local NormalisedPattern = StringLower( StringGSub( Pattern, "%*+", "*" ) )
		return PatternMatchCache[ NormalisedPattern ]
	end
end

function EmojiRepository.GetAllEmoji()
	return EmojiByName
end

function EmojiRepository.GetEmojiDefinition( EmojiName )
	return EmojiByName[ EmojiName ]
end

return EmojiRepository
