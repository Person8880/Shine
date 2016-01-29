--[[
	Makes storing values to disk easy.

	Use Storage:GetAtPath() and Storage:SetAtPath() to get the most out of it,
	rather than just reading/writing to the internal data table.
]]

local Shine = Shine

local StringStartsWith = string.StartsWith
local TableBuild = table.Build
local tostring = tostring

local Storage = Shine.TypeDef()
Shine.Storage = Storage

--[[
	Construct a storage from a file path.
]]
function Storage:Init( FilePath )
	Shine.TypeCheck( FilePath, "string", 1, "Storage:Init()" )
	Shine.AssertAtLevel( StringStartsWith( FilePath, "config://" ),
		"A storage can only be created for a file under the config:// path.", 3 )

	self.Data = Shine.LoadJSONFile( FilePath ) or {}
	self.FilePath = FilePath
	self.StorageSettings = { indent = false }

	return self
end

--[[
	Forces a save of the current data to disk. Will not save any uncommitted transaction
	values.
]]
function Storage:Save()
	return Shine.SaveJSONFile( self.Data, self.FilePath, self.StorageSettings )
end

--[[
	Begins a transaction for this storage.

	While a transaction has started but not been committed or rolled back,
	the storage will remember all values set, but not commit them to the
	underlying data storage.

	To complete a transaction, call either Storage:Commit() or Storage:Rollback(),
	to either save the changes made or roll them all back.
]]
function Storage:BeginTransaction()
	Shine.AssertAtLevel( not self.Transaction, "A transaction has already been started.", 3 )
	self.Transaction = Shine.Map()
end

--[[
	Commits the current transaction.

	This sets all values to the underlying data table, then saves to disk.
]]
function Storage:Commit()
	local DataToCommit = Shine.AssertAtLevel( self.Transaction, "No transaction has been started.", 3 )
	self.Transaction = nil

	for PathKey, Data in DataToCommit:Iterate() do
		self:SetAtPath( Data.Value, unpack( Data.Path ) )
	end

	self:Save()
end

--[[
	Rolls back the current transaction, discarding all changes made since the
	call to BeginTransaction().
]]
function Storage:Rollback()
	Shine.AssertAtLevel( self.Transaction, "No transaction has been started.", 3 )
	self.Transaction = nil
end

local function GetPathKey( ... )
	-- Can get away with this because JSON cannot have number and string indices in the same object.
	return Shine.Stream( { ... } ):Concat( "", tostring )
end

--[[
	Internal method, use GetAtPath(), not this.

	Returns the value at the given path if it has been set/updated in
	the current transaction.
]]
function Storage:GetInTransaction( ... )
	local Entry = self.Transaction:Get( GetPathKey( ... ) )
	return Entry and Entry.Value
end

--[[
	Returns the value stored at the given path, if any.

	When in a transaction, this will include values added/changed
	during the transaction.
]]
function Storage:GetAtPath( ... )
	if self.Transaction then
		local Result = self:GetInTransaction( ... )
		if Result ~= nil then return Result end
	end

	local PathCount = select( "#", ... )
	local Value = self.Data

	for i = 1, PathCount do
		local Segment = select( i, ... )
		Value = Value[ Segment ]
		if Value == nil then
			return nil
		end
	end

	return Value
end

--[[
	Sets the given value to the location specified by the given path.

	If any of the intermediate steps in the path are missing, they will be created
	as new tables.
]]
function Storage:SetAtPath( Value, ... )
	-- If we're in a transaction, temporarily store the values outside the data table.
	if self.Transaction then
		self.Transaction:Add( GetPathKey( ... ), {
			Value = Value,
			Path = { ... }
		} )

		return
	end

	-- Otherwise, store as normal.
	local PathCount = select( "#", ... )
	local Parent = self.Data
	if PathCount > 1 then
		local Args = { ... }
		Args[ #Args ] = nil

		Parent = TableBuild( self.Data, unpack( Args ) )
	end

	Parent[ select( PathCount, ... ) ] = Value
end
