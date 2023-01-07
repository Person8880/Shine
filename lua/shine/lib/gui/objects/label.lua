--[[
	Basically a GUI text item bound to SGUI.
]]

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local getmetatable = getmetatable
local StringFind = string.find
local StringUTF8Encode = string.UTF8Encode
local TableConcat = table.concat

local Label = {}

SGUI.AddBoundProperty( Label, "Colour", "self:SetBackgroundColour" )
SGUI.AddBoundProperty( Label, "Font", "Label:SetFontName", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Label, "Text", "Label", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Label, "TextAlignmentX", "Label" )
SGUI.AddBoundProperty( Label, "TextAlignmentY", "Label" )
SGUI.AddBoundProperty( Label, "TextScale", "Label:SetScale", { "InvalidatesParent" } )

-- Auto-wrapping allows labels to automatically word-wrap based on a given auto-width (or fill size).
SGUI.AddProperty( Label, "AutoWrap", false, { "InvalidatesParent" } )
-- Auto-ellipsis shortens text if it extends beyond the given auto-width (or fill size).
SGUI.AddProperty( Label, "AutoEllipsis", false, { "InvalidatesParent" } )

local function MarkSizeDirty( self )
	self.CachedTextWidth = nil
	self.CachedTextHeight = nil
	self.NeedsTextSizeRefresh = true
	self:InvalidateMouseState()
end

do
	local function SetupElementForFontName( self, Font )
		SGUI.FontManager.SetupElementForFontName( self.Label, Font )
	end

	function Label:Initialise()
		self.BaseClass.Initialise( self )

		self.Label = self:MakeGUITextItem()
		self.Background = self.Label
		self.Text = ""
		self.TextScale = Vector2( 1, 1 )
		self.TextAlignmentX = GUIItem.Align_Min
		self.TextAlignmentY = GUIItem.Align_Min
		self.NeedsTextSizeRefresh = true

		self:AddPropertyChangeListener( "Text", MarkSizeDirty )
		self:AddPropertyChangeListener( "Font", MarkSizeDirty )
		self:AddPropertyChangeListener( "TextScale", MarkSizeDirty )

		self:AddPropertyChangeListener( "Text", self.EvaluateOptionFlags )
		self:AddPropertyChangeListener( "Font", SetupElementForFontName )
	end
end

function Label:EvaluateOptionFlags( Text )
	if StringFind( Text, "\n", 1, true ) then
		-- This flag causes random blurring on text, so only set it if it's really needed.
		self.Label:SetOptionFlag( GUIItem.PerLineTextAlignment )
	else
		self.Label:ClearOptionFlag( GUIItem.PerLineTextAlignment )
	end
end

-- Sets whether the label should offset itself during layout to ensure alignment does not affect position.
-- For backwards compatibility, this is disabled by default.
function Label:SetUseAlignmentCompensation( UseAlignmentCompensation )
	if UseAlignmentCompensation then
		self.GetLayoutOffset = self.GetTopLeftLayoutOffset
	else
		self.GetLayoutOffset = self.BaseClass.GetLayoutOffset
	end
end

do
	local AlignmentOffsets = {
		[ GUIItem.Align_Center ] = 0.5,
		[ GUIItem.Align_Max ] = 1,
		[ GUIItem.Align_Min ] = 0
	}

	function Label:GetTopLeftLayoutOffset()
		local Size = self:GetSize()
		return Vector2(
			Size.x * AlignmentOffsets[ self:GetTextAlignmentX() ],
			Size.y * AlignmentOffsets[ self:GetTextAlignmentY() ]
		)
	end
end

function Label:MouseIn( Element, Mult )
	return self:MouseInControl( Mult )
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

-- Do nothing by default.
function Label:PreComputeHeight() end

local WordWrapDummy = {
	GetTextWidth = function( self, Text )
		-- Need to account for scale here.
		return self.Element:GetTextWidth( Text )
	end,
	SetText = function( self, Text )
		self.Element.Label:SetText( Text )
		self.Element:EvaluateOptionFlags( Text )
	end
}

local SetAutoWrap = Label.SetAutoWrap
function Label:SetAutoWrap( AutoWrap )
	if not SetAutoWrap( self, AutoWrap ) then return false end

	if AutoWrap and self.PreComputeHeight ~= self.ApplyAutoWrapping then
		self.PreComputeHeight = self.ApplyAutoWrapping
	elseif not AutoWrap and self.PreComputeHeight == self.ApplyAutoWrapping then
		self.PreComputeHeight = nil
	end

	return true
