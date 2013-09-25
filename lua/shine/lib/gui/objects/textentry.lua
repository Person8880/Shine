--[[
	Text entry control.
]]

local SGUI = Shine.GUI

local Clamp = math.Clamp
local Max = math.max
local Min = math.min

local TextEntry = {}

local BorderSize = Vector( 2, 2, 0 )
local CaretCol = Color( 0, 0, 0, 1 )
local Clear = Color( 0, 0, 0, 0 )
local TextPos = Vector( 0, 0, 0 )

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

	--The caret to edit from.
	local Caret = Manager:CreateGraphicItem()
	Caret:SetAnchor( GUIItem.Left, GUIItem.Top )
	Caret:SetColor( Clear )

	self.Caret = Caret

	InnerBox:AddChild( Caret )
	InnerBox:AddChild( Stencil )

	Background:AddChild( InnerBox )

	self.InnerBox = InnerBox

	--The actual text object.
	local Text = Manager:CreateTextItem()
	Text:SetAnchor( GUIItem.Left, GUIItem.Center )
	Text:SetTextAlignmentY( GUIItem.Align_Center )
	Text:SetPosition( TextPos )
	Text:SetInheritsParentStencilSettings( false )
	Text:SetStencilFunc( GUIItem.NotEqual )

	InnerBox:AddChild( Text )

	self.TextObj = Text

	--The actual text string.
	self.Text = ""

	--Where's the caret?
	self.Column = 0

	--How far along we are (this will be negative or 0)
	self.TextOffset = 0

	self.WidthScale = 1
	self.HeightScale = 1

	local Scheme = SGUI:GetSkin()

	--Default colour scheme.
	self.FocusColour = Scheme.TextEntryFocus
	self.DarkCol = Scheme.TextEntry

	Background:SetColor( Scheme.ButtonBorder )
	InnerBox:SetColor( self.DarkCol )
	Text:SetColor( Scheme.DarkText )
end

function TextEntry:SetSize( SizeVec )
	self.Background:SetSize( SizeVec )

	local InnerBoxSize = SizeVec - BorderSize * 2

	self.Stencil:SetSize( InnerBoxSize )
	self.InnerBox:SetSize( InnerBoxSize )

	self.Width = InnerBoxSize.x - 5
	self.Height = InnerBoxSize.y
end

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

function TextEntry:GetIsVisible()
	if self.Parent and not self.Parent:GetIsVisible() then
		return false
	end

	return self.Background:GetIsVisible()
end

--[[
	Colour scheme changed, change our colours!
]]
function TextEntry:OnSchemeChange( Scheme )
	if not self.UseScheme then return end
	
	self.FocusColour = Scheme.TextEntryFocus
	self.DarkCol = Scheme.TextEntry

	self.Background:SetColor( Scheme.ButtonBorder )
	self.TextObj:SetColor( Scheme.DarkText )

	if self.Highlighted or self.Enabled then
		self.InnerBox:SetColor( self.FocusColour )
	else
		self.InnerBox:SetColor( self.DarkCol )
	end
end

function TextEntry:SetFont( Font )
	self.TextObj:SetFontName( Font )

	self:SetupCaret()
end

function TextEntry:SetupCaret()
	local Caret = self.Caret
	local TextObj = self.TextObj

	local Height = TextObj:GetTextHeight( "!" ) * self.HeightScale

	Caret:SetSize( Vector( 1, Height, 0 ) )

	local Width = TextObj:GetTextWidth( self.Text ) * self.WidthScale

	if Width > self.Width then
		local Diff = -( Width - self.Width )

		TextObj:SetPosition( Vector( Diff, 0, 0 ) )

		self.Column = self.Text:UTF8Length()

		Caret:SetPosition( Vector( Width + Diff, self.Height * 0.5 - Height * 0.5, 0 ) )

		self.TextOffset = Diff
	else
		self.TextOffset = 0

		self.Column = self.Text:UTF8Length()

		local Pos = Caret:GetPosition()

		Caret:SetPosition( Vector( Width, self.Height * 0.5 - Height * 0.5, 0 ) )

		TextObj:SetPosition( TextPos )
	end
