--[[
	Render pipelines.
]]

local Shine = Shine
local SGUI = Shine.GUI
local Hook = Shine.Hook

local assert = assert
local IsType = Shine.IsType
local getmetatable = getmetatable
local ipairs = ipairs
local setmetatable = setmetatable
local StringFormat = string.format
local TableAdd = table.Add
local TableNew = require "table.new"
local xpcall = xpcall

local RenderPipeline = {}

-- Provides a JIT friendly way to pass a method as a callback.
local BoundMethodCallback = Shine.TypeDef()
function BoundMethodCallback:Init( Context, Method )
	self.Context = Context
	self.Method = Method
	return self
end

function BoundMethodCallback:__call( Arg1, Arg2 )
	return self.Method( self.Context, Arg1, Arg2 )
end

local TextureInput = {}
function TextureInput:ResolveInputValue( Context )
	return Context.CurrentTexture:GetName()
end

-- An input used to select a single texture from a list that was output by a previous node.
-- This allows for a node to emit multiple textures which can then be joined together by another node, or passed further
-- along parallel pipelines.
local TextureListInput = Shine.TypeDef()
function TextureListInput:Init( Index )
	self.Index = Index
	return self
end

function TextureListInput:ResolveInputValue( Context )
	return Context.CurrentTexture:Get( self.Index ):GetName()
end

local PipelineTexture = Shine.TypeDef()
function PipelineTexture:Init( Name, GUIView, Pool )
	self.Name = Name
	self.GUIView = GUIView
	self.Pool = Pool
	return self
end

function PipelineTexture:GetName()
	return self.Name
end

function PipelineTexture:SetPipeline( Pipeline, Width, Height )
	self.Pipeline = Pipeline
	self.Width = Width
	self.Height = Height

	if Pipeline then
		-- If the texture data is lost, re-render this texture from its original pipeline.
		Hook.Add( "OnRenderDeviceReset", self, BoundMethodCallback( self, self.Refresh ) )
	else
		Hook.Remove( "OnRenderDeviceReset", self )
	end
end

local function DestroyGUIView( self )
	if self.GUIView then
		Client.DestroyGUIView( self.GUIView )
		Hook.Remove( "Think", self.GUIView )
		self.GUIView = nil
	end
end

local function CancelTextureRefresh( self )
	if self.RefreshContext then
		-- Stop any ongoing refresh.
		self.RefreshContext:Destroy()
		self.RefreshContext = nil
	end
end

do
	local function OnRefreshed( self, OutputTexture, Pipeline )
		self.RefreshContext = nil

		if self.Pipeline ~= Pipeline or self.GUIView ~= OutputTexture.GUIView or self.IsFree then
			-- Somehow wasn't cancelled when freed or rendered elsewhere, ignore this texture.
			Shine.Logger:Debug(
				"Discarding refreshed texture %s as %s is not in a valid state to be refreshed.",
				OutputTexture,
				self
			)
			OutputTexture:Free()
			return
		end

		assert( OutputTexture == self, "Pipeline didn't re-render to the same output texture!" )

		if self.OnRefreshComplete then
			self:OnRefreshComplete( Pipeline )
			self.OnRefreshComplete = nil
		end
	end

	--[[
		Re-renders the given texture, executing its original render pipeline again.
	]]
	function PipelineTexture:Refresh( OnRefreshComplete )
		local Pipeline = self.Pipeline
		if not Pipeline then return end

		CancelTextureRefresh( self )

		self.OnRefreshComplete = OnRefreshComplete

		Shine.Logger:Debug( "Refreshing %s...", self )

		self.RefreshContext = RenderPipeline.Execute(
			Pipeline,
			self.Width,
			self.Height,
			BoundMethodCallback( self, OnRefreshed )
		)
	end
end

function PipelineTexture:Free()
	if self.IsFree then return end

	Shine.Logger:Debug( "Freeing %s...", self )

	CancelTextureRefresh( self )
	DestroyGUIView( self )

	self:SetPipeline( nil )
	self.IsFree = true

	local Texture = self.Pool.FreeTextures.Next
	if Texture then
		self.Next = Texture
	end
	self.Pool.FreeTextures.Next = self
end

function PipelineTexture:__tostring()
	return StringFormat( "PipelineTexture[%s]", self.Name )
end

