--[[
	Provides a memory-efficient set of non-negative integer values.

	This stores at most n / 32 numbers for a given set with a max value of n. Adding, removing, and retrieving are all
	constant time operations.

	Passing negative values to this set will result in undefined behaviour.
]]

local BitBAnd = bit.band
local BitBNot = bit.bnot
local BitBOr = bit.bor
local BitLShift = bit.lshift
local BitRShift = bit.rshift
local Max = math.max
local Min = math.min
local setmetatable = setmetatable
local StringFormat = string.format
local TableEmpty = table.Empty
local TableNew = require "table.new"

local BitSet = Shine.TypeDef()
Shine.BitSet = BitSet

local function CountBits( Value )
	local Count = 0
	for i = 0, 31 do
		Count = Count + BitRShift( BitBAnd( Value, BitLShift( 1, i ) ), i )
	end
	return Count
end

--[[
	Constructs a bitset from the given (1-based) array of raw integer values.
]]
function BitSet.FromData( Values )
	local Set = BitSet()
	local NumValues = #Values
	local Size = 0

	for i = 1, NumValues do
		Set.Values[ i - 1 ] = Values[ i ]
		Size = Size + CountBits( Values[ i ] )
	end

	Set.MaxArrayIndex = Max( NumValues - 1, 0 )
	Set.Size = Size

	return Set
end

local DefaultZeroMeta = {
	-- For simplicity, make unpopulated array values equal to 0 without needing nil checks.
	__index = function() return 0 end
}

function BitSet:Init()
	-- Note: this table uses 0-based indexing as that fits the bitwise arithmetic.
	self.Values = setmetatable( {
		[ 0 ] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	}, DefaultZeroMeta )
	self.Size = 0
	-- This value is inclusive (as per Lua iteration conventions).
	self.MaxArrayIndex = 0

	return self
end

local function GetIndexForValue( Value )
	-- Right shift by 5 is equivalent to floored-division by 32, and bitwise-and with 31 is equivalent to modulo 32.
	-- LuaJIT uses signed 32-bit integer values for its bitwise functions when passed a Lua number, hence the bitset is
	-- treated as an array of 32-bit integers.
	-- These indices are both 0-based.
	return BitRShift( Value, 5 ), BitBAnd( Value, 31 )
end

local function AddBit( self, ArrayIndex, BitIndex )
	local ArrayValue = self.Values[ ArrayIndex ]
	local BitFlag = BitLShift( 1, BitIndex )
	-- Avoid branching here by using a bitwise expression to conditionally increment the size. This will be 0 if the
	-- value exists already, or 1 otherwise.
	local SizeIncrement = 1 - BitRShift( BitBAnd( ArrayValue, BitFlag ), BitIndex )

	self.Values[ ArrayIndex ] = BitBOr( ArrayValue, BitFlag )
	self.Size = self.Size + SizeIncrement
	self.MaxArrayIndex = Max( self.MaxArrayIndex, ArrayIndex )
end

--[[
	Adds the given integer value to this set.
]]
function BitSet:Add( Value )
	local ArrayIndex, BitIndex = GetIndexForValue( Value )

	AddBit( self, ArrayIndex, BitIndex )

	return self
end

local FilledValue = 0
for i = 0, 31 do
	FilledValue = BitBOr( FilledValue, BitLShift( 1, i ) )
end

--[[
	Adds the given inclusive range of values to the set.
]]
function BitSet:AddRange( StartValue, EndValue )
	local StartArrayIndex, StartBitIndex = GetIndexForValue( StartValue )
	local EndArrayIndex, EndBitIndex = GetIndexForValue( EndValue )

	for i = StartBitIndex, 31 do
		AddBit( self, StartArrayIndex, i )
	end

	for i = StartArrayIndex + 1, EndArrayIndex - 1 do
		local SizeBefore = CountBits( self.Values[ i ] )
		self.Values[ i ] = FilledValue
		self.Size = self.Size + ( 32 - SizeBefore )
	end

	for i = 0, EndBitIndex do
		AddBit( self, EndArrayIndex, i )
	end

	return self
end

--[[
	Adds all values from the given set to this set.
]]
function BitSet:Union( OtherSet )
	local Size = 0
	-- Iterate through the entirety of the other set, adding its values.
	for i = 0, OtherSet.MaxArrayIndex do
		local NewValue = BitBOr( self.Values[ i ], OtherSet.Values[ i ] )
		Size = Size + CountBits( NewValue )
		self.Values[ i ] = NewValue
	end

	self.MaxArrayIndex = Max( self.MaxArrayIndex, OtherSet.MaxArrayIndex )
	self.Size = Size

	return self
end

