--[[
	Text entry control.
]]

local SGUI = Shine.GUI
local Timer = Shine.Timer

local CalculateTextSize = GUI.CalculateTextSize
local Clamp = math.Clamp
local Clock = SGUI.GetTime
local Floor = math.floor
local Max = math.max
local Min = math.min
local StringFind = string.find
local StringFormat = string.format
local StringLower = string.lower
local StringSub = string.sub
local StringUTF8Chars = string.UTF8Chars
local StringUTF8Encode = string.UTF8Encode
local StringUTF8Length = string.UTF8Length
local StringUTF8Sub = string.UTF8Sub
local TableConcat = table.concat
local TableNew = require "table.new"
local TableRemove = table.remove
local tonumber = tonumber
local Vector2 = Vector2
local Vector = Vector

local TextEntry = {}

TextEntry.UsesKeyboardFocus = true

local CaretCol = Colour( 1, 1, 1, 1 )
local TextPos = Vector2( 2, 0 )

SGUI.AddProperty( TextEntry, "MaxUndoHistory", 100 )
SGUI.AddProperty( TextEntry, "AutoCompleteHandler" )
SGUI.AddProperty( TextEntry, "OnGainFocus" )
SGUI.AddProperty( TextEntry, "OnEnter" )
SGUI.AddProperty( TextEntry, "OnEscape" )
SGUI.AddProperty( TextEntry, "OnLoseFocus" )
SGUI.AddProperty( TextEntry, "OnTextChanged" )
SGUI.AddProperty( TextEntry, "OnUnhandledKey" )

local function GetInnerBoxColour( self, Col )
	if self:ShouldAutoInheritAlpha() then
		return self:ApplyAlphaCompensationToChildItemColour( Col, self:GetTargetAlpha() )
	end
	return Col
end

local function UpdateInnerBoxChildItemColours( self, InnerBoxColour )
	if self.TextColour then
		local TextColour = self:ApplyAlphaCompensationToChildItemColour( self.TextColour, InnerBoxColour.a )
		self.TextObj:SetColor( TextColour )
		self.Caret:SetColor( TextColour )
	end

	if self.HighlightColour then
		self.SelectionBox:SetColor(
			self:ApplyAlphaCompensationToChildItemColour( self.HighlightColour, InnerBoxColour.a )
		)
	end

	if self.PlaceholderTextColour and self.PlaceholderText then
		self.PlaceholderText:SetColor(
			self:ApplyAlphaCompensationToChildItemColour( self.PlaceholderTextColour, InnerBoxColour.a )
		)
	end
end

local function OnInnerBoxColourChanged( self, InnerBoxColour )
	if not self:ShouldAutoInheritAlpha() then return end
	return UpdateInnerBoxChildItemColours( self, InnerBoxColour )
end

local function OnVisibilityChange( self, IsVisible )
	if not IsVisible then
		self.Highlighted = false
		self:StopFade( self.InnerBox )
		self.InnerBox:SetColor( GetInnerBoxColour( self, self.DarkCol ) )
		OnInnerBoxColourChanged( self, self.DarkCol )
	else
		local MouseIn = self:HasMouseEntered()
		if MouseIn or self.Focused then
			self:StopFade( self.InnerBox )
			self.InnerBox:SetColor( GetInnerBoxColour( self, self.FocusColour ) )
			OnInnerBoxColourChanged( self, self.FocusColour )
		end

		self.Highlighted = MouseIn
	end
end

local function GetCurrentInnerBoxColour( self )
	local Colour
	if ( self.Focused or self.Highlighted ) and self.FocusColour then
		Colour = self.FocusColour
	elseif not self.Focused and not self.Highlighted and self.DarkCol then
		Colour = self.DarkCol
	end
	return Colour
end

function TextEntry:Initialise()
	self.BaseClass.Initialise( self )

	-- Border.
	local Background = self:MakeGUIItem()
	self.Background = Background

	-- Coloured entry field.
	local InnerBox = self:MakeGUICroppingItem()

	local SelectionBox = self:MakeGUIItem()
	SelectionBox:SetSize( Vector2( 0, 0 ) )

	self.SelectionBox = SelectionBox

	-- The actual text object.
	local Text = self:MakeGUITextItem()
	Text:SetAnchor( 0, 0.5 )
	Text:SetTextAlignmentY( GUIItem.Align_Center )
	Text:SetPosition( TextPos )

	-- The caret to edit from.
	local Caret = self:MakeGUIItem()
	Caret:SetIsVisible( false )

	self.Caret = Caret

	InnerBox:AddChild( Caret )

	Background:AddChild( InnerBox )

	self.InnerBox = InnerBox

	InnerBox:AddChild( SelectionBox )
	InnerBox:AddChild( Text )

	self.TextObj = Text
	self.Font = Text:GetFontName()

	-- The actual text string.
	self.Text = ""
	self.TextColour = CaretCol

	-- Where's the caret?
	self.Column = 0

	-- How far along we are (this will be negative or self.Padding)
	self.TextOffset = 2

	self.WidthScale = 1
	self.HeightScale = 1

	self.Padding = 2
	self.CaretOffset = 0
	self.BorderSize = Vector2( 0, 0 )

	self.SelectionBounds = { 0, 0 }
	self.UndoPosition = 0
	self.UndoStack = {}

	self.Enabled = true

	self:AddPropertyChangeListener( "IsVisible", OnVisibilityChange )