end

function TextEntry:SetTextScale( Scale )
	self.TextObj:SetScale( Scale )

	self.WidthScale = Scale.x
	self.HeightScale = Scale.y

	self:SetupCaret()
end

--[[
	Sets the position of the caret, and moves the text accordingly.
]]
function TextEntry:SetCaretPos( Column )
	local Text = self.Text
	local Length = self.Text:UTF8Length()

	Column = Clamp( Column, 0, Length )

	self.Column = Column

	local Caret = self.Caret
	local TextObj = self.TextObj

	local Pos = Caret:GetPosition()

	local UTF8W = TextObj:GetTextWidth( self.Text:UTF8Sub( 1, self.Column ) ) * self.WidthScale

	local NewPos = UTF8W + self.TextOffset

	--We need to move the text along with the caret, otherwise it'll go out of vision!
	if NewPos < 0 then
		self.TextOffset = Min( self.TextOffset - NewPos, 0 )

		TextObj:SetPosition( Vector( self.TextOffset, 0, 0 ) )
	elseif NewPos > self.Width then
		local Diff = NewPos - self.Width

		self.TextOffset = self.TextOffset - Diff

		TextObj:SetPosition( Vector( self.TextOffset, 0, 0 ) )
	end

	Caret:SetPosition( Vector( UTF8W + self.TextOffset, Pos.y, 0 ) )
end

function TextEntry:SetText( Text )
	self.Text = Text

	self.TextObj:SetText( Text )

	self:SetupCaret()
end

function TextEntry:GetText()
	return self.Text
end

function TextEntry:AllowChar( Char )
	if not Char:IsValidUTF8() then return false end

	if self.ShouldAllowChar then
		if self:ShouldAllowChar( Char ) == false then return false end
	end

	return true
end

--[[
	Inserts a character wherever the caret is.
]]
function TextEntry:AddCharacter( Char )
	if not self:AllowChar( Char ) then return end

	self.Text = self.Text:UTF8Sub( 1, self.Column )..Char..self.Text:UTF8Sub( self.Column + 1 )

	self.Column = self.Column + 1

	local Caret = self.Caret
	local TextObj = self.TextObj

	TextObj:SetText( self.Text )

	local Width = TextObj:GetTextWidth( self.Text ) * self.WidthScale

	if Width > self.Width then
		local Diff = -( Width - self.Width )

		TextObj:SetPosition( Vector( Diff, 0, 0 ) )

		self:SetCaretPos( self.Column )

		self.TextOffset = Diff
	else
		self.TextOffset = 0

		self:SetCaretPos( self.Column )

		TextObj:SetPosition( TextPos )
	end
end

--[[
	Removes a character from wherever the caret is.
]]
function TextEntry:RemoveCharacter( Forward )
	if self.Column == 0 and not Forward then return end

	local Caret = self.Caret
	local TextObj = self.TextObj

	local OldWidth = TextObj:GetTextWidth( self.Text ) * self.WidthScale

	if Forward then
		if self.Column > 0 then
			self.Text = self.Text:UTF8Sub( 1, self.Column )..self.Text:UTF8Sub( self.Column + 2 )
		else
			self.Text = self.Text:UTF8Sub( 2 )
		end
	else
		self.Text = self.Text:UTF8Sub( 1, self.Column - 1 )..self.Text:UTF8Sub( self.Column + 1 )

		self.Column = Max( self.Column - 1, 0 )
	end

	local NewWidth = TextObj:GetTextWidth( self.Text ) * self.WidthScale

	TextObj:SetText( self.Text )

	if NewWidth > self.Width then
		local Diff = -( NewWidth - self.Width )

		self.TextOffset = Min( Diff, 0 )

		self:SetCaretPos( self.Column )

		TextObj:SetPosition( Vector( self.TextOffset, 0, 0 ) )
	else
		self.TextOffset = 0

		self:SetCaretPos( self.Column )

		TextObj:SetPosition( TextPos )
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
	
	self.BaseClass.Think( self, DeltaTime )

	if self.Enabled then 
		local Time = Shared.GetTime()

		if ( self.NextCaretChange or 0 ) < Time then
			self.NextCaretChange = Time + 0.5

			self.CaretVis = not self.CaretVis

			self.Caret:SetColor( self.CaretVis and CaretCol or Clear )
		end

		return 
	end
