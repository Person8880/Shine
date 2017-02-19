--[[
	Version object, allowing comparison of version numbers.
]]

local StringExplode = string.Explode

local Version = Shine.TypeDef()

local function ToNumberOrZero( Value ) return tonumber( Value ) or 0 end

function Version:Init( Specifier )
	self.Components = Shine.Stream( StringExplode( Specifier, "%." ) ):Map( ToNumberOrZero ):AsTable()
	while #self.Components < 3 do
		self.Components[ #self.Components + 1 ] = 0
	end

	return self
end

function Version:LessThan( OtherVersion )
	for i = 1, 3 do
		local OurComponent = self.Components[ i ]
		local TheirComponent = OtherVersion.Components[ i ]

		-- If our major > their major, we're newer, and so on.
		if OurComponent > TheirComponent then return false end
		-- If our major < their major, we're older, and so on.
		if OurComponent < TheirComponent then return true end
	end

	-- No conclusion.
	return nil
end

function Version:__lt( OtherVersion )
	return self:LessThan( OtherVersion ) or false
end

function Version:__le( OtherVersion )
	-- Either less than explicitly...
	local IsLessThan = self:LessThan( OtherVersion )
	if IsLessThan ~= nil then return IsLessThan end

	-- Or exactly equal.
	return true
end

function Version:__eq( OtherVersion )
	-- Equal if first 3 version components are equal.
	for i = 1, 3 do
		if self.Components[ i ] ~= OtherVersion.Components[ i ] then
			return false
		end
	end

	return true
end

function Version:__tostring()
	return Shine.Stream( self.Components ):Concat( ".", tostring )
end

Shine.VersionHolder = Version
