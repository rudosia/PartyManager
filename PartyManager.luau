--!strict

--[[
	PartyManager Module
	Created by: park_112

	A type-safe and robust party management system for Roblox.

	Features:
	
	- Create and manage isolated Party objects
	- Strictly typed parameters and methods using Luau typing
	- Built-in dynamic signal dispatching for player additions, departures, leader changes, and disbanding
	- Global reverse-lookup optimization to map players back to active groups
	- Automatic leader promotion logic and server-wide cleanup handling

	Usage:

	PartyManager.new(leader, maxPlayers) -> Party
		- Instantiates a brand new Party object with a designated leader.
		- Args:
			* leader (Player) - The player instance who initializes and owns the party
			* maxPlayers (number?) - Optional capacity cap limitation (Defaults to 4)
		- Returns:
			* Party object

	PartyManager.GetPlayerParty(player) -> Party?
		- Globally queries and returns the active party object a player belongs to, if any.

	Party:AddPlayer(player) -> boolean
		- Adds a player to the party. Returns false if party is full or player is already in a party.
 
	Party:RemovePlayer(player)
		- Removes a player from the party. Automatically handles new leader promotions or disbands if empty.

	Party:SetLeader(newLeader) -> boolean
		- Reassigns the party leader to another existing party member. Returns false if player isn't in the party.

	Party:HasPlayer(player) -> boolean
		- Returns true if the targeted player is currently part of the group object, otherwise false.

	Party:GetPlayers() -> {Player}
		- Returns a clean array containing all current Player instances currently inside the party.

	Party:IsFull() -> boolean
		- Returns true if the party's current member count has reached its defined max capacity.

	Party:Disband()
		- Instantly dissolves the party, clearing internal memory matrices and destroying tracking signals.

	Usage Example:

	local PartyManager = require(path.To.PartyManager)

	-- Create a new party for a player with a 3-player maximum limit
	local myParty = PartyManager.new(somePlayer, 3)

	-- Hook up listeners to respond to structural change signals
	myParty.PlayerAdded:Connect(function(joinedPlayer)
		print(joinedPlayer.Name .. " joined the lobby room!")
	end)

	myParty.LeaderChanged:Connect(function(newLeader, previousLeader)
		print("The leader changed from " .. previousLeader.Name .. " to " .. newLeader.Name)
	end)

	myParty.PlayerRemoved:Connect(function(leftPlayer)
		print(leftPlayer.Name .. " left. Current leader is: " .. myParty.Leader.Name)
	end)

	-- Check status and add a friend
	if not myParty:IsFull() then
		myParty:AddPlayer(friendPlayer)
	end

--]]

local HttpService = game:GetService("HttpService")

-- Types
export type Party = {
	Id: string,
	Leader: Player,
	MaxPlayers: number,

	-- Events
	PlayerAdded: RBXScriptSignal,
	PlayerRemoved: RBXScriptSignal,
	LeaderChanged: RBXScriptSignal,
	Disbanded: RBXScriptSignal,

	-- Methods
	AddPlayer: (self: Party, player: Player) -> boolean,
	RemovePlayer: (self: Party, player: Player) -> (),
	SetLeader: (self: Party, newLeader: Player) -> boolean,
	HasPlayer: (self: Party, player: Player) -> boolean,
	GetPlayers: (self: Party) -> {Player},
	IsFull: (self: Party) -> boolean,
	Disband: (self: Party) -> ()
}

type InternalParty = Party & {
	_members: { [Player]: boolean },
	_memberCount: number,
	_playerAddedEvent: BindableEvent,
	_playerRemovedEvent: BindableEvent,
	_leaderChangedEvent: BindableEvent,
	_disbandedEvent: BindableEvent,
	_isDisbanded: boolean,

	_setLeaderInternal: (self: InternalParty, player: Player) -> ()
}

local PartyManager = {}
local PartyFunc = {} :: InternalParty
PartyFunc.__index = PartyFunc

-- Track global state cleanly to prevent players from joining multiple parties simultaneously
local PlayerToPartyMap: { [Player]: Party } = setmetatable({}, { __mode = "k" })

-- Global lookup utility
function PartyManager.GetPlayerParty(player: Player): Party?
	return PlayerToPartyMap[player]
end

