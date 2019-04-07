--[[
	Button control.
]]

local SGUI = Shine.GUI

local rawget = rawget

local Button = {}

local ClickSound = "sound/NS2.fev/common/button_enter"
Client.PrecacheLocalSound( ClickSound )
Button.Sound = ClickSound

function Button:Initialise()
	self.BaseClass.Initialise( self )
	self.Background = self:MakeGUIItem()
	self:SetHighlightOnMouseOver( true )
	self:SetTextInheritsParentAlpha( true )
end

function Button:SetCustomSound( Sound )
	self.Sound = Sound
end

function Button:SetText( Text )
	self:InvalidateParent()

	if self.Label then
		self.Label:SetText( Text )

		return
	end

	local Description = self:MakeGUITextItem()
	Description:SetAnchor( GUIItem.Middle, GUIItem.Center )
	Description:SetTextAlignmentX( GUIItem.Align_Center )
	Description:SetTextAlignmentY( GUIItem.Align_Center )
	Description:SetText( Text )
	Description:SetColor( self.TextColour )
	Description:SetInheritsParentAlpha( self.TextInheritsParentAlpha )

	if self.Font then
		Description:SetFontName( self.Font )
	end

	if self.TextScale then
		Description:SetScale( self.TextScale )
	end

	self.Background:AddChild( Description )
	self.Label = Description
end

function Button:GetText()
	if not self.Label then return "" end
	return self.Label:GetText()
end

SGUI.AddBoundProperty( Button, "Font", "Label:SetFontName" )
SGUI.AddBoundProperty( Button, "TextColour", "Label:SetColor" )
SGUI.AddBoundProperty( Button, "TextScale", "Label:SetScale" )
SGUI.AddBoundProperty( Button, "TextInheritsParentAlpha", "Label:SetInheritsParentAlpha" )

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

Button.MenuPos = {
	RIGHT = "RIGHT",
	BOTTOM = "BOTTOM"
}

function Button:AddMenu( Size, MenuPos )
	if SGUI.IsValid( self.Menu ) then
		return self.Menu
	end

	MenuPos = MenuPos or self.MenuPos.RIGHT

	local Pos = self:GetScreenPos()
	if MenuPos == self.MenuPos.RIGHT then
		Pos.x = Pos.x + self:GetSize().x
	else
		Pos.y = Pos.y + self:GetSize().y
	end

	local Menu = SGUI:Create( "Menu" )
	Menu:SetPos( Pos )
	Menu:SetButtonSize( Size or self:GetSize() )

	self:SetForceHighlight( true )
	Menu:CallOnRemove( function()
		self:SetForceHighlight( false )
	end )

	self.Menu = Menu

	return Menu
end

-- Provides a helper that automatically handles menu opening on click, as well as closing the menu
-- when clicked while the menu is open without re-opening it.
function Button:SetOpenMenuOnClick( PopulateMenuFunc )
	self:SetDoClick( function( self )
		if self.Menu and rawget( self.Menu, "DestroyedBy" ) == self then
			-- Clicked the button to close the menu.
			self.Menu = nil
			return
		end

		local MenuParams = PopulateMenuFunc( self )
		local Menu = self:AddMenu( MenuParams.Size, MenuParams.MenuPos )
		MenuParams.Populate( Menu )
	end )
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

SGUI:AddMixin( Button, "AutoSizeText" )
SGUI:AddMixin( Button, "Clickable" )
SGUI:AddMixin( Button, "EnableMixin" )
SGUI:Register( "Button", Button )
