--[[
	A notification popup.
]]

local SGUI = Shine.GUI

local Min = math.min

local Notification = {}
Notification.IsWindow = true
Notification.FadedAlpha = 0.1

SGUI.AddBoundProperty( Notification, "Colour", "Background:SetColor" )
SGUI.AddBoundProperty( Notification, "FlairColour", "Flair:SetColor" )
SGUI.AddBoundProperty( Notification, "FlairIconText", "FlairIcon:SetText" )
SGUI.AddBoundProperty( Notification, "FlairIconColour", "FlairIcon:SetColor" )
SGUI.AddBoundProperty( Notification, "TextColour", "Text:SetColour" )

function Notification:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	self.Background = Background

	local Flair = self:MakeGUIItem()
	Flair:SetInheritsParentAlpha( true )
	Background:AddChild( Flair )
	self.Flair = Flair

	local FlairIcon = self:MakeGUITextItem()
	FlairIcon:SetInheritsParentAlpha( true )
	FlairIcon:SetTextAlignmentX( GUIItem.Align_Center )
	FlairIcon:SetTextAlignmentY( GUIItem.Align_Center )
	FlairIcon:SetAnchor( GUIItem.Middle, GUIItem.Center )
	FlairIcon:SetFontName( SGUI.Fonts.Ionicons )
	Flair:AddChild( FlairIcon )

	self.FlairIcon = FlairIcon

	self.FlairWidth = 48
	self.Padding = 16
	self.MaxWidth = math.huge
	self.TemporaryFadeState = false
end

function Notification:SetIconScale( Scale )
	self.FlairIcon:SetScale( Scale )
end

function Notification:SetLayer( Layer )
	-- Should always be on top.
	self.BaseClass.SetLayer( self, Layer + 100 )
end

function Notification:SetSize( Size )
	self.BaseClass.SetSize( self, Size )
	self.Flair:SetSize( Vector2( self.FlairWidth, Size.y ) )
end

function Notification:SetFlairWidth( Width )
	self.FlairWidth = Width
	self.Flair:SetSize( Vector2( Width, self.Flair:GetSize().y ) )
end

function Notification:SetText( Text, Font, Scale )
	local Label = self.Text
	if not SGUI.IsValid( Label ) then
		Label = SGUI:Create( "Label", self )
		self.Text = Label
	end

	Label:SetFont( Font or Fonts.kAgencyFB_Small )
	Label:SetText( Text )
	if Scale then
		Label:SetTextScale( Scale )
	end
	if self.TextColour then
		Label:SetColour( self.TextColour )
	end
	Label:SetInheritsParentAlpha( true )
	Label:SetPos( self:GetTextPos() )
end

function Notification:GetTextPos()
	return Vector2( self.FlairWidth + self.Padding, self.Padding )
end

function Notification:SetPadding( Padding )
	self.Padding = Padding

	if SGUI.IsValid( self.Text ) then
		self.Text:SetPos( self:GetTextPos() )
	end
end

function Notification:SizeToContents()
	local TextW = self.Text:GetTextWidth()
	local DesiredWidth = TextW + self.Padding * 2 + self.FlairWidth
	local Width = Min( self.MaxWidth, DesiredWidth )

	if Width ~= DesiredWidth then
		SGUI.WordWrap( self.Text, self.Text:GetText(), 0, Width - self.Padding * 2 - self.FlairWidth )
	end

	local H = self.Text:GetTextHeight() + self.Padding * 2

	self:SetSize( Vector2( Width, H ) )
end

function Notification:SetMaxWidth( Width )
	self.MaxWidth = Width
end

function Notification:Think( DeltaTime )
	self.BaseClass.Think( self, DeltaTime )

	if self.FadingIn or self.FadingOut then
		return
	end

	-- If we're hovering the mouse over a notification and there's a window beneath it,
	-- fade the notification out so the content below is visible.
	local ShouldBeFadedOut = false
	if self:MouseIn( self.Background ) then
		for i = 1, #SGUI.Windows do
			local Window = SGUI.Windows[ i ]
			if Window.Class ~= "Notification" and Window:MouseIn( Window.Background ) then
				ShouldBeFadedOut = true
				break
			end
		end
	end

	if self.TemporaryFadeState ~= ShouldBeFadedOut then
		self.TemporaryFadeState = ShouldBeFadedOut

		if ShouldBeFadedOut then
			self.OriginalAlpha = self.OriginalAlpha or self:GetColour().a
			self:AlphaTo( self.Background, self.OriginalAlpha, self.FadedAlpha, 0, 0.1 )
		else
			self:AlphaTo( self.Background, self.Background:GetColor().a, self.OriginalAlpha, 0, 0.1 )
		end
	end
end

function Notification:FadeIn()
	self.FadingIn = true
	self:AlphaTo( self.Background, 0, self:GetColour().a, 0, 0.3, function()
		self.FadingIn = false
	end )
end

function Notification:FadeOutAfter( Duration, Callback )
	Shine.Timer.Simple( Duration, function()
		if not SGUI.IsValid( self ) then return end

		self.FadingOut = true
		self:AlphaTo( self.Background, self.Background:GetColor().a, 0, 0, 0.3, function()
			Callback( self )
			self:Destroy()
		end )
	end )
end

SGUI:Register( "Notification", Notification )
