local HttpService = game:GetService("HttpService")
local DataManager = {}
local CONFIG_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/config.json"

function DataManager.Load()
    local okFetch, rawBody = pcall(function() return game:HttpGet(CONFIG_URL) end)
    if not okFetch then return nil end

    local okDecode, config = pcall(function() return HttpService:JSONDecode(rawBody) end)
    if not okDecode then return nil end

    for _, loc in ipairs(config.Locations) do
        local c = loc.Coords
        loc.CFrame = CFrame.new(c[1], c[2], c[3])
    end
    return config
end

return DataManager