--[[
	Retains all values in this set that are also contained within the given set.
	All other values are removed from this set.
]]
function BitSet:Intersection( OtherSet )
	local Size = 0
	-- Only need to iterate the local set, anything in the other set beyond that will be ignored.
	for i = 0, self.MaxArrayIndex do
		local NewValue = BitBAnd( self.Values[ i ], OtherSet.Values[ i ] )
		Size = Size + CountBits( NewValue )
		self.Values[ i ] = NewValue
	end

	self.Size = Size

	return self
end

--[[
	Adds all integer values from the given array to this set.
]]
function BitSet:AddAll( Values )
	for i = 1, #Values do
		self:Add( Values[ i ] )
	end
	return self
end

function BitSet:Contains( Value )
	local ArrayIndex, BitIndex = GetIndexForValue( Value )
	return BitBAnd( self.Values[ ArrayIndex ], BitLShift( 1, BitIndex ) ) ~= 0
end

local function RemoveBit( self, ArrayIndex, BitIndex )
	local ArrayValue = self.Values[ ArrayIndex ]
	local BitFlag = BitLShift( 1, BitIndex )
	-- As with adding, avoid branching here. This will be 1 if the value was stored, or 0 otherwise.
	local SizeDecrement = BitRShift( BitBAnd( ArrayValue, BitFlag ), BitIndex )

	self.Values[ ArrayIndex ] = BitBAnd( ArrayValue, BitBNot( BitFlag ) )
	self.Size = self.Size - SizeDecrement
end

--[[
	Removes the given integer value from this set.
]]
function BitSet:Remove( Value )
	local ArrayIndex, BitIndex = GetIndexForValue( Value )

	RemoveBit( self, ArrayIndex, BitIndex )

	return self
end

--[[
	Removes the given inclusive range of values from the set.
]]
function BitSet:RemoveRange( StartValue, EndValue )
	local StartArrayIndex, StartBitIndex = GetIndexForValue( StartValue )
	local EndArrayIndex, EndBitIndex = GetIndexForValue( EndValue )

	for i = StartBitIndex, 31 do
		RemoveBit( self, StartArrayIndex, i )
	end

	for i = StartArrayIndex + 1, EndArrayIndex - 1 do
		local SizeBefore = CountBits( self.Values[ i ] )
		self.Values[ i ] = 0
		self.Size = self.Size - SizeBefore
	end

	for i = 0, EndBitIndex do
		RemoveBit( self, EndArrayIndex, i )
	end

	return self
end

--[[
	Removes all integer values in the given array from this set.
]]
function BitSet:RemoveAll( Values )
	for i = 1, #Values do
		self:Remove( Values[ i ] )
	end
	return self
end

--[[
	Removes all values contained within the given set from this set.
]]
function BitSet:AndNot( OtherSet )
	local Size = 0
	-- Even if the other set is smaller, iterate the full length of this set to ensure the new size is correct.
	for i = 0, self.MaxArrayIndex do
		local NewValue = BitBAnd( self.Values[ i ], BitBNot( OtherSet.Values[ i ] ) )
		Size = Size + CountBits( NewValue )
		self.Values[ i ] = NewValue
	end

	self.Size = Size

	return self
end

function BitSet:Clear()
	TableEmpty( self.Values )
	self.Size = 0
	self.MaxArrayIndex = 0
	return self
end

function BitSet:GetCount()
	return self.Size
end

do
	local function IterateBitSet( Set, Value )
		local Values = Set.Values
		local ArrayIndex, BitIndex

		if Value then
			-- Not the first step, start from the last found value.
			ArrayIndex, BitIndex = GetIndexForValue( Value )
		else
			-- First step of the iteration, start from the first element.
			ArrayIndex = 0
			BitIndex = -1
		end

		for i = ArrayIndex, Set.MaxArrayIndex do
			local Int = Values[ i ]
			for j = BitIndex + 1, 31 do
				local NextValue = BitBAnd( Int, BitLShift( 1, j ) )
				if NextValue ~= 0 then
					return i * 32 + j
				end
			end
			-- Make sure the next iteration starts from bit 0.
			BitIndex = -1
		end

		return nil
	end

	--[[
		Iterates all values in the set.

		Note that this is a somewhat costly operation relative to a normal set. Generally, it's preferable to use the
		Union/Intersection/AndNot methods to work over batches of values.
	]]
	function BitSet:Iterate()
		return IterateBitSet, self
	end
end

BitSet.__len = BitSet.GetCount

function BitSet:__eq( OtherSet )
	local OurSize = self:GetCount()
	if OtherSet:GetCount() ~= OurSize then return false end

	-- Have to iterate over the max of the two arrays, one side may store 0 explicitly while the other does not.
	for i = 1, Max( self.MaxArrayIndex, OtherSet.MaxArrayIndex ) do
		if self.Values[ i ] ~= OtherSet.Values[ i ] then
			return false
		end
	end

	return true
end

function BitSet:__tostring()
	return StringFormat(
		"BitSet [%s element%s, MaxArrayIndex = %s]",
		self.Size,
		self.Size == 1 and "" or "s",
		self.MaxArrayIndex
	)
end
