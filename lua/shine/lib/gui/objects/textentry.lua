--[[
	Text entry control.
]]

local SGUI = Shine.GUI
local Timer = Shine.Timer

local Clamp = math.Clamp
local Clock = os.clock
local Max = math.max
local Min = math.min
local StringFind = string.find
local StringFormat = string.format
local StringLength = string.len
local StringLower = string.lower
local StringSub = string.sub
local StringUTF8Encode = string.UTF8Encode
local StringUTF8Length = string.UTF8Length
local StringUTF8Sub = string.UTF8Sub
local TableConcat = table.concat
local TableRemove = table.remove
local tonumber = tonumber

local TextEntry = {}

TextEntry.UsesKeyboardFocus = true

local BorderSize = Vector( 2, 2, 0 )
local CaretCol = Color( 1, 1, 1, 1 )
local Clear = Color( 0, 0, 0, 0 )
local TextPos = Vector( 2, 0, 0 )

SGUI.AddProperty( TextEntry, "MaxUndoHistory", 100 )

function TextEntry:Initialise()
	self.BaseClass.Initialise( self )

	if self.Background then GUI.DestroyItem( self.Background ) end

	local Manager = GetGUIManager()

	--Border.
	local Background = Manager:CreateGraphicItem()

	self.Background = Background

	--Coloured entry field.
	local InnerBox = Manager:CreateGraphicItem()
	InnerBox:SetAnchor( GUIItem.Left, GUIItem.Top )
	InnerBox:SetPosition( BorderSize )

	--Stencil to prevent text leaking.
	local Stencil = Manager:CreateGraphicItem()
	Stencil:SetIsStencil( true )
	Stencil:SetInheritsParentStencilSettings( false )
	Stencil:SetClearsStencilBuffer( true )

	self.Stencil = Stencil

	local SelectionBox = Manager:CreateGraphicItem()
	SelectionBox:SetAnchor( GUIItem.Left, GUIItem.Top )
	SelectionBox:SetInheritsParentStencilSettings( false )
	SelectionBox:SetStencilFunc( GUIItem.NotEqual )
	SelectionBox:SetSize( Vector( 0, 0, 0 ) )

	self.SelectionBox = SelectionBox

	--The actual text object.
	local Text = Manager:CreateTextItem()
	Text:SetAnchor( GUIItem.Left, GUIItem.Center )
	Text:SetTextAlignmentY( GUIItem.Align_Center )
	Text:SetPosition( TextPos )
	Text:SetInheritsParentStencilSettings( false )
	Text:SetStencilFunc( GUIItem.NotEqual )

	--The caret to edit from.
	local Caret = Manager:CreateGraphicItem()
	Caret:SetAnchor( GUIItem.Left, GUIItem.Top )
	Caret:SetColor( Clear )

	self.Caret = Caret

	InnerBox:AddChild( Caret )
	InnerBox:AddChild( Stencil )

	Background:AddChild( InnerBox )

	self.InnerBox = InnerBox

	InnerBox:AddChild( SelectionBox )
	InnerBox:AddChild( Text )

	self.TextObj = Text

	--The actual text string.
	self.Text = ""

	--Where's the caret?
	self.Column = 0

	--How far along we are (this will be negative or self.Padding)
	self.TextOffset = 2

	self.WidthScale = 1
	self.HeightScale = 1

	self.Padding = 2
	self.CaretOffset = 0
	self.BorderSize = BorderSize

	self.SelectionBounds = { 0, 0 }
	self.UndoPosition = 0
	self.UndoStack = {}
end

function TextEntry:SetSize( SizeVec )
	self.Background:SetSize( SizeVec )

	local InnerBoxSize = SizeVec - self.BorderSize * 2

	self.Stencil:SetSize( InnerBoxSize )
	self.InnerBox:SetSize( InnerBoxSize )

	self.Width = InnerBoxSize.x - 5
	self.Height = InnerBoxSize.y

	self:InvalidateLayout()
end

SGUI.AddBoundProperty( TextEntry, "PlaceholderTextColour", "PlaceholderText:SetColor" )

function TextEntry:SetFocusColour( Col )
	self.FocusColour = Col

	if self.Enabled then
		self.InnerBox:SetColor( Col )
	end
end

function TextEntry:SetDarkColour( Col )
	self.DarkCol = Col

	if not self.Enabled then
		self.InnerBox:SetColor( Col )
	end
end

function TextEntry:SetBorderColour( Col )
	self.Background:SetColor( Col )
