-- Host-side ballot tally. One vote per peer id, changeable until the ballot
-- resolves. The host's own vote uses the peer id "host".
local Votes = {}

local ballot_id = 0
local option_count = 0
local by_peer = {}

Votes.open = function (id, count)
	ballot_id = id
	option_count = count
	by_peer = {}
end

Votes.close = function ()
	option_count = 0
	by_peer = {}
end

Votes.ballot_id = function ()
	return ballot_id
end

-- Returns true when the vote was accepted (right ballot, valid option).
Votes.cast = function (id, peer_id, option)
	if id ~= ballot_id or option_count == 0 then
		return false
	end

	option = math.floor(option)

	if option < 1 or option > option_count then
		return false
	end

	by_peer[peer_id] = option

	return true
end

Votes.remove_peer = function (peer_id)
	by_peer[peer_id] = nil
end

-- One scratch table is reused: the HUD asks for the counts every frame on the host (through
-- Director.view), and a fresh table per call was steady garbage. Every caller reads the result
-- immediately and never keeps it, so sharing it is safe.
local counts = {}

Votes.counts = function ()
	for i = 1, option_count do
		counts[i] = 0
	end

	for i = #counts, option_count + 1, -1 do
		counts[i] = nil
	end

	for _, option in pairs(by_peer) do
		counts[option] = counts[option] + 1
	end

	return counts
end

-- Index of the winning option (random among ties), or nil when nobody voted.
Votes.winner = function ()
	local counts = Votes.counts()
	local best, leaders = 0, {}

	for i = 1, #counts do
		if counts[i] > best then
			best = counts[i]
			leaders = { i }
		elseif counts[i] == best and best > 0 then
			leaders[#leaders + 1] = i
		end
	end

	if best == 0 then
		return nil
	end

	return leaders[math.random(1, #leaders)]
end

return Votes
