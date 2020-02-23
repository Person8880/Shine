--[[
	Rich text element that supports arbitrary wrapped colour text, images and
	other elements.
]]

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local Max = math.max

local RichText = {}
local BackgroundColour = Colour( 0, 0, 0, 0 )

SGUI.AddProperty( RichText, "LineSpacing" )

function RichText:Initialise()
	self:SetIsSchemed( false )

	self.Background = self:MakeGUIItem()
	self.Background:SetSize( Vector2( 0, 0 ) )

	self.WrappedWidth = 0
	self.WrappedHeight = 0
	self.LineSpacing = Units.GUIScaled( 2 )
end

function RichText:SetFont( Font )
	if self.Font == Font then return end

	self.Font = Font

	self.ComputedWrapping = false
	self:InvalidateLayout()
end

function RichText:SetTextScale( Scale )
	if self.TextScale == Scale then return end

	self.TextScale = Scale

	self.ComputedWrapping = false
	self:InvalidateLayout()
end

function RichText:PerformLayout()
	if not self.ComputedWrapping then
		self:PerformWrapping()
	end
end

function RichText:SetSize( Size )
	local MaxWidth = Max( Size.x, 0 )

	if self.MaxWidth == MaxWidth and self.ComputedWrapping then return end

	self.MaxWidth = MaxWidth
	self.ComputedWrapping = false
	self:InvalidateLayout()
end

function RichText:GetComputedSize( Index, ParentSize )
	if Index == 1 then
		return ParentSize
	end

	return self:GetSize().y
end

function RichText:GetSize()
	if not self.ComputedWrapping and self.MaxWidth then
		-- Ensure wrapping is computed before returning the size, otherwise we may return an older
		-- size value if we've been re-used.
		self:InvalidateLayout( true )
	end

	return Vector2( self.WrappedWidth, self.WrappedHeight )
end

local Multimap = Shine.Multimap

local Max = math.max
local TableEmpty = table.Empty
local TableNew = require "table.new"
local TableRemove = table.remove

-- Parses a flat list of text/colours/elements into a list of lines, based on the line breaks
-- in each text element. These lines will be wrapped individually when the layout is computed.
function RichText:ParseContents( Contents )
	local Lines = {}
	local Elements = TableNew( #Contents, 0 )
	local HasVisibleElements = false

	for i = 1, #Contents do
		local CurrentElement = Contents[ i ]:Copy()
		local ElementLines = CurrentElement:GetLines()

		Elements[ #Elements + 1 ] = CurrentElement

		HasVisibleElements = HasVisibleElements or CurrentElement:IsVisibleElement()

		if ElementLines then
			Elements[ #Elements ] = ElementLines[ 1 ]
			for j = 2, #ElementLines do
				Lines[ #Lines + 1 ] = Elements
				Elements = { ElementLines[ j ] }
			end
		end
	end

	if #Elements > 0 then
		Lines[ #Lines + 1 ] = Elements
	end

	Lines.HasVisibleElements = HasVisibleElements

	return Lines
end

function RichText:SetContent( Contents )
	self.Lines = self:ParseContents( Contents )
	self.ComputedWrapping = false
	self:InvalidateLayout()
end

function RichText:RestoreFromLines( Lines )
	self.Lines = Lines
	self.ComputedWrapping = false
	self:InvalidateLayout()
end

function RichText:HasVisibleElements()
	return self.Lines ~= nil and self.Lines.HasVisibleElements
end

local Wrapper = require "shine/lib/gui/richtext/wrapper"

function RichText:PerformWrapping()
	local Lines = self.Lines
	local MaxWidth = self.MaxWidth
	if not MaxWidth or not Lines then return end

	local WrappedLines = Wrapper.WordWrapRichTextLines( {
		Lines = Lines,
		MaxWidth = MaxWidth,
		Font = self.Font,
		TextScale = self.TextScale
	} )

	self:ApplyLines( WrappedLines )
	self.ComputedWrapping = true
end

local function MakeElementFromPool( self, Class )
	local Elements = self.ElementPool:Get( Class )

	local Element
	if Elements then
		-- It's OK to do this here as we don't care about the multimap other than
		-- to hold lists of elements.
		Element = TableRemove( Elements )
	end

	return Element or SGUI:Create( Class )
end

local function MakeElement( self, Class )
	return SGUI:Create( Class )
end

local CreatedElements = TableNew( 30, 0 )
function RichText:ApplyLines( Lines )
	local ElementPool
	local ElementFactory = MakeElement
	if self.Children then
		ElementPool = Multimap()
		ElementFactory = MakeElementFromPool
		for Child in self.Children:IterateBackwards() do
			ElementPool:Add( Child.Class, Child )
		end
	end

	local Context = {
		CurrentFont = self.Font,
		CurrentScale = self.TextScale,
		DefaultFont = self.Font,
		DefaultScale = self.TextScale,
		CurrentColour = Colour( 1, 1, 1, 1 ),
		ElementPool = ElementPool,
		MakeElement = ElementFactory,
		NextMargin = 0
	}

	local YOffset = 0
	local MaxWidth = 0
	local Spacing = self.LineSpacing:GetValue()

	for i = 1, #Lines do
		local Line = Lines[ i ]

		local LineWidth = 0
		local LineHeight = 0
		local ElementCount = 0
		local NeedsAlignment = false

		for j = 1, #Line do
			Context.CurrentIndex = j

			local Control = Line[ j ]:MakeElement( Context )
			if Control then
				ElementCount = ElementCount + 1
				CreatedElements[ ElementCount ] = Control

				Control:SetParent( self )
				Control:SetInheritsParentAlpha( true )
				-- Make each element start from where the previous one ends.
				Control:SetPos( Vector2( LineWidth + Context.NextMargin, YOffset ) )
				Context.NextMargin = 0

				local Size = Control:GetSize()
				LineWidth = LineWidth + Size.x
				NeedsAlignment = NeedsAlignment or ( LineHeight ~= 0 and Size.y ~= LineHeight )
				LineHeight = Max( LineHeight, Size.y )
			end
		end

		-- Align all items in the line centrally to avoid one larger element looking out of place.
		if NeedsAlignment then
			local FirstOffset
			for i = 1, ElementCount do
				local Pos = CreatedElements[ i ]:GetPos()

				local Offset = LineHeight * 0.5 - CreatedElements[ i ]:GetSize().y * 0.5
				Pos.y = Pos.y + Offset

				CreatedElements[ i ]:SetPos( Pos )
			end
		end

		Context.NextMargin = 0
		MaxWidth = Max( MaxWidth, LineWidth )
		YOffset = YOffset + LineHeight + Spacing
	end

	TableEmpty( CreatedElements )

	self.WrappedWidth = MaxWidth
	self.WrappedHeight = Max( YOffset - Spacing, 0 )

	-- Any unused elements left behind should be destroyed.
	if ElementPool then
		for Class, Elements in ElementPool:Iterate() do
			for i = 1, #Elements do
				Elements[ i ]:Destroy()
			end
		end
	end
end

SGUI:Register( "RichText", RichText )
