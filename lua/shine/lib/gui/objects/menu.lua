--[[
	Shine popup menu.

	Think right clicking the desktop in Windows, that kind of menu.
]]

local SGUI = Shine.GUI

local Menu = {}

Menu.IsWindow = true

local DefaultSize = Vector( 200, 32, 0 )
local DefaultOffset = Vector( 0, 32, 0 )
local Padding = Vector( 0, 0, 0 )

function Menu:Initialise()
	self.BaseClass.Initialise( self )

	local Background = GetGUIManager():CreateGraphicItem()

	self.Background = Background

	local Scheme = SGUI:GetSkin()

	Background:SetColor( Scheme.MenuButton )

	self.ButtonSize = DefaultSize
	self.ButtonOffset = DefaultOffset
	self.Buttons = {}
	self.ButtonCount = 0

	self.Font = "fonts/AgencyFB_small.fnt"
end

function Menu:OnSchemeChange( Scheme )
	if not self.UseScheme then return end
	
	self.Background:SetColor( Scheme.MenuButton )
	for i = 1, #Buttons do
		Buttons[ i ]:SetInactiveCol( Scheme.MenuButton )
	end
end

function Menu:SetIsVisible( Bool )
	if not self.Background then return end
	if self.Background:GetIsVisible() == Bool then return end
	
	self.Background:SetIsVisible( Bool )
	
	local Buttons = self.Buttons

	for i = 1, #Buttons do
		Buttons[ i ]:SetIsVisible( Bool )
	end
end

function Menu:SetButtonSize( Vec )
	self.ButtonSize = Vec
	self.ButtonOffset = Vector( 0, Vec.y, 0 )
end

function Menu:AddButton( Text, DoClick )
	local Button = SGUI:Create( "Button", self )
	Button:SetAnchor( GUIItem.Left, GUIItem.Top )
	Button:SetPos( Padding + self.ButtonCount * self.ButtonOffset )
	Button:SetDoClick( DoClick )
	Button:SetSize( self.ButtonSize )
	Button:SetText( Text )
	if self.Font then
		Button:SetFont( self.Font )
	end
	Button.UseScheme = false

	local Scheme = SGUI:GetSkin()
	Button:SetInactiveCol( Scheme.MenuButton )

	self.ButtonCount = self.ButtonCount + 1

	self.Background:SetSize( Padding * 2 + self.ButtonSize + ( self.ButtonCount - 1 ) * self.ButtonOffset )

	self.Buttons[ self.ButtonCount ] = Button
end

function Menu:Cleanup()
	if self.Parent then return end

	if self.Background then
		GUI.DestroyItem( self.Background )
	end
end

------------------- Event calling -------------------
function Menu:OnMouseDown( Key, DoubleClick )
	local Result = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )

	if Result ~= nil then return true end

	--Delay so we don't mess up the event calling.
	Shine.Timer.Simple( 0.1, function()
		if not self:IsValid() then return end
		
		self:SetParent()
		self:Destroy()
	end )
end

function Menu:OnMouseUp( Key )
	self:CallOnChildren( "OnMouseUp", Key )
end

function Menu:OnMouseMove( Down )
	self:CallOnChildren( "OnMouseMove", Down )

	if self:MouseIn( self.Background ) then
		return true
	end
end

function Menu:Think( DeltaTime )
	self.BaseClass.Think( self, DeltaTime )

	self:CallOnChildren( "Think", DeltaTime )
end

function Menu:OnMouseWheel( Down )
	local Result = self:CallOnChildren( "OnMouseWheel", Down )

	if Result ~= nil then return true end
end

function Menu:PlayerKeyPress( Key, Down )
	if self:CallOnChildren( "PlayerKeyPress", Key, Down ) then
		return true
	end
end

function Menu:PlayerType( Char )
	if self:CallOnChildren( "PlayerType", Char ) then
		return true
	end
end

SGUI:Register( "Menu", Menu )