end

function TextEntry:OnTextChangedInternal( OldText, NewText )
	self:OnTextChanged( OldText, NewText )
	self:OnPropertyChanged( "Text", NewText )
end

local function OnTargetAlphaChanged( self, TargetAlpha )
	local Colour = GetCurrentInnerBoxColour( self )
	if Colour then
		self:StopFade( self.InnerBox )
		self.InnerBox:SetColor( self:ApplyAlphaCompensationToChildItemColour( Colour, TargetAlpha ) )
	end
end

function TextEntry:OnAutoInheritAlphaChanged( IsAutoInherit )
	if IsAutoInherit then
		OnTargetAlphaChanged( self, self:GetTargetAlpha() )
		self:AddPropertyChangeListener( "TargetAlpha", OnTargetAlphaChanged )
	else
		local Colour = GetCurrentInnerBoxColour( self )
		if Colour then
			self:StopFade( self.InnerBox )
			self.InnerBox:SetColor( Colour )

			if self.TextColour then
				self.TextObj:SetColor( self.TextColour )
				self.Caret:SetColor( self.TextColour )
			end

			if self.HighlightColour then
				self.SelectionBox:SetColor( self.HighlightColour )
			end

			if self.PlaceholderTextColour and self.PlaceholderText then
				self.PlaceholderText:SetColor( self.PlaceholderTextColour )
			end
		end
		self:RemovePropertyChangeListener( "TargetAlpha", OnTargetAlphaChanged )
	end
end

local function RefreshWidth( self, InnerBoxSize, Padding )
	self.Width = Max( InnerBoxSize.x - ( Padding * 2 ), 0 )
end

function TextEntry:SetTextPadding( Padding )
	if self.Padding == Padding then return false end

	self.Padding = Padding
	self.TextOffset = Min( self.TextOffset, Padding )

	RefreshWidth( self, self.InnerBox:GetSize(), Padding )

	self:InvalidateLayout()

	return true
end

function TextEntry:GetTextHeight()
	local FontHeight = SGUI.FontManager.GetFontSizeForFontName( self.Font ) or CalculateTextSize( self.Font, "!" ).y
	return FontHeight * self.HeightScale
end

function TextEntry:GetContentSizeForAxis( Axis )
	if Axis == 1 then
		return self:GetSize().x
	end
	return self:GetTextHeight()
end

local function RefreshInternalSize( self, Size, BorderSize )
	local InnerBoxSize = Vector2(
		Max( Size.x - BorderSize.x * 2, 0 ),
		Max( Size.y - BorderSize.y * 2, 0 )
	)
	self.InnerBox:SetSize( InnerBoxSize )

	if self.AbsoluteBorderRadii then
		self.InnerBox:SetShader( SGUI.Shaders.RoundedRect )
		self.InnerBox:SetFloat2Parameter( "size", InnerBoxSize )
		self.InnerBox:SetFloat4Parameter( "radii", self.AbsoluteBorderRadii )
	else
		self.InnerBox:SetShader( "shaders/GUIBasic.surface_shader" )
	end

	RefreshWidth( self, InnerBoxSize, self.Padding )
	self.Height = InnerBoxSize.y
end

function TextEntry:SetSize( SizeVec )
	if not self.BaseClass.SetSize( self, SizeVec ) then return false end

	RefreshInternalSize( self, SizeVec, self.BorderSize )

	return true
end

function TextEntry:GetInnerBoxTargetAlpha()
	local TargetAlpha = 1
	if ( self.Focused or self.Highlighted ) and self.FocusColour then
		TargetAlpha = self.FocusColour.a
	elseif not self.Focused and not self.Highlighted and self.DarkCol then
		TargetAlpha = self.DarkCol.a
	end
	return TargetAlpha
end

SGUI.AddBoundColourProperty(
	TextEntry,
	"PlaceholderTextColour",
	"PlaceholderText:SetColor",
	nil,
	"self:GetInnerBoxTargetAlpha()"
)

local function GetInnerBoxChildColour( self, Col )
	if self:ShouldAutoInheritAlpha() then
		return self:ApplyAlphaCompensationToChildItemColour( Col, self:GetInnerBoxTargetAlpha() )
	end
	return Col
end

function TextEntry:SetFocusColour( Col )
	self.FocusColour = Col

	if self.Focused or self.Highlighted then
		self:StopFade( self.InnerBox )
		self.InnerBox:SetColor( GetInnerBoxColour( self, Col ) )
		OnInnerBoxColourChanged( self, Col )
	end
end