end

function TextEntry:OnMouseMove( Down )
	if not self:MouseIn( self.Background ) then 
		if self.Highlighted then
			self:FadeTo( self.InnerBox, self.FocusColour, self.DarkCol, 0, 0.5, function( InnerBox )
				if self.Enabled then 
					InnerBox:SetColor( self.FocusColour )

					return 
				end
				
				InnerBox:SetColor( self.DarkCol )
			end )
		
			self.Highlighted = false 
		end

		return 
	end
	
	if self.Highlighted then return end

	self:FadeTo( self.InnerBox, self.DarkCol, self.FocusColour, 0, 0.5, function( InnerBox )
		InnerBox:SetColor( self.FocusColour )
	end )

	self.Highlighted = true
end

function TextEntry:GetColumnFromMouse( X )
	local Offset = self.TextOffset
	local Text = self.Text
	local TextObj = self.TextObj

	local Length = Text:UTF8Length()

	local i = 1

	local Width = TextObj:GetTextWidth( Text:UTF8Sub( 1, i ) ) * self.WidthScale + Offset

	repeat
		local Pos = Width + Offset

		if Pos > X then
			local Dist = Pos - X
			local PrevWidth = TextObj:GetTextWidth( Text:UTF8Sub( i - 1, i - 1 ) ) * self.WidthScale

			if Dist < PrevWidth * 0.5 then
				return i
			else
				return i - 1
			end
		end

		i = i + 1

		Width = TextObj:GetTextWidth( Text:UTF8Sub( 1, i ) ) * self.WidthScale
	until i >= Length

	return Length
end

function TextEntry:SetStickyFocus( Bool )
	self.StickyFocus = Bool and true or false
end

function TextEntry:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end

	if Key == InputKey.MouseButton0 and Down then
		local In, X, Y = self:MouseIn( self.InnerBox )

		if not self.Enabled then
			if In then
				self:RequestFocus()

				return true
			end
		
			return
		end

		if not In then
			if self.StickyFocus then return end
			
			self:LoseFocus()

			return
		end
		
		self.Column = self:GetColumnFromMouse( X )

		self:SetCaretPos( self.Column )

		return true
	end 

	if not self.Enabled then return end
	if not Down then return end

	if Key == InputKey.Back then
		self:RemoveCharacter()

		return true
	elseif Key == InputKey.Delete then
		self:RemoveCharacter( true )

		return true
	elseif Key == InputKey.Left then
		self:SetCaretPos( self.Column - 1 )

		return true
	elseif Key == InputKey.Right then
		self:SetCaretPos( self.Column + 1 )

		return true
	elseif Key == InputKey.Return then
		if self.OnEnter then
			self:OnEnter()
		end

		return true
	elseif Key == InputKey.Escape then
		self:LoseFocus()

		return true
	end

	return true
end

function TextEntry:OnFocusChange( NewFocus )
	if NewFocus ~= self then
		self.Enabled = false

		self:FadeTo( self.InnerBox, self.FocusColour, self.DarkCol, 0, 0.5, function( InnerBox )
			if self.Enabled then
				InnerBox:SetColor( self.FocusColour )

				return
			end
			
			InnerBox:SetColor( self.DarkCol )
		end )

		self.Caret:SetColor( Clear )

		return
	end

	self:StopFade( self.InnerBox )

	self.Enabled = true

	self.InnerBox:SetColor( self.FocusColour )
end

function TextEntry:Cleanup()
	if self.Parent then return end
	
	if self.Background then
		GUI.DestroyItem( self.Background )
	end
end

SGUI:Register( "TextEntry", TextEntry )