local PiplineTexturePool = {
	FreeTextures = {},
	TexturePrefix = "*shine_render_pipeline_",
	Index = 1
}
function PiplineTexturePool:AllocateTexture( GUIView )
	local Texture = self.FreeTextures.Next
	if Texture then
		Shine.Logger:Debug( "Using existing texture '%s' from pipeline texture pool...", Texture.Name )

		self.FreeTextures.Next = Texture.Next
		Texture.Next = nil
		Texture.IsFree = nil
		Texture.GUIView = GUIView

		return Texture
	end

	local Name = self.TexturePrefix..self.Index
	self.Index = self.Index + 1

	Shine.Logger:Debug( "Allocating new pipeline texture '%s'...", Name )

	Texture = PipelineTexture( Name, GUIView, self )

	return Texture
end

-- Wraps a list of textures, allows nodes to return multiple textures to be held as the current texture.
-- Note that lists used outside of pipelines should be freed and refreshed as a unit, do not free individual textures.
local TextureList = Shine.TypeDef()
function TextureList:Init( Textures )
	self.Textures = Textures
	return self
end

function TextureList:Iterate()
	return ipairs( self.Textures )
end

function TextureList:Get( Index )
	return self.Textures[ Index ]
end

function TextureList:GetCount()
	return #self.Textures
end

TextureList.SetPipeline = PipelineTexture.SetPipeline

do
	local function OnRefreshed( self, OutputTexture, Pipeline )
		self.RefreshContext = nil

		if not self.Pipeline then
			OutputTexture:Free()
			return
		end

		-- The refreshed output should be an identical list, pointing at the same textures as before.
		for Index, Texture in self:Iterate() do
			assert(
				Texture == OutputTexture:Get( Index ),
				"Pipeline didn't re-render texture in list to the same output texture!"
			)
		end

		if self.OnRefreshComplete then
			self:OnRefreshComplete( Pipeline )
			self.OnRefreshComplete = nil
		end
	end

	function TextureList:Refresh( OnRefreshComplete )
		if not self.Pipeline then return end

		CancelTextureRefresh( self )

		self.OnRefreshComplete = OnRefreshComplete

		Shine.Logger:Debug( "Refreshing %s...", self )

		self.RefreshContext = RenderPipeline.Execute(
			self.Pipeline,
			self.Width,
			self.Height,
			BoundMethodCallback( self, OnRefreshed )
		)
	end
end

function TextureList:Free()
	CancelTextureRefresh( self )

	self:SetPipeline( nil )

	for Index, Texture in self:Iterate() do
		Texture:Free()
	end
end

function TextureList:__tostring()
	return StringFormat( "TextureList[%s]", Shine.Stream( self.Textures ):Concat( ", " ) )
end

--[[
	A node that performs a single rendering operation to an output texture.

	Note that the final GUIViewNode in a pipeline will retain its output texture to allow for re-rendering. Thus,
	a GUIViewNode should only be added to a single pipeline.

	Re-use the definition and/or use the Copy() method if the same node is required in multiple distinct pipelines.
]]
local GUIViewNode = Shine.TypeDef()
function GUIViewNode:Init( Params )
	self.View = Params.View
	self.Input = Params.Input
	return self
end

function GUIViewNode:Copy()
	return GUIViewNode( {
		View = self.View,
		Input = TableAdd( {}, self.Input )
	} )
end

function GUIViewNode:CopyWithInputs( Inputs )
	return GUIViewNode( {
		View = self.View,
		Input = TableAdd( TableAdd( {}, self.Input ), Inputs )
	} )
end

