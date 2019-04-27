--[[
	A simple progress wheel.
]]

local Clamp = math.Clamp
local Max = math.max
local Min = math.min
local Pi = math.pi

local SGUI = Shine.GUI

local ProgressWheel = {}

SGUI.AddBoundProperty( ProgressWheel, "Colour", { "LeftHalf:SetColor", "RightHalf:SetColor" } )

function ProgressWheel:Initialise()
	self.BaseClass.Initialise( self )

	self.Background = self:MakeGUIItem()
	self.Background:SetColor( Colour( 1, 1, 1, 0 ) )
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

	self.Angle = Vector( 0, 0, 0 )
	self.Fraction = 0

	self.LeftRotation = 0
	self.RightRotation = 0

	self.LeftAngle = Vector( 0, 0, 0 )
	self.RightAngle = Vector( 0, 0, 0 )

	self:SetVisibleFraction( 0 )
end

function ProgressWheel:SetWheelTexture( Params )
	local X = Params.X or 0
	local Y = Params.Y or 0
	local W = Params.W
	local H = Params.H
	local Texture = Params.Texture

	self.LeftHalf:SetTexture( Texture )
	self.LeftHalf:SetTexturePixelCoordinates( X, Y, X + W * 0.5, Y + H )

	self.RightHalf:SetTexture( Texture )
	self.RightHalf:SetTexturePixelCoordinates( X + W * 0.5, Y, X + W, Y + H )
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

local Easer = {
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

function ProgressWheel:SetFraction( Fraction, Smooth )
	Fraction = Clamp( Fraction, 0, 1 )

	self.Fraction = Fraction

	if not Smooth then
		self.VisibleFraction = Fraction
		self:SetVisibleFraction( Fraction )
		return
	end

	self:EaseValue( self.Background, self.VisibleFraction, Fraction, 0, 0.3 )
end

local function UpdateMaskRotations( self )
	self.LeftAngle.z = self.LeftRotation + self.Angle.z
	self.RightAngle.z = self.RightRotation + self.Angle.z

	self.LeftMask:SetRotation( self.LeftAngle )
	self.RightMask:SetRotation( self.RightAngle )
end

function ProgressWheel:SetVisibleFraction( Fraction )
	self.VisibleFraction = Fraction

	local LeftFraction = Max( ( Fraction - 0.5 ) * 2, 0 )
	local RightFraction = Max( Min( Fraction * 2, 1 ), 0 )

	self.LeftRotation = Pi * ( 1 - LeftFraction )
	self.RightRotation = Pi * ( 1 - RightFraction )

	UpdateMaskRotations( self )
end

function ProgressWheel:GetAngle()
	return self.Angle.z
end

function ProgressWheel:SetAngle( Angle )
	self.Angle.z = Angle

	UpdateMaskRotations( self )

	self.LeftHalf:SetRotation( self.Angle )
	self.RightHalf:SetRotation( self.Angle )
	self.Background:SetRotation( self.Angle )
end

SGUI:Register( "ProgressWheel", ProgressWheel )
