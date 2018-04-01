--[[
	Chat line object for the chatbox.
]]

local SGUI = Shine.GUI

local ChatLine = {}

SGUI.AddProperty( ChatLine, "Pos", nil, { "InvalidatesLayoutNow" } )
SGUI.AddProperty( ChatLine, "LineSpacing" )
SGUI.AddProperty( ChatLine, "PreMargin" )

function ChatLine:Initialise()
	self.PreLabel = SGUI:Create( "Label", self.Parent )
	self.MessageLabel = SGUI:Create( "Label", self.Parent )

	self.Pos = Vector2( 0, 0 )
end

function ChatLine:GetAnchor()
	return self.PreLabel:GetAnchor()
end

function ChatLine:GetIsVisible()
	return self.PreLabel:GetIsVisible()
end

function ChatLine:SetParent( Parent )
	self.BaseClass.SetParent( self, Parent )
	self:ForEachLabel( "SetParent", Parent, Parent and Parent.ScrollParent )
end

do
	local function CallMethod( Object, Method, ... )
		Object[ Method ]( Object, ... )
	end

	function ChatLine:ForEachLabel( Method, ... )
		CallMethod( self.PreLabel, Method, ... )
		CallMethod( self.MessageLabel, Method, ... )

		if self.WrappedLabel then
			CallMethod( self.WrappedLabel, Method, ... )
		end

		self:ForEach( "Tags", Method, ... )
	end
end

function ChatLine:SetFont( Font )
	self.Font = Font
	self:ForEachLabel( "SetFont", Font )
end

function ChatLine:SetTextScale( Scale )
	self.TextScale = Scale
	self:ForEachLabel( "SetTextScale", Scale )
end

function ChatLine:SetupStencil()
	self:ForEachLabel( "SetupStencil" )
end

function ChatLine:SetMessageColour( Colour )
	self.MessageLabel:SetColour( Colour )
	if self.WrappedLabel then
		self.WrappedLabel:SetColour( Colour )
	end
end

function ChatLine:SetPrefixColour( Colour )
	self.PreLabel:SetColour( Colour )
end

function ChatLine:RemoveTags()
	local Tags = self.Tags
	if not Tags then return end

	for i = 1, #Tags do
		Tags[ i ]:Destroy()
	end

	self.Tags = nil
end

function ChatLine:SetupTag( Tag, TagData )
	Tag:SetParent( self.Parent, self.Parent.ScrollParent )
	Tag:SetText( TagData.Text )
	Tag:SetColour( TagData.Colour )
	Tag:SetFont( self.Font )
	Tag:SetTextScale( self.TextScale )
	Tag:SetupStencil()
end

do
	local Max = math.max

	function ChatLine:SetTags( TagData )
		if not TagData or #TagData == 0 then
			self:RemoveTags()
			return
		end

		local Tags = self.Tags
		if not Tags then
			Tags = {}
			self.Tags = Tags
		end

		for i = 1, Max( #Tags, #TagData ) do
			if TagData[ i ] then
				Tags[ i ] = Tags[ i ] or SGUI:Create( "Label", self.Parent )
				self:SetupTag( Tags[ i ], TagData[ i ] )
			elseif Tags[ i ] then
				Tags[ i ]:Destroy()
				Tags[ i ] = nil
			end
		end
	end
end

function ChatLine:SetMessage( PreColour, Prefix, MessageColour, MessageText )
	self.PreLabel:SetColour( PreColour )
	self.PreLabel:SetText( Prefix )
	self.MessageLabel:SetColour( MessageColour )
	self.MessageLabel:SetText( MessageText )

	self.MessageText = MessageText
	self.ComputedWrapping = false
end

function ChatLine:PerformLayout()
	local Pos = Vector2( self.Pos.x, self.Pos.y )

	local Tags = self.Tags
	if Tags then
		for i = 1, #Tags do
			Tags[ i ]:SetPos( Pos )
			Pos.x = Pos.x + Tags[ i ]:GetTextWidth()
		end
	end

	self.PreLabel:SetPos( Pos )

	local PreTextW = self.PreLabel:GetTextWidth()
	if PreTextW > 0 then
		Pos.x = Pos.x + PreTextW + self.PreMargin:GetValue()
	end

	self.MessageLabel:SetPos( Pos )
	self:ComputeWrapping( Pos.x )

	if self.WrappedLabel then
		Pos.x = self.Pos.x
		Pos.y = Pos.y + self.MessageLabel:GetTextHeight() + self.LineSpacing:GetValue()
		self.WrappedLabel:SetPos( Pos )
	end
end

function ChatLine:SetSize( Size )
	if self.MaxWidth == Size.x and self.ComputedWrapping then return end

	self.MaxWidth = Size.x
	self.ComputedWrapping = false
	self.MessageLabel:SetText( self.MessageText )

	self:InvalidateLayout()
end

function ChatLine:GetComputedSize( Index, ParentSize )
	if Index == 1 then
		return ParentSize
	end

	return self:GetSize().y
end

do
	local WordWrap = SGUI.WordWrap
	local FORCE_NEW_LINE_FRACTION = 0.9

	function ChatLine:ComputeWrapping( XPos )
		if self.ComputedWrapping then return end

		self.ComputedWrapping = true

		local MaxWidth = self.MaxWidth
		local MessageLabel = self.MessageLabel
		local Text = MessageLabel:GetText()

		if not Text:find( "[^%s]" ) then return end

		local Width = MessageLabel:GetTextWidth()
		if XPos + Width <= MaxWidth then
			self:RemoveWrappedLine()
			return
		end

		local Remaining
		if XPos / MaxWidth > FORCE_NEW_LINE_FRACTION then
			-- Not enough room to bother wrapping, start on a new line.
			MessageLabel:SetText( "" )
			Remaining = Text
		else
			Remaining = WordWrap( MessageLabel, Text, XPos, MaxWidth, 1 )
		end

		if Remaining == "" then
			self:RemoveWrappedLine()
			return
		end

		local WrappedLabel = self:GetWrappedLabel()
		WordWrap( WrappedLabel, Remaining, 0, MaxWidth )
		self.WrappedLabel = WrappedLabel
	end
end

function ChatLine:GetWrappedLabel()
	if self.WrappedLabel then
		return self.WrappedLabel
	end

	local WrappedLabel = SGUI:Create( "Label" )
	WrappedLabel:SetParent( self.Parent, self.Parent.ScrollParent )
	WrappedLabel:SetFont( self.Font )
	WrappedLabel:SetTextScale( self.TextScale )
	WrappedLabel:SetColour( self.MessageLabel:GetColour() )
	WrappedLabel:SetupStencil()

	return WrappedLabel
end

function ChatLine:GetSize()
	local Width = self.PreLabel:GetTextWidth() + self.MessageLabel:GetTextWidth()
	local Height = self.MessageLabel:GetTextHeight( "!" )

	if self.WrappedLabel then
		Height = Height + self.LineSpacing:GetValue() + self.WrappedLabel:GetTextHeight()
	end

	return Vector2( Width, Height )
end

function ChatLine:RemoveWrappedLine()
	if not self.WrappedLabel then return end

	self.WrappedLabel:Destroy()
	self.WrappedLabel = nil
end

function ChatLine:Cleanup()
	if self.Parent then return end

	self:ForEachLabel( "Destroy" )
end

SGUI:Register( "ChatLine", ChatLine )