function GUIViewNode:OnStart( Context )
	local RootPipeline = Context:GetRootPipeline()
	local IsOutputNode = RootPipeline:IsOutputNode( self )

	local GUIView
	local UsingPreviousTexture
	if IsOutputNode and self.OutputTexture then
		-- If this is an output node that previously rendered, re-use its output texture.
		-- Note that GUIViewNodes aren't permitted to change their size or script, but they can change any other
		-- parameter when re-rendering.
		GUIView = assert( self.OutputTexture.GUIView, "Output texture was freed during rendering!" )
		UsingPreviousTexture = true
		Shine.Logger:Debug( "Re-using previous output texture for output node %s: %s", self, self.OutputTexture )
	else
		Shine.Logger:Debug(
			"Loading GUIView with script %s and size (%s, %s)",
			self.View,
			Context.Width,
			Context.Height
		)
		GUIView = Client.CreateGUIView( Context.Width, Context.Height )
		GUIView:Load( self.View )
	end

	GUIView:SetGlobal( "Width", Context.Width )
	GUIView:SetGlobal( "Height", Context.Height )

	for i = 1, #self.Input do
		local Input = self.Input[ i ]
		local Value = Input.Value
		if IsType( Value, "table" ) and IsType( Value.ResolveInputValue, "function" ) then
			Value = Value:ResolveInputValue( Context )
		end
		GUIView:SetGlobal( Input.Key, Value )
		Shine.Logger:Trace( "Set global value on GUIView: %s = %s", Input.Key, Value )
	end

	if Shine.Logger:IsDebugEnabled() then
		GUIView:SetGlobal( "DebugLog", 1 )
	end

	GUIView:SetGlobal( "NeedsUpdate", 1 )
	GUIView:SetRenderCondition( GUIView.RenderOnce )

	if not UsingPreviousTexture then
		local TargetTexture = Context:AllocateTexture( GUIView )
		GUIView:SetTargetTexture( TargetTexture:GetName() )

		if IsOutputNode then
			-- If this is an output node (i.e. its output texture is going to be returned by the pipeline), then
			-- hold onto it here so the pipeline can re-render to the same texture later.
			self.OutputTexture = TargetTexture
		else
			-- Otherwise just store it temporarily in the context.
			Context:SetVariable( self, "OutputTexture", TargetTexture )
		end
	end

	Context:SetVariable( self, "GUIView", GUIView )
end

function GUIViewNode:Terminate( Context )
	-- Free the node's temporary texture if it has one, this will also destroy the associated GUIView.
	local OutputTexture
	if self.OutputTexture and not self.OutputTexture.Pipeline then
		OutputTexture = self.OutputTexture
	else
		OutputTexture = Context:GetVariable( self, "OutputTexture" )
	end
	if OutputTexture then
		OutputTexture:Free()
	end
end

function GUIViewNode:Think( Context )
	local GUIView = Context:GetVariable( self, "GUIView" )

	if GUIView:GetRenderCondition() == GUIView.RenderNever then
		return self.OutputTexture or Context:GetVariable( self, "OutputTexture" )
	end
end

function GUIViewNode:IsOutputNode( Node )
	-- This method is only called on the last node in a pipeline, so self is guaranteed to be an output node.
	return Node == self
end

function GUIViewNode:OnFinish( Context )
	-- Nothing to do, default free is enough.
end

function GUIViewNode:__tostring()
	return StringFormat( "GUIViewNode[%s]", self.View )
end

--[[
	A node that executes a sequence of child nodes, passing along the current texture and cleaning it up once it has
	been processed.

	Child nodes can be any other node, be it another pipeline, a fork, or a single GUI view render operation.

	Each pipeline executes within an isolated scope, with any textures it creates not affecting its parent pipeline.
	Only the final output texture is passed back up to a parent pipeline to be passed along to the next node or returned
	as the final output of the parent.

	Pipelines should not be modified once they have been created. Create a new pipeline if additional nodes are
	required.
]]
local PipelineNode = Shine.TypeDef()
function PipelineNode:Init( Nodes )
	self.Nodes = Nodes
	self.NumNodes = #Nodes
	Shine.AssertAtLevel( self.NumNodes > 0, "Pipelines must have at least one node!", 3 )
	return self
end

function PipelineNode:Copy()
	local CopiedNodes = TableNew( self.NumNodes, 0 )
	for i = 1, self.NumNodes do
		CopiedNodes[ i ] = self.Nodes[ i ]:Copy()
	end
	return PipelineNode( CopiedNodes )
end

function PipelineNode:CopyWithAdditionalNodes( Nodes )
	local NumNewNodes = #Nodes
	local CopiedNodes = TableNew( self.NumNodes + NumNewNodes, 0 )
	for i = 1, self.NumNodes do
		CopiedNodes[ i ] = self.Nodes[ i ]:Copy()
	end
	for i = 1, NumNewNodes do
		CopiedNodes[ self.NumNodes + i ] = Nodes[ i ]
	end
	return PipelineNode( CopiedNodes )
end

