--[[
	Manages skinning of controls through simple property setting.

	Controls themselves only have to worry about what happens when a property is set, not
	the actual setting of colours/fonts etc. at startup.
]]

local Map = Shine.Map
local SGUI = Shine.GUI

local getmetatable = getmetatable
local pairs = pairs
local setmetatable = setmetatable
local TableShallowMerge = table.ShallowMerge

local SkinManager = {}
SGUI.SkinManager = SkinManager

SkinManager.Skins = {}

--[[
	Compiles the given skin into a format that avoids needing to use pairs() at runtime.
]]
function SkinManager.CompileSkin( Skin )
	local CompiledSkin = {}

	for Element, Data in pairs( Skin ) do
		local ElementStyles = {}

		for StyleName, StyleData in pairs( Data ) do
			local Properties = {}
			local States = {}

			for Key, Value in pairs( StyleData ) do
				if Key == "States" then
					for StateName, StateData in pairs( Value ) do
						local StateProperties = {}

						for StateKey, StateValue in pairs( StateData ) do
							StateProperties[ #StateProperties + 1 ] = { StateKey, StateValue }
						end

						States[ StateName ] = StateProperties
					end
				else
					Properties[ #Properties + 1 ] = { Key, Value }
				end
			end

			ElementStyles[ StyleName ] = {
				Properties = Properties,
				States = States,
				PropertiesByName = StyleData
			}
		end

		CompiledSkin[ Element ] = ElementStyles
	end

	return CompiledSkin
end

function SkinManager:GetCompiledSkin( Skin )
	local MetaTable = getmetatable( Skin )
	local CompiledSkin = MetaTable and MetaTable.CompiledSkin

	if not CompiledSkin then
		CompiledSkin = self.CompileSkin( Skin )
		setmetatable( Skin, { CompiledSkin = CompiledSkin } )
	end

	return CompiledSkin
end

function SkinManager:RegisterSkin( Name, SkinTable )
	for Element, Data in pairs( SkinTable ) do
		local Default = Data.Default

		for StyleName, StyleData in pairs( Data ) do
			if StyleName ~= "Default" then
				-- Inherit default styling values
				TableShallowMerge( Default, StyleData )

				-- Also inherit any states from the default that are not overridden.
				if Default.States and StyleData.States then
					TableShallowMerge( Default.States, StyleData.States )
				end
			end
		end
	end

	self.Skins[ Name ] = SkinTable

	-- Compile and store the skin upfront.
	self:GetCompiledSkin( SkinTable )
end

function SkinManager:RefreshSkin()
	for Element in SGUI.ActiveControls:Iterate() do
		self:ApplySkin( Element )
	end
end

function SkinManager:ReloadSkins()
	Shine.LoadScriptsByPath( "lua/shine/lib/gui/skins", false, true )

	self:RefreshSkin()

	Shared.Message( "[SGUI] Skins reloaded successfully." )
end

function SkinManager:GetSkin()
	return self.Skin
end

function SkinManager:GetSkinsByName()
	return self.Skins
end

function SkinManager:SetSkin( Name )
	local SkinTable = self.Skins[ Name ]

	assert( SkinTable, "[SGUI] Attempted to set a non-existant skin!" )

	self.Skin = SkinTable
	self:RefreshSkin()
end

function SkinManager:GetStyleForElement( Element )
	local Skin = Element:GetSkin() or self.Skin
	if not Skin then return nil end

	Skin = self:GetCompiledSkin( Skin )

	local Styles = Skin[ Element.Class ]
	if not Styles then return nil end

	local Style = Element:GetStyleName() or "Default"
	return Styles[ Style ] or Styles.Default
end

-- These are properties that should be applied only as defaults. They may be changed
-- dynamically based on resolution and thus should not be reset if the skin changes.
local PropertiesToApplyAsDefaults = {
	Font = true,
	TextScale = true,
	HeaderSize = true,
	LineSize = true
}

local function CopyValues( Element, Values, Destination )
	for i = 1, #Values do
		local Entry = Values[ i ]
		local Key = Entry[ 1 ]

		if not PropertiesToApplyAsDefaults[ Key ] or Element[ Key ] == nil then
			local Value = Entry[ 2 ]
			if SGUI.IsColour( Value ) then
				Destination:Add( Key, SGUI.CopyColour( Value ) )
			else
				Destination:Add( Key, Value )
			end
		end
	end

	return Destination
end

function SkinManager:ApplySkin( Element )
	if not Element.UseScheme then return end

	local StyleDef = self:GetStyleForElement( Element )
	if not StyleDef then return end

	-- Combine the current styling with the state to get the final styling values.
	-- If only the state values were applied, changing skins could lead to incorrect
	-- values being left from a previous skin.
	local StyleCopy = CopyValues( Element, StyleDef.Properties, Map() )

	-- If the element has styling states (not using the getter to avoid initialising them), apply them.
	local States = Element.StylingStates
	if States and StyleDef.States then
		for State in States:Iterate() do
			local StateValues = StyleDef.States[ State ]
			if StateValues then
				StyleCopy = CopyValues( Element, StateValues, StyleCopy )
			end
		end
	end

	Element:SetupFromMap( StyleCopy )
end

Shine.LoadScriptsByPath( "lua/shine/lib/gui/skins" )

local ConfiguredSkin = Shine.Config.Skin
if not SkinManager.Skins[ ConfiguredSkin ] then
	ConfiguredSkin = "Default"
end
SkinManager:SetSkin( ConfiguredSkin )