function TextEntry:SetDarkColour( Col )
	self.DarkCol = Col

	if not self.Focused and not self.Highlighted then
		self:StopFade( self.InnerBox )
		self.InnerBox:SetColor( GetInnerBoxColour( self, Col ) )
		OnInnerBoxColourChanged( self, Col )
	end
end

function TextEntry:SetBorderColour( Col )
	self:SetBackgroundColour( Col )
end

function TextEntry:SetTextColour( Col )
	self.TextColour = Col

	local ActualColour = GetInnerBoxChildColour( self, Col )
	self.TextObj:SetColor( ActualColour )
	self.Caret:SetColor( ActualColour )
end

function TextEntry:SetTextShadow( Params )
	self.Shadow = Params

	if not Params then
		self.ShadowOffset = nil
		self.ShadowColour = nil
		self.TextObj:SetDropShadowEnabled( false )
		return
	end

	self.ShadowOffset = Params.Offset or Vector2( 2, 2 )
	self.ShadowColour = Params.Colour

	self.TextObj:SetDropShadowEnabled( true )
	self.TextObj:SetDropShadowOffset( self.ShadowOffset )
	self.TextObj:SetDropShadowColor( Params.Colour )
end

function TextEntry:SetHighlightColour( Col )
	self.HighlightColour = Col
	self.SelectionBox:SetColor( GetInnerBoxChildColour( self, Col ) )
end

function TextEntry:SetBorderSize( BorderSize )
	if self.BorderSize == BorderSize then return false end

	self.InnerBox:SetPosition( BorderSize )
	self.BorderSize = Vector( BorderSize )

	RefreshInternalSize( self, self:GetSize(), BorderSize )

	self:InvalidateLayout()

	return true
end

local function GetPlaceholderTextPos( self )
	local Pos = self.TextObj:GetPosition()
	-- Placeholder text uses text alignment, so no need for vertical offset.
	Pos.y = 0
	return Pos
end

function TextEntry:SetPlaceholderText( Text )
	if Text == "" then
		if self.PlaceholderText then
			self:DestroyGUIItem( self.PlaceholderText )
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

	local PlaceholderText = self:MakeGUITextItem()
	PlaceholderText:SetAnchor( 0, 0.5 )
	PlaceholderText:SetTextAlignmentY( GUIItem.Align_Center )
	PlaceholderText:SetText( Text )
	PlaceholderText:SetInheritsParentScaling( self.TextObj:GetInheritsParentScaling() )

	if self.Font then
		PlaceholderText:SetFontName( self.Font )
		SGUI.FontManager.SetupElementForFontName( PlaceholderText, self.Font )
	end

	if self.TextScale then
		PlaceholderText:SetScale( self.TextScale )
	end

	PlaceholderText:SetPosition( GetPlaceholderTextPos( self ) )
	PlaceholderText:SetColor( GetInnerBoxChildColour( self, self.PlaceholderTextColour or PlaceholderText:GetColor() ) )

	self.InnerBox:AddChild( PlaceholderText )
	self.PlaceholderText = PlaceholderText
end

function TextEntry:SetInternalTextFont( Font )
	self.TextObj:SetFontName( Font )
	SGUI.FontManager.SetupElementForFontName( self.TextObj, Font )
end

function TextEntry:SetFont( Font )
	self.Font = Font
	self:SetInternalTextFont( Font )

	self:SetupCaret()

	if self.PlaceholderText then
		self.PlaceholderText:SetFontName( Font )
		SGUI.FontManager.SetupElementForFontName( self.PlaceholderText, Font )
	end
end

function TextEntry:PerformLayout()
	local OldColumn = self.Column
	self:SetupCaret()
	self:SetCaretPos( OldColumn )
end

function TextEntry:GetTextWidth()
	return self.TextObj:GetTextWidth( self.Text ) * self.WidthScale
end

function TextEntry:GetMaxColumn()
	return StringUTF8Length( self.Text )
end

function TextEntry:SetupCaret()
	local Caret = self.Caret
	local SelectionBox = self.SelectionBox
	local TextObj = self.TextObj

	local Height = self:GetTextHeight() * 0.8

	Caret:SetSize( Vector2( 1, Height ) )
	SelectionBox:SetSize( Vector2( SelectionBox:GetSize().x, Height ) )

	if not self.Width then return end

	self.Column = self:GetMaxColumn()

	local Width = self:GetTextWidth()
	if Width > self.Width then
		local Diff = -( Width - self.Width )

		TextObj:SetPosition( Vector2( Diff, 0 ) )
		Caret:SetPosition( Vector2( Width + Diff + self.CaretOffset, self.Height * 0.5 - Height * 0.5 ) )

		self.TextOffset = Diff
	else
		self.TextOffset = self.Padding

		Caret:SetPosition( Vector2( Width + self.Padding + self.CaretOffset, self.Height * 0.5 - Height * 0.5 ) )
		TextObj:SetPosition( Vector2( self.Padding, 0 ) )
	end
end

