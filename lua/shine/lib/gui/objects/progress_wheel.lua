--[[
	A simple progress wheel.
]]

local Clamp = math.Clamp
local Max = math.max
local Min = math.min
local Pi = math.pi
local StringEndsWith = string.EndsWith

local SGUI = Shine.GUI

local ProgressWheel = {}

SGUI.AddBoundProperty( ProgressWheel, "Colour", { "LeftHalf:SetColor", "RightHalf:SetColor" } )
SGUI.AddBoundProperty( ProgressWheel, "InheritsParentAlpha", { "Background", "LeftHalf", "RightHalf" } )

SGUI.AddProperty( ProgressWheel, "Angle", 0 )
SGUI.AddProperty( ProgressWheel, "AngleOffset", 0 )
SGUI.AddProperty( ProgressWheel, "SpinRate", 0 )

function ProgressWheel:Initialise()
	self.BaseClass.Initialise( self )

	self.Background = self:MakeGUIItem()
	self.Background:SetShader( "shaders/shine/gui_none.surface_shader" )
	self.Background:SetColor( Colour( 1, 1, 1, 1 ) )
	self.Background:SetClearsStencilBuffer( true )

	self.LeftMask = self:MakeGUIItem()
	self.LeftMask:SetIsStencil( true )
	self.LeftMask:SetAnchor( GUIItem.Middle, GUIItem.Center )

	self.LeftHalf = self:MakeGUIItem()
	self.LeftHalf:SetStencilFunc( GUIItem.Equal )

	self.RightMask = self:MakeGUIItem()
	self.RightMask:SetIsStencil( true )
	self.RightMask:SetAnchor( GUIItem.Middle, GUIItem.Center )

	self.RightHalf = self:MakeGUIItem()
	self.RightHalf:SetStencilFunc( GUIItem.Equal )

	self.Background:AddChild( self.LeftMask )
	self.Background:AddChild( self.LeftHalf )
	self.Background:AddChild( self.RightMask )
	self.Background:AddChild( self.RightHalf )

	self.Angle = 0
	self.AngleOffset = 0
	self.Fraction = 0
	self.VisibleFraction = 0

	self.LeftRotation = 0
	self.RightRotation = 0

	self.LeftAngle = 0
	self.RightAngle = 0

	self.SpinRate = 0
	self.SpinDirection = 1

	self:SetVisibleFraction( 0 )
end

function ProgressWheel:SetWheelTexture( Params )
	local X = Params.X or 0
	local Y = Params.Y or 0
	local W = Params.W
	local H = Params.H
	local Texture = Params.Texture

	local UsePixelCoords = StringEndsWith( Texture, ".dds" )

	self.LeftHalf:SetTexture( Texture )
	self.RightHalf:SetTexture( Texture )

	if UsePixelCoords then
		self.LeftHalf:SetTexturePixelCoordinates( X, Y, X + W * 0.5, Y + H )
		self.RightHalf:SetTexturePixelCoordinates( X + W * 0.5, Y, X + W, Y + H )
	else
		local FullWidth = Params.FullWidth or W
		local FullHeight = Params.FullHeight or H
		-- Pixel co-ordinates seem to only work for DDS images...
		self.LeftHalf:SetTextureCoordinates( X / FullWidth, Y / FullHeight, ( X + W * 0.5 ) / FullWidth,
			( Y + H ) / FullHeight )
		self.RightHalf:SetTextureCoordinates( ( X + W * 0.5 ) / FullWidth, Y / FullHeight, ( X + W ) / FullWidth,
			( Y + H ) / FullHeight )
	end
end

function ProgressWheel:SetSize( Size )
	local OldSize = self:GetSize()

	self.BaseClass.SetSize( self, Size )

	if OldSize == Size then return end

	local HalfSize = Vector2( Size.x * 0.5, Size.y )
	self.LeftHalf:SetSize( HalfSize )
	self.LeftHalf:SetRotationOffset( Vector2( Size.x * 0.5, 0 ) )

	self.RightHalf:SetSize( HalfSize )
	self.RightHalf:SetPosition( Vector2( Size.x * 0.5, 0 ) )
	self.RightHalf:SetRotationOffset( Vector2( -Size.x * 0.5, 0 ) )

	local MaskSize = Vector2( Size.x, Size.y * 2 )
	self.LeftMask:SetSize( MaskSize )
	self.RightMask:SetSize( MaskSize )

	self.LeftMask:SetPosition( Vector2( 0, -Size.y ) )
	self.LeftMask:SetRotationOffset( Vector2( -Size.x, 0 ) )

	self.RightMask:SetPosition( Vector2( -Size.x, -Size.y ) )
	self.RightMask:SetRotationOffset( Vector2( Size.x, 0 ) )
