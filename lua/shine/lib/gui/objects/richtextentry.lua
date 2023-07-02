--[[
	Rich text entry control, allowing for images to be displayed and edited alongside text.
]]

local ImageElement = require "shine/lib/gui/richtext/elements/image"
local TextElement = require "shine/lib/gui/richtext/elements/text"
local TextEntryUtil = require "shine/lib/gui/objects/textentry/util"

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local CalculateTextSize = GUI and GUI.CalculateTextSize
local Ceil = math.ceil
local Huge = math.huge
local Implements = Shine.Implements
local Max = math.max
local Min = math.min
local StringFormat = string.format
local StringUTF8Chars = string.UTF8Chars
local StringUTF8Encode = string.UTF8Encode
local StringUTF8Length = string.UTF8Length
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableNew = require "table.new"

local RichTextEntry = {}

local SetTextParser = SGUI.AddProperty( RichTextEntry, "TextParser" )

local TextObjectProxy = Shine.TypeDef()
function TextObjectProxy:Init( RichText, TextEntry )
	self.RichText = RichText
	self.TextEntry = TextEntry
	return self
end

function TextObjectProxy:SetColor( Colour )
	self.RichText:SetTextColour( Colour )
end

function TextObjectProxy:SetPosition( Pos )
	-- Centre-align the rich text vertically.
	Pos.y = Ceil( -self.TextEntry:GetTextHeight() * 0.5 )
	self.RichText:SetPos( Pos )
end

function TextObjectProxy:SetScale( Scale )
	self.RichText:SetTextScale( Scale )
end

function TextObjectProxy:GetInheritsParentScaling()
	return self.RichText.Background:GetInheritsParentScaling()
end

function TextObjectProxy:GetPosition()
	return self.RichText:GetPos()
end

local function DefaultParser( Text )
	return { TextElement( Text ) }
end

function RichTextEntry:Initialise()
	Controls.TextEntry.Initialise( self )

	self.RichText = SGUI:Create( "RichText", self, self.InnerBox )
	self.RichText:SetAnchorFraction( 0, 0.5 )
	self.RichText:SetFont( self.Font )
	self.RichText:SetMaxWidth( Huge )

	local Pos = self.TextObj:GetPosition()

	self:DestroyGUIItem( self.TextObj )

	-- To allow re-using some TextEntry functionality, retain a dummy element representing the visible text.
	self.TextObj = TextObjectProxy( self.RichText, self )
	self.TextObj:SetPosition( Pos )
	self.TextParser = DefaultParser
end

function RichTextEntry:GetContents()
	return self.RichText:GetWrappedLines()[ 1 ]
end

function RichTextEntry:IsEmpty()
	local Line = self:GetContents()
	if not Line then return true end

	local FirstElement = Line[ 1 ]
	if not FirstElement then return true end

	if Implements( FirstElement, TextElement ) then
		return FirstElement.Value == ""
	end

	return false
end

function RichTextEntry:SetInternalTextFont( Font )
	self.RichText:SetFont( Font )
end

function RichTextEntry:SetTextParser( TextParser )
	if not SetTextParser( self, TextParser ) then return false end

	local Text = self:GetText()
	self.RichText:SetContent( TextParser( Text ) )

	return true
end

function RichTextEntry:SetTextShadow( Params )
	self.Shadow = Params
	self.RichText:SetTextShadow( Params )
end

function RichTextEntry:GetMaxColumn()
	local Line = self:GetContents()
	if not Line then return 0 end

	local NumColumns = 0

	for i = 1, #Line do
		local Element = Line[ i ]
		if Implements( Element, ImageElement ) then
			NumColumns = NumColumns + 1
		elseif Implements( Element, TextElement ) then
			NumColumns = NumColumns + StringUTF8Length( Element.Value )
		end
	end

	return NumColumns
end

function RichTextEntry.GetElementIndexForColumn( Line, Column )
	local NumColumns = 0
	local LastElementIndex = 0

	for i = 1, #Line do
		LastElementIndex = i

		local Element = Line[ i ]
		if Implements( Element, ImageElement ) then
			NumColumns = NumColumns + 1
		elseif Implements( Element, TextElement ) then
			NumColumns = NumColumns + StringUTF8Length( Element.Value )
		end

		if NumColumns >= Column then break end
	end

	return LastElementIndex, NumColumns
end