function TextEntry:SetTextScale( Scale )
	self.TextObj:SetScale( Scale )
	if self.PlaceholderText then
		self.PlaceholderText:SetScale( Scale )
	end

	self.WidthScale = Scale.x
	self.HeightScale = Scale.y
	self.TextScale = Scale

	self:SetupCaret()
end

function TextEntry:GetCaretPos()
	return self.Column
end

function TextEntry:GetColumnTextWidth( Column )
	local Characters = StringUTF8Encode( self.Text )
	return self.TextObj:GetTextWidth( TableConcat( Characters, "", 1, Column ) ) * self.WidthScale
end

--[[
	Sets the position of the caret, and moves the text accordingly.
]]
function TextEntry:SetCaretPos( Column )
	Column = Clamp( Column, 0, self:GetMaxColumn() )

	self.Column = Column

	local WidthUpToColumn = self:GetColumnTextWidth( Column )
	local NewPos = WidthUpToColumn + self.TextOffset

	-- We need to move the text along with the caret, otherwise it'll go out of vision!
	if NewPos < 0 then
		self.TextOffset = Min( self.TextOffset - NewPos, self.Padding )

		if self.Column == 0 then
			self.TextOffset = self.Padding
		end

		NewPos = Max( NewPos, self.TextOffset )
	elseif NewPos > self.Width then
		local Diff = NewPos - self.Width

		self.TextOffset = self.TextOffset - Diff
	end

	NewPos = Clamp( NewPos + self.CaretOffset, 0, self.Width )

	local Caret = self.Caret
	local Pos = Caret:GetPosition()
	Caret:SetPosition( Vector2( NewPos, Pos.y ) )

	self.TextObj:SetPosition( Vector2( self.TextOffset, 0 ) )
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

function TextEntry:GetTextBetween( StartColumn, EndColumn )
	return StringUTF8Sub( self.Text, StartColumn, EndColumn )
end

function TextEntry:RemoveSelectedText()
	local Text = self:GetText()

	local LowerBound = self.SelectionBounds[ 1 ]
	local UpperBound = self.SelectionBounds[ 2 ]

	local TextBefore = self:GetTextBetween( 1, LowerBound )
	local TextAfter = self:GetTextBetween( UpperBound + 1 )

	self:SetTextInternal( TextBefore..TextAfter )
	self:ResetSelectionBounds()

	self.Column = LowerBound
	self:SetCaretPos( self.Column )

	self:OnTextChangedInternal( Text, self:GetText() )
end

TextEntry.SelectionEasingTime = 0.1

function TextEntry:GetSelectionWidth( SelectionBounds )
	local TextBetween = StringUTF8Sub( self.Text, SelectionBounds[ 1 ] + 1, SelectionBounds[ 2 ] )
	return self.TextObj:GetTextWidth( TextBetween ) * self.WidthScale
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
			self:StopMoving( self.SelectionBox )
			self:StopResizing( self.SelectionBox )
		else
			self:MoveTo( self.SelectionBox, nil, Pos, 0, self.SelectionEasingTime, nil, nil, 3 )
			self:SizeTo( self.SelectionBox, nil, Size, 0, self.SelectionEasingTime )
		end

		return
	end

	local Width = self:GetSelectionWidth( SelectionBounds )
	-- If it was hidden, don't ease it.
	if ( Size.x == 0 and not XOverride ) or SkipAnim then
		self:StopMoving( self.SelectionBox )
		self.SelectionBox:SetPosition( Pos )
	else
		self:MoveTo( self.SelectionBox, nil, Pos, 0, self.SelectionEasingTime, nil, nil, 3 )
	end

	if SkipAnim then
		self:StopResizing( self.SelectionBox )
		self.SelectionBox:SetSize( Vector2( Width, self.Caret:GetSize().y ) )
	else
		self:SizeTo( self.SelectionBox, nil, Vector2( Width, self.Caret:GetSize().y ), 0, self.SelectionEasingTime )
	end
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

		-- Have to perform the adjustment after so we get the correct text offset value.
		local WidthBeforeCaret = self:GetColumnTextWidth( LowerBound )
		local Pos = self.Caret:GetPosition()
		Pos.x = WidthBeforeCaret + self.TextOffset + self.CaretOffset

		self:MoveTo( self.SelectionBox, nil, Pos, 0, self.SelectionEasingTime, nil, nil, 3 )
	end
end

function TextEntry:SetSelection( Lower, Upper, SkipAnim, XOverride )
	self.SelectionBounds[ 1 ] = Lower
	self.SelectionBounds[ 2 ] = Upper

	self:SetCaretPos( Lower )
	self.SelectionBox:SetPosition( self.Caret:GetPosition() )
	self:UpdateSelectionBounds( SkipAnim, XOverride )
	self:SetCaretPos( Upper )
end

