--[[
	A file for hotfixing issues that annoy me.
]]

local Shine = Shine
local Hotfixes

if Server then
	-- Server hotfixes
else
	-- Client hotfixes
end

if not Hotfixes then return end

for Name, HotfixData in pairs( Hotfixes ) do
	if HotfixData:ShouldApply() then
		HotfixData:Hotfix()
		Hotfixes[ Name ] = nil
	end
end

Shine.Hook.Add( "PostLoadScript", "HotfixNS2Bugs", function( ScriptName )
	local HotfixData = Hotfixes[ ScriptName ]
	if HotfixData and HotfixData:ShouldApply() then
		HotfixData:Hotfix()
	end
end )