function PipelineNode:OnStart( Context )
	-- Allocate a new context for this pipeline to isolate it from its parent.
	-- This allows for scoped lifecycle management of temporary textures.
	local NestedContext = Context:CreateNestedContext( self )
	-- Copy over the current texture, note that attempts to free it within this pipeline will be ignored.
	NestedContext.CurrentTexture = Context.CurrentTexture
	-- Initialise the first node in the nested context.
	NestedContext.CurrentNode:OnStart( NestedContext )
end

function PipelineNode:Terminate( Context )
	local NestedContext = Context:GetContextForNode( self )
	NestedContext:Terminate()
end

function PipelineNode:Think( Context )
	local CurrentNode = Context.CurrentNode
	local OutputTexture = CurrentNode:Think( Context:GetContextForNode( CurrentNode ) )
	if OutputTexture then
		Shine.Logger:Debug( "Node %s finished rendering and returned output: %s", CurrentNode, OutputTexture )

		-- Let the node clean up after itself if it has extra logic.
		CurrentNode:OnFinish( Context, OutputTexture )

		-- Free the current texture that's been processed at this level.
		if Context.CurrentTexture then
			Context:FreeTexture( Context.CurrentTexture )
		end

		-- Take the output from the node and apply it as the new current texture.
		Context.CurrentTexture = OutputTexture

		-- Advance to the next node if there is one, otherwise stop.
		local NextNode = Context:AdvanceNode()
		if not NextNode then
			Shine.Logger:Debug( "No more nodes in pipeline %s.", self )
			return OutputTexture
		end

		Shine.Logger:Debug( "Advancing to next node: %s", NextNode )

		NextNode:OnStart( Context )

		-- Run again with the next node until either a node isn't finished yet, or all nodes are completed.
		return self:Think( Context )
	end
end

function PipelineNode:IsOutputNode( Node )
	return self.Nodes[ self.NumNodes ]:IsOutputNode( Node )
end

function PipelineNode:OnFinish( Context, OutputTexture )
	Context:RemoveNestedContext( self )
	-- Need to borrow the output texture here to ensure that, if this node is not the final node, its output is cleaned
	-- up later. Otherwise only the nested context owns the texture and it'll never clean it up.
	Context:BorrowTexture( OutputTexture )
end

function PipelineNode:__tostring()
	return StringFormat( "PipelineNode[(%s)]", Shine.Stream( self.Nodes ):Concat( "), (" ) )
end

--[[
	A node that executes multiple pipelines concurrently and collects their outputs into a texture list.

	This is useful if needing to perform separate render operations on the same input texture with different results, as
	it avoids needing to render the same thing more than once.

	Note that a pipeline here could be a single GUIViewNode, a pipeline, or even another fork node.

	As with pipeline nodes, fork nodes should not be modified after they have been created.
]]
local ForkNode = Shine.TypeDef()
function ForkNode:Init( Pipelines )
	self.Pipelines = Pipelines
	self.NumPipelines = #Pipelines
	Shine.AssertAtLevel( self.NumPipelines > 0, "Fork nodes must have at least one pipeline!", 3 )
	return self
end

function ForkNode:Copy()
	local CopiedPipelines = TableNew( self.NumPipelines, 0 )
	for i = 1, self.NumPipelines do
		CopiedPipelines[ i ] = self.Pipelines[ i ]:Copy()
	end
	return ForkNode( CopiedPipelines )
end

function ForkNode:OnStart( Context )
	local ActivePipelines = TableNew( self.NumPipelines, 0 )
	-- Start with all pipelines active.
	for i = 1, self.NumPipelines do
		local Pipeline = self.Pipelines[ i ]
		ActivePipelines[ i ] = Pipeline
		Pipeline:OnStart( Context )
	end
	Context:SetVariable( self, "ActivePipelines", ActivePipelines )
	Context:SetVariable( self, "OutputTextures", TableNew( self.NumPipelines, 0 ) )
end

function ForkNode:Terminate( Context )
	for i = 1, self.NumPipelines do
		local Pipeline = self.Pipelines[ i ]
		Pipeline:Terminate( Context )
	end
end

