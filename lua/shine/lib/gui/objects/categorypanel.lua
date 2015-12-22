--[[
	Category panel.

	Separates objects into categories.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local TableRemove = table.remove

local CategoryPanel = {}

CategoryPanel.CategoryHeight = 24
CategoryPanel.ScrollPos = Vector( 0, 0, 0 )
CategoryPanel.ScrollbarHeightOffset = 0
CategoryPanel.BufferAmount = 0

function CategoryPanel:Initialise()
	Controls.Panel.Initialise( self )

	self.Categories = {}
	self.NumCategories = 0

	self:SetScrollable()
end

function CategoryPanel:SetIsVisible( Visible )
	self.BaseClass.SetIsVisible( self, Visible )

	if not Visible then
		Controls.Panel.SetIsVisible( self, Visible )

		return
	end

	--Only set expanded categories to visible.
	local Categories = self.Categories

	for i = 1, self.NumCategories do
		local Category = Categories[ i ]
		local Objects = Category.Objects
		local Header = Category.Header

		Header:SetIsVisible( true )

		if Category.Expanded then
			for j = 1, #Objects do
				Objects[ j ]:SetIsVisible( true )
			end
		end
	end
end

function CategoryPanel:AddCategory( Name )
	local Categories = self.Categories

	local Button = self:Add( "Button" )
	Button:SetSize( Vector( self:GetSize().x, self.CategoryHeight, 0 ) )
	Button:SetText( Name )
	Button:SetStyleName( "CategoryPanelButton" )

	self.NumCategories = self.NumCategories + 1

	local CategoryObj = {
		Header = Button,
		Objects = {},
		Expanded = true,
		Name = Name
	}

	Categories[ self.NumCategories ] = CategoryObj

	local Height = 0
	--We get the total height of every object above the new category.
	for i = 1, self.NumCategories - 1 do
		local Category = Categories[ i ]

		if Category.Expanded then
			Height = Height + Category.Header:GetSize().y

			for j = 1, #Category.Objects do
				local Object = Category.Objects[ j ]

				Height = Height + Object:GetSize().y
			end
		end
	end
	--So we can set the new category directly below them.
	Button:SetPos( Vector( 0, Height, 0 ) )

	function Button.DoClick()
		self:SetCategoryExpanded( Name, not CategoryObj.Expanded )
	end
end

function CategoryPanel:RemoveCategory( Name )
	local Categories = self.Categories
	local CategoryObj
	local Index

	--This is not ideal, but maintaining a name -> index mapping would be annoying.
	for i = 1, #Categories do
		local Category = Categories[ i ]

		if Category.Name == Name then
			Index = i
			CategoryObj = Category
			break
		end
	end

	if not CategoryObj then return end

	--We get the total height taken up by this category, and destroy its objects.
	local Objects = CategoryObj.Objects
	local Height = 0
	for i = 1, #Objects do
		local Object = Objects[ i ]

		Height = Height + Object:GetSize().y

		Object.Removing = true
		Object:Destroy( true )
	end

	Height = Height + CategoryObj.Header:GetSize().y

	CategoryObj.Header:Destroy( true )

	TableRemove( Categories, Index )

	self.NumCategories = self.NumCategories - 1

	local HeightDiff = Vector( 0, -Height, 0 )
	--Now anything below where this category used to be needs to move up.
	for i = Index, self.NumCategories do
		local Category = Categories[ i ]
		local Objects = Category.Objects

		Category.Header:SetPos( Category.Header:GetPos() + HeightDiff )

		for j = 1, #Objects do
			local Obj = Objects[ j ]

			Obj:SetPos( Obj:GetPos() + HeightDiff )
		end
	end
end

function CategoryPanel:SetCategoryExpanded( Name, Expand )
	local Categories = self.Categories
	local Found
	local HeightDiff = 0
	local HeightVec

	for i = 1, #Categories do
		local Category = Categories[ i ]

		if not Found and Category.Name == Name then
			if Expand and Category.Expanded then return end
			if not Expand and not Category.Expanded then return end

			--Here we get the amount to move all objects below by.
			Found = true
			for j = 1, #Category.Objects do
				local Object = Category.Objects[ j ]

				HeightDiff = HeightDiff + Object:GetSize().y

				Object:SetIsVisible( Expand and true or false )
			end

			Category.Expanded = Expand and true or false

			if HeightDiff == 0 then return end

			HeightVec = Vector( 0, Expand and HeightDiff or -HeightDiff, 0 )
		elseif Found then
			--Move everything in this category up/down by the amount we calculated.
			Category.Header:SetPos( Category.Header:GetPos() + HeightVec )

			for j = 1, #Category.Objects do
				local Object = Category.Objects[ j ]

				Object:SetPos( Object:GetPos() + HeightVec )
			end
		end
	end
end

--Shortcut functions.
function CategoryPanel:ExpandCategory( Name )
	self:SetCategoryExpanded( Name, true )
end

function CategoryPanel:ContractCategory( Name )
	self:SetCategoryExpanded( Name, false )
end

function CategoryPanel:AddObject( CatName, Object )
	local Categories = self.Categories
	local CategoryObj
	local StartIndex

	for i = 1, self.NumCategories do
		local Category = Categories[ i ]

		if Category.Name == CatName then
			CategoryObj = Category
			StartIndex = i + 1
			break
		end
	end

	if not CategoryObj then return end

	local Objects = CategoryObj.Objects
	local LastObject = Objects[ #Objects ]
	local Header = CategoryObj.Header

	--We want to place the new object at the bottom of the category.
	local Height = Header:GetPos().y + Header:GetSize().y
	if LastObject then
		Height = LastObject:GetPos().y + LastObject:GetSize().y
	end

	local Index = #Objects + 1

	self:Add( nil, Object )
	Object:SetPos( Vector( 0, Height, 0 ) )
	Object:CallOnRemove( function()
		--The whole thing's being removed.
		if not SGUI.IsValid( self ) or Object.Removing then return end

		local HeightDiff = Vector( 0, -Object:GetSize().y, 0 )

		--Move objects below us up to compensate for our removal.
		for i = Index + 1, #Objects do
			local Object = Objects[ i ]

			Object:SetPos( Object:GetPos() + HeightDiff )
		end

		TableRemove( Objects, Index )
	end )

	Objects[ Index ] = Object

	--If we're not expanded, we don't have to worry about moving other categories yet.
	if not CategoryObj.Expanded then
		Object:SetIsVisible( false )

		return
	end

	--Move all the other categories below us down by our new object's height.
	local HeightDiff = Vector( 0, Object:GetSize().y, 0 )

	for i = StartIndex, self.NumCategories do
		local Category = Categories[ i ]
		local Objects = Category.Objects

		Category:SetPos( Category:GetPos() + HeightDiff )

		for j = 1, #Objects do
			local Object = Objects[ j ]

			Object:SetPos( Object:GetPos() + HeightDiff )
		end
	end
end

SGUI:Register( "CategoryPanel", CategoryPanel, "Panel" )
