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

function ProgressWheel:SetFraction( Fraction, Smooth, Callback )
	Fraction = Clamp( Fraction, 0, 1 )

	self.Fraction = Fraction

	if not Smooth then
		self.VisibleFraction = Fraction
		self:SetVisibleFraction( Fraction )
		return
	end

	self:EaseValue( self.Background, self.VisibleFraction, Fraction, 0, 0.3, Callback, Easer )
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