function TextEntry:OffsetSelection( Amount )
	local CaretPos = self.Column
	local Bounds = self.SelectionBounds

	if Bounds[ 1 ] == Bounds[ 2 ] then
		if Amount < 0 then
			Bounds[ 2 ] = CaretPos
			CaretPos = Max( CaretPos + Amount, 0 )
			Bounds[ 1 ] = CaretPos
		else
			Bounds[ 1 ] = CaretPos
			CaretPos = Min( CaretPos + Amount, self:GetMaxColumn() )
			Bounds[ 2 ] = CaretPos
		end

		self:SetSelection( Bounds[ 1 ], Bounds[ 2 ], true, Bounds[ 1 ] == 0 and ( self.Padding + self.CaretOffset ) or nil )
		self:SetCaretPos( CaretPos )
		return
	end

	local NewCaretPos = Clamp( CaretPos + Amount, 0, self:GetMaxColumn() )
	if CaretPos <= Bounds[ 1 ] then
		Bounds[ 1 ] = NewCaretPos
		if Bounds[ 1 ] > Bounds[ 2 ] then
			Bounds[ 1 ] = Bounds[ 2 ]
			Bounds[ 2 ] = NewCaretPos
		end
	else
		Bounds[ 2 ] = NewCaretPos
		if Bounds[ 2 ] < Bounds[ 1 ] then
			Bounds[ 2 ] = Bounds[ 1 ]
			Bounds[ 1 ] = NewCaretPos
		end
	end

	self:SetSelection( Bounds[ 1 ], Bounds[ 2 ], true, Bounds[ 1 ] == 0 and ( self.Padding + self.CaretOffset ) or nil )
	self:SetCaretPos( NewCaretPos )
end

function TextEntry:SelectAll()
	self:SetSelection( 0, self:GetMaxColumn(), false, self.Padding + self.CaretOffset )
end

local TextEntryUtil = require "shine/lib/gui/objects/textentry/util"

function TextEntry:FindWordBounds( CharPos )
	local Characters, Length = StringUTF8Encode( self.Text )
	if Length == 0 then return 0, 0 end

	local PrevSpace, NextSpace = TextEntryUtil.FindWordBoundsFromCharacters( Characters, Length, CharPos )
	if PrevSpace == 1 then
		PrevSpace = 0
	end
	return PrevSpace, NextSpace
end

function TextEntry:FindNextWordBoundInDir( Pos, Dir )
	local PrevSpace, NextSpace = self:FindWordBounds( Pos )

	if Dir == 1 and NextSpace == Pos and Pos ~= self:GetMaxColumn() then
		PrevSpace, NextSpace = self:FindWordBounds( Pos + 1 )
	elseif Dir == -1 and PrevSpace == Pos and Pos ~= 0 then
		PrevSpace = self:FindWordBounds( Pos - 1 )
	end

	return Dir == 1 and NextSpace or PrevSpace
end

function TextEntry:SelectWord( CharPos )
	self:SetSelection( self:FindWordBounds( CharPos ) )
end

function TextEntry:SetTextInternal( Text )
	self.Text = Text
	self.TextObj:SetText( Text )
	self.TextObj:ForceUpdateTextSize()
end

function TextEntry:SetText( Text, IgnoreUndo )
	local Changed = Text ~= self:GetText()
	if not IgnoreUndo and Changed then
		self:PushUndoState()
	end

	self:ResetSelectionBounds()
	self:SetTextInternal( Text )
	self:SetupCaret()

	if self.PlaceholderText then
		self.PlaceholderText:SetIsVisible( Text == "" )
		self.PlaceholderText:SetPosition( GetPlaceholderTextPos( self ) )
	end

	if Changed then
		-- Only call the property change, OnTextChanged is for user-initiated changes to text only.
		self:OnPropertyChanged( "Text", Text )
	end
end

function TextEntry:GetText()
	return self.Text
end

function TextEntry:IsEmpty()
	return self.Text == ""
end

function TextEntry:AllowChar( Char )
	if not Char:IsValidUTF8() then return false end
	if self:ShouldAllowChar( Char ) == false then return false end

	return true
end

function TextEntry:IsAtMaxLength()
	return not not ( self.MaxLength and StringUTF8Length( self:GetText() ) >= self.MaxLength )
end

function TextEntry:DoesCharPassPatternChecks( Char )
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

function TextEntry:ShouldAllowChar( Char )
	if not self:DoesCharPassPatternChecks( Char ) then
		return false
	end

	if self:IsAtMaxLength() then
		return false
	end

	return true
end

SGUI.AddProperty( TextEntry, "Numeric" )
SGUI.AddProperty( TextEntry, "AlphaNumeric" )
SGUI.AddProperty( TextEntry, "CharPattern" )
SGUI.AddProperty( TextEntry, "MaxLength" )

do
	local function ClearUndoTimer( Timer )
		Timer.Data.UndoTimer = nil
	end

	function TextEntry:QueueUndo()
		if not self.UndoTimer then
			self:PushUndoState()
			self.UndoTimer = Timer.Create( self, 0.5, 1, ClearUndoTimer, self )
		end
		self.UndoTimer:Debounce()
	end
end

function TextEntry:OnTextChanged( OldText, NewText )

end