function ForkNode:Think( Context )
	local ActivePipelines = Context:GetVariable( self, "ActivePipelines" )
	local OutputTextures = Context:GetVariable( self, "OutputTextures" )

	local AllFinished = true
	for i = 1, self.NumPipelines do
		local Pipeline = ActivePipelines[ i ]
		if Pipeline then
			local OutputTexture = Pipeline:Think( Context:GetContextForNode( Pipeline ) )
			if OutputTexture then
				Pipeline:OnFinish( Context, OutputTexture )

				ActivePipelines[ i ] = nil
				-- Retain the index the pipeline was configured under for its output to allow for deterministic
				-- correlation in subsequent nodes.
				OutputTextures[ i ] = OutputTexture
			else
				-- Pipeline isn't done yet, have to keep waiting.
				AllFinished = false
			end
		end
	end

	if AllFinished then
		Shine.Logger:Debug( "All pipelines completed in fork node %s.", self )
		-- All pipelines finished, return the list of results. It's assumed that the next node is expecting a list (or
		-- if this is the last node, that the caller knows to expect a list of outputs).
		return TextureList( OutputTextures )
	end
end

function ForkNode:IsOutputNode( Node )
	-- Fork nodes have multiple branches, thus there's multiple output nodes to consider here.
	for i = 1, self.NumPipelines do
		if self.Pipelines[ i ]:IsOutputNode( Node ) then
			return true
		end
	end
	return false
end

function ForkNode:OnFinish( Context, OutputTextures )
	for i = 1, self.NumPipelines do
		self.Pipelines[ i ]:OnFinish( Context, OutputTextures:Get( i ) )
	end
end

function ForkNode:__tostring()
	return StringFormat( "ForkNode[(%s)]", Shine.Stream( self.Pipelines ):Concat( "), (" ) )
end

local NodeVariableTable = {
	__index = function( self, Key )
		-- Auto-populate with a new table if no variables exist yet.
		local Vars = {}
		self[ Key ] = Vars
		return Vars
	end
}

local PipelineID = 0
local PipelineContext = Shine.TypeDef()
function PipelineContext:Init( Pipeline, Width, Height, Parent )
	PipelineID = PipelineID + 1
	self.ID = PipelineID
	self.Pipeline = Pipeline
	self.Nodes = Pipeline.Nodes
	self.NumNodes = Pipeline.NumNodes
	self.Width = Width
	self.Height = Height
	self.Callbacks = {}
	self.Parent = Parent
	return self:Reset()
end

function PipelineContext:GetRootPipeline()
	local Root = self
	while Root.Parent do
		Root = Root.Parent
	end
	return Root.Pipeline
end

function PipelineContext:Reset()
	self.NestedContexts = TableNew( 0, self.NumNodes )
	for i = 1, self.NumNodes do
		-- Use this context for all of the pipeline nodes by default. Nodes can optionally assign themselves a new
		-- nested context if they need it.
		self.NestedContexts[ self.Nodes[ i ] ] = self
	end
	self.CurrentNode = self.Nodes[ 1 ]
	self.CurrentNodeIndex = 1
	self.Textures = {}
	self.Variables = setmetatable( {}, NodeVariableTable )
	return self
end

function PipelineContext:Start()
	Shine.Logger:Debug( "Starting %s...", self )
	self.CurrentNode:OnStart( self )
end

function PipelineContext:Terminate()
	Shine.Logger:Debug( "Terminating %s...", self )

	if self.CurrentNode then
		-- Notify the current node to free any temporary resources, this will cascade down to nested contexts.
		self.CurrentNode:Terminate( self )
	end

	if self.CurrentTexture and not self.CurrentTexture.Pipeline then
		-- Directly free the current texture, ignoring reference counts. Freeing is idempotent and nothing should be
		-- retained after termination except the final output texture(s).
		self.CurrentTexture:Free()
	end

	self.CurrentTexture = nil
end

function PipelineContext:Restart()
	-- Terminate and reset the context state.
	self:Terminate()
	self:Reset()
	-- Then start again from the first node.
	return self:Start()
end

function PipelineContext:AdvanceNode()
	local CurrentNode = self.CurrentNode
	-- Clear out the current node's state now that it's finished. Nodes are expected to be self-contained and not need
	-- to access any internal state from another node.
	self.Variables[ CurrentNode ] = nil
	self.NestedContexts[ CurrentNode ] = nil

	local NewNodeIndex = self.CurrentNodeIndex + 1
	CurrentNode = self.Nodes[ NewNodeIndex ]

	self.CurrentNode = CurrentNode
	self.CurrentNodeIndex = NewNodeIndex

	return CurrentNode
end

