--!strict
-- Pure sliding-window rate limiter: at most `maxPerSecond` allowed calls in any 1 s window.
local RateLimit = {}
RateLimit.__index = RateLimit

export type Limiter = typeof(setmetatable({} :: { max: number, stamps: { number } }, RateLimit))

function RateLimit.new(maxPerSecond: number): Limiter
	return setmetatable({ max = maxPerSecond, stamps = {} }, RateLimit)
end

function RateLimit.allow(self: Limiter, now: number): boolean
	local stamps = self.stamps
	while stamps[1] ~= nil and stamps[1] <= now - 1 do
		table.remove(stamps, 1)
	end
	if #stamps >= self.max then
		return false
	end
	table.insert(stamps, now)
	return true
end

return RateLimit
