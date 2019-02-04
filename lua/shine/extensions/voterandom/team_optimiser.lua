--[[
	Optimises a pair of teams by minimising the difference in average
	"skill" and standard deviation of "skill".

	Skill is defined by whatever function is provided.

	The method used is either based on hard rules (legacy method, usually worse), or based on a cost
	function to be minimised (usually produces better teams in less time).

	The hard rule based method is roughly the following (assuming TakeSwapImmediately = false):

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

	The cost based method has the following key differences (assuming TakeSwapImmediately = true):

	1. As soon as a swap that lowers the cost is found, it is chosen and applied. This avoids having to compute
	   lots of potential swaps and helps avoid being overly greedy and getting stuck in a local minimum.

	2. Instead of hard rules looking at average/standard deviation, a cost is derived from the difference
	   in average/standard deviation between teams. The goal is then to lower the cost.
]]

local Abs = math.abs
local Huge = math.huge
local Max = math.max
local Remap = math.Remap
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

-- Sort by average ascending, standard deviation descending.
-- This means the last entry has the largest average (but still lower than the current)
-- and the smallest standard deviation in that average group.
local CompareAverage = Shine.Comparator( "Field", 1, "AverageDiff" )
local CompareStdDiff = Shine.Comparator( "Field", -1, "StdDiff" )
local DEFAULT_COMPARATOR = Shine.Comparator( "Composition", CompareStdDiff, CompareAverage ):Compile()

