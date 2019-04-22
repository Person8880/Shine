--[[
	Basically a GUI text item bound to SGUI.
]]

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local getmetatable = getmetatable

local Label = {}

SGUI.AddBoundProperty( Label, "Colour", "Label:SetColor" )
SGUI.AddBoundProperty( Label, "InheritsParentAlpha", "Label" )
SGUI.AddBoundProperty( Label, "Font", "Label:SetFontName", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Label, "Text", "Label", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Label, "TextAlignmentX", "Label" )
SGUI.AddBoundProperty( Label, "TextAlignmentY", "Label" )
SGUI.AddBoundProperty( Label, "TextScale", "Label:SetScale", { "InvalidatesParent" } )

-- Auto-wrapping allows labels to automatically word-wrap based on a given auto-width (or fill size).
SGUI.AddProperty( Label, "AutoWrap", { "InvalidatesParent" } )

function Label:Initialise()
	self.BaseClass.Initialise( self )

	self.Label = self:MakeGUITextItem()
	self.Background = self.Label
	self.TextScale = Vector2( 1, 1 )
	self.TextAlignmentX = GUIItem.Align_Min
	self.TextAlignmentY = GUIItem.Align_Min

	local function MarkSizeDirty()
		self.CachedTextWidth = nil
		self.CachedTextHeight = nil
	end
	self:AddPropertyChangeListener( "Text", MarkSizeDirty )
	self:AddPropertyChangeListener( "Font", MarkSizeDirty )
	self:AddPropertyChangeListener( "TextScale", MarkSizeDirty )
end

function Label:MouseIn( Element, Mult, MaxX, MaxY )
	return self:MouseInControl( Mult, MaxX, MaxY )
end

local AlignmentMultipliers = {
	[ GUIItem.Align_Center ] = -0.5,
	[ GUIItem.Align_Max ] = -1,
	[ GUIItem.Align_Min ] = 0
}

function Label:GetScreenPos()
	local Pos = self.BaseClass.GetScreenPos( self )
	local Size = self:GetSize()

	local XAlign = self:GetTextAlignmentX()
	Pos.x = Pos.x + Size.x * AlignmentMultipliers[ XAlign ]

	local YAlign = self:GetTextAlignmentY()
	Pos.y = Pos.y + Size.y * AlignmentMultipliers[ YAlign ]

	return Pos
end

function Label:SetupStencil()
	self.Label:SetInheritsParentStencilSettings( false )
	self.Label:SetStencilFunc( GUIItem.NotEqual )
end

-- Apply word wrapping before the height is computed (assuming height = Units.Auto()).
function Label:PreComputeHeight( Width )
	if not self.AutoWrap then return end

	local CurrentText = self.Label:GetText()
	-- Pass in a dummy to avoid mutating the actual text value assigned to this label,
	-- and instead only update the displayed text on the GUIItem.
	local WordWrapDummy = {
		GetTextWidth = function( _, Text )
			-- Need to account for scale here.
			return self:GetTextWidth( Text )
		end,
		SetText = function( _, Text )
			self.Label:SetText( Text )
		end
	}

	SGUI.WordWrap( WordWrapDummy, self.Text, 0, Width )

	if CurrentText ~= self.Label:GetText() then
		self.CachedTextWidth = nil
		self.CachedTextHeight = nil

		-- Look for the first ancestor whose height is not determined automatically, and invalidate it.
		-- This ensures any change in height from wrapping the text is accounted for.
		local Parent = self.Parent
		while SGUI.IsValid( Parent ) do
			local AutoSize = Parent:GetAutoSize()
			if not AutoSize or getmetatable( AutoSize[ 2 ] ) ~= Units.Auto then
				Parent:InvalidateLayout()
				break
			end

			Parent = Parent.Parent
		end
	end
end

function Label:SetSize() end

function Label:GetSize()
	return Vector2( self:GetCachedTextWidth(), self:GetCachedTextHeight() )
end

function Label:SetBright( Bright )
	-- Deprecated, does nothing.
end

SGUI:AddMixin( Label, "AutoSizeText" )
SGUI:AddMixin( Label, "Clickable" )
SGUI:Register( "Label", Label )
