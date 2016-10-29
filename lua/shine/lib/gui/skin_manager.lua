--[[
	Manages skinning of controls through simple property setting.

	Controls themselves only have to worry about what happens when a property is set, not
	the actual setting of colours/fonts etc. at startup.
]]

local SGUI = Shine.GUI

local pairs = pairs
local TableShallowMerge = table.ShallowMerge

local SkinManager = {}
SGUI.SkinManager = SkinManager

SkinManager.Skins = {}

function SkinManager:RegisterSkin( Name, SkinTable )
	for Element, Data in pairs( SkinTable ) do
		local Default = Data.Default

		for StyleName, StyleData in pairs( Data ) do
			if StyleName ~= "Default" then
				TableShallowMerge( Default, StyleData )
			end
		end
	end

	self.Skins[ Name ] = SkinTable
end

function SkinManager:RefreshSkin()
	for Control in SGUI.ActiveControls:Iterate() do
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

function SkinManager:SetSkin( Name )
	local SkinTable = self.Skins[ Name ]

	assert( SkinTable, "[SGUI] Attempted to set a non-existant skin!" )

	self.Skin = SkinTable
	self:RefreshSkin()
end

function SkinManager:GetStyleForElement( Element )
	local Skin = Element:GetSkin() or self.Skin
	if not Skin then return nil end

	local Styles = Skin[ Element.Class ]
	if not Styles then return nil end

	local Style = Element:GetStyleName() or "Default"
	return Styles[ Style ] or Styles.Default
end

function SkinManager:ApplySkin( Element )
	if not Element.UseScheme then return end

	local StyleDef = self:GetStyleForElement( Element )
	if not StyleDef then return end

	-- States can apply different scheme values, e.g. focus/hover etc.
	local State = Element:GetStylingState()
	if State and StyleDef.States then
		StyleDef = StyleDef.States[ State ] or StyleDef
	end

	local StyleCopy = {}
	for Key, Value in pairs( StyleDef ) do
		if SGUI.IsColour( Value ) then
			StyleCopy[ Key ] = SGUI.CopyColour( Value )
		else
			StyleCopy[ Key ] = Value
		end
	end

	Element:SetupFromTable( StyleCopy )
end

Shine.LoadScriptsByPath( "lua/shine/lib/gui/skins" )
SkinManager:SetSkin( "Default" )
