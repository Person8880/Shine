--[[
	Progress bar control.
]]

local SGUI = Shine.GUI

local Clamp = math.Clamp
local Vector = Vector

local ProgressBar = {}

local Padding = Vector( 1, 1, 0 )

function ProgressBar:Initialise()
	self.BaseClass.Initialise( self )

	local Manager = GetGUIManager()

	local Background = Manager:CreateGraphicItem()
	local InnerBack = Manager:CreateGraphicItem()
	InnerBack:SetAnchor( GUIItem.Left, GUIItem.Top )

	local Bar = Manager:CreateGraphicItem()
	Bar:SetAnchor( GUIItem.Left, GUIItem.Top )

	Background:AddChild( InnerBack )
	InnerBack:AddChild( Bar )

	InnerBack:SetPosition( Padding )

	local Skin = SGUI:GetSkin()

	Background:SetColor( Skin.ButtonBorder )
	InnerBack:SetColor( Skin.ProgressBarEmpty )
	Bar:SetColor( Skin.ProgressBar )

	self.Background = Background
	self.InnerBack = InnerBack
	self.Bar = Bar

	self.Progress = 0
	self.BarSize = Vector( 0, 0, 0 )
end

function ProgressBar:SetSize( Size )
	self.Background:SetSize( Size )

	local BoxSize = Size - Padding * 2

	self.MaxSize = BoxSize.x

	self.InnerBack:SetSize( BoxSize )

	self.BarSize.x = self.Progress * BoxSize.x
	self.BarSize.y = BoxSize.y

	self.Bar:SetSize( self.BarSize )
end

function ProgressBar:OnSchemeChange( Skin )
	self.Background:SetColor( Skin.ButtonBorder )
	self.InnerBack:SetColor( Skin.ProgressBarEmpty )
	self.Bar:SetColor( Skin.ProgressBar )
end

function ProgressBar:SetupStencil()
	self.BaseClass.SetupStencil( self )

	self.InnerBack:SetInheritsParentStencilSettings( true )
	self.Bar:SetInheritsParentStencilSettings( true )
end

--[[
	Sets the progress value on the bar.
]]
function ProgressBar:SetFraction( Fraction, Smooth )
	Fraction = Clamp( Fraction, 0, 1 )

	if not Smooth then
		self.BarSize.x = self.MaxSize * Fraction

		self.Bar:SetSize( self.BarSize )

		return
	end

	self.BarSize.x = self.MaxSize * Fraction

	self:SizeTo( self.Bar, nil, self.BarSize, 0, 0.3, function( Bar )
		Bar:SetSize( self.BarSize )
	end )
end

SGUI:Register( "ProgressBar", ProgressBar )