end

local FractionEaser = {
	Easer = function( self, Element, EasingData, Progress )
		EasingData.CurValue = EasingData.Start + EasingData.Diff * Progress
	end,
	Setter = function( self, Element, Fraction )
		self:SetVisibleFraction( Fraction )
	end,
	Getter = function( self, Element )
		return self.VisibleFraction
	end
}

function ProgressWheel:SetFraction( Fraction, Smooth, Callback )
	Fraction = Clamp( Fraction, 0, 1 )

	self.Fraction = Fraction

	if not Smooth then
		self.VisibleFraction = Fraction
		self:SetVisibleFraction( Fraction )
		return
	end

	self:EaseValue( self.Background, self.VisibleFraction, Fraction, 0, 0.3, Callback, FractionEaser )
end

local function UpdateMaskRotations( self )
	self.LeftAngle = self.LeftRotation + self.Angle + self.AngleOffset
	self.RightAngle = self.RightRotation + self.Angle + self.AngleOffset

	self.LeftMask:SetAngle( self.LeftAngle )
	self.RightMask:SetAngle( self.RightAngle )
end

local TwoPi = Pi * 2

function ProgressWheel:SetVisibleFraction( Fraction )
	local Delta = Fraction - self.VisibleFraction

	self.VisibleFraction = Fraction

	local LeftFraction = Max( ( Fraction - 0.5 ) * 2, 0 )
	local RightFraction = Max( Min( Fraction * 2, 1 ), 0 )

	self.LeftRotation = Pi * ( 1 - LeftFraction )
	self.RightRotation = Pi * ( 1 - RightFraction )

	if self.ApplyAngleOffsetWithFraction then
		self:SetAngleOffset( self.AngleOffset + TwoPi * Delta * -self.SpinDirection )
	else
		UpdateMaskRotations( self )
	end
end

local function UpdateAngles( self )
	UpdateMaskRotations( self )

	self.LeftHalf:SetAngle( self.Angle + self.AngleOffset )
	self.RightHalf:SetAngle( self.Angle + self.AngleOffset )
	self.Background:SetAngle( self.Angle + self.AngleOffset )
end

function ProgressWheel:SetAngle( Angle )
	self.Angle = Angle % TwoPi

	UpdateAngles( self )
end

local AngleOffsetEaser = {
	Easer = function( self, Element, EasingData, Progress )
		EasingData.CurValue = EasingData.Start + EasingData.Diff * Progress
	end,
	Setter = function( self, Element, AngleOffset )
		self:SetAngleOffset( AngleOffset )
	end,
	Getter = function( self, Element )
		return self.AngleOffset
	end
}

function ProgressWheel:SetAngleOffset( AngleOffset )
	self.AngleOffset = AngleOffset % TwoPi

	UpdateAngles( self )
end

function ProgressWheel:SetSpinRate( SpinRate )
	self.SpinRate = SpinRate
	self.SpinDirection = SpinRate < 0 and -1 or 1
end

function ProgressWheel:SetAnimateLoading( AnimateLoading )
	if not AnimateLoading then
		self:StopEasing( self.Background, FractionEaser )
		self:StopEasing( self.Background, AngleOffsetEaser )
		return
	end

	local Collapse
	local Expand
	local ExpandedSize = 0.75
	local CollapsedSize = 0.1
	local SpinDuration = 0.5

	Collapse = function()
		self:EaseValue(
			self.Background, self.VisibleFraction, CollapsedSize, 0.25, SpinDuration, Expand, FractionEaser
		)
		self.ApplyAngleOffsetWithFraction = true
	end

	Expand = function()
		self.ApplyAngleOffsetWithFraction = false
		self:EaseValue(
			self.Background, self.VisibleFraction, ExpandedSize, 0.25, SpinDuration, Collapse, FractionEaser
		)
	end

	self:SetFraction( CollapsedSize )
	self:EaseValue( self.Background, self.VisibleFraction, ExpandedSize, 0, SpinDuration, Collapse, FractionEaser )
end

function ProgressWheel:Think( DeltaTime )
	if not self:GetIsVisible() then return end

	self.BaseClass.Think( self, DeltaTime )
	self:CallOnChildren( "Think", DeltaTime )

	local SpinRate = self:GetSpinRate()
	if SpinRate and SpinRate ~= 0 then
		self:SetAngle( self:GetAngle() + DeltaTime * SpinRate )
	end
end

SGUI:Register( "ProgressWheel", ProgressWheel )
