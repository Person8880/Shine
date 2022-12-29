--[[
	Shadow mixin to add managed shadow textures beneath elements.
]]

local SGUI = Shine.GUI

local ShadowManager = require "shine/lib/gui/util/shadows"

local Shadow = {}

local function AddShadow( self, Shadow )
	self.ShadowTexture = Shadow

	if not self.BoxShadowItem then
		self.BoxShadowItem = self:MakeGUIItem()
		-- Set the layer to something really low to make sure this renders behind everything else on the element.
		self.BoxShadowItem:SetLayer( -100 )
		self.BoxShadowItem:SetAnchor( Vector2( 0.5, 0.5 ) )
		self.BoxShadowItem:SetHotSpot( Vector2( 0.5, 0.5 ) )
		self.Background:AddChild( self.BoxShadowItem )
	end

	self.BoxShadowItem:SetTexture( Shadow:GetTextureName() )
	self.BoxShadowItem:SetSize( Vector2( self.BoxShadowItem:GetTextureWidth(), self.BoxShadowItem:GetTextureHeight() ) )
	self.BoxShadowItem:SetIsVisible( true )
end

local function OnSizeChanged( self, Size )
	self:FreeBoxShadow()

	if self.BoxShadowItem then
		self.BoxShadowItem:SetIsVisible( false )
	end

	local ShadowRequestCount = ( self.ShadowRequestCount or 0 ) + 1
	self.ShadowRequestCount = ShadowRequestCount

	ShadowManager.GetBoxShadow( {
		Width = Size.x,
		Height = Size.y,
		BlurRadius = self.ShadowParams.BlurRadius,
		Colour = self.ShadowParams.Colour
	}, function( Shadow )
		-- Make sure the request is the latest, otherwise the same texture could be borrowed twice.
		if not SGUI.IsValid( self ) or self:GetSize() ~= Size or self.ShadowRequestCount ~= ShadowRequestCount then
			Shadow:Free()
			return
		end
		return AddShadow( self, Shadow )
	end )
end

function Shadow:FreeBoxShadow()
	if self.ShadowTexture then
		self.ShadowTexture:Free()
		self.ShadowTexture = nil
	end
end

function Shadow:SetBoxShadow( Params )
	if self.ShadowParams == Params then return end
	if
		self.ShadowParams and Params and
		self.ShadowParams.BlurRadius == Params.BlurRadius and
		self.ShadowParams.Colour == Params.Colour
	then
		return
	end

	self.ShadowParams = Params

	if Params then
		-- Note that property change listeners are unique so this is idempotent.
		self:AddPropertyChangeListener( "Size", OnSizeChanged )

		if self.Size then
			-- If the element has had its size configured already, render its shadow immediately. Otherwise wait for
			-- the size to be set.
			OnSizeChanged( self, self:GetSize() )
		end
	else
		self:RemovePropertyChangeListener( "Size", OnSizeChanged )

		if self.BoxShadowItem then
			self:DestroyGUIItem( self.BoxShadowItem )
			self.BoxShadowItem = nil
		end

		self:FreeBoxShadow()
	end
end

SGUI:RegisterMixin( "Shadow", Shadow )
