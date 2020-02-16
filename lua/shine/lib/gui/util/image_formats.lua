--[[
	Provides parser/validator functions for various image formats.
]]

local BAnd = bit.band
local BOr = bit.bor
local LShift = bit.lshift
local Min = math.min
local RShift = bit.rshift
local StringByte = string.byte
local StringSub = string.sub

local function UInt16BE( Byte1, Byte2 )
	return BOr( LShift( Byte1, 8 ), Byte2 )
end

local function UInt16LE( Byte1, Byte2 )
	return BOr( LShift( Byte2, 8 ), Byte1 )
end

local function UInt24LE( Byte1, Byte2, Byte3 )
	return BOr( LShift( Byte3, 16 ), LShift( Byte2, 8 ), Byte1 )
end

local function UInt32BE( Byte1, Byte2, Byte3, Byte4 )
	return BOr( LShift( Byte1, 24 ), LShift( Byte2, 16 ), LShift( Byte3, 8 ), Byte4 )
end

local function UInt32LE( Byte1, Byte2, Byte3, Byte4 )
	return BOr( LShift( Byte4, 24 ), LShift( Byte3, 16 ), LShift( Byte2, 8 ), Byte1 )
end

return {
	[ "image/png" ] = function( Data )
		-- Validate the header is as expected.
		local ExpectedBytes = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }
		for i = 1, #ExpectedBytes do
			local Byte = StringByte( Data, i )
			if Byte ~= ExpectedBytes[ i ] then
				return nil
			end
		end

		-- Expect an image header.
		if StringSub( Data, 13, 16 ) ~= "IHDR" then
			return nil
		end

		local SizeData = StringSub( Data, 17, 24 )
		if #SizeData ~= 8 then return nil end

		local Width = UInt32BE( StringByte( SizeData, 1, 4 ) )
		local Height = UInt32BE( StringByte( SizeData, 5, 8 ) )

		return Width, Height
	end,
	[ "image/jpeg" ] = function( Data )
		-- Look for the expected magic bytes (FF D8) then the start of a marker (FF).
		local Byte1, Byte2, Byte3, Byte4 = StringByte( Data, 1, 4 )
		if Byte1 ~= 0xFF or Byte2 ~= 0xD8 or Byte3 ~= 0xFF then
			return nil
		end

		-- Must be a supported type of JPG (raw, JFIF or EXIF).
		if Byte4 ~= 0xDB and Byte4 ~= 0xE0 and Byte4 ~= 0xE1 then
			return nil
		end

		-- Should always end in FF D9, otherwise it's corrupt.
		local LastByte1, LastByte2 = StringByte( Data, #Data - 1, #Data )
		if LastByte1 ~= 0xFF or LastByte2 ~= 0xD9 then
			return nil
		end

		local Index = 3
		local Length = #Data
		local Width, Height
		while Index <= Length do
			-- Segment marker (FF ??)
			local Marker, Code = StringByte( Data, Index, Index + 1 )
			if Marker ~= 0xFF then
				return nil
			end

			-- Size of segment as a 16 bit integer.
			local SizeByte1, SizeByte2 = StringByte( Data, Index + 2, Index + 3 )
			if not SizeByte1 or not SizeByte2 then
				return nil
			end

			Index = Index + 4

			if Code >= 0xC0 and Code <= 0xC3 then
				-- Is a Start Of Frame segment, extract the width/height from it.
				local SizeData = StringSub( Data, Index, Index + 4 )
				if #SizeData ~= 5 then
					return nil
				end

				local Height1, Height2, Width1, Width2 = StringByte( SizeData, 2, 5 )
				Width = UInt16BE( Width1, Width2 )
				Height = UInt16BE( Height1, Height2 )

				break
			end

			local Length = UInt16BE( SizeByte1, SizeByte2 )
			-- Length includes its own 2 bytes.
			Index = Index + Length - 2
		end

		return Width, Height
	end,
	[ "image/gif" ] = function( Data )
		local Header = StringSub( Data, 1, 6 )
		if Header ~= "GIF87a" and Header ~= "GIF89a" then
			return nil
		end

		-- Make sure there's enough information to parse the width/height values.
		if #Data < 10 then
			return nil
		end

		local Width = UInt16LE( StringByte( Data, 7, 8 ) )
		local Height = UInt16LE( StringByte( Data, 9, 10 ) )

		return Width, Height
	end,
	[ "image/webp" ] = function( Data )
		local Header = StringSub( Data, 1, 4 )
		if Header ~= "RIFF" then
			return nil
		end

		local Index = 5
		local FileSize = Min( UInt32LE( StringByte( Data, Index, Index + 3 ) ) - 4, #Data )
		Index = Index + 4

		local Identifier = StringSub( Data, Index, Index + 3 )
		if Identifier ~= "WEBP" then
			return nil
		end

		Index = Index + 4

		while Index <= FileSize do
			-- Chunks always start with 4 bytes of text indicating the type.
			local ChunkType = StringSub( Data, Index, Index + 3 )
			if #ChunkType < 4 then
				return nil
			end

			Index = Index + 4

			if Index + 3 > FileSize then
				return nil
			end

			-- Then the length of the chunk.
			local ChunkLength = UInt32LE( StringByte( Data, Index, Index + 3 ) )
			Index = Index + 4

			if ChunkType == "VP8 " then
				-- Make sure all expected header bytes are present.
				if Index + 9 > FileSize then
					return nil
				end

				-- VP8 encoded frame, make sure the expected magic bytes are present.
				if StringByte( Data, Index + 3 ) ~= 0x9D
				or StringByte( Data, Index + 4 ) ~= 0x01
				or StringByte( Data, Index + 5 ) ~= 0x2A then
					return nil
				end

				local Width = UInt16LE( StringByte( Data, Index + 6, Index + 7 ) )
				local Height = UInt16LE( StringByte( Data, Index + 8, Index + 9 ) )

				return Width, Height
			elseif ChunkType == "VP8L" then
				-- Make sure all expected header bytes are present.
				if Index + 4 > FileSize then
					return nil
				end

				-- VP8 lossless frame, look for magic byte.
				if StringByte( Data, Index ) ~= 0x2F then
					return nil
				end

				local Byte1, Byte2, Byte3, Byte4 = StringByte( Data, Index + 1, Index + 4 )
				-- Width and height are encoded in 14 bits for each dimension, but as 1 less than their value.
				local WidthMinusOne = BOr( LShift( BAnd( Byte2, 0x3F ), 8 ), Byte1 )
				local HeightMinusOne = BOr( LShift( BAnd( Byte4, 0xF ), 10 ), LShift( Byte3, 2 ),
					RShift( Byte2, 6 ) )

				return WidthMinusOne + 1, HeightMinusOne + 1
			elseif ChunkType == "VP8X" then
				-- Make sure all expected header bytes are present.
				if Index + 9 > FileSize then
					return nil
				end

				-- VP8 lossy frame, no magic bytes so just grab the 24 bit width/height values.
				local WidthMinusOne = UInt24LE( StringByte( Data, Index + 4, Index + 6 ) )
				local HeightMinusOne = UInt24LE( StringByte( Data, Index + 7, Index + 9 ) )

				return WidthMinusOne + 1, HeightMinusOne + 1
			else
				-- Chunks are always padded to have even size.
				Index = Index + ChunkLength + ChunkLength % 2
			end
		end

		return nil
	end
}
