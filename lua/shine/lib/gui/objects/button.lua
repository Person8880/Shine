--[[
	Button control.
]]

local SGUI = Shine.GUI

local Button = {}

local ClickSound = "sound/NS2.fev/common/button_enter"
Client.PrecacheLocalSound( ClickSound )

function Button:Initialise()
	self.BaseClass.Initialise( self )
	
	if self.Background then GUI.DestroyItem( self.Background ) end

	local Background = GetGUIManager():CreateGraphicItem()

	self.Background = Background

	self.Sound = ClickSound

	local Scheme = SGUI:GetSkin()

	self.ActiveCol = Scheme.ActiveButton
	self.InactiveCol = Scheme.InactiveButton

	self.TextCol = Scheme.DarkText

	self:SetHighlightOnMouseOver( true )
end

function Button:OnSchemeChange( Scheme )
	if not self.UseScheme then return end
	
	self.ActiveCol = Scheme.ActiveButton
	self.InactiveCol = Scheme.InactiveButton
	self.TextCol = Scheme.DarkText

	if self.Text then
		self.Text:SetColor( self.TextCol )
	end

	self.Background:SetColor( self.Highlighted and self.ActiveCol or self.InactiveCol )
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
	Description:SetColor( self.TextCol )

	self.Background:AddChild( Description )
	self.Text = Description
end

function Button:GetText()
	return self.Text:GetText()
end

function Button:SetFont( Font )
	self.Text:SetFontName( Font )
end

function Button:SetTextScale( Scale )
	self.Text:SetScale( Scale )
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

function Button:SetTextColour( Col )
	self.TextCol = Col

	if not self.Text then return end
	
	self.Text:SetColor( Col )
end

function Button:SetTooltip( Text )
	self.TooltipText = Text

	function self:OnHover( X, Y )
		local Tooltip = SGUI:Create( "Tooltip", self )
		Tooltip:SetAnchor( GUIItem.Left, GUIItem.Top )
		Tooltip:SetPos( Vector( X, Y, 0 ) )
		Tooltip:SetText( self.TooltipText )
		Tooltip:FadeIn()

		self.Tooltip = Tooltip
	end

	function self:OnLoseHover()
		if self.Tooltip then
			self.Tooltip:FadeOut()
		end
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
end

function Button:SetDoClick( Func )
	self.DoClick = Func
end

function Button:SetTexture( Texture )
	self.Background:SetTexture( Texture )
	self.Texture = Texture
end

function Button:SetHighlightTexture( Texture )
	self.HighlightTexture = Texture
end

function Button:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end
	if Key ~= InputKey.MouseButton0 then return end
	if not self.Highlighted then return end

	local Time = Shared.GetTime()

	if ( self.NextClick or 0 ) > Time then return end

	self.NextClick = Time + ( self.ClickDelay or 0.5 )

	if self.DoClick then
		Shared.PlaySound( nil, self.Sound )

		self.DoClick( self ) 

		return true
	end
end

function Button:Cleanup()
	if self.Parent then return end --Parent will clean up our objects for us.
	
	self:SetIsVisible( false )

	if self.Background then
		GUI.DestroyItem( self.Background )
	end
	
	self.Background = nil
end

SGUI:Register( "Button", Button )
