--[[
	Button control.
]]

local SGUI = Shine.GUI

local Clock = os.clock

local Button = {}

local ClickSound = "sound/NS2.fev/common/button_enter"
Client.PrecacheLocalSound( ClickSound )
Button.Sound = ClickSound

function Button:Initialise()
	self.BaseClass.Initialise( self )
	self.Background = GetGUIManager():CreateGraphicItem()
	self:SetHighlightOnMouseOver( true )
end

function Button:SetupStencil()
	self.BaseClass.SetupStencil( self )

	if not self.Text then return end

	self.Text:SetInheritsParentStencilSettings( true )
end

function Button:SetCustomSound( Sound )
	self.Sound = Sound
end

function Button:SetText( Text )
	if self.Text then
		self.Text:SetText( Text )

		return
	end

	local Description = GetGUIManager():CreateTextItem()
	Description:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Description:SetTextAlignmentX( GUIItem.Align_Center )
	Description:SetTextAlignmentY( GUIItem.Align_Center )
	Description:SetText( Text )
	Description:SetColor( self.TextColour )
	Description:SetInheritsParentAlpha( true )

	if self.Font then
		Description:SetFontName( self.Font )
	end

	if self.TextScale then
		Description:SetScale( self.TextScale )
	end

	if self.Stencilled then
		Description:SetInheritsParentStencilSettings( true )
	end

	self.Background:AddChild( Description )
	self.Text = Description
end

function Button:GetText()
	if not self.Text then return "" end
	return self.Text:GetText()
end

SGUI.AddBoundProperty( Button, "Font", "Text:SetFontName" )
SGUI.AddBoundProperty( Button, "TextColour", "Text:SetColor" )
SGUI.AddBoundProperty( Button, "TextScale", "Text:SetScale" )

function Button:GetTextWidth()
	if not self.Text then return 0 end

	local Scale = self.TextScale
	Scale = Scale and Scale.x or 1

	return self.Text:GetTextWidth( self.Text:GetText() ) * Scale
end

function Button:SetActiveCol( Col )
	self.ActiveCol = Col

	if self.Highlighted then
		self.Background:SetColor( Col )
	end
end

function Button:SetInactiveCol( Col )
	self.InactiveCol = Col

	if not self.Highlighted then
		self.Background:SetColor( Col )
	end
end

function Button:SetIsVisible( Bool )
	if not self.Background then return end

	Bool = Bool and true or false

	local WasVisible = self.Background:GetIsVisible()
	if WasVisible == Bool then return end

	self.Background:SetIsVisible( Bool )
end

function Button:Think( DeltaTime )
	if not self.Background then return end
	if not self.Background:GetIsVisible() then return end

	self.BaseClass.Think( self, DeltaTime )

	if SGUI.IsValid( self.Tooltip ) then
		self.Tooltip:Think( DeltaTime )
	end

	self:CallOnChildren( "Think", DeltaTime )
end

function Button:SetDoClick( Func )
	self.DoClick = Func
end

function Button:SetHighlightTexture( Texture )
	self.HighlightTexture = Texture
end

function Button:AddMenu( Size )
	if SGUI.IsValid( self.Menu ) then
		return self.Menu
	end

	local Pos = self:GetScreenPos()
	Pos.x = Pos.x + self:GetSize().x

	local Menu = SGUI:Create( "Menu" )
	Menu:SetPos( Pos )
	Menu:SetButtonSize( Size or self:GetSize() )

	self.ForceHighlight = true
	Menu:CallOnRemove( function()
		self.ForceHighlight = nil
	end )

	self.Menu = Menu

	return Menu
end

function Button:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )
	if Result then
		return true, Child
	end

	if not self:IsEnabled() then return end

	return self.Mixins.Clickable.OnMouseDown( self, Key, DoubleClick )
end

function Button:OnMouseMove( Down )
	self.BaseClass.OnMouseMove( self, Down )

	self:CallOnChildren( "OnMouseMove", Down )
end

function Button:OnMouseWheel( Down )
	local Result = self:CallOnChildren( "OnMouseWheel", Down )

	if Result ~= nil then return true end
end

function Button:PlayerKeyPress( Key, Down )
	if self:CallOnChildren( "PlayerKeyPress", Key, Down ) then
		return true
	end
end

function Button:PlayerType( Char )
	if self:CallOnChildren( "PlayerType", Char ) then
		return true
	end
end

SGUI:AddMixin( Button, "Clickable" )
SGUI:AddMixin( Button, "EnableMixin" )
SGUI:Register( "Button", Button )
