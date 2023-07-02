--[[
	Rich text element that supports arbitrary wrapped colour text, images and
	other elements.
]]

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local Max = math.max

local RichText = {}

local DefaultTextColour = Colour( 1, 1, 1, 1 )
local DefaultLineSpacing = Units.GUIScaled( 2 )
local SetLineSpacing = SGUI.AddProperty( RichText, "LineSpacing" )
SGUI.AddProperty( RichText, "TextShadow" )

function RichText:Initialise()
	self:SetIsSchemed( false )

	self.Background = self:MakeGUIItem()
	self.Background:SetShader( SGUI.Shaders.Invisible )

	self.WrappedWidth = 0
	self.WrappedHeight = 0
	self.LineSpacing = DefaultLineSpacing
	self.TextColour = DefaultTextColour
end

function RichText:InvalidateWrapping()
	self.ComputedWrapping = false
	self:InvalidateLayout()
	self:InvalidateMouseState()
end

function RichText:RefreshElementTree()
	if self.ComputedWrapping then
		self:ApplyLines( self.WrappedLines )
	end
end

function RichText:SetLineSpacing( LineSpacing )
	if not SetLineSpacing( self, LineSpacing ) then return false end

	self:InvalidateWrapping()

	return true
end

function RichText:SetTextColour( TextColour )
	if self.TextColour == TextColour then return end

	-- Text colour doesn't affect the layout, just need to rebuild the element tree.
	self.TextColour = TextColour
	self:RefreshElementTree()

	return true
end

function RichText:SetFont( Font )
	if self.Font == Font then return end

	self.Font = Font
	self:InvalidateWrapping()

	return true
end

function RichText:SetTextScale( Scale )
	if self.TextScale == Scale then return end

	self.TextScale = Scale
	self:InvalidateWrapping()

	return true
end

function RichText:SetTextShadow( Params )
	if self.TextShadow == Params then return end
	if
		Params and self.TextShadow and
		Params.Colour == self.TextShadow.Colour and
		Params.Offset == self.TextShadow.Offset
	then
		return
	end

	self.TextShadow = Params

	-- Text shadow doesn't affect the layout, just need to rebuild the element tree.
	self:RefreshElementTree()

	return true
end

function RichText:PerformLayout()
	if not self.ComputedWrapping then
		self:PerformWrapping()
	end
end

function RichText:SetMaxWidth( MaxWidth )
	if self.MaxWidth == MaxWidth and self.ComputedWrapping then return end

	self.MaxWidth = MaxWidth
	self:InvalidateWrapping()

	return true
end

function RichText:SetSize( Size )
	return self:SetMaxWidth( Max( Size.x, 0 ) )
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

local TableEmpty = table.Empty
local TableNew = require "table.new"
local TableRemove = table.remove

-- Parses a flat list of text/colours/elements into a list of lines, based on the line breaks
-- in each text element. These lines will be wrapped individually when the layout is computed.
function RichText:ParseContents( Contents )
	local NumContents = #Contents
	local Lines = {}
	local LineCount = 0
	local Elements = TableNew( NumContents, 0 )
	local ElementCount = 0
	local HasVisibleElements = false

	for i = 1, NumContents do
		local CurrentElement = Contents[ i ]:Copy()
		local ElementLines = CurrentElement:GetLines()

		ElementCount = ElementCount + 1
		Elements[ ElementCount ] = CurrentElement

		HasVisibleElements = HasVisibleElements or CurrentElement:IsVisibleElement()

		if ElementLines then
			Elements[ ElementCount ] = ElementLines[ 1 ]
			for j = 2, #ElementLines do
				LineCount = LineCount + 1
				Lines[ LineCount ] = Elements
				Elements = { ElementLines[ j ] }
			end
		end
	end

	if #Elements > 0 then
		LineCount = LineCount + 1
		Lines[ LineCount ] = Elements
	end

	Lines.HasVisibleElements = HasVisibleElements

	return Lines
end

function RichText:SetContent( Contents )
	self.Lines = self:ParseContents( Contents )
	self:InvalidateWrapping()
end

function RichText:RestoreFromLines( Lines )
	self.Lines = Lines
	self:InvalidateWrapping()
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
	self.WrappedLines = WrappedLines

	local OldW, OldH = self.WrappedWidth, self.WrappedHeight

	self:ApplyLines( WrappedLines )
	self.ComputedWrapping = true

	if OldW ~= self.WrappedWidth or OldH ~= self.WrappedHeight then
		self:OnPropertyChanged( "Size", Vector2( self.WrappedWidth, self.WrappedHeight ) )
	end
end

function RichText:GetWrappedLines()
	self:PerformLayout()
	return self.WrappedLines or {}
end

local function NewElementList( InitialCapacity )
	local List = TableNew( InitialCapacity, 0 )
	List[ 0 ] = 0
	return List
end

local ElementPool = {
	Label = NewElementList( 30 ),
	Image = NewElementList( 5 )
}

local function MakeElementFromPool( Class )
	local Elements = ElementPool[ Class ]

	local Element
	if Elements then
		Elements[ 0 ] = Max( Elements[ 0 ] - 1, 0 )
		Element = TableRemove( Elements )
	end

	return Element or SGUI:Create( Class )
end

function RichText:ReleaseElements()
	if not self.Children then return end

	-- Release children back into the shared pool to allow for re-use.
	-- Different lines may have a different number of elements, sharing the pool avoids cases where the number
	-- of elements in a previous line is not enough to create all elements in this line.
	for Child in self.Children:IterateBackwards() do
		local Elements = ElementPool[ Child.Class ]
		if not Elements then
			Elements = NewElementList( 5 )
			ElementPool[ Child.Class ] = Elements
		end
		Elements[ 0 ] = Elements[ 0 ] + 1
		Elements[ Elements[ 0 ] ] = Child

		Child:SetIsVisible( false )
		Child:SetParent( nil )
	end
end

local CreatedElements = TableNew( 30, 0 )
function RichText:ApplyLines( Lines )
	self:ReleaseElements()

	local Context = {
		CurrentFont = self.Font,
		CurrentScale = self.TextScale,
		CurrentTextShadow = self.TextShadow,
		DefaultFont = self.Font,
		DefaultScale = self.TextScale,
		DefaultTextShadow = self.TextShadow,
		CurrentColour = self.TextColour,
		MakeElement = MakeElementFromPool,
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
				Control:SetIsVisible( true )
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
end

SGUI:Register( "RichText", RichText )