function RichTextEntry:FindWordBounds( Column )
	local Line = self:GetContents()
	if not Line then return 0, 0 end

	local LastElementIndex, NumColumns = self.GetElementIndexForColumn( Line, Column )
	local LastElement = Line[ LastElementIndex ]
	while LastElement do
		if Implements( LastElement, ImageElement ) then
			if Column == NumColumns or LastElementIndex == 1 then
				-- Boundary is after an image element, treat the image as a single word.
				return NumColumns - 1, NumColumns
			end
			NumColumns = NumColumns - 1
		elseif Implements( LastElement, TextElement ) then
			local Characters, Length = StringUTF8Encode( LastElement.Value )
			local StartColumn = NumColumns - Length
			local ColumnIndexInText = Column - StartColumn

			local StartIndex, EndIndex = TextEntryUtil.FindWordBoundsFromCharacters(
				Characters,
				Length,
				ColumnIndexInText
			)
			if StartIndex == 1 then
				StartIndex = 0
			end
			return StartColumn + StartIndex, StartColumn + EndIndex
		end

		LastElement = Line[ LastElementIndex - 1 ]
	end

	return 0, 0
end

function RichTextEntry:GetTextWidth()
	local Line = self:GetContents()
	if not Line then return 0 end

	local Width = 0

	for i = 1, #Line do
		local Element = Line[ i ]
		if Implements( Element, ImageElement ) then
			Width = Width + Element.Size.x
		elseif Implements( Element, TextElement ) then
			Width = Width + Element.Width
		end
	end

	return Width
end

function RichTextEntry:GetColumnTextWidth( Column )
	local Line = self:GetContents()
	if not Line then return 0 end

	local CurrentColumn = 0
	local Width = 0

	for i = 1, #Line do
		if CurrentColumn == Column then break end

		local Element = Line[ i ]
		if Implements( Element, ImageElement ) then
			CurrentColumn = CurrentColumn + 1
			Width = Width + Element.Size.x
		elseif Implements( Element, TextElement ) then
			local Characters, Length = StringUTF8Encode( Element.Value )

			if CurrentColumn + Length <= Column then
				Width = Width + Element.Width
				CurrentColumn = CurrentColumn + Length
			else
				local TextUpToColumn = TableConcat( Characters, "", 1, Column - CurrentColumn )
				Width = Width + CalculateTextSize( self.Font, TextUpToColumn ).x * self.WidthScale
				break
			end
		end
	end

	return Width
end

function RichTextEntry:GetSelectionWidth( SelectionBounds )
	local UpperWidth = self:GetColumnTextWidth( SelectionBounds[ 2 ] )
	local LowerWidth = self:GetColumnTextWidth( SelectionBounds[ 1 ] )
	return UpperWidth - LowerWidth
end

local TextContents = TableNew( 25, 0 )
local function GetTextBetweenColumnsFromRichText( Line, StartColumn, EndColumn, TextType )
	TextType = TextType or "Text"
	EndColumn = EndColumn or Huge

	if StartColumn > EndColumn then return "" end

	local Count = 0
	local CurrentColumn = 0

	TableEmpty( TextContents )

	for i = 1, #Line do
		if CurrentColumn >= EndColumn then break end

		local Element = Line[ i ]

		if Implements( Element, ImageElement ) then
			CurrentColumn = CurrentColumn + 1
			if CurrentColumn >= StartColumn then
				Count = Count + 1
				TextContents[ Count ] = Element[ TextType ] or Element.Text or ""
			end
		elseif Implements( Element, TextElement ) then
			local Characters, Length = StringUTF8Encode( Element.Value )
			local TextEnd = CurrentColumn + Length

			if TextEnd >= StartColumn then
				local StartIndex
				if CurrentColumn >= StartColumn then
					-- Already past the start column, can start from the first character.
					StartIndex = 1
				else
					-- Not past the start column yet, have to jump ahead, e.g.
					-- "|Exam[ple Text" - start column is 5, current is 0, so have to start from character 5.
					StartIndex = StartColumn - CurrentColumn
				end

				-- "|Exam[ple Te]xt" - start at 5, end column is 10, so need to select [5, 10].
				-- "|[Example Text    ]" - start at 1, end column is beyond the range, need to select [1, Length]
				local DistToEnd = EndColumn - ( CurrentColumn + StartIndex )
				local EndIndex = StartIndex + Min( DistToEnd, Length - StartIndex )

				Count = Count + 1
				TextContents[ Count ] = TableConcat( Characters, "", StartIndex, EndIndex )
			end

			CurrentColumn = TextEnd
		end
	end

	local Text = TableConcat( TextContents, "", 1, Count )

	TableEmpty( TextContents )

	return Text