end

function TextEntry:SetTextColour( Col )
	self.TextObj:SetColor( Col )
end

function TextEntry:SetHighlightColour( Col )
	self.SelectionBox:SetColor( Col )
end

function TextEntry:SetBorderSize( BorderSize )
	self.InnerBox:SetPosition( BorderSize )
	self.BorderSize = BorderSize
	self:SetSize( self.Background:GetSize() )
end

function TextEntry:SetPlaceholderText( Text )
	if Text == "" then
		if self.PlaceholderText then
			GUI.DestroyItem( self.PlaceholderText )
		end
		self.PlaceholderText = nil
		self.Placeholder = nil

		return
	end

	self.Placeholder = Text

	if self.PlaceholderText then
		self.PlaceholderText:SetText( Text )

		return
	end

	local Manager = GetGUIManager()
	local PlaceholderText = Manager:CreateTextItem()
	PlaceholderText:SetAnchor( GUIItem.Left, GUIItem.Top )
	PlaceholderText:SetTextAlignmentY( GUIItem.Align_Center )
	PlaceholderText:SetInheritsParentStencilSettings( false )
	PlaceholderText:SetStencilFunc( GUIItem.NotEqual )
	PlaceholderText:SetText( Text )

	if self.Font then
		PlaceholderText:SetFontName( self.Font )
	end

	if self.TextScale then
		PlaceholderText:SetScale( self.TextScale )
	end

	PlaceholderText:SetPosition( Vector( 0, 0, 0 ) )
	PlaceholderText:SetColor( self.PlaceholderTextColour )

	self.TextObj:AddChild( PlaceholderText )
	self.PlaceholderText = PlaceholderText
end

function TextEntry:GetIsVisible()
	if self.Parent and not self.Parent:GetIsVisible() then
		return false
	end

	return self.Background:GetIsVisible()
end

function TextEntry:SetFont( Font )
	self.Font = Font
	self.TextObj:SetFontName( Font )
	self:SetupCaret()

	if self.PlaceholderText then
		self.PlaceholderText:SetFontName( Font )
	end
end

function TextEntry:PerformLayout()
	self:SetupCaret()
end

function TextEntry:SetupCaret()
	local Caret = self.Caret
	local SelectionBox = self.SelectionBox
	local TextObj = self.TextObj

	local Height = TextObj:GetTextHeight( "!" ) * self.HeightScale * 0.8

	Caret:SetSize( Vector( 1, Height, 0 ) )
	SelectionBox:SetSize( Vector( SelectionBox:GetSize().x, Height, 0 ) )

	if not self.Width then return end

	local Width = TextObj:GetTextWidth( self.Text ) * self.WidthScale
	self.Column = StringUTF8Length( self.Text )

	if Width > self.Width then
		local Diff = -( Width - self.Width )

		TextObj:SetPosition( Vector( Diff, 0, 0 ) )
		Caret:SetPosition( Vector( Width + Diff + self.CaretOffset, self.Height * 0.5 - Height * 0.5, 0 ) )

		self.TextOffset = Diff
	else
		self.TextOffset = self.Padding

		Caret:SetPosition( Vector( Width + self.Padding + self.CaretOffset, self.Height * 0.5 - Height * 0.5, 0 ) )
		TextObj:SetPosition( Vector( self.Padding, 0, 0 ) )
	end
end

function TextEntry:SetTextScale( Scale )
	self.TextObj:SetScale( Scale )

	self.WidthScale = Scale.x
	self.HeightScale = Scale.y
	self.TextScale = Scale

	self:SetupCaret()
end

--[[
	Sets the position of the caret, and moves the text accordingly.
]]
function TextEntry:SetCaretPos( Column )
	local Text = self.Text
	local Length = StringUTF8Length( self.Text )

	Column = Clamp( Column, 0, Length )

	self.Column = Column

	local Caret = self.Caret
	local TextObj = self.TextObj

	local Pos = Caret:GetPosition()
	local UTF8W = TextObj:GetTextWidth( StringUTF8Sub( self.Text, 1, self.Column ) ) * self.WidthScale
	local NewPos = UTF8W + self.TextOffset

	--We need to move the text along with the caret, otherwise it'll go out of vision!
	if NewPos < 0 then
		self.TextOffset = Min( self.TextOffset - NewPos, self.Padding )

		if self.Column == 0 then
			self.TextOffset = self.Padding
		end
	elseif NewPos > self.Width then
		local Diff = NewPos - self.Width

		self.TextOffset = self.TextOffset - Diff
	end

	NewPos = Clamp( NewPos + self.CaretOffset, 0, self.Width )
	Caret:SetPosition( Vector( NewPos, Pos.y, 0 ) )
	TextObj:SetPosition( Vector( self.TextOffset, 0, 0 ) )
