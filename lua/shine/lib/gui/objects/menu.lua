--[[
	Shine popup menu.

	Think right clicking the desktop in Windows, that kind of menu.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local Menu = {}

Menu.IsWindow = true

local DefaultSize = Vector( 200, 32, 0 )
local DefaultOffset = Vector( 0, 32, 0 )

SGUI.AddProperty( Menu, "ButtonSpacing" )
SGUI.AddProperty( Menu, "MaxVisibleButtons" )

function Menu:Initialise()
	Controls.Panel.Initialise( self )

	self.ButtonSize = DefaultSize
	self.ButtonOffset = DefaultOffset
	self.Buttons = {}
	self.ButtonCount = 0
	self.ButtonSpacing = Vector( 0, 0, 0 )

	self.Font = Fonts.kAgencyFB_Small
end

function Menu:SetMaxVisibleButtons( Max )
	self.MaxVisibleButtons = Max
	self:SetScrollable()
	self:SetScrollbarPos( Vector( -8, 0, 0 ) )
	self:SetScrollbarWidth( 8 )
	self:SetScrollbarHeightOffset( 0 )
	self.BufferAmount = 0
end

function Menu:SetButtonSize( Vec )
	self.ButtonSize = Vec
	self.ButtonOffset = Vector( 0, Vec.y, 0 )
end

function Menu:AddButton( Text, DoClick, Tooltip )
	local Button = self.MaxVisibleButtons and self:Add( "Button" ) or SGUI:Create( "Button", self )
	Button:SetAnchor( GUIItem.Left, GUIItem.Top )
	Button:SetPos( self.ButtonSpacing + self.ButtonCount * self.ButtonOffset )
	Button:SetDoClick( DoClick )
	Button:SetSize( self.ButtonSize )
	Button:SetText( Text )
	if self.Font then
		Button:SetFont( self.Font )
	end
	Button:SetStyleName( "MenuButton" )
	if Tooltip then
		Button:SetTooltip( Tooltip )
	end

	self.ButtonCount = self.ButtonCount + 1
	self.Buttons[ self.ButtonCount ] = Button

	if not ( self.MaxVisibleButtons and self.ButtonCount > self.MaxVisibleButtons ) then
		self:SetSize( self.ButtonSpacing * 2 + self.ButtonSize
			+ ( self.ButtonCount - 1 ) * self.ButtonOffset )
	end

	return Button
end

------------------- Event calling -------------------
function Menu:OnMouseDown( Key, DoubleClick )
	if SGUI.IsValid( self.Scrollbar ) then
		if self.Scrollbar:OnMouseDown( Key, DoubleClick ) then
			return true, self.Scrollbar
		end
	end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )

	if Result ~= nil then return true, Child end

	--Delay so we don't mess up the event calling.
	SGUI:AddPostEventAction( function()
		if not self:IsValid() then return end

		self:Destroy( true )
	end )
end

SGUI:Register( "Menu", Menu, "Panel" )