function PipelineContext:CreateNestedContext( Pipeline )
	local NestedContext = PipelineContext( Pipeline, self.Width, self.Height, self )
	self.NestedContexts[ Pipeline ] = NestedContext
	return NestedContext
end

function PipelineContext:RemoveNestedContext( Pipeline )
	self.NestedContexts[ Pipeline ] = nil
end

function PipelineContext:GetContextForNode( Node )
	return self.NestedContexts[ Node ]
end

function PipelineContext:AllocateTexture( GUIView )
	local Texture = PiplineTexturePool:AllocateTexture( GUIView )
	self.Textures[ Texture ] = 1
	return Texture
end

function PipelineContext:BorrowTexture( Texture )
	local RefCount = self.Textures[ Texture ]
	if not RefCount then
		RefCount = 0
	end

	RefCount = RefCount + 1
	self.Textures[ Texture ] = RefCount

	Shine.Logger:Debug( "%s now has reference count: %s", Texture, RefCount )
end

function PipelineContext:FreeTexture( Texture )
	if getmetatable( Texture ) == TextureList then
		for Index, TextureElement in Texture:Iterate() do
			self:FreeTexture( TextureElement )
		end
		return
	end

	local RefCount = self.Textures[ Texture ]
	if not RefCount then return end

	RefCount = RefCount - 1

	Shine.Logger:Debug( "%s now has reference count: %s", Texture, RefCount )

	if RefCount <= 0 then
		Texture:Free()
		self.Textures[ Texture ] = nil
	else
		self.Textures[ Texture ] = RefCount
	end
end

function PipelineContext:SetVariable( Node, Key, Value )
	self.Variables[ Node ][ Key ] = Value
end

function PipelineContext:GetVariable( Node, Key )
	return self.Variables[ Node ][ Key ]
end