end

function TextEntry:ResetSelectionBounds()
	self.SelectionBounds[ 1 ] = 0
	self.SelectionBounds[ 2 ] = 0

	self:UpdateSelectionBounds( true )
end

function TextEntry:HasSelection()
	return self.SelectionBounds[ 1 ] ~= self.SelectionBounds[ 2 ]
end

function TextEntry:GetSelectedText()
	return StringUTF8Sub( self.Text, self.SelectionBounds[ 1 ] + 1, self.SelectionBounds[ 2 ] )
end

function TextEntry:RemoveSelectedText()
	local Text = self.Text
	local Length = StringUTF8Length( Text )

	local LowerBound = self.SelectionBounds[ 1 ] + 1
	local UpperBound = self.SelectionBounds[ 2 ]

	local Before = StringUTF8Sub( Text, 1, LowerBound - 1 )
	if UpperBound < Length then
		local After = StringUTF8Sub( Text, UpperBound + 1 )
		self.Text = Before..After
	else
		self.Text = Before
	end

	self:ResetSelectionBounds()

	self.TextObj:SetText( self.Text )
	self:SetCaretPos( self.Column )

	if self.OnTextChanged then
		self:OnTextChanged( Text, self.Text )
	end
end

function TextEntry:UpdateSelectionBounds( SkipAnim, XOverride )
	local SelectionBounds = self.SelectionBounds

	local Pos = self.Caret:GetPosition()
	if XOverride then
		Pos.x = XOverride
	end
	local Size = self.SelectionBox:GetSize()

	if SelectionBounds[ 1 ] == SelectionBounds[ 2 ] then
		Size.x = 0

		if SkipAnim then
			self.SelectionBox:SetPosition( Pos )
			self.SelectionBox:SetSize( Size )
			self:StopMoving()
			self:StopResizing( self.SelectionBox )
		else
			self:MoveTo( self.SelectionBox, nil, Pos, 0, 0.2, nil, nil, 3 )
			self:SizeTo( self.SelectionBox, nil, Size, 0, 0.2 )
		end

		return
	end

	local TextBetween = self.Text:UTF8Sub( SelectionBounds[ 1 ] + 1,
		SelectionBounds[ 2 ] )
	local Width = self.TextObj:GetTextWidth( TextBetween ) * self.WidthScale

	--If it was hidden, don't ease it.
	if Size.x == 0 and not XOverride then
		self.SelectionBox:SetPosition( Pos )
	else
		self:MoveTo( self.SelectionBox, nil, Pos, 0, 0.2, nil, nil, 3 )
	end

	self:SizeTo( self.SelectionBox, nil, Vector( Width, self.Caret:GetSize().y, 0 ), 0, 0.2 )
end

function TextEntry:HandleSelectingText()
	local In, X, Y = self:MouseIn( self.InnerBox )

	local Column = self:GetColumnFromMouse( X )
	local LowerBound = Min( Column, self.SelectingColumn )
	local UpperBound = Max( Column, self.SelectingColumn )

	if LowerBound == self.SelectionBounds[ 1 ] and UpperBound == self.SelectionBounds[ 2 ] then
		return
	end

	self.SelectionBounds[ 1 ] = LowerBound
	self.SelectionBounds[ 2 ] = UpperBound

	if Column <= self.SelectingColumn then
		self:SetCaretPos( LowerBound )
	end

	self:UpdateSelectionBounds()

	if Column > self.SelectingColumn then
		self:SetCaretPos( UpperBound )

		--Have to perform the adjustment after so we get the correct text offset value.
		local BeforeText = StringUTF8Sub( self.Text, 1, LowerBound )
		local Pos = self.Caret:GetPosition()
		Pos.x = self.TextObj:GetTextWidth( BeforeText ) * self.WidthScale + self.TextOffset + self.CaretOffset

		self:MoveTo( self.SelectionBox, nil, Pos, 0, 0.2, nil, nil, 3 )
	end
end

function TextEntry:SetSelection( Lower, Upper, XOverride )
	self.SelectionBounds[ 1 ] = Lower
	self.SelectionBounds[ 2 ] = Upper

	self:SetCaretPos( Lower )
	self.SelectionBox:SetPosition( self.Caret:GetPosition() )
	self:UpdateSelectionBounds( nil, XOverride )
	self:SetCaretPos( Upper )