do
	function TextEntry:InsertTextInternal( NewText, NumChars )
		local Text = self.Text
		local Characters, Length = StringUTF8Encode( Text )
		local TextBefore = TableConcat( Characters, "", 1, self.Column )
		local TextAfter = ""

		if self.Column + 1 <= Length then
			TextAfter = TableConcat( Characters, "", self.Column + 1 )
		end

		self.Text = StringFormat( "%s%s%s", TextBefore, NewText, TextAfter )
		self.Column = self.Column + NumChars

		self.TextObj:SetText( self.Text )
		self:SetCaretPos( self.Column )
		self:OnTextChangedInternal( Text, self.Text )
	end

	function TextEntry:InsertTextWithoutValidation( NewText, NumChars, SkipUndo )
		if not SkipUndo then
			self:QueueUndo()
		end

		if self:HasSelection() then
			self:RemoveSelectedText()
		end

		self:InsertTextInternal( NewText, NumChars )

		if self.PlaceholderText then
			self.PlaceholderText:SetIsVisible( false )
		end
	end

	--[[
		Inserts a character wherever the caret is.
	]]
	function TextEntry:AddCharacter( Char, SkipUndo )
		if not self:AllowChar( Char ) then return false end

		self:InsertTextWithoutValidation( Char, 1, SkipUndo )

		return true
	end

	--[[
		Inserts arbitrary text wherever the caret is.

		Pass options to configure the behaviour:
		* "SkipIfAnyCharBlocked" - If true, the text must be insertable in its entirety. If any part of it cannot be
		inserted, nothing will be inserted.
	]]
	function TextEntry:InsertTextAtCaret( Text, Options )
		local CurrentLength
		if self.MaxLength then
			CurrentLength = StringUTF8Length( self:GetText() )

			if CurrentLength >= self.MaxLength then return false end
		end

		local Count = 0
		local StoppedEarly = false
		local TextToInsert = TableNew( #Text, 0 )
		for ByteIndex, Char in StringUTF8Chars( Text ) do
			if
				( CurrentLength and CurrentLength + Count >= self.MaxLength ) or
				not self:DoesCharPassPatternChecks( Char )
			then
				StoppedEarly = true
				break
			end

			Count = Count + 1
			TextToInsert[ Count ] = Char
		end

		if StoppedEarly and Options and Options.SkipIfAnyCharBlocked then return false end

		self:PushUndoState()
		self:InsertTextWithoutValidation( TableConcat( TextToInsert ), Count, true )

		return true
	end
end

function TextEntry:UpdateCaretPos( TextColumn, UpdatedText, NewText )
	self:SetCaretPos( TextColumn )
end

function TextEntry:RemoveWord( Forward )
	self:QueueUndo()

	local TextBefore
	local TextAfter
	local OldText = self:GetText()

	local NextBound = self:FindNextWordBoundInDir( self.Column, Forward and 1 or -1 )
	if Forward then
		TextBefore = self:GetTextBetween( 1, self.Column )
		TextAfter = self:GetTextBetween( NextBound + 1 )
	else
		if self.Column == 0 then return end

		TextBefore = self:GetTextBetween( 1, Max( NextBound - 1, 0 ) )
		TextAfter = self:GetTextBetween( self.Column + 1 )
	end

	local UpdatedText = TextBefore..TextAfter

	self:SetTextInternal( UpdatedText )

	local NewText = self:GetText()
	self:UpdateCaretPos( StringUTF8Length( TextBefore ), UpdatedText, NewText )

	self:OnTextChangedInternal( OldText, NewText )
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

	local OldText = self:GetText()
	local UpdatedText
	local TextColumn

	if Forward then
		if self.Column > 0 then
			local TextBefore = self:GetTextBetween( 1, self.Column )
			local TextAfter = self:GetTextBetween( self.Column + 2 )

			UpdatedText = TextBefore..TextAfter
			TextColumn = StringUTF8Length( TextBefore )
		else
			UpdatedText = self:GetTextBetween( 2 )
			TextColumn = 0
		end
	else
		local TextBefore = self:GetTextBetween( 1, Max( self.Column - 1, 0 ) )
		local TextAfter = self:GetTextBetween( self.Column + 1 )

		UpdatedText = TextBefore..TextAfter

		TextColumn = StringUTF8Length( TextBefore )
	end

	self:SetTextInternal( UpdatedText )

	NewText = self:GetText()
	self:UpdateCaretPos( TextColumn, UpdatedText, NewText )

	self:OnTextChangedInternal( OldText, NewText )
end

function TextEntry:PlayerType( Char )
	if not self.Focused then return end
	if not self:GetIsVisible() then return end

	if self.AutoCompleteHandler then
		self:ResetAutoComplete()
	end

	self:AddCharacter( Char )

	return true
end

local function SetCaretVisible( self, Visible )
	self.CaretVis = Visible
	self.Caret:SetIsVisible( Visible )
end

function TextEntry:Think( DeltaTime )
	if not self:GetIsVisible() then return end

	if self.Focused then
		local Time = Clock()

		if ( self.NextCaretChange or 0 ) < Time then
			self.NextCaretChange = Time + 0.5
			SetCaretVisible( self, not self.CaretVis )
		end
	end

	self.BaseClass.Think( self, DeltaTime )
	self:CallOnChildren( "Think", DeltaTime )
end

function TextEntry:OnMouseUp()
	self.SelectingText = false

	if self.DoubleClick and Clock() - self.ClickStart < 0.3 then
		self:SelectWord( self.SelectingColumn )
	end

	return true
end

function TextEntry:OnMouseEnter()
	self.BaseClass.OnMouseEnter( self )

	if self.Focused or self.Highlighted or not self.Enabled then return end

	self:FadeTo(
		self.InnerBox,
		SGUI.CopyColour( GetInnerBoxColour( self, self.DarkCol ) ),
		SGUI.CopyColour( GetInnerBoxColour( self, self.FocusColour ) ),
		0,
		0.1
	)
	self.Highlighted = true
end

function TextEntry:OnMouseLeave()
	self.BaseClass.OnMouseLeave( self )

	if self.Focused or not self.Highlighted then return end

	self:FadeTo(
		self.InnerBox,
		SGUI.CopyColour( GetInnerBoxColour( self, self.FocusColour ) ),
		SGUI.CopyColour( GetInnerBoxColour( self, self.DarkCol ) ),
		0,
		0.1
	)
	self.Highlighted = false
end

function TextEntry:OnMouseMove( Down )
	if not self:GetIsVisible() then return end

	if self.SelectingText then
		self:HandleSelectingText()

		return
	end

	self.BaseClass.OnMouseMove( self, Down )
end

function TextEntry:GetColumnFromMouse( X )
	local Text = self.Text
	local Characters, Length = StringUTF8Encode( Text )
	if Length == 0 then
		return 0
	end

	local Offset = self.TextOffset
	local TextObj = self.TextObj
	local WidthScale = self.WidthScale

	local Pos = Offset
	local CaretIndex = 0
	local CaretCharacterWidth = 0
	while Pos <= X and CaretIndex < Length do
		CaretIndex = CaretIndex + 1
		CaretCharacterWidth = TextObj:GetTextWidth( Characters[ CaretIndex ] ) * WidthScale
		Pos = Pos + CaretCharacterWidth
	end

	local Dist = Pos - X
	if Dist < CaretCharacterWidth * 0.5 then
		return CaretIndex
	end

	return Max( CaretIndex - 1, 0 )
end

function TextEntry:SetStickyFocus( Bool )
	self.StickyFocus = Bool and true or false
end

function TextEntry:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() or not self.Enabled then return end

	if Key == InputKey.MouseButton0 then
		local In, X, Y = self:MouseIn( self.InnerBox )

		if not self.Focused then
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
		Text = self:GetText(),
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

	return self.UndoStack[ self.UndoPosition ]
end

function TextEntry:RestoreState( State )
	local Text = self:GetText()

	self:SetText( State.Text, true )
	self:SetCaretPos( State.CaretPos )
	self:OnTextChangedInternal( Text, self:GetText() )
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

do
	local AutoCompleteErrorHandler = Shine.BuildErrorHandler( "Auto complete error" )

	function TextEntry:ConvertStateToAutoComplete( State )
		return State
	end

	function TextEntry:ConvertStateFromAutoComplete( State )
		return State
	end

	function TextEntry:OnTab()
		if not self.AutoCompleteHandler then return end

		local OldState
		local WasAutoCompleting
		if self.AutoCompleteHandler:IsAutoCompleting() then
			WasAutoCompleting = true
			OldState = self.AutoCompleteInitialState
		else
			OldState = self:ConvertStateToAutoComplete( self:GetState() )
		end

		-- Auto completion should provide the new state of the text and caret.
		-- Tab advances the match index, Shift + Tab reverses it.
		local Success, NewState = xpcall( self.AutoCompleteHandler.PerformCompletion,
			AutoCompleteErrorHandler,
			self.AutoCompleteHandler, OldState, SGUI:IsShiftDown() )
		if not Success or not NewState then return end

		if not WasAutoCompleting then
			self.AutoCompleteInitialState = OldState
		end

		NewState = self:ConvertStateFromAutoComplete( NewState )

		if self.MaxLength then
			-- Enforce maximum length as this won't go through ShouldAllowChar.
			NewState.Text = StringUTF8Sub( NewState.Text, 1, self.MaxLength )
		end

		-- If there's no change in the state, then ignore the completion.
		local CurrentState = self:GetState()
		if NewState.Text == CurrentState.Text and NewState.CaretPos == CurrentState.CaretPos then
			return
		end

		self:PushUndoState()
		self:RestoreState( NewState )
	end
end

function TextEntry:ResetAutoComplete()
	self.AutoCompleteInitialState = nil
	self.AutoCompleteHandler:Reset()
end

function TextEntry:OnEnter()

end

function TextEntry:OnEscape()
	return false
end

function TextEntry:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end
	if not self.Focused then return end

	-- Reset the auto-completion list on any action other than pressing tab.
	if
		Key ~= InputKey.Tab and
		Key ~= InputKey.LeftShift and
		Key ~= InputKey.RightShift and
		self.AutoCompleteHandler
	then
		self:ResetAutoComplete()
	end

	if SGUI:IsControlDown() then
		if Down and Key == InputKey.A then
			self:SelectAll()

			return true
		end

		if self:HasSelection() then
			if Down and Key == InputKey.C then
				SGUI.SetClipboardText( self:GetSelectedText() )

				return true
			end

			if Down and Key == InputKey.X then
				self:PushUndoState()
				SGUI.SetClipboardText( self:GetSelectedText() )
				self:RemoveSelectedText()

				return true
			end
		end

		if Down and Key == InputKey.V then
			self:InsertTextAtCaret( SGUI.GetClipboardText() )
			return true
		end

		if Down and Key == InputKey.Z then
			self:Undo()
			return true
		end

		if Down and Key == InputKey.Y then
			self:Redo()
			return true
		end
	end

	if Down and ( Key == InputKey.Back or Key == InputKey.Delete ) then
		self:RemoveCharacter( Key == InputKey.Delete )
		if self.PlaceholderText and self:IsEmpty() then
			self.PlaceholderText:SetIsVisible( true )
			self.PlaceholderText:SetPosition( GetPlaceholderTextPos( self ) )
		end

		return true
	end

	if Down and Key == InputKey.Left then
		if SGUI:IsShiftDown() then
			if SGUI:IsControlDown() then
				local PrevSpace = self:FindNextWordBoundInDir( self.Column, -1 )
				self:OffsetSelection( PrevSpace - self.Column )

				return true
			end

			self:OffsetSelection( -1 )
			return true
		end

		self:ResetSelectionBounds()

		if SGUI:IsControlDown() then
			local PrevSpace = self:FindNextWordBoundInDir( self.Column, -1 )
			self:SetCaretPos( PrevSpace )
			return true
		end

		self:SetCaretPos( self.Column - 1 )

		return true
	end

	if Down and Key == InputKey.Right then
		if SGUI:IsShiftDown() then
			if SGUI:IsControlDown() then
				local NextSpace = self:FindNextWordBoundInDir( self.Column, 1 )
				self:OffsetSelection( NextSpace - self.Column )

				return true
			end

			self:OffsetSelection( 1 )
			return true
		end

		self:ResetSelectionBounds()

		if SGUI:IsControlDown() then
			local NextSpace = self:FindNextWordBoundInDir( self.Column, 1 )
			self:SetCaretPos( NextSpace )
			return true
		end

		self:SetCaretPos( self.Column + 1 )

		return true
	end

	if Down and Key == InputKey.Home then
		if SGUI:IsShiftDown() then
			self:OffsetSelection( -self.Column )
			return true
		end

		self:SetCaretPos( 0 )

		return true
	end

	if Down and Key == InputKey.End then
		local MaxCaretPos = self:GetMaxColumn()
		if SGUI:IsShiftDown() then
			self:OffsetSelection( MaxCaretPos - self.Column )
			return true
		end

		self:SetCaretPos( MaxCaretPos )

		return true
	end

	if Down and Key == InputKey.Return then
		self:OnEnter()

		return true
	end

	if Down and Key == InputKey.Tab then
		self:OnTab()

		return true
	end

	if Down and Key == InputKey.Escape then
		if not self:OnEscape() then
			self:LoseFocus()
		end

		return true
	end

	self:OnUnhandledKey( Key, Down )

	return true
end

function TextEntry:RequestFocus()
	if not self.Enabled then return end
	return self.BaseClass.RequestFocus( self )
end

function TextEntry:OnFocusChange( NewFocus, ClickingOtherElement )
	if NewFocus ~= self then
		if self.StickyFocus and ClickingOtherElement then
			self:RequestFocus()

			return true
		end

		if self.Focused then
			self.Focused = false

			if not self:HasMouseEntered() then
				self.Highlighted = false
				self:FadeTo( self.InnerBox, self.FocusColour, self.DarkCol, 0, 0.1 )
			end

			self:RemoveStylingState( "Focus" )
		end

		SetCaretVisible( self, false )
		self:OnLoseFocus()

		return
	end

	self:AddStylingState( "Focus" )
	self:StopFade( self.InnerBox )
	self.InnerBox:SetColor( GetInnerBoxColour( self, self.FocusColour ) )
	OnInnerBoxColourChanged( self, self.FocusColour )

	-- Show the caret immediately so it's clear that the text entry has been focused.
	SetCaretVisible( self, true )
	self.NextCaretChange = Clock() + 0.5

	if not self.Focused then
		self:OnGainFocus()
	end

	self.Focused = true
end

function TextEntry:OnGainFocus()

end

function TextEntry:OnLoseFocus()

end

TextEntry.StandardAutoComplete = require "shine/lib/gui/objects/textentry/auto_complete"

SGUI:AddMixin( TextEntry, "EnableMixin" )
SGUI:Register( "TextEntry", TextEntry )
