--[[
	Optimises a pair of teams by minimising the difference in average
	"skill" and standard deviation of "skill".

	Skill is defined by whatever function is provided.

	The method used is roughly the following:

	1. Start with two lists of players, one for each team. Make sure the average skill, total skill,
	   and number of players is already known.

	2. Run through the team with more players (or team 1 if both teams are equal size), and
	   work out what the average skill and standard deviation of skill for both teams will be
	   when each player is swapped with every player on the other team. If one team is larger,
	   also consider moving each player from the larger team onto the smaller team.

	3. If a simulated swap produces an improvement found acceptable, add it to a list of potential swaps.

	4. Once all possible swaps are enumerated, sort them by average difference ascending, standard deviation
	   difference descending. This creates something like this (average, standard deviation):

	   { 10, 100 }, { 10, 50 }, { 10, 20 }, { 30, 70 }, { 30, 40 }, { 50, 10 }

	5. Choose the last entry in the sorted list, and perform the swap defined.

	6. Go back to step 2 and repeat until the list of allowed swaps is empty.

	This method produces a slow, but steady path towards an optimal solution. It keeps chipping away at the average
	bit by bit, while never choosing a standard deviation that's too high.
]]

local Abs = math.abs
local Huge = math.huge
local Max = math.max
local select = select
local Sqrt = math.sqrt
local TableRemove = table.remove
local TableSort = table.sort

local TeamOptimiser = Shine.TypeDef()

local function Larger( A, B )
	return Max( A, B ) == A and 1 or 2
end

-- Inverts team numbers, 1 becomes 2, 2 becomes 1.
local function Opposite( TeamNum )
	return TeamNum % 2 + 1
end

