--- === MicDuck ===
---
--- Turn music down while any app is using the microphone.
---
--- When an input device opens, Spotify and Apple Music (whichever are
--- running) fade down to `MicDuck.duckTo` percent; when it closes, they fade
--- back to where they were. CoreAudio tells Hammerspoon when a mic's "in use"
--- state changes, so nothing polls for it.
---
--- Download: [https://github.com/dabeeeenster/micduck](https://github.com/dabeeeenster/micduck)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "MicDuck"
obj.version = "1.0"
obj.author = "Ben Rometsch"
obj.homepage = "https://github.com/dabeeeenster/micduck"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- MicDuck.duckTo
--- Variable
--- Volume, in percent of the player's own volume, to fade down to while the mic is in use. Default 50.
obj.duckTo = 50

--- MicDuck.fadeDuration
--- Variable
--- Seconds each fade takes. Default 0.2.
obj.fadeDuration = 0.2

--- MicDuck.fadeSteps
--- Variable
--- Volume steps in each fade. Default 10.
obj.fadeSteps = 10

--- MicDuck.rescanInterval
--- Variable
--- Seconds between checks for newly connected mics, e.g. AirPods. Default 30.
obj.rescanInterval = 30

--- MicDuck.players
--- Variable
--- Players to duck: AppleScript name and bundle ID. Each must have a `sound volume` property.
obj.players = {
    { name = "Spotify", bundleID = "com.spotify.client" },
    { name = "Music", bundleID = "com.apple.Music" },
}

obj.logger = hs.logger.new("MicDuck")

local SETTINGS_KEY = "MicDuck.saved"

local saved = {}     -- player name -> volume before ducking
local fades = {}     -- player name -> hs.timer
local mics = {}      -- device UID -> hs.audiodevice, kept so their watchers live
local ducked = false
local rescanTimer = nil

local function isRunning(p)
    return #hs.application.applicationsForBundleID(p.bundleID) > 0
end

-- Only ever called for a running player, so AppleScript never launches it
-- or asks where an uninstalled app is.
local function tell(p, command)
    local ok, result = hs.osascript.applescript(
        string.format('tell application "%s" to %s', p.name, command))
    if not ok then obj.logger.w(p.name .. ": " .. hs.inspect(result)) end
    return ok and result or nil
end

local function save(name, volume)
    saved[name] = volume
    hs.settings.set(SETTINGS_KEY, saved)
end

-- Step the volume from wherever it is now to target, replacing any fade
-- already running on that player so a quick on/off/on just turns around.
local function fade(p, target, done)
    if fades[p.name] then fades[p.name]:stop() end
    local start = tell(p, "get sound volume")
    if not start then return end
    local step = 0
    fades[p.name] = hs.timer.doEvery(obj.fadeDuration / obj.fadeSteps, function()
        step = step + 1
        tell(p, "set sound volume to " .. math.floor(start + (target - start) * step / obj.fadeSteps + 0.5))
        if step == obj.fadeSteps then
            fades[p.name]:stop()
            fades[p.name] = nil
            if done then done() end
        end
    end)
end

local function duck()
    for _, p in ipairs(obj.players) do
        if isRunning(p) then
            if saved[p.name] == nil then
                local v = tell(p, "get sound volume")
                if v and v > obj.duckTo then save(p.name, v) end
            end
            if saved[p.name] then
                obj.logger.i("mic on: " .. p.name .. " " .. saved[p.name] .. " -> " .. obj.duckTo)
                fade(p, obj.duckTo)
            end
        end
    end
end

local function restore(instant)
    for _, p in ipairs(obj.players) do
        local v = saved[p.name]
        if v and isRunning(p) then
            obj.logger.i("mic off: " .. p.name .. " -> " .. v)
            if instant then
                if fades[p.name] then fades[p.name]:stop(); fades[p.name] = nil end
                tell(p, "set sound volume to " .. v)
                save(p.name, nil)
            else
                fade(p, v, function() save(p.name, nil) end)
            end
        elseif v then
            save(p.name, nil)
        end
    end
end

local function micInUse()
    for _, mic in pairs(mics) do
        if mic:inUse() then return true end
    end
    return false
end

local function update()
    local busy = micInUse()
    if busy == ducked then return end
    ducked = busy
    if busy then duck() else restore() end
end

-- Watch every input device, so it doesn't matter which mic an app picks.
-- Hammerspoon's device-list watcher is a single global callback that other
-- configs often own, so new devices are picked up by a slow rescan instead.
local function rescan()
    local seen = {}
    for _, dev in ipairs(hs.audiodevice.allInputDevices()) do
        local uid = dev:uid()
        seen[uid] = true
        if not mics[uid] then
            dev:watcherCallback(function(_, event)
                if event == "gone" then update() end
            end)
            dev:watcherStart()
            mics[uid] = dev
        end
    end
    for uid, dev in pairs(mics) do
        if not seen[uid] then
            dev:watcherStop()
            mics[uid] = nil
        end
    end
    update()
end

--- MicDuck:start()
--- Method
--- Start watching the microphones.
function obj:start()
    -- Volumes saved before a reload: put them back if the mic has since closed.
    saved = hs.settings.get(SETTINGS_KEY) or {}
    rescan()
    if not ducked then restore(true) end
    rescanTimer = hs.timer.doEvery(self.rescanInterval, rescan)
    return self
end

--- MicDuck:stop()
--- Method
--- Stop watching and put any ducked players straight back.
function obj:stop()
    if rescanTimer then rescanTimer:stop(); rescanTimer = nil end
    for uid, dev in pairs(mics) do
        dev:watcherStop()
        mics[uid] = nil
    end
    restore(true)
    ducked = false
    return self
end

return obj
