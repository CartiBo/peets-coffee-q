-- Jujutsu Adaptive Combat loader (Jujutsu Shenanigans, PlaceId 9391468976). No autoexec needed.
-- Downloads current.luau + pvp modules into memory and runs them; does not touch local files.
local BASE = "https://raw.githubusercontent.com/CartiBo/peets-coffee-q/main/jujutsu-adaptive-combat/"
if game.PlaceId ~= 9391468976 then warn("[JAC] Wrong place: " .. tostring(game.PlaceId)) return end
local BOM = string.char(239, 187, 191)
local function fetch(path)
    local src = game:HttpGet(BASE .. path .. "?t=" .. os.time())
    return (src:gsub("^" .. BOM, ""))
end
local cache = {}
for _, name in ipairs({"combos", "dynamic", "panel", "movement", "moveset_data"}) do
    cache["pvp/" .. name .. ".luau"] = fetch("pvp/" .. name .. ".luau")
end
local main = fetch("current.luau")
local realReadfile = readfile
local shim = setmetatable({
    readfile = function(path)
        return cache[path] or realReadfile(path)
    end,
}, {__index = getfenv(0), __newindex = getfenv(0)})
local chunk, err = loadstring(main, "@JAC_current")
assert(chunk, err)
setfenv(chunk, shim)
chunk()