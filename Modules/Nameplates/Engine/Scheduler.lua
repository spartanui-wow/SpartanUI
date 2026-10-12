local _, ns = ...
local P = ns.Plates

-- Shared timing (6.5): no plate ever has its own OnUpdate. One hidden driver frame runs only
-- while it has work:
--   * repeating tasks on a shared 0.1 s tick (mouseover leave check, kick mark alpha, fact poller)
--   * eases (target size and alpha, cast fade, interrupted flash), updated every frame
--   * a once-per-frame layout queue: settings mark plates dirty, each plate lays out once
--   * next-frame jobs that coalesce by id
--   * after-combat jobs for anything combat lockdown blocks (plate size, secure CVars)
-- The frame is created on first use, so loading this file creates nothing.

---@class Plates.Scheduler
local Scheduler = { tasks = {}, eases = {}, layout = {}, nextFrame = {}, afterCombat = {}, elapsed = 0 }
P.Scheduler = Scheduler

Scheduler.TICK = 0.1

local frame

local function HasWork()
	return next(Scheduler.tasks) ~= nil or next(Scheduler.eases) ~= nil or next(Scheduler.layout) ~= nil or next(Scheduler.nextFrame) ~= nil
end

local function Smooth(t)
	return t * t * (3 - 2 * t)
end

local function RunSafe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		P.log.error('Scheduled job failed: ' .. tostring(err))
		if geterrorhandler then
			geterrorhandler()(err)
		end
	end
end

local function OnUpdate(self, elapsed)
	local now = P.services.GetTime()

	if next(Scheduler.nextFrame) then
		local jobs = Scheduler.nextFrame
		Scheduler.nextFrame = {}
		for _, fn in pairs(jobs) do
			RunSafe(fn)
		end
	end

	if next(Scheduler.layout) then
		local plates = Scheduler.layout
		Scheduler.layout = {}
		for plate in pairs(plates) do
			if plate.Layout then
				RunSafe(plate.Layout, plate)
			end
		end
	end

	for id, ease in pairs(Scheduler.eases) do
		local t = ease.duration > 0 and (now - ease.start) / ease.duration or 1
		if t >= 1 then
			Scheduler.eases[id] = nil
			RunSafe(ease.apply, ease.to)
			if ease.done then
				RunSafe(ease.done)
			end
		else
			RunSafe(ease.apply, ease.from + (ease.to - ease.from) * Smooth(t))
		end
	end

	Scheduler.elapsed = Scheduler.elapsed + elapsed
	if Scheduler.elapsed >= Scheduler.TICK then
		Scheduler.elapsed = 0
		for _, task in pairs(Scheduler.tasks) do
			if now >= task.due then
				task.due = now + task.interval
				RunSafe(task.fn, now)
			end
		end
	end

	if not HasWork() then
		self:Hide()
	end
end

local function Wake()
	if not frame then
		frame = CreateFrame('Frame')
		frame:Hide()
		frame:SetScript('OnUpdate', OnUpdate)
	end
	frame:Show()
end

---Run fn every `interval` seconds (at least the 0.1 s tick) until cancelled.
---@param id string
---@param interval number
---@param fn fun(now: number)
function Scheduler:Every(id, interval, fn)
	self.tasks[id] = { interval = math.max(interval, self.TICK), fn = fn, due = P.services.GetTime() + interval }
	Wake()
end

---@param id string
function Scheduler:Cancel(id)
	self.tasks[id] = nil
end

---@param id string
---@return boolean
function Scheduler:IsRunning(id)
	return self.tasks[id] ~= nil
end

---Ease a number from `from` to `to`. A new ease with the same id replaces the old one.
---@param id string Use one id per plate and property, e.g. tostring(plate) .. 'alpha'
---@param from number
---@param to number
---@param duration number Seconds
---@param apply fun(value: number)
---@param done? fun()
function Scheduler:Ease(id, from, to, duration, apply, done)
	if duration <= 0 or from == to then
		self.eases[id] = nil
		apply(to)
		if done then
			done()
		end
		return
	end
	self.eases[id] = { from = from, to = to, duration = duration, start = P.services.GetTime(), apply = apply, done = done }
	Wake()
end

---@param id string
function Scheduler:StopEase(id)
	self.eases[id] = nil
end

---Lay a plate out once on the next frame (plate:Layout()), however often it is marked.
---@param plate table
function Scheduler:QueueLayout(plate)
	self.layout[plate] = true
	Wake()
end

---Run fn on the next frame; repeated calls with the same id collapse into one run.
---@param id string
---@param fn fun()
function Scheduler:NextFrame(id, fn)
	self.nextFrame[id] = fn
	Wake()
end

---Run fn now, or after combat when combat lockdown blocks it. Repeated ids collapse.
---@param id string
---@param fn fun()
function Scheduler:AfterCombat(id, fn)
	if InCombatLockdown and InCombatLockdown() then
		self.afterCombat[id] = fn
		return
	end
	self.afterCombat[id] = nil
	RunSafe(fn)
end

function Scheduler:FlushAfterCombat()
	local jobs = self.afterCombat
	self.afterCombat = {}
	for _, fn in pairs(jobs) do
		RunSafe(fn)
	end
end

function Scheduler:Enable()
	P:RegisterEvent('PLAYER_REGEN_ENABLED', 'Scheduler', function()
		Scheduler:FlushAfterCombat()
	end)
end

function Scheduler:Disable()
	P:UnregisterEvent('PLAYER_REGEN_ENABLED', 'Scheduler')
	P.util.Wipe(self.tasks)
	P.util.Wipe(self.eases)
	P.util.Wipe(self.layout)
	P.util.Wipe(self.nextFrame)
	P.util.Wipe(self.afterCombat)
	if frame then
		frame:Hide()
	end
end
