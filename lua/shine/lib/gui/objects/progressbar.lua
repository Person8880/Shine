--[[
	Progress bar control.
]]

local SGUI = Shine.GUI

local Clamp = math.Clamp

local ProgressBar = {}

SGUI.AddBoundProperty( ProgressBar, "BorderColour", "Background:SetColor" )
SGUI.AddBoundProperty( ProgressBar, "ProgressColour", "Bar:SetColor" )
SGUI.AddBoundProperty( ProgressBar, "Colour", "InnerBack:SetColor" )

function ProgressBar:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	local InnerBack = self:MakeGUIItem()
	local Bar = self:MakeGUIItem()

	Background:AddChild( InnerBack )
	InnerBack:AddChild( Bar )

	self.Background = Background
	self.InnerBack = InnerBack
	self.Bar = Bar

	self.Progress = 0
	self.BarSize = Vector2( 0, 0 )
	self.BorderSize = Vector2( 1, 1 )

	InnerBack:SetPosition( self.BorderSize )
end

local function RefreshInnerSizes( self, BoxSize )
	self.InnerBack:SetSize( BoxSize )

	self.BarSize.x = self.Progress * BoxSize.x
	self.BarSize.y = BoxSize.y
	self.Bar:SetSize( self.BarSize )
end

function ProgressBar:SetBorderSize( BorderSize )
	self.BorderSize = BorderSize
	self.InnerBack:SetPosition( BorderSize )

	RefreshInnerSizes( self, self:GetSize() - BorderSize * 2 )
end

function ProgressBar:SetSize( Size )
	self.Background:SetSize( Size )

	local BoxSize = Size - self.BorderSize * 2
	RefreshInnerSizes( self, BoxSize )
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

	local MaxSize = self.InnerBack:GetSize().x
	self.BarSize.x = MaxSize * Fraction

	if not Smooth then
		self.Bar:SetSize( self.BarSize )
		return
	end

	self:SizeTo( self.Bar, nil, self.BarSize, 0, 0.3 )
end

SGUI:Register( "ProgressBar", ProgressBar )