function PipelineContext:AddCallback( Callback )
	if self.Finished then
		-- Call without xpcall here as this is within the context of the caller so will only break them if they error.
		Callback( self.CurrentTexture, self.Pipeline )
		return
	end
	self.Callbacks[ #self.Callbacks + 1 ] = Callback
end

function PipelineContext:__tostring()
	return StringFormat(
		"PipelineContext[ID = %s, Width = %s, Height = %s, CurrentTexture = %s, CurrentNode = %s: %s, Nodes = %s]",
		self.ID,
		self.Width,
		self.Height,
		self.CurrentTexture,
		self.CurrentNodeIndex,
		self.CurrentNode,
		Shine.Stream( self.Nodes ):Concat( ", " )
	)
end

local OnError = Shine.BuildErrorHandler( "Pipeline render callback error:" )

function PipelineContext:RemoveHooks()
	Hook.Remove( "Think", self )
	Hook.Remove( "OnRenderDeviceReset", self )
end

function PipelineContext:OnExecutionCompleted( FinalOutputTexture )
	self.Finished = true

	Shine.Logger:Debug( "Pipeline finished execution: %s ", self )

	for i = 1, #self.Callbacks do
		-- Avoid errors in one callback suppressing the others.
		xpcall( self.Callbacks[ i ], OnError, FinalOutputTexture, self.Pipeline )
	end
end

function PipelineContext:Think()
	local OutputTexture = self.Pipeline:Think( self )
	if OutputTexture then
		self:RemoveHooks()
		-- Attach the pipeline and parameters to the output texture to allow it to re-render itself if texture data
		-- is lost later.
		OutputTexture:SetPipeline( self.Pipeline, self.Width, self.Height )
		self:OnExecutionCompleted( OutputTexture )
	end
end

function PipelineContext:Destroy()
	self:Terminate()
	self:RemoveHooks()
end

-- Export various types for external use/type checking.
RenderPipeline.ForkNode = ForkNode
RenderPipeline.GUIViewNode = GUIViewNode
RenderPipeline.PipelineNode = PipelineNode
RenderPipeline.PipelineTexture = PipelineTexture
RenderPipeline.TextureInput = TextureInput
RenderPipeline.TextureList = TextureList
RenderPipeline.TextureListInput = TextureListInput

local ItemSerialiser = require "shine/lib/gui/views/serialise"

--[[
	A helper function to build a pipeline that renders a given node, then blurs it by the given blur radius.

	Input:
		- Width - the texture width (should be large enough to contain the node's content, plus the blur radius).
		- Height - the texture height (should be large enough to contain the node's content, plus the blur radius).
		- BlurRadius - the blur radius in pixels.

	Output: A PipelineNode that can be used to render the given node with blur applied.
]]
function RenderPipeline.ApplyBlurToNode( Params )
	local Width = Params.Width
	local Height = Params.Height
	local BlurRadius = Params.BlurRadius

	return PipelineNode( {
		-- First render the node whose output will be blurred.
		Params.NodeToBlur,
		-- Then blur along the y-axis using the given blur radius.
		GUIViewNode {
			View = "lua/shine/lib/gui/views/content.lua",
			Input = ItemSerialiser.SerialiseObjects( {
				{
					X = 0,
					Y = 0,
					Width = Width,
					Height = Height,
					Colour = Colour( 1, 1, 1, 1 ),
					Shader = "shaders/GUI/menu/gaussianBlurY.surface_shader",
					ShaderParams = {
						{ Key = "blurRadius", Value = BlurRadius },
						{ Key = "rcpFrameY", Value = 1 / Height }
					},
					Texture = TextureInput
				}
			} )
		},
		-- Finally, blur along the x-axis. The final output is a texture containing a blurred version of the original
		-- node's output.
		GUIViewNode {
			View = "lua/shine/lib/gui/views/content.lua",
			Input = ItemSerialiser.SerialiseObjects( {
				{
					X = 0,
					Y = 0,
					Width = Width,
					Height = Height,
					Colour = Colour( 1, 1, 1, 1 ),
					Shader = "shaders/GUI/menu/gaussianBlurX.surface_shader",
					ShaderParams = {
						{ Key = "blurRadius", Value = BlurRadius },
						{ Key = "rcpFrameX", Value = 1 / Width }
					},
					Texture = TextureInput
				}
			} )
		}
	} )
end

--[[
	A helper function to build a pipeline that renders a box shadow with the given size, blur radius and colour.

	Input:
		- Width - the box width (will be used to determine the texture width).
		- Height - the box height (will be used to determine the texture height).
		- BlurRadius - the blur radius in pixels (will be used to determine the texture size).
		- Colour - the colour of the box to render as a shadow.

	Outputs:
		1. A PipelineNode that can be used to render the specified box shadow.
		2. The width of the texture that should be output by the pipeline (large enough to contain the box and the blur
		radius).
		3. The height of the texture that should be output by the pipeline (large enough to contain the box and the blur
		radius).
]]
function RenderPipeline.BuildBoxShadowPipeline( Params )
	local Width = Params.Width
	local Height = Params.Height
	local BlurRadius = Params.BlurRadius

	local TextureWidth = Width + BlurRadius * 2
	local TextureHeight = Height + BlurRadius * 2

	return RenderPipeline.ApplyBlurToNode( {
		Width = TextureWidth,
		Height = TextureHeight,
		BlurRadius = BlurRadius,
		-- Render a box in the middle of the texture with the specified colour.
		NodeToBlur = GUIViewNode {
			View = "lua/shine/lib/gui/views/content.lua",
			Input = ItemSerialiser.SerialiseObjects( {
				{
					X = BlurRadius,
					Y = BlurRadius,
					Width = Width,
					Height = Height,
					Colour = Params.Colour
				}
			} )
		}
	} ), TextureWidth, TextureHeight
end

--[[
	Executes the given pipeline, allocating textures with the given width and height at each step.

	Inputs:
		1. The pipeline to execute.
		2. The desired width of the output texture.
		3. The desired height of the output texture.
		4. A callback that will be invoked with the final output texture on completion of the pipeline.

	Output: A context object that can be used to add additional callbacks, or to terminate/restart rendering.
	Note that once rendering is complete, this context object should be discarded. To re-render the pipeline after
	completion, use the Refresh() method on the output texture.
]]
function RenderPipeline.Execute( Pipeline, Width, Height, OnExecutionCompleted )
	local Context = PipelineContext( Pipeline, Width, Height )
	Context:AddCallback( OnExecutionCompleted )
	Context:Start()

	Hook.Add( "Think", Context, BoundMethodCallback( Context, Context.Think ) )

	-- If the render device is lost mid-render, restart the pipeline from scratch, discarding any existing textures.
	Hook.Add( "OnRenderDeviceReset", Context, BoundMethodCallback( Context, Context.Restart ) )

	return Context
end

return RenderPipeline