-- Constructor
function PartyManager.new(leader: Player, maxPlayers: number?): Party
	assert(typeof(leader) == "Instance" and leader:IsA("Player"), "PartyManager.new: Leader must be a Player Instance.")

	if PlayerToPartyMap[leader] then
		error("PartyManager: This player is already in an active party. Leave that party first.", 2)
	end

	local playerAddedEvent = Instance.new("BindableEvent")
	local playerRemovedEvent = Instance.new("BindableEvent")
	local leaderChangedEvent = Instance.new("BindableEvent")
	local disbandedEvent = Instance.new("BindableEvent")

	local self = setmetatable({
		Id = HttpService:GenerateGUID(false),
		Leader = leader,
		MaxPlayers = maxPlayers or 4,

		PlayerAdded = playerAddedEvent.Event,
		PlayerRemoved = playerRemovedEvent.Event,
		LeaderChanged = leaderChangedEvent.Event,
		Disbanded = disbandedEvent.Event,

		_members = {},
		_memberCount = 0,
		_playerAddedEvent = playerAddedEvent,
		_playerRemovedEvent = playerRemovedEvent,
		_leaderChangedEvent = leaderChangedEvent,
		_disbandedEvent = disbandedEvent,
		_isDisbanded = false
	}, PartyFunc) :: any

	-- Add the leader implicitly
	self:_addInternal(leader)

	return self
end

-- Internal addition handler
function PartyFunc:_addInternal(player: Player): boolean
	if self._isDisbanded then return false end
	if self._memberCount >= self.MaxPlayers then return false end
	if self._members[player] then return false end

	self._members[player] = true
	self._memberCount += 1
	PlayerToPartyMap[player] = self

	return true
end

-- Internal helper to safely update the leader property and fire the change signal
function PartyFunc:_setLeaderInternal(player: Player)
	local oldLeader = self.Leader
	if oldLeader == player then return end

	self.Leader = player
	self._leaderChangedEvent:Fire(player, oldLeader)
end

-- Public Methods
function PartyFunc:AddPlayer(player: Player): boolean
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Party:AddPlayer: Expected a Player Instance.")

	if PlayerToPartyMap[player] then
		warn("PartyManager: Player is already assigned to a party.")
		return false
	end

	local success = self:_addInternal(player)
	if success then
		self._playerAddedEvent:Fire(player)
	end
	return success
end

function PartyFunc:RemovePlayer(player: Player)
	if self._isDisbanded then return end
	if not self._members[player] then return end

	self._members[player] = nil
	self._memberCount -= 1

	if PlayerToPartyMap[player] == self then
		PlayerToPartyMap[player] = nil
	end

	self._playerRemovedEvent:Fire(player)

	-- Edge Case: Handle Leader departure
	if self.Leader == player then
		if self._memberCount > 0 then
			-- Promote the next available player to leader
			local nextLeader: Player? = nil
			for member in pairs(self._members) do
				nextLeader = member
				break
			end
			if nextLeader then
				self:_setLeaderInternal(nextLeader)
			end
		else
			-- No members left, collapse the party
			self:Disband()
		end
	elseif self._memberCount == 0 then
		self:Disband()
	end
end

function PartyFunc:SetLeader(newLeader: Player): boolean
	assert(typeof(newLeader) == "Instance" and newLeader:IsA("Player"), "Party:SetLeader: Expected a Player Instance.")

	if self._isDisbanded then return false end
	if not self._members[newLeader] then 
		warn("PartyManager: Cannot assign leader. Player is not in this party.")
		return false 
	end

	if self.Leader == newLeader then return true end

	self:_setLeaderInternal(newLeader)
	return true
end

function PartyFunc:HasPlayer(player: Player): boolean
	return self._members[player] == true
end

function PartyFunc:GetPlayers(): {Player}
	local list = {}
	for player in pairs(self._members) do
		table.insert(list, player)
	end
	return list
end

function PartyFunc:IsFull(): boolean
	return self._memberCount >= self.MaxPlayers
end

function PartyFunc:Disband()
	if self._isDisbanded then return end
	self._isDisbanded = true

	self._disbandedEvent:Fire()

	-- Clean up global lookup tracking
	for player in pairs(self._members) do
		if PlayerToPartyMap[player] == self then
			PlayerToPartyMap[player] = nil
		end
	end

	-- Clear data references
	table.clear(self._members)
	self._memberCount = 0

	-- Destroy internal engine wrappers to prevent memory leaks
	self._playerAddedEvent:Destroy()
	self._playerRemovedEvent:Destroy()
	self._leaderChangedEvent:Destroy()
	self._disbandedEvent:Destroy()
end

-- Clear out cache arrays automatically if players drop physical connectivity mid-session
game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
	local party = PlayerToPartyMap[player]
	if party then
		party:RemovePlayer(player)
	end
end)

return PartyManager