end

function TextEntry:SelectAll()
	self:SetSelection( 0, StringUTF8Length( self.Text ), self.Padding + self.CaretOffset )
end

local function FindFurthestSpace( Text )
	local PreviousSpace = StringFind( Text, " " )
	--Find the furthest along space before the caret.
	while PreviousSpace do
		local NextSpace = StringFind( Text, " ", PreviousSpace + 1 )

		if NextSpace then
			PreviousSpace = NextSpace
		else
			break
		end
	end

	return PreviousSpace or 1
end

function TextEntry:SelectWord( CharPos )
	local Text = self.Text
	local Length = StringUTF8Length( Text )
	if Length == 0 then return end

	CharPos = CharPos + 1

	local Before = StringUTF8Sub( Text, 1, CharPos - 1 )
	local PreSpace = FindFurthestSpace( Before )

	if PreSpace > 1 then
		PreSpace = StringUTF8Length( StringSub( Text, 1, PreSpace ) )
	else
		PreSpace = 0
	end

	local After = StringUTF8Sub( Text, CharPos )
	local NextSpace = StringFind( After, " " ) or ( #After + 1 )
	NextSpace = StringUTF8Length( Before ) + StringUTF8Length( StringSub( After, 1, NextSpace - 1 ) )

	self:SetSelection( PreSpace, NextSpace )
end

function TextEntry:SetText( Text, IgnoreUndo )
	if not IgnoreUndo and Text ~= self.Text then
		self:PushUndoState()
	end

	self:ResetSelectionBounds()
	self.Text = Text

	self.TextObj:SetText( Text )

	self:SetupCaret()

	if self.PlaceholderText then
		self.PlaceholderText:SetIsVisible( Text == "" )
	end
end

function TextEntry:GetText()
	return self.Text
end

function TextEntry:AllowChar( Char )
	if not Char:IsValidUTF8() then return false end
	if self:ShouldAllowChar( Char ) == false then return false end

	return true
end

function TextEntry:ShouldAllowChar( Char )
	if self.Numeric then
		return tonumber( Char ) ~= nil
	end

	if self.AlphaNumeric then
		return StringFind( Char, "[%w]" ) ~= nil
	end

	if self.CharPattern then
		return StringFind( Char, self.CharPattern ) ~= nil
	end

	return true
end

SGUI.AddProperty( TextEntry, "Numeric" )
SGUI.AddProperty( TextEntry, "AlphaNumeric" )
SGUI.AddProperty( TextEntry, "CharPattern" )

function TextEntry:QueueUndo()
	if not self.UndoTimer then
		self:PushUndoState()
		self.UndoTimer = Timer.Create( self, 0.5, 1, function()
			self.UndoTimer = nil
		end )
	end

	self.UndoTimer:Debounce()
end

--[[
	Inserts a character wherever the caret is.
]]
function TextEntry:AddCharacter( Char, SkipUndo )
	if not self:AllowChar( Char ) then return false end

	if not SkipUndo then
		self:QueueUndo()
	end

	if self:HasSelection() then
		self:RemoveSelectedText()
	end

	local Text = self.Text
	local Length = StringUTF8Length( Text )
	local Before = StringUTF8Sub( Text, 1, self.Column )
	local After = ""

	if self.Column + 1 <= Length then
		After = StringUTF8Sub( Text, self.Column + 1 )
	end

	self.Text = StringFormat( "%s%s%s", Before, Char, After )

	self.Column = self.Column + 1

	self.TextObj:SetText( self.Text )
	self:SetCaretPos( self.Column )

	if self.OnTextChanged then
		self:OnTextChanged( Text, self.Text )
	end

	if self.PlaceholderText then
		self.PlaceholderText:SetIsVisible( false )
	end

	return true
end

function TextEntry:RemoveWord( Forward )
	self:QueueUndo()

	local Before
	local After

	local Text = self.Text

	if Forward then
		if self.Column == StringUTF8Length( self.Text ) then return end

		After = StringUTF8Sub( self.Text, self.Column + 1 )

		local NextSpace = StringFind( After, " " )
		if not NextSpace then
			NextSpace = StringLength( self.Text )
		end

		Before = StringUTF8Sub( self.Text, 1, self.Column )
		After = StringSub( After, NextSpace + 1 )
	else
		if self.Column == 0 then return end

		Before = StringUTF8Sub( self.Text, 1, self.Column - 1 )

		local PreviousSpace = FindFurthestSpace( Before )

		Before = StringSub( self.Text, 1, PreviousSpace - 1 )
		After = StringUTF8Sub( self.Text, self.Column + 1 )
	end

	self.Text = Before..After
	self.TextObj:SetText( self.Text )
	self:SetCaretPos( StringUTF8Length( Before ) )

	if self.OnTextChanged then
		self:OnTextChanged( Text, self.Text )
	end
end

--[[
	Removes a character from wherever the caret is.
]]
function TextEntry:RemoveCharacter( Forward )
	if self:HasSelection() then
		self:QueueUndo()
		self:RemoveSelectedText()

		return
	end

	if self.Column == 0 and not Forward then return end

	if SGUI:IsControlDown() then
		self:RemoveWord( Forward )
		return
	end

	self:QueueUndo()

	local Text = self.Text
	local Length = StringUTF8Length( Text )

	if Forward then
		if self.Column > 0 then
			local Before = StringUTF8Sub( Text, 1, self.Column )

			if self.Column + 2 <= Length then
				local After = StringUTF8Sub( Text, self.Column + 2 )
				self.Text = Before..After
			else
				self.Text = Before
			end
		else
			self.Text = StringUTF8Sub( Text, 2 )
		end
	else
		local Before = StringUTF8Sub( Text, 1, self.Column - 1 )

		if self.Column + 1 <= Length then
			local After = StringUTF8Sub( Text, self.Column + 1 )
			self.Text = Before..After
		else
			self.Text = Before
		end

		self.Column = Max( self.Column - 1, 0 )
	end

	self.TextObj:SetText( self.Text )
	self:SetCaretPos( self.Column )

	if self.OnTextChanged then
		self:OnTextChanged( Text, self.Text )
	end
end

function TextEntry:PlayerType( Char )
	if not self.Enabled then return end
	if not self:GetIsVisible() then return end

	self:AddCharacter( Char )

	return true
end

function TextEntry:Think( DeltaTime )
	if not self:GetIsVisible() then return end

	if self.Enabled then
		local Time = Clock()

		if ( self.NextCaretChange or 0 ) < Time then
			self.NextCaretChange = Time + 0.5
			self.CaretVis = not self.CaretVis
			self.Caret:SetColor( self.CaretVis and CaretCol or Clear )
		end
	end

	self.BaseClass.Think( self, DeltaTime )
end

function TextEntry:OnMouseUp()
	self.SelectingText = false

	if self.DoubleClick and Clock() - self.ClickStart < 0.3 then
		self:SelectWord( self.SelectingColumn )
	end

	return true
end

function TextEntry:OnMouseMove( Down )
	if self.SelectingText then
		self:HandleSelectingText()

		return
	end

	if not self:MouseIn( self.Background ) then
		if not self.Enabled and self.Highlighted then
			self:FadeTo( self.InnerBox, self.FocusColour, self.DarkCol, 0, 0.1 )
			self.Highlighted = false
		end

		return
	end

	if self.Highlighted or self.Enabled then return end

	self:FadeTo( self.InnerBox, self.DarkCol, self.FocusColour, 0, 0.1 )
	self.Highlighted = true
end

function TextEntry:GetColumnFromMouse( X )
	local Offset = self.TextOffset
	local Text = self.Text
	local TextObj = self.TextObj

	local Chars = StringUTF8Encode( Text )
	local Length = #Chars
	if Length == 0 then
		return 0
	end

	local i = 0
	local Width = 0

	repeat
		local Pos = Width + Offset

		if Pos > X then
			local Dist = Pos - X
			local PrevWidth = TextObj:GetTextWidth( Chars[ i - 1 ] or "" ) * self.WidthScale

			if Dist < PrevWidth * 0.5 then
				return i
			else
				return Max( i - 1, 0 )
			end
		end

		i = i + 1

		Width = TextObj:GetTextWidth( TableConcat( Chars, "", 1, i ) ) * self.WidthScale
	until i >= Length

	return Length
end

function TextEntry:SetStickyFocus( Bool )
	self.StickyFocus = Bool and true or false
end

function TextEntry:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end

	if Key == InputKey.MouseButton0 then
		local In, X, Y = self:MouseIn( self.InnerBox )

		if not self.Enabled then
			if In then
				self:RequestFocus()
			else
				return
			end
		end

		if not In then
			if self.StickyFocus then return end

			self:LoseFocus()

			return
		end

		self.SelectingText = true

		local Column = self:GetColumnFromMouse( X )
		self.DoubleClick = DoubleClick
		self.ClickStart = Clock()
		self.SelectingColumn = Column

		self.SelectionBounds[ 1 ] = Column
		self.SelectionBounds[ 2 ] = Column

		self:UpdateSelectionBounds( true )
		self:SetCaretPos( Column )

		return true, self
	end
end

function TextEntry:OnUnhandledKey( Key, Down )

end

function TextEntry:GetState()
	return {
		Text = self.Text,
		CaretPos = self.Column
	}
end

function TextEntry:ResetUndoState()
	self.UndoPosition = 0
	self.UndoStack = {}
end

function TextEntry:PushUndoState()
	local MaxHistory = self:GetMaxUndoHistory()
	for i = self.UndoPosition + 1, #self.UndoStack do
		self.UndoStack[ i ] = nil
	end

	self.UndoStack[ #self.UndoStack + 1 ] = self:GetState()

	while #self.UndoStack > MaxHistory do
		TableRemove( self.UndoStack, 1 )
	end

	self.UndoPosition = #self.UndoStack
end

function TextEntry:RestoreState( State )
	local Text = self.Text

	self:SetText( State.Text, true )
	self:SetCaretPos( State.CaretPos )

	if self.OnTextChanged then
		self:OnTextChanged( Text, self.Text )
	end
end

function TextEntry:Undo()
	local UndoPos = self.UndoPosition
	local Entry = self.UndoStack[ UndoPos ]

	if not Entry then return end

	Entry.Redo = self:GetState()

	self.UndoPosition = self.UndoPosition - 1
	self:RestoreState( Entry )
end

function TextEntry:Redo()
	local UndoPos = self.UndoPosition + 1
	local Entry = self.UndoStack[ UndoPos ]

	if not Entry then return end

	self.UndoPosition = UndoPos
	self:RestoreState( Entry.Redo )
end

function TextEntry:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end
	if not self.Enabled then return end
	if not Down then return end

	if SGUI:IsControlDown() then
		if Key == InputKey.A then
			self:SelectAll()

			return true
		end

		if self:HasSelection() then
			if Key == InputKey.C then
				SGUI.SetClipboardText( self:GetSelectedText() )

				return true
			end

			if Key == InputKey.X then
				self:PushUndoState()
				SGUI.SetClipboardText( self:GetSelectedText() )
				self:RemoveSelectedText()

				return true
			end
		end

		if Key == InputKey.V then
			self:PushUndoState()
			local Chars = StringUTF8Encode( SGUI.GetClipboardText() )
			for i = 1, #Chars do
				if not self:AddCharacter( Chars[ i ], true ) then break end
			end

			return true
		end

		if Key == InputKey.Z then
			self:Undo()
			return true
		end

		if Key == InputKey.Y then
			self:Redo()
			return true
		end
	end

	if Key == InputKey.Back or Key == InputKey.Delete then
		self:RemoveCharacter( Key == InputKey.Delete )
		if self.PlaceholderText and self.Text == "" then
			self.PlaceholderText:SetIsVisible( true )
		end

		return true
	elseif Key == InputKey.Left then
		self:ResetSelectionBounds()
		self:SetCaretPos( self.Column - 1 )

		return true
	elseif Key == InputKey.Right then
		self:ResetSelectionBounds()
		self:SetCaretPos( self.Column + 1 )

		return true
	elseif Key == InputKey.Return then
		if self.OnEnter then
			self:OnEnter()
		end

		return true
	elseif Key == InputKey.Tab then
		if self.OnTab then
			self:OnTab()
		end

		return true
	elseif Key == InputKey.Escape then
		self:LoseFocus()

		return true
	end

	self:OnUnhandledKey( Key, Down )

	return true
end

function TextEntry:OnFocusChange( NewFocus, ClickingOtherElement )
	if NewFocus ~= self then
		if self.StickyFocus and ClickingOtherElement then
			self:RequestFocus()

			return true
		end

		if self.Enabled then
			self.Enabled = false
			self.Highlighted = false
			self:FadeTo( self.InnerBox, self.FocusColour, self.DarkCol, 0, 0.1 )
		end

		self.Caret:SetColor( Clear )

		return
	end

	self:StopFade( self.InnerBox )
	self.Enabled = true
	self.InnerBox:SetColor( self.FocusColour )
end

SGUI:Register( "TextEntry", TextEntry )