end

function RichTextEntry:GetTextBetween( StartColumn, EndColumn, TextType )
	local Line = self:GetContents()
	if not Line then return "" end

	return GetTextBetweenColumnsFromRichText( Line, StartColumn, EndColumn, TextType )
end

function RichTextEntry:SetTextInternal( Text )
	self.RichText:SetContent( self.TextParser( Text ) )
end

function RichTextEntry:GetText()
	return self:GetTextBetween( 1, Huge, "Text" )
end

function RichTextEntry:GetSelectedText()
	local StartColumn, EndColumn = self.SelectionBounds[ 1 ] + 1, self.SelectionBounds[ 2 ]
	return self:GetTextBetween( StartColumn, EndColumn, "CopyText" )
end

-- Note: XPos here is the visual width relative to the rich text's position (i.e. 0 is the start of the rich text, not
-- the inner box).
function RichTextEntry:GetColumnForVisualPosition( XPos )
	local Line = self:GetContents()
	if not Line then return 0 end

	local Column = 0
	local CurrentWidth = 0

	for i = 1, #Line do
		if CurrentWidth >= XPos then break end

		local Element = Line[ i ]
		if Implements( Element, ImageElement ) then
			local ElementWidth = Element.Size.x

			Column = Column + 1
			CurrentWidth = CurrentWidth + ElementWidth

			if CurrentWidth >= XPos then
				-- Pick the column nearest to the given width.
				return CurrentWidth - XPos > ElementWidth * 0.5 and ( Column - 1 ) or Column
			end
		elseif Implements( Element, TextElement ) then
			CurrentWidth = CurrentWidth + Element.Width

			local Characters, Length = StringUTF8Encode( Element.Value )
			Column = Column + Length

			if CurrentWidth >= XPos then
				local CharIndex = Length

				-- Column is within this text element, need to find the exact offset.
				while CurrentWidth > XPos and CharIndex > 0 do
					local CharWidth = CalculateTextSize( self.Font, Characters[ CharIndex ] ).x * self.WidthScale
					CurrentWidth = CurrentWidth - CharWidth

					if CurrentWidth <= XPos then
						local Dist = CurrentWidth + CharWidth - XPos
						if Dist < CharWidth * 0.5 then
							return Column
						end
						return Max( Column - 1, 0 )
					end

					CharIndex = CharIndex - 1
					Column = Column - 1
				end

				return Column
			end
		end
	end

	return Column
end

function RichTextEntry:GetColumnFromMouse( X )
	local RichTextXPos = X - self.TextOffset
	return self:GetColumnForVisualPosition( RichTextXPos )
end

local function GetVisualColumnFromTextColumn( Line, TextColumn )
	local VisualColumn = 0
	local CurrentTextColumn = 0

	for i = 1, #Line do
		if CurrentTextColumn >= TextColumn then break end

		local Element = Line[ i ]
		if Implements( Element, ImageElement ) then
			VisualColumn = VisualColumn + 1
			CurrentTextColumn = CurrentTextColumn + StringUTF8Length( Element.Text or "" )
		elseif Implements( Element, TextElement ) then
			local Length = StringUTF8Length( Element.Value )
			local NextTextColumn = CurrentTextColumn + Length

			if NextTextColumn >= TextColumn then
				VisualColumn = VisualColumn + Length - ( NextTextColumn - TextColumn )
				break
			end

			CurrentTextColumn = NextTextColumn
			VisualColumn = VisualColumn + Length
		end
	end

	return VisualColumn
end

function RichTextEntry:GetVisualColumnFromTextColumn( TextColumn )
	local Line = self:GetContents()
	if not Line then return 0 end

	return GetVisualColumnFromTextColumn( Line, TextColumn )
end

function RichTextEntry:UpdateCaretPos( TextColumn, UpdatedText, NewText )
	-- Parsing the text may cause the new text to change length (e.g. because some text was shortened to represent an
	-- emoji). If this happens, the text column needs to be shifted to account for the change.
	local Delta = StringUTF8Length( NewText ) - StringUTF8Length( UpdatedText )
	TextColumn = TextColumn + Delta

	-- With the shifted text column, find the visually closest equivalent column in the new rich text state. This should
	-- snap the caret to the edge of a new image element if one was inserted to replace some text.
	self:SetCaretPos( self:GetVisualColumnFromTextColumn( TextColumn ) )
