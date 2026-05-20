PartyManager Module Created by: park_112/rudosia

A type-safe and robust party management system for Roblox.

Features:

* Create and manage isolated Party objects
* Strictly typed parameters and methods using Luau typing
* Built-in dynamic signal dispatching for player additions, departures, leader changes, and disbanding
* Global reverse-lookup optimization to map players back to active groups
* Automatic leader promotion logic and server-wide cleanup handling

Usage:

PartyManager.new(leader, maxPlayers)

* Instantiates a brand new Party object with a designated leader.
- Args:
  * leader (Player) - The player instance who initializes and owns the party
  * maxPlayers (number?) - Optional capacity cap limitation (Defaults to 4)

- Returns:
  * Party object



PartyManager.GetPlayerParty(player) -> Party?

* Globally queries and returns the active party object a player belongs to, if any.

Party:AddPlayer(player) -> boolean

* Adds a player to the party. Returns false if party is full or player is already in a party.

Party:RemovePlayer(player)

* Removes a player from the party. Automatically handles new leader promotions or disbands if empty.

Party:SetLeader(newLeader) -> boolean

* Reassigns the party leader to another existing party member. Returns false if player isn't in the party.

Party:HasPlayer(player) -> boolean

* Returns true if the targeted player is currently part of the group object, otherwise false.

Party:GetPlayers() -> {Player}

* Returns a clean array containing all current Player instances currently inside the party.

Party:IsFull() -> boolean

* Returns true if the party's current member count has reached its defined max capacity.

Party:Disband()

* Instantly dissolves the party, clearing internal memory matrices and destroying tracking signals.

Usage Example:

```
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

```