--[[
	Initialise the team optimiser with a table of team members, a table containing the current skill
	data (Total, Count and Average fields), and a function that returns a skill value for a player
	on a given team.
]]
function TeamOptimiser:Init( TeamMembers, TeamSkills, RankFunc, Comparator )
	self.TeamMembers = TeamMembers
	self.TeamSkills = TeamSkills

	-- Larger and lesser may not actually be different sizes, this just makes the logic easier.
	self.LargerTeam = Larger( #TeamMembers[ 1 ], #TeamMembers[ 2 ] )
	self.LesserTeam = Opposite( self.LargerTeam )
	self.TeamsAreEqual = #TeamMembers[ 1 ] == #TeamMembers[ 2 ]

	self.PlayerGroups = TeamMembers.PlayerGroups or {}
	self.GroupWeights = {}

	self.GroupsByPlayer = {}
	for i = 1, #self.PlayerGroups do
		local Group = self.PlayerGroups[ i ]
		for j = 1, #Group.Players do
			self.GroupsByPlayer[ Group.Players[ j ] ] = Group
		end
	end

	self.TeamLookup = {}
	for i = 1, 2 do
		local Players = TeamMembers[ i ]
		for j = 1, #Players do
			self.TeamLookup[ Players[ j ] ] = i
		end
	end

	self.TakeSwapImmediately = false

	do
		local RankCache = {}
		self.RankFunc = function( Ply, TeamNumber )
			local Cached = RankCache[ Ply ]
			if Cached and Cached[ TeamNumber ] then
				return Cached[ TeamNumber ]
			end

			local Value = RankFunc( Ply, TeamNumber )
			if not Cached then
				Cached = {}
			end
			Cached[ TeamNumber ] = Value
			RankCache[ Ply ] = Cached

			return Value
		end
	end

	self.Comparator = Comparator or DEFAULT_COMPARATOR

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

function TeamOptimiser:GetTeamPreferenceWeighting( Player, TeamNumber )
	return 0
end

--[[
	Gets the standard deviation of the given players, accounting for a potential swap.
]]
function TeamOptimiser:GetPlayerStats( Players, Average, TeamNumber, GainingPlayer, Index )
	local Count = #Players
	if Count == 0 and not GainingPlayer then
		return 0, 0
	end

	local Sum = 0
	local PreferenceWeight = 0
	-- + 1 because we might be adding a new player on the end.
	local RealCount = Count + 1
	for i = 1, RealCount do
		local Player
		if i == Index then
			Player = GainingPlayer
		else
			Player = Players[ i ]
		end

		if Player then
			PreferenceWeight = PreferenceWeight + self:GetTeamPreferenceWeighting( Player, TeamNumber )
			Sum = Sum + ( ( self.RankFunc( Player, TeamNumber ) or 0 ) - Average ) ^ 2
		else
			RealCount = RealCount - 1
		end
	end

	if RealCount == 0 then
		return 0, 0
	end

	return Sqrt( Sum / RealCount ), PreferenceWeight
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
	local TotalPlayers = TeamSkills[ TeamNumber ].Count + ( Gaining and 0 or -1 )
	if TotalPlayers == 0 then
		return 0, NewSkill
	end

	return NewSkill / TotalPlayers, NewSkill
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

	local StdDev, TeamPreferenceWeight = self:GetPlayerStats( self.TeamMembers[ TeamNumber ],
		Average, TeamNumber, GainingPlayer, SwapContext.Indices[ TeamNumber ] )
	PostData.StandardDeviation = StdDev
	PostData.TeamPreferenceWeighting = TeamPreferenceWeight
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

-- Override this to alter the factor by which groups are weighted.
function TeamOptimiser:ScaleGroupWeighting( GroupWeight )
	return GroupWeight
end

function TeamOptimiser:GetGroupWeighting( Group, ChangedPlayer, NewTeam )
	local Players = Group.Players
	local TeamLookup = self.TeamLookup
	local NumOnTeam1 = 0
	local NumOnTeam2 = 0
	for i = 1, #Players do
		local Player = Players[ i ]
		local Team = TeamLookup[ Player ]
		if Player == ChangedPlayer then
			Team = NewTeam
		end

		NumOnTeam1 = NumOnTeam1 + Team % 2
		NumOnTeam2 = NumOnTeam2 + ( Team - 1 )
	end

	-- Map from [0.5 * GroupSize, GroupSize] to [1, 0], meaning the strongest increase in cost
	-- comes from the group being split evenly, and the smallest from them being all together.
	local MajorityOnTeam = Max( NumOnTeam1, NumOnTeam2 )
	local Weight = Remap( MajorityOnTeam, 0.5 * #Players, #Players, 1, 0 )
	return self:ScaleGroupWeighting( Weight )
end

function TeamOptimiser:UpdateWeighting( CurrentWeight, Group, Player, NewTeam )
	if not Group then return CurrentWeight end

	-- Update the weighting by subtracting the old weight for this group and adding its new weight.
	-- This is much cheaper than recomputing all group weights.
	local NewWeight = self:GetGroupWeighting( Group, Player, NewTeam )
	local NewTotalWeight = CurrentWeight - self.GroupWeights[ Group ] + NewWeight
	return NewTotalWeight, NewWeight
end

function TeamOptimiser:RecomputeGroupWeighting( Team1Player, Team2Player )
	local CurrentWeight = self.CurrentPotentialState.PlayWithFriendsWeighting
	local Group1, Group1Weighting = self.GroupsByPlayer[ Team1Player ]
	local Group2, Group2Weighting = self.GroupsByPlayer[ Team2Player ]

	if Group1 == Group2 then
		-- Same group, so swapping players around will have no effect on the weighting.
		return CurrentWeight
	end

	-- Different groups, simulate them separately.
	if Group1 then
		CurrentWeight, Group1Weighting = self:UpdateWeighting( CurrentWeight, Group1, Team1Player, 2 )
	end

	if Group2 then
		CurrentWeight, Group2Weighting = self:UpdateWeighting( CurrentWeight, Group2, Team2Player, 1 )
	end

	return CurrentWeight, Group1, Group1Weighting, Group2, Group2Weighting
end

--[[
	Simulates a single swap (or move if index 2 is > team 2's size) of players.

	If the swap passes our criteria for improving the difference in average/standard deviation,
	then the swap is added to our potential swaps list.
]]
function TeamOptimiser:SimulateSwap( Team1Player, Team2Player )
	local SwapContext = self.SwapContext
	local Indices = SwapContext.Indices
	local Players = SwapContext.Players

	Indices[ 1 ] = Team1Player
	Indices[ 2 ] = Team2Player

	Players[ 1 ] = self.TeamMembers[ 1 ][ Team1Player ]
	Players[ 2 ] = self.TeamMembers[ 2 ][ Team2Player ]

	-- Get the before and after stats for this swap.
	self:SnapshotStats( 1, SwapContext )
	self:SnapshotStats( 2, SwapContext )

	local PlayWithFriendsWeight, Group1, Group1Weighting, Group2, Group2Weighting =
		self:RecomputeGroupWeighting( Players[ 1 ], Players[ 2 ] )

	local PostData = SwapContext.PostData
	local AverageDiffAfter = Difference( PostData, "Average" )
	local StdDiff = Difference( PostData, "StandardDeviation" )
	local TeamPreferenceWeight = PostData[ 1 ].TeamPreferenceWeighting + PostData[ 2 ].TeamPreferenceWeighting

	local Permitted, Cost = self:SwapPassesRequirements( AverageDiffAfter, StdDiff,
		TeamPreferenceWeight, PlayWithFriendsWeight )
	if not Permitted then return end

	self.SwapCount = self.SwapCount + 1
	local Swap = self:GetSwap( self.SwapCount )
	for i = 1, 2 do
		Swap.Indices[ i ] = Indices[ i ]
		Swap.Players[ i ] = Players[ i ]
		Swap.Totals[ i ] = PostData[ i ].Total
	end
	Swap.AverageDiff = AverageDiffAfter
	Swap.StdDiff = StdDiff
	Swap.Cost = Cost
	Swap.TeamPreferenceWeighting = TeamPreferenceWeight
	Swap.PlayWithFriendsWeighting = PlayWithFriendsWeight
	Swap.Group1 = Group1
	Swap.Group1Weighting = Group1Weighting
	Swap.Group2 = Group2
	Swap.Group2Weighting = Group2Weighting
end

--[[
	Caches the initial standard deviation of both teams, if required.
]]
function TeamOptimiser:CacheStats()
	self.StandardDeviationCache = self.StandardDeviationCache or {}

	local PreferenceWeight = 0
	for i = 1, 2 do
		local StdDev, TeamPref = self:GetPlayerStats( self.TeamMembers[ i ],
			self.TeamSkills[ i ].Average, i )
		self.StandardDeviationCache[ i ] = StdDev
		PreferenceWeight = PreferenceWeight + TeamPref
	end

	self.InitialTeamPreferenceWeighting = PreferenceWeight
end

--[[
	Tries to swap the player held at PlayerIndex in the larger team, with every
	player in the smaller team.

	If the best swap in these is better than the current swap, it is set as the
	current best swap.
]]
function TeamOptimiser:TrySwaps( PlayerIndex, Pass )
	local TeamMembers = self.TeamMembers

	local LargerTeamNum = self.LargerTeam
	local LesserTeamNum = self.LesserTeam

	local LargerTeam = TeamMembers[ LargerTeamNum ]
	local LesserTeam = TeamMembers[ LesserTeamNum ]

	local Player = LargerTeam[ PlayerIndex ]
	if not Player or not self:IsValidForSwap( Player, Pass, LargerTeamNum ) then return end

	local TakeSwapImmediately = self.TakeSwapImmediately
	-- Check every player on the other team against this player for a better swap.
	for OtherPlayerIndex = 1, #LesserTeam do
		local OtherPlayer = LesserTeam[ OtherPlayerIndex ]

		if OtherPlayer and self:IsValidForSwap( OtherPlayer, Pass, LesserTeamNum ) then
			if LargerTeamNum == 1 then
				self:SimulateSwap( PlayerIndex, OtherPlayerIndex )
			else
				self:SimulateSwap( OtherPlayerIndex, PlayerIndex )
			end

			if TakeSwapImmediately and self.SwapCount > 0 then
				return
			end
		end
	end

	-- Nothing left to try if team numbers are equal.
	if self.TeamsAreEqual then return end

	-- Otherwise, try adding this player to the smaller team without a swap.
	if LargerTeamNum == 1 then
		self:SimulateSwap( PlayerIndex, #LesserTeam + 1 )
	else
		self:SimulateSwap( #LesserTeam + 1, PlayerIndex )
	end
end

TeamOptimiser.RESULT_TERMINATE = 1
TeamOptimiser.RESULT_NEXTPASS = 2

function TeamOptimiser:SwapPassesRequirements( AverageDiff, StdDiff, TeamPreferenceWeight, PlayWithFriendsWeight )
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

function TeamOptimiser:CommitGroupWeighting( Group, Weighting )
	if Group then
		self.GroupWeights[ Group ] = Weighting
	end
end

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

	-- Use the configured comparator to rank the swaps in descending order of improvement.
	if not self.TakeSwapImmediately then
		TableSort( SwapBuffer, self.Comparator )
	end

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
			self.TeamLookup[ SwapPly ] = i
		end

		TeamSkills[ i ].Total = OptimalSwap.Totals[ i ]
		if TeamSkills[ i ].Count == 0 then
			TeamSkills[ i ].Average = 0
		else
			TeamSkills[ i ].Average = TeamSkills[ i ].Total / TeamSkills[ i ].Count
		end
	end

	self.CurrentPotentialState.Cost = OptimalSwap.Cost
	self.CurrentPotentialState.TeamPreferenceWeighting = OptimalSwap.TeamPreferenceWeighting
	self.CurrentPotentialState.PlayWithFriendsWeighting = OptimalSwap.PlayWithFriendsWeighting

	self:CommitGroupWeighting( OptimalSwap.Group1, OptimalSwap.Group1Weighting )
	self:CommitGroupWeighting( OptimalSwap.Group2, OptimalSwap.Group2Weighting )

	-- If an average tolerance is set, and we're now less-equal to it, stop completely.
	if self.AverageValueTolerance > 0 and Difference( TeamSkills, "Average" ) <= self.AverageValueTolerance then
		self.CurrentPotentialState.AverageDiffBefore = OptimalSwap.AverageDiff
		self.CurrentPotentialState.StdDiffBefore = OptimalSwap.StdDiff
		return self.RESULT_TERMINATE
	end
end

function TeamOptimiser:ComputeInitialGroupWeightings()
	local PlayerGroups = self.PlayerGroups
	local TotalWeight = 0
	for i = 1, #PlayerGroups do
		local Weight = self:GetGroupWeighting( PlayerGroups[ i ] )
		self.GroupWeights[ PlayerGroups[ i ] ] = Weight
		TotalWeight = TotalWeight + Weight
	end
	return TotalWeight
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

	local TakeSwapImmediately = self.TakeSwapImmediately

	while Iterations < 1000 do
		self:CacheStats()
		self.SwapCount = 0

		-- Pre-populate the current pre-swap data.
		for TeamNumber = 1, 2 do
			local PreData = SwapContext.PreData[ TeamNumber ]
			PreData.Average = self.TeamSkills[ TeamNumber ].Average
			PreData.StandardDeviation = self.StandardDeviationCache[ TeamNumber ]
		end

		self.CurrentPotentialState.AverageDiffBefore = Difference( SwapContext.PreData, "Average" )
		self.CurrentPotentialState.StdDiffBefore = Difference( SwapContext.PreData, "StandardDeviation" )
		self.CurrentPotentialState.TeamPreferenceWeighting = self.InitialTeamPreferenceWeighting

		-- Try swapping every player on the larger team, with every player on the smaller team.
		for i = 1, #TeamMembers[ self.LargerTeam ] do
			self:TrySwaps( i, Pass )

			if TakeSwapImmediately and self.SwapCount > 0 then
				break
			end
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
	-- Compute initial group weighting upfront. We only incrementally change it afterwards.
	self.CurrentPotentialState.PlayWithFriendsWeighting = self:ComputeInitialGroupWeightings()

	for Pass = 1, self:GetNumPasses() do
		if self:PerformOptimisationPass( Pass ) then break end
	end
end

return TeamOptimiser