--[[
	Initialise the team optimiser with a table of team members, a table containing the current skill
	data (Total, Count and Average fields), and a function that returns a skill value for a player
	on a given team.
]]
function TeamOptimiser:Init( TeamMembers, TeamSkills, RankFunc )
	self.TeamMembers = TeamMembers
	self.TeamSkills = TeamSkills

	-- Larger and lesser may not actually be different sizes, this just makes the logic easier.
	self.LargerTeam = Larger( #TeamMembers[ 1 ], #TeamMembers[ 2 ] )
	self.LesserTeam = Opposite( self.LargerTeam )
	self.TeamsAreEqual = #TeamMembers[ 1 ] == #TeamMembers[ 2 ]

	do
		local RankCache = {}
		self.RankFunc = function( Ply, TeamMember )
			local Cached = RankCache[ Ply ]
			if Cached and Cached[ TeamMember ] then
				return Cached[ TeamMember ]
			end

			local Value = RankFunc( Ply, TeamMember )
			if not Cached then
				Cached = {}
			end
			Cached[ TeamMember ] = Value
			RankCache[ Ply ] = Cached

			return Value
		end
	end

	self.StandardDeviationTolerance = 40
	self.AverageValueTolerance = 0

	self.SwapContext = {
		Players = {},
		Indices = {},
		PreData = { {}, {} },
		PostData = { {}, {} }
	}
	self.CurrentPotentialState = { Swaps = {} }
	self.SwapBuffer = {}

	return self
end

--[[
	Determines if a player may be swapped.
	Override to filter out players.
]]
function TeamOptimiser:IsValidForSwap( Player )
	return true
end

--[[
	Cycles the values indicating which team is larger.
]]
function TeamOptimiser:CycleTeams()
	self.LargerTeam = Opposite( self.LargerTeam )
	self.LesserTeam = Opposite( self.LargerTeam )
end

--[[
	Gets the standard deviation of the given players, accounting for a potential swap.
]]
function TeamOptimiser:GetStandardDeviation( Players, Average, TeamNumber, GainingPlayer, Index )
	local Count = #Players
	if Count == 0 then return 0 end

	local Sum = 0
	-- + 1 because we might be adding a new player on the end.
	local RealCount = Count + 1
	for i = 1, RealCount do
		local Player = i == Index and GainingPlayer or Players[ i ]
		if Player then
			Sum = Sum + ( ( self.RankFunc( Player, TeamNumber ) or 0 ) - Average ) ^ 2
		else
			RealCount = RealCount - 1
		end
	end

	return Sqrt( Sum / RealCount )
end

--[[
	Gets the average skill value for the given team number, based on their current skills,
	and the player(s) they are gaining and losing.

	Returns the new average, and the new total.
]]
function TeamOptimiser:GetAverage( TeamNumber, TeamSkills, Losing, Gaining )
	local LosingSkill = Losing and self.RankFunc( Losing, TeamNumber ) or 0
	local GainingSkill = Gaining and self.RankFunc( Gaining, TeamNumber ) or 0

	local NewSkill = TeamSkills[ TeamNumber ].Total - LosingSkill + GainingSkill
	return NewSkill / ( TeamSkills[ TeamNumber ].Count + ( Gaining and 0 or -1 ) ), NewSkill
end

--[[
	Sets the values in SwapContext.PreData/PostData pertaining to the swapping
	of the players provided between the two current teams.
]]
function TeamOptimiser:SnapshotStats( TeamNumber, SwapContext )
	-- Work out what the average will be if we lose our current player, and gain a player from the other team.
	local GainingPlayer = SwapContext.Players[ Opposite( TeamNumber ) ]
	local LosingPlayer = SwapContext.Players[ TeamNumber ]
	local Average, Total = self:GetAverage( TeamNumber, self.TeamSkills, LosingPlayer, GainingPlayer )

	local PostData = SwapContext.PostData[ TeamNumber ]
	PostData.Average = Average
	PostData.Total = Total
	PostData.StandardDeviation = self:GetStandardDeviation( self.TeamMembers[ TeamNumber ],
		PostData.Average, TeamNumber, GainingPlayer, SwapContext.Indices[ TeamNumber ] )
end

local function Difference( SkillHolder, Stat )
	return Abs( SkillHolder[ 1 ][ Stat ] - SkillHolder[ 2 ][ Stat ] )
end

function TeamOptimiser:GetSwap( Index )
	local Swap = self.CurrentPotentialState.Swaps[ Index ]
	if not Swap then
		Swap = {
			Indices = {},
			Players = {},
			Totals = {}
		}
		self.CurrentPotentialState.Swaps[ Index ] = Swap
	end

	return Swap
end

--[[
	Simulates a single swap (or move if index 2 is > team 2's size) of players.

	If the swap passes our criteria for improving the difference in average/standard deviation,
	then the swap is added to our potential swaps list.
]]
function TeamOptimiser:SimulateSwap( ... )
	local SwapContext = self.SwapContext
	local Indices = SwapContext.Indices
	local Players = SwapContext.Players
	for i = 1, 2 do
		Indices[ i ] = select( i, ... )
		Players[ i ] = self.TeamMembers[ i ][ Indices[ i ] ]
	end

	-- Get the before and after stats for this swap.
	for i = 1, 2 do
		self:SnapshotStats( i, SwapContext )
	end

	local AverageDiffAfter = Difference( SwapContext.PostData, "Average" )
	local StdDiff = Difference( SwapContext.PostData, "StandardDeviation" )
	if not self:SwapPassesRequirements( AverageDiffAfter, StdDiff ) then return end

	self.SwapCount = self.SwapCount + 1
	local Swap = self:GetSwap( self.SwapCount )
	for i = 1, 2 do
		Swap.Indices[ i ] = Indices[ i ]
		Swap.Players[ i ] = Players[ i ]
		Swap.Totals[ i ] = SwapContext.PostData[ i ].Total
	end
	Swap.AverageDiff = AverageDiffAfter
	Swap.StdDiff = StdDiff
end

--[[
	Caches the initial standard deviation of both teams, if required.
]]
function TeamOptimiser:CacheStandardDeviations()
	self.StandardDeviationCache = self.StandardDeviationCache or {}
	for i = 1, 2 do
		self.StandardDeviationCache[ i ] = self:GetStandardDeviation( self.TeamMembers[ i ],
			self.TeamSkills[ i ].Average, i )
	end
end

--[[
	Tries to swap the player held at PlayerIndex in the larger team, with every
	player in the smaller team.

	If the best swap in these is better than the current swap, it is set as the
	current best swap.
]]
function TeamOptimiser:TrySwaps( PlayerIndex, Pass )
	local TeamMembers = self.TeamMembers

	local Player = TeamMembers[ self.LargerTeam ][ PlayerIndex ]
	if not Player or not self:IsValidForSwap( Player, Pass ) then return end

	-- Check every player on the other team against this player for a better swap.
	for OtherPlayerIndex = 1, #TeamMembers[ self.LesserTeam ] do
		local OtherPlayer = TeamMembers[ self.LesserTeam ][ OtherPlayerIndex ]

		if OtherPlayer and self:IsValidForSwap( OtherPlayer, Pass ) then
			if self.LargerTeam == 1 then
				self:SimulateSwap( PlayerIndex, OtherPlayerIndex )
			else
				self:SimulateSwap( OtherPlayerIndex, PlayerIndex )
			end
		end
	end

	-- Nothing left to try if team numbers are equal.
	if self.TeamsAreEqual then return end

	-- Otherwise, try adding this player to the smaller team without a swap.
	if self.LargerTeam == 1 then
		self:SimulateSwap( PlayerIndex, #TeamMembers[ self.LesserTeam ] + 1 )
	else
		self:SimulateSwap( #TeamMembers[ self.LesserTeam ] + 1, PlayerIndex )
	end
end

TeamOptimiser.RESULT_TERMINATE = 1
TeamOptimiser.RESULT_NEXTPASS = 2

function TeamOptimiser:SwapPassesRequirements( AverageDiff, StdDiff )
	local CurrentAverage = self.CurrentPotentialState.AverageDiffBefore
	-- Average must be improved.
	if AverageDiff > CurrentAverage then return false end

	local CurrentStdDiff = self.CurrentPotentialState.StdDiffBefore
	local StdDiffBetter = StdDiff < CurrentStdDiff
	-- If this is a pure win in standard deviation, it passes.
	if StdDiffBetter then return true end

	-- If this is making no change to the average and standard deviation, deny it.
	if StdDiff == CurrentStdDiff and AverageDiff == CurrentAverage then return false end
	-- Standard deviation is more than it was before, so don't allow it if average is remaining constant.
	if AverageDiff == CurrentAverage then return false end

	-- At this point, average is going to be better for sure, but standard deviation won't.
	-- Thus, make sure it's below our tolerance.
	return StdDiff - CurrentStdDiff < self.StandardDeviationTolerance
end

local CompareAverage = Shine.Comparator( "Field", 1, "AverageDiff" )
local CompareStdDiff = Shine.Comparator( "Field", -1, "StdDiff" )
local Comparator = Shine.Comparator( "Composition", CompareStdDiff, CompareAverage ):Compile()

--[[
	Commits the best swap operation held in self.CurrentPotentialState.Swaps.

	Returns RESULT_NEXTPASS if the pass should halt.
	Returns RESULT_TERMINATE if the entire process should halt.
]]
function TeamOptimiser:CommitSwap()
	local Swaps = self.CurrentPotentialState.Swaps
	local SwapBuffer = self.SwapBuffer
	for i = 1, self.SwapCount do
		SwapBuffer[ i ] = Swaps[ i ]
	end

	-- Sort by average ascending, standard deviation descending.
	-- This means the last entry has the largest average (but still lower than the current)
	-- and the smallest standard deviation in that average group.
	TableSort( SwapBuffer, Comparator )

	local OptimalSwap = SwapBuffer[ #SwapBuffer ]
	if not OptimalSwap then return self.RESULT_NEXTPASS end

	for i = 1, self.SwapCount do
		SwapBuffer[ i ] = nil
	end

	local TeamSkills = self.TeamSkills
	local TeamMembers = self.TeamMembers

	for i = 1, 2 do
		local SwapPly = OptimalSwap.Players[ Opposite( i ) ]

		if not SwapPly then
			-- If there's no player joining us, then remove our player.
			TableRemove( TeamMembers[ i ], OptimalSwap.Indices[ i ] )
			TeamSkills[ self.LargerTeam ].Count = TeamSkills[ self.LargerTeam ].Count - 1
			TeamSkills[ self.LesserTeam ].Count = TeamSkills[ self.LesserTeam ].Count + 1

			self:CycleTeams()
		else
			-- Otherwise, add the player to our team.
			TeamMembers[ i ][ OptimalSwap.Indices[ i ] ] = SwapPly
		end

		TeamSkills[ i ].Total = OptimalSwap.Totals[ i ]
		TeamSkills[ i ].Average = TeamSkills[ i ].Total / TeamSkills[ i ].Count
	end

	-- If an average tolerance is set, and we're now less-equal to it, stop completely.
	if self.AverageValueTolerance > 0 and Difference( TeamSkills, "Average" ) <= self.AverageValueTolerance then
		return self.RESULT_TERMINATE
	end
end

--[[
	Performs a single optimisation pass. This checks the result of every possible swap
	of a single player between both teams. It may also check the result of moving each player
	from the larger team onto the smaller team, if one team is larger than the other.

	Will terminate the pass when either no more swaps/moves result in an improvement, or
	the average tolerance is met.
]]
function TeamOptimiser:PerformOptimisationPass( Pass )
	local Iterations = 0
	local SwapContext = self.SwapContext
	local TeamMembers = self.TeamMembers

	while Iterations < 1000 do
		self:CacheStandardDeviations()
		self.SwapCount = 0

		-- Pre-populate the current pre-swap data.
		for TeamNumber = 1, 2 do
			local PreData = SwapContext.PreData[ TeamNumber ]
			PreData.Average = self.TeamSkills[ TeamNumber ].Average
			PreData.StandardDeviation = self.StandardDeviationCache[ TeamNumber ]
		end

		self.CurrentPotentialState.AverageDiffBefore = Difference( SwapContext.PreData, "Average" )
		self.CurrentPotentialState.StdDiffBefore = Difference( SwapContext.PreData, "StandardDeviation" )

		-- Try swapping every player on the larger team, with every player on the smaller team.
		for i = 1, #TeamMembers[ self.LargerTeam ] do
			self:TrySwaps( i, Pass )
		end

		-- Check if there's a good swap, and if we should continue.
		local Result = self:CommitSwap()
		if Result == self.RESULT_TERMINATE then return true end
		if Result == self.RESULT_NEXTPASS then break end

		Iterations = Iterations + 1
	end
end

-- Override with team preference accounting.
function TeamOptimiser:GetNumPasses()
	return 1
end

--[[
	Main entry point for optimising teams.

	Will perform GetNumPasses() number of optimisation attempts,
	trying all possible single player swaps until the best is found,
	or no more improve the teams.

	This will edit the TeamMembers table directly.
]]
function TeamOptimiser:Optimise()
	for Pass = 1, self:GetNumPasses() do
		if self:PerformOptimisationPass( Pass ) then break end
	end
end

Plugin.TeamOptimiser = TeamOptimiser