end

-- Apply word wrapping before the height is computed (assuming height = Units.Auto.INSTANCE).
function Label:ApplyAutoWrapping( Width )
	local CurrentText = self.Label:GetText()

	-- Pass in a dummy to avoid mutating the actual text value assigned to this label,
	-- and instead only update the displayed text on the GUIItem.
	WordWrapDummy.Element = self
	SGUI.WordWrap( WordWrapDummy, self.Text, 0, Width )

	if CurrentText ~= self.Label:GetText() then
		MarkSizeDirty( self )

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

local function ResetAutoEllipsis( self, Text )
	self.Label:SetText( Text )
	self:EvaluateOptionFlags( Text )

	if self.UsingAutoEllipsisTooltip then
		self:SetTooltip( nil )
	end

	MarkSizeDirty( self )

	self.AutoEllipsisApplied = false
	self:OnPropertyChanged( "AutoEllipsisApplied", false )
end

local SetAutoEllipsis = Label.SetAutoEllipsis
function Label:SetAutoEllipsis( AutoEllipsis )
	if not SetAutoEllipsis( self, AutoEllipsis ) then return false end

	if AutoEllipsis and self.PreComputeHeight ~= self.ApplyAutoEllipsis then
		self.PreComputeHeight = self.ApplyAutoEllipsis
	elseif not AutoEllipsis and self.PreComputeHeight == self.ApplyAutoEllipsis then
		self.PreComputeHeight = nil
		if self.AutoEllipsisApplied then
			ResetAutoEllipsis( self, self.Text )
		end
	end

	return true
end

function Label:ApplyAutoEllipsis( Width )
	local Text = self.Text
	if self:GetTextWidth( Text ) <= Width then
		if self.AutoEllipsisApplied then
			ResetAutoEllipsis( self, Text )
		end

		return
	end

	local Chars = StringUTF8Encode( Text )
	for i = #Chars, 1, -3 do
		local TextWithEllipsis = TableConcat( Chars, "", 1, i - 3 ).."..."
		if self:GetTextWidth( TextWithEllipsis ) <= Width then
			if self.Label:GetText() ~= TextWithEllipsis then
				self.Label:SetText( TextWithEllipsis )
				self:EvaluateOptionFlags( TextWithEllipsis )
				if self.TooltipText == nil or self.UsingAutoEllipsisTooltip then
					self:SetTooltip( Text )
					self.UsingAutoEllipsisTooltip = true
				end

				MarkSizeDirty( self )
			end

			if not self.AutoEllipsisApplied then
				self.AutoEllipsisApplied = true
				self:OnPropertyChanged( "AutoEllipsisApplied", true )
			end

			break
		end
	end
end

function Label:SetTooltip( Text )
	-- Reset the auto-ellipsis flag if the tooltip is changed externally. If it's changed internally, this will be added
	-- again immediately after.
	self.UsingAutoEllipsisTooltip = nil
	return self.BaseClass.SetTooltip( self, Text )
end

function Label:SetSize() end

function Label:GetSize()
	return Vector2( self:GetCachedTextWidth(), self:GetCachedTextHeight() )
end

function Label:SetBright( Bright )
	-- Deprecated, does nothing.
end

function Label:GetShadow()
	return self.Shadow
end

function Label:SetShadow( Params )
	self.Shadow = Params

	if not Params then
		self.ShadowOffset = nil
		self.ShadowColour = nil
		self.Label:SetDropShadowEnabled( false )
		return
	end

	self.ShadowOffset = Params.Offset or Vector2( 2, 2 )
	self.ShadowColour = Params.Colour

	self.Label:SetDropShadowEnabled( true )
	self.Label:SetDropShadowOffset( self.ShadowOffset )
	self.Label:SetDropShadowColor( Params.Colour )
end

function Label:Think( DeltaTime )
	if self.NeedsTextSizeRefresh then
		self.NeedsTextSizeRefresh = false
		-- When cropped, the label may be invisible due to the cropping logic not evaluating this...
		self.Label:ForceUpdateTextSize()
	end

	return self.BaseClass.ThinkWithChildren( self, DeltaTime )
end

SGUI:AddMixin( Label, "AutoSizeText" )
SGUI:AddMixin( Label, "Clickable" )
SGUI:Register( "Label", Label )

-- Maintain backwards compatibility with the old separate control type.
SGUI:RegisterAlias( "Label", "ShadowLabel" )
