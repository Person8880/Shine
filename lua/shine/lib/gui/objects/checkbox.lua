--[[
	Shine checkbox control.

	(More of a rectangle than a check.)
]]

local SGUI = Shine.GUI

local CheckBox = {}

function CheckBox:Initialise()
	self.BaseClass.Initialise( self )

	if self.Background then GUI.DestroyItem( self.Background ) end
	
	local Manager = GetGUIManager()

	local Background = Manager:CreateGraphicItem()

	self.Background = Background

	local Box = Manager:CreateGraphicItem()
	Box:SetAnchor( GUIItem.Middle, GUIItem.Center )

	Background:AddChild( Box )

	self.Box = Box

	local Scheme = SGUI:GetSkin()

	self.BackgroundCol = Scheme.InactiveButton
	self.BoxCol = Scheme.ActiveButton
	self.BoxHideCol = SGUI.CopyColour( Scheme.ActiveButton )
	self.BoxHideCol.a = 0

	Box:SetColor( self.BoxHideCol )
	Background:SetColor( self.BackgroundCol )

	self.Checked = false
end

function CheckBox:OnSchemeChange( Scheme )
	if not self.UseScheme then return end
	
	self.BackgroundCol = Scheme.InactiveButton
	self.BoxCol = Scheme.ActiveButton
	self.BoxHideCol = SGUI.CopyColour( Scheme.ActiveButton )
	self.BoxHideCol.a = 0

	self.Box:SetColor( self.Checked and self.BoxCol or self.BoxHideCol )
	self.Background:SetColor( self.BackgroundCol )
end

function CheckBox:SetCheckedColour( Col )
	self.BoxCol = Col
	self.BoxHideCol = SGUI.CopyColour( Col )
	self.BoxHideCol.a = 0

	self.Box:SetColor( self.Checked and self.BoxCol or self.BoxHideCol )
end

function CheckBox:SetBackgroundColour( Col )
	self.BackgroundCol = Col

	self.Background:SetColor( Col )
end

function CheckBox:SetupStencil()
	self.BaseClass.SetupStencil( self )
	
	self.Box:SetInheritsParentStencilSettings( true )

	if self.Label then
		self.Label.Text:SetInheritsParentStencilSettings( true )
	end
end

function CheckBox:SetSize( Vec )
	self.Background:SetSize( Vec )

	local BoxSize = Vec * 0.75

	self.Box:SetSize( BoxSize )
	self.Box:SetPosition( -BoxSize * 0.5 )
end

function CheckBox:GetChecked()
	return self.Checked
end

function CheckBox:SetChecked( Value, DontFade )
	if Value then
		self.Checked = true

		if DontFade then
			self.Box:SetColor( self.BoxCol )
		else
			self:FadeTo( self.Box, self.BoxHideCol, self.BoxCol, 0, 0.1, function( Box )
				Box:SetColor( self.BoxCol )
			end )
		end

		if self.OnChecked then
			self:OnChecked( true )
		end

		return
	end
	
	self.Checked = false

	if DontFade then
		self.Box:SetColor( self.BoxHideCol )	
	else
		self:FadeTo( self.Box, self.BoxCol, self.BoxHideCol, 0, 0.1, function( Box )
			Box:SetColor( self.BoxHideCol )
		end )
	end
	
	if self.OnChecked then
		self:OnChecked( false )
	end
end

function CheckBox:OnMouseDown( Key, DoubleClick )
	if not self.Background then return end
	if not self.Background:GetIsVisible() then return end
	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Background ) then return end

	if not self.Checked then
		self:SetChecked( true )
	else
		self:SetChecked( false )
	end

	return true
end

function CheckBox:AddLabel( Text )
	if self.Label then
		self.Label:SetText( Text )
		local Size = self:GetSize().x

		self.Label:SetPos( Vector( Size + 10, 0, 0 ) )

		return
	end

	local Label = SGUI:Create( "Label", self )
	Label:SetAnchor( GUIItem.Left, GUIItem.Center )
	Label:SetTextAlignmentY( GUIItem.Align_Center )
	Label:SetText( Text )
	Label:SetPos( Vector( self:GetSize().x + 10, 0, 0 ) )

	if self.Font then
		Label:SetFont( self.Font )
	end

	if self.TextColour then
		Label:SetColour( self.TextColour )
	end

	if self.Stencilled then
		Label.Text:SetInheritsParentStencilSettings( true )
	end

	self.Label = Label
end

function CheckBox:SetFont( Name )
	self.Font = Name

	if not self.Label then return end
	
	self.Label:SetFont( Name )
end

function CheckBox:SetTextColour( Col )
	self.TextColour = Col

	if not self.Label then return end
	
	self.Label:SetColour( Col )
end

function CheckBox:SetTextScale( Scale )
	self.TextScale = Scale

	if not self.Label then return end
	
	self.Label:SetTextScale( Scale )
end

function CheckBox:Cleanup()
	if self.Parent then return end
	
	if self.Background then
		GUI.DestroyItem( self.Background )
	end
end

SGUI:Register( "CheckBox", CheckBox )