end

local function UpdateText( self, OldText, UpdatedText, TextColumn )
	self:SetTextInternal( UpdatedText )

	local NewText = self:GetText()

	self:UpdateCaretPos( TextColumn, UpdatedText, NewText )
	self:OnTextChangedInternal( OldText, NewText )
end

function RichTextEntry:InsertTextInternal( NewText, NumChars )
	local OldText = self:GetText()
	local Line = self:GetContents()
	if not Line then
		-- No content, just add the text as-is.
		self:SetTextInternal( NewText )
		self:SetCaretPos( self:GetMaxColumn() )
		self:OnTextChangedInternal( OldText, self:GetText() )
		return
	end

	local TextBefore = self:GetTextBetween( 1, self.Column )
	local TextAfter = self:GetTextBetween( self.Column + 1 )

	UpdateText(
		self,
		OldText,
		StringFormat( "%s%s%s", TextBefore, NewText, TextAfter ),
		StringUTF8Length( TextBefore ) + NumChars
	)
end

function RichTextEntry:InsertTextAtCaret( Text, Options )
	local CurrentLength
	if self.MaxLength then
		CurrentLength = StringUTF8Length( self:GetText() )

		if CurrentLength >= self.MaxLength then return false end
	end

	local Count = 0
	local StoppedEarly = false
	local TextToInsert = TableNew( #Text, 0 )
	for ByteIndex, Char in StringUTF8Chars( Text ) do
		if not self:DoesCharPassPatternChecks( Char ) then
			StoppedEarly = true
			break
		end

		Count = Count + 1
		TextToInsert[ Count ] = Char
	end

	if StoppedEarly and Options and Options.SkipIfAnyCharBlocked then return false end

	local TextBefore, TextAfter
	if self:HasSelection() then
		local LowerBound = self.SelectionBounds[ 1 ]
		local UpperBound = self.SelectionBounds[ 2 ]

		-- Cut out the selection in the new text.
		TextBefore = self:GetTextBetween( 1, LowerBound )
		TextAfter = self:GetTextBetween( UpperBound + 1 )
	else
		TextBefore = self:GetTextBetween( 1, self.Column )
		TextAfter = self:GetTextBetween( self.Column + 1 )
	end

	local NewTextToInsert = TableConcat( TextToInsert, "", 1, Count )
	local NewText = StringFormat( "%s%s%s", TextBefore, NewTextToInsert, TextAfter )

	if self.MaxLength then
		-- Parse the new text first, as the parser may return elements whose actual text differs from what the user
		-- originally typed here (e.g. an emoji may have short name that replaces a user-typed name).
		local ParsedContents = self.TextParser( NewText )

		-- Figure out the length of the text from the newly parsed rich text elements, to account for any substitutions.
		local ParsedNewText = GetTextBetweenColumnsFromRichText( ParsedContents, 1, Huge, "Text" )

		if StringUTF8Length( ParsedNewText ) >= self.MaxLength then
			return false
		end
	end

	self:PushUndoState()

	-- As the work to remove the selected text and compute the new text has been done already, directly update the
	-- text here rather than going through self:InsertTextWithoutValidation().
	UpdateText( self, self:GetText(), NewText, StringUTF8Length( TextBefore ) + Count )

	if self.PlaceholderText then
		self.PlaceholderText:SetIsVisible( false )
	end

	return true
end

function RichTextEntry:ConvertStateToAutoComplete( State )
	-- Caret position is the visual caret, need to translate back to text for auto-completion to work.
	local TextBefore = self:GetTextBetween( 1, State.CaretPos )
	return {
		Text = State.Text,
		CaretPos = StringUTF8Length( TextBefore )
	}
end

function RichTextEntry:ConvertStateFromAutoComplete( State )
	-- Caret position is the text caret, need to parse the new text, then find the matching visual caret position.
	local ParsedContents = self.TextParser( State.Text )
	local ParsedText = GetTextBetweenColumnsFromRichText( ParsedContents, 1, Huge, "Text" )
	-- As above, account for the fact the text may grow or shrink depending on the parse result.
	local Delta = StringUTF8Length( ParsedText ) - StringUTF8Length( State.Text )
	local CaretPos = GetVisualColumnFromTextColumn( ParsedContents, State.CaretPos + Delta )

	return {
		Text = State.Text,
		CaretPos = CaretPos
	}
end

SGUI:Register( "RichTextEntry", RichTextEntry, "TextEntry" )
