--!optimize 2

local Config = {
    WindowName = "Plot Manager",
    Color = Color3.fromRGB(100, 180, 255),
    Keybind = Enum.KeyCode.RightBracket,
    DefaultNpc = "Lil Alien",
    DefaultPattern = "spiral",
    DefaultEggCount = 1,
    HeightOffset = 15,
    BatchSize = 100,
}

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/juywvm/ui-libs/refs/heads/main/Bracket_V3_Ui_Library/Bracketv3UiLibrary"))()
local Window = Library:CreateWindow({ WindowName = Config.WindowName, Color = Config.Color, Keybind = Config.Keybind }, game:GetService("CoreGui"))

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local NpcStash = Instance.new("Folder")
NpcStash.Name = "NpcStash"
NpcStash.Parent = RS

local npcHidden = false

local childConnAdded = nil

local function comma(n)
    local s = tostring(math.floor(n))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- plot helpers

local function getplot()
    local name = tostring(lp) .. "'s Plot"
    for _, v in ipairs(workspace.Plots:GetDescendants()) do
        if v:IsA("Model") and v.Name == "PlayerSign" and v.Main.SurfaceGui.TextLabel.Text == name then
            return v.Parent
        end
    end
end

local function plotmid(plane, floor)
    local p = getplot().Building.floors[floor].CFrame.Position
    return plane == "X" and p.X or plane == "Y" and p.Y or p.Z
end

local function plotsize(plane, floor)
    local s = getplot().Building.floors[floor].Size
    return plane == "X" and s.X or plane == "Y" and s.Y or s.Z
end

-- npc hiding

local function hideNPCs()
    npcHidden = true
    local builds = getplot().Builds
    for _, npc in pairs(builds:GetChildren()) do
        npc.Parent = NpcStash
    end
    if childAddedConn then childAddedConn:Disconnect() end
    childAddedConn = builds.ChildAdded:Connect(function(npc)
        if npcHidden then npc.Parent = NpcStash end
    end)
end

local function showNPCs()
    npcHidden = false
    if childAddedConn then childAddedConn:Disconnect() childAddedConn = nil end
    local builds = getplot().Builds
    for _, npc in pairs(NpcStash:GetChildren()) do
        npc.Parent = builds
    end
end

-- farm

local function pickup()
    local wasHidden = npcHidden
    if wasHidden then showNPCs() end

    local npcs = getplot().Builds:GetChildren()
    for _, npc in ipairs(npcs) do
        if npc and npc.Parent then
            RS.events.pickUp:FireServer(tostring(npc))
        end
    end

    if wasHidden then
        task.wait(0.5)
        for _, npc in pairs(NpcStash:GetChildren()) do
            if not npc.Parent then npc:Destroy() end
        end
        hideNPCs()
    end
end

local function collect()
    local wasHidden = npcHidden
    if wasHidden then showNPCs() end

    local npcs = getplot().Builds:GetChildren()
    for _, npc in ipairs(npcs) do
        if npc and npc.Parent then
            RS.events.collect:FireServer(tostring(npc))
        end
    end

    if wasHidden then
        task.wait(0.5)
        for _, npc in pairs(NpcStash:GetChildren()) do
            if not npc.Parent then npc:Destroy() end
        end
        hideNPCs()
    end
end

-- hotbar

local function gethotbar()
    local items = {}
    for _, v in pairs(lp.PlayerGui.ScreenGui.Hotbar:GetChildren()) do
        local amtLabel = v:FindFirstChild("amount")
        if amtLabel then
            local amt = tonumber(amtLabel.Text:sub(2)) or 0
            if amt > 0 then
                table.insert(items, { name = v.Name, count = amt })
            end
        end
    end
    return items
end

local function maybeyield(i)
    if i % Config.BatchSize == 0 then task.wait() end
end

local function buildpositions(cx, cz, R, s)
    local positions = {}

    -- spiral layer first
    local i = 1
    while true do
        local r = i * s
        if r > R then break end
        local a = i * 0.04
        table.insert(positions, { cx + math.cos(a)*r, cz + math.sin(a)*r })
        i = i + 1
    end

    -- grid fills the rest of the plot
    local x = cx - R
    while x <= cx + R do
        local z = cz - R
        while z <= cz + R do
            local dx, dz = x - cx, z - cz
            if (dx*dx + dz*dz) <= R*R then
                -- only add if not already close to a spiral point
                table.insert(positions, { x, z })
            end
            z = z + s
        end
        x = x + s
    end

    return positions
end

-- build a set of known npc names from the hotbar for comparison
local function getnpcnames()
    local names = {}
    for _, v in pairs(lp.PlayerGui.ScreenGui.Hotbar:GetChildren()) do
        if v:IsA("GuiObject") then
            names[v.Name] = true
        end
    end
    return names
end

local function countinventory()
    local videos, npcs = 0, 0

    for _, v in pairs(lp.videosFolder.videos:GetChildren()) do
        videos = videos + v.Value
    end

    for _, v in pairs(lp.youtuberData.youtubers:GetChildren()) do
        npcs = npcs + v.Value
    end

    return videos, npcs
end

-- state

local selNpc     = Config.DefaultNpc
local selPattern = Config.DefaultPattern
local eggCount   = Config.DefaultEggCount
local selFloor   = 0
local selStep    = 0.5

-- placement
local function placespecial(ptype, npc)
    local cos, sin, sqrt, new, PI = math.cos, math.sin, math.sqrt, CFrame.new, math.pi
    local spawn = task.spawn
    local Event = RS.events.placeYoutuber

    local sX = plotsize("X", selFloor)
    local sZ = plotsize("Z", selFloor)
    local cx = plotmid("X", selFloor)
    local cy = plotmid("Y", selFloor)
    local cz = plotmid("Z", selFloor)

    if not sX or not sZ or not cx or not cy or not cz then
        print("couldn't read plot on floor " .. tostring(selFloor))
        return
    end

    cy = cy + Config.HeightOffset
    local R = math.min(sX, sZ) / 2 * 0.9
    local s = selStep

    local useAll = npc:lower() == "all"
    local npcQueue = {}

    if useAll then
        for _, item in ipairs(gethotbar()) do
            for _ = 1, item.count do
                table.insert(npcQueue, item.name)
            end
        end
        if #npcQueue == 0 then print("hotbar is empty") return end
    end

    local function getnpc(i)
        if not useAll then return npc end
        return npcQueue[((i - 1) % #npcQueue) + 1]
    end

   local getpos

    if ptype == "spiral" then
        getpos = function(i)
            local r = ((i * s - 0.001) % R) + 0.001 -- wraps back inward when hitting wall
            local a = i * 0.04
            return cx + cos(a)*r, cz + sin(a)*r
        end

    elseif ptype == "galaxy" then
        getpos = function(i)
            local r = math.min(sqrt(i) * s, R - 0.01)
            local wrapped = ((r - 0.001) % R) + 0.001
            return cx + cos(i * 0.05)*wrapped, cz + sin(i * 0.05)*wrapped
        end

    elseif ptype == "vortex" then
        getpos = function(i, opp)
            local r = ((i * s - 0.001) % R) + 0.001
            local a = i * 0.04
            if opp then
                return cx + cos(a+PI)*r, cz + sin(a+PI)*r
            end
            return cx + cos(a)*r, cz + sin(a)*r
        end

    elseif ptype == "sunflower" then
        local golden = PI * (3 - sqrt(5))
        getpos = function(i)
            local r = ((sqrt(i) * s - 0.001) % R) + 0.001
            return cx + cos(i*golden)*r, cz + sin(i*golden)*r
        end

    elseif ptype == "heart" then
        getpos = function(i, max)
            local t = i * (2*PI / max)
            local scale = R / 16
            return cx + 16*sin(t)^3*scale,
                   cz - (13*cos(t) - 5*cos(2*t) - 2*cos(3*t) - cos(4*t))*scale
        end

    elseif ptype == "helix" then
        getpos = function(i, max)
            local r = ((i * s - 0.001) % R) + 0.001
            return cx + cos(i*0.18)*r, cz + sin(i*0.18)*r
        end

    elseif ptype == "lissajous" then
        getpos = function(i, max)
            local t = i * (2*PI / max)
            return cx + cos(3*t)*R, cz + sin(2*t)*R
        end

    elseif ptype == "rose" then
        getpos = function(i, max)
            local a = i * (2*PI / max) * 5
            local r = cos(5 * (i/max) * PI) * R
            return cx + cos(a)*r, cz + sin(a)*r
        end
    end

    local max = useAll and #npcQueue or math.max(math.floor(R / s), 700)

    if ptype == "vortex" then
        local vmax = useAll and math.floor(#npcQueue/2) or math.floor(R/s)
        for i = 1, vmax do
            local x1, z1 = getpos(i, false)
            local x2, z2 = getpos(i, true)
            spawn(Event.InvokeServer, Event, getnpc(i),       new(x1, cy, z1), i,       "0")
            spawn(Event.InvokeServer, Event, getnpc(i+vmax),  new(x2, cy, z2), i+vmax,  "0")
            maybeyield(i)
        end

    elseif ptype == "rings" then
        local rings, idx = math.max(math.floor(R / (s*5)), 1), 1
        for ring = 1, rings do
            local r = ring * (R / rings)
            local count = ring * 10
            for j = 1, count do
                if useAll and idx > #npcQueue then break end
                local a = (j / count) * 2*PI
                spawn(Event.InvokeServer, Event, getnpc(idx), new(cx+cos(a)*r, cy, cz+sin(a)*r), idx, "0")
                maybeyield(idx)
                idx = idx + 1
            end
            if useAll and idx > #npcQueue then break end
        end

    elseif ptype == "pentagram" then
        local pts, order, idx = {}, {1,3,5,2,4,1}, 1
        local perSeg = math.floor(max / 5)
        for i = 1, 5 do
            local a = (i/5) * 2*PI - PI/2
            pts[i] = { x = cx + cos(a)*R, z = cz + sin(a)*R }
        end
        for seg = 1, 5 do
            local a, b = pts[order[seg]], pts[order[seg+1]]
            for j = 0, perSeg do
                local t = j/perSeg
                spawn(Event.InvokeServer, Event, getnpc(idx), new(a.x+(b.x-a.x)*t, cy, a.z+(b.z-a.z)*t), idx, "0")
                maybeyield(idx)
                idx = idx + 1
            end
        end

    else
        -- all other patterns use getpos
        for i = 1, max do
            local x, z = getpos(i, max)
            spawn(Event.InvokeServer, Event, getnpc(i), new(x, cy, z), i, "0")
            maybeyield(i)
        end
    end
end

local function placeall()
    local items = gethotbar()
    if #items == 0 then print("nothing in hotbar") return end

    local Event = RS.events.placeYoutuber
    local cx = plotmid("X", selFloor)
    local cy = plotmid("Y", selFloor) + Config.HeightOffset
    local cz = plotmid("Z", selFloor)
    local R = math.min(plotsize("X", selFloor), plotsize("Z", selFloor)) / 2 * 0.9

    local step = 0.1
    local gridCols = math.floor((R * 2) / step)
    local fallbackX, fallbackZ = cx - R, cz - R

    local function spiralpos(i)
        return cx + math.cos(i * 0.1) * (i * step), cz + math.sin(i * 0.1) * (i * step)
    end

    local function gridpos(i)
        return fallbackX + (i % gridCols) * step, fallbackZ + math.floor(i / gridCols) * step
    end

    local queue = {}
    local idx, fallbackIdx = 1, 0
    for _, item in ipairs(items) do
        for _ = 1, item.count do
            local x, z
            if idx * step <= R then
                x, z = spiralpos(idx)
            else
                x, z = gridpos(fallbackIdx)
                fallbackIdx = fallbackIdx + 1
            end
            table.insert(queue, { name = item.name, cf = CFrame.new(x, cy, z), idx = idx })
            idx = idx + 1
        end
    end

    local pos = 0
    local function next()
        pos = pos + 1
        local entry = queue[pos]
        if not entry then return end
        task.spawn(function()
            Event:InvokeServer(entry.name, entry.cf, entry.idx, "0")
            next()
        end)
    end

    for _ = 1, Config.BatchSize do
        if pos < #queue then next() end
    end
end

-- tabs

local TabPlot     = Window:CreateTab("Plot")
local TabFarm     = Window:CreateTab("Farm")
local TabGamepass = Window:CreateTab("Misc")
local TabSettings = Window:CreateTab("Settings")


local SecGamepass = TabGamepass:CreateSection("Gamepasses")
local SecNPCs    = TabPlot:CreateSection("NPCs")
local SecSetup   = TabPlot:CreateSection("Patterns")
local SecFloor   = TabPlot:CreateSection("Floor")
local SecActions = TabFarm:CreateSection("Actions")
local SecShop    = TabFarm:CreateSection("Shop")
local SecInv     = TabFarm:CreateSection("Inventory")
local SecEggs    = TabFarm:CreateSection("Eggs")
local SecMenu    = TabSettings:CreateSection("Menu")
local SecBG      = TabSettings:CreateSection("Background")

-- plot tab - npcs

SecNPCs:CreateToggle("Hide NPCs", false, function(state)
    if state then hideNPCs() else showNPCs() end
end):AddToolTip("Parents NPCs out of workspace so they don't render")

local uiConn = nil
local uiHidden = false

local function toggleNpcUI(state)
    uiHidden = state
    for _, npc in pairs(getplot().Builds:GetChildren()) do
        local ui = npc:FindFirstChild("youtuberUI")
        if ui then ui.Enabled = not state end
    end
    for _, npc in pairs(NpcStash:GetChildren()) do
        local ui = npc:FindFirstChild("youtuberUI")
        if ui then ui.Enabled = not state end
    end
    if uiConn then uiConn:Disconnect() uiConn = nil end
    if state then
        uiConn = getplot().Builds.ChildAdded:Connect(function(npc)
            task.spawn(function()
                local ui = npc:WaitForChild("youtuberUI", 10)
                if ui then ui.Enabled = false end
            end)
        end)
    end
end

SecNPCs:CreateToggle("Hide NPC UI", false, function(state)
    toggleNpcUI(state)
end):AddToolTip("Disables the UI on each NPC, reduces lag without fully hiding them")

SecNPCs:CreateButton("Place All From Hotbar", function()
    task.spawn(placeall)
end):AddToolTip("Places all hotbar NPCs onto the plot")

-- plot tab - floor

local FloorLabel = SecFloor:CreateLabel("Current Floor: 0")

SecFloor:CreateTextBox("Floor Number", "0", true, function(v)
    local n = tonumber(v)
    if n then
        selFloor = n
        FloorLabel:UpdateText("Current Floor: " .. n)
    end
end):AddToolTip("Which floor to place NPCs on (0 = ground)")

SecFloor:CreateButton("Reset to Ground", function()
    selFloor = 0
    FloorLabel:UpdateText("Current Floor: 0")
end):AddToolTip("Snaps back to floor 0")

-- plot tab - patterns

SecSetup:CreateTextBox("NPC Name", Config.DefaultNpc, false, function(v)
    selNpc = v ~= "" and v or Config.DefaultNpc
end):AddToolTip("NPC to place, or type 'all' to use your whole hotbar")

SecSetup:CreateSlider("NPC Spacing", 0.01, 2, nil, false, function(v)
    selStep = v
end):SetValue(0.5)

local PatternDrop = SecSetup:CreateDropdown("Pattern", {
    "spiral","galaxy","vortex","sunflower","heart",
    "helix","rings","lissajous","rose","pentagram"
}, function(v)
    selPattern = v
end)
PatternDrop:SetOption(Config.DefaultPattern)

SecSetup:CreateButton("Place Pattern", function()
    task.spawn(placespecial, selPattern, selNpc)
end):AddToolTip("Places the selected pattern on your plot")

SecSetup:CreateButton("Read Plot Size", function()
    local ok, msg = pcall(function()
        local sX, sZ = plotsize("X", selFloor), plotsize("Z", selFloor)
        return ("Size: %dx%d  |  R: %.1f"):format(sX, sZ, math.min(sX,sZ)/2*0.9)
    end)
    print(ok and msg or "Couldn't read plot, are you on your plot?")
end):AddToolTip("Prints plot dimensions to console")

-- farm tab

SecActions:CreateButton("Pickup All", pickup):AddToolTip("Picks up all NPCs")
SecActions:CreateButton("Collect All", collect):AddToolTip("Collects from all NPCs")
SecActions:CreateButton("Pickup + Collect", function() collect() pickup() end):AddToolTip("Does both at once")

local EggBox = SecEggs:CreateTextBox("Egg Count", tostring(Config.DefaultEggCount), true, function(v)
    eggCount = tonumber(v) or eggCount
end)
EggBox:AddToolTip("How many eggs to open, no limit")

SecEggs:CreateButton("Open Eggs", function()
    RS.events.openEventEgg:FireServer(eggCount)
end):AddToolTip("Opens the entered amount of eggs (leave and rejoin to skin animations)")

local CrateLabel = SecEggs:CreateLabel("Event Eggs: -")

SecEggs:CreateButton("Refresh Egg Count", function()
    CrateLabel:UpdateText("Event Eggs: " .. comma(lp.event.Crates3.Value))
end):AddToolTip("Reads your current event egg count")

SecEggs:CreateButton("Open All Event Eggs", function()
    local count = lp.event.Crates3.Value
    if count <= 0 then print("no event eggs") return end
    RS.events.openEventEgg:FireServer(count)
    CrateLabel:UpdateText("Event Eggs: 0")
end):AddToolTip("Opens every event egg you have")

-- shop

local buyName = "Lil Alien"
local buyAmount = 1

SecShop:CreateTextBox("NPC Name", "Lil Alien", false, function(v)
    buyName = v ~= "" and v or buyName
end):AddToolTip("Name of the NPC to buy")

SecShop:CreateTextBox("Amount", "1", true, function(v)
    buyAmount = tonumber(v) or buyAmount
end):AddToolTip("How many to buy, no limit")

SecShop:CreateButton("Buy", function()
    for _ = 1, buyAmount do
        RS.events.buyYoutuber:FireServer(tostring(buyName))
    end
end):AddToolTip("Buys the set amount of the NPC")

local VideoLabel  = SecInv:CreateLabel("Videos: -")
local NpcLabel    = SecInv:CreateLabel("NPCs: -")
local TotalLabel  = SecInv:CreateLabel("Total: -")

SecInv:CreateButton("Refresh", function()
    local ok, videos, npcs = pcall(function()
        return countinventory()
    end)
    if ok then
        local total = videos + npcs
        VideoLabel:UpdateText("Videos: " .. comma(videos))
        NpcLabel:UpdateText("NPCs: "   .. comma(npcs))
        TotalLabel:UpdateText("Total: " .. comma(videos + npcs))
    else
        VideoLabel:UpdateText("Videos: error")
        NpcLabel:UpdateText("NPCs: error")
        TotalLabel:UpdateText("couldn't read inventory")
    end
end):AddToolTip("Reads your inventory and counts videos vs NPCs")

local gpValues = lp.gamepassValues

local gpList = {
    { name = "Auto Collect",       key = "autoCollect" },
    { name = "Auto Upload",        key = "autoUpload" },
    { name = "Auto Rebirth",       key = "autoRebirth" },
    { name = "Infinite Rebirths",  key = "infiniteRebirths" },
    { name = "View Bot",           key = "viewBot" },
    { name = "x2 Videos",         key = "x2Videos" },
    { name = "x2 Cash",           key = "x2Cash" },
    { name = "Luck",               key = "luck" },
    { name = "VIP",                key = "VIP" },
}

for _, gp in ipairs(gpList) do
    local toggle = SecGamepass:CreateToggle(gp.name, gpValues[gp.key].Value, function(state)
        gpValues[gp.key].Value = state
    end)
    toggle:AddToolTip("Toggle " .. gp.name .. " gamepass effect")
end

-- settings tab

local UIToggle = SecMenu:CreateToggle("Show UI", nil, function(state)
    Window:Toggle(state)
end)
UIToggle:CreateKeybind(tostring(Config.Keybind):gsub("Enum.KeyCode.", ""), function(key)
    Config.Keybind = Enum.KeyCode[key]
end)
UIToggle:SetState(true)

local UIColor = SecMenu:CreateColorpicker("Accent Color", function(color)
    Window:ChangeColor(color)
end)
UIColor:UpdateColor(Config.Color)

local BGs = {
    Default            = "2151741365",
    Hearts             = "6073763717",
    Abstract           = "6073743871",
    Hexagon            = "6073628839",
    Circles            = "6071579801",
    ["Lace & Flowers"] = "6071575925",
    Floral             = "5553946656",
}

local bgNames = {}
for k in pairs(BGs) do table.insert(bgNames, k) end

SecBG:CreateDropdown("Image", bgNames, function(name)
    Window:SetBackground(BGs[name])
end):SetOption("Default")

local BGColor = SecBG:CreateColorpicker("Tint", function(color)
    Window:SetBackgroundColor(color)
end)
BGColor:UpdateColor(Color3.new(1,1,1))

SecBG:CreateSlider("Transparency", 0, 1, nil, false, function(v)
    Window:SetBackgroundTransparency(v)
end):SetValue(0)

SecBG:CreateSlider("Tile Scale", 0, 1, nil, false, function(v)
    Window:SetTileScale(v)
end):SetValue(0.5)

local SecMisc    = TabSettings:CreateSection("Misc")
local SecChar    = TabSettings:CreateSection("Character")
local SecPerf    = TabSettings:CreateSection("Performance")

-- misc

SecMisc:CreateButton("Rejoin", function()
    game:GetService("TeleportService"):Teleport(game.PlaceId, lp)
end):AddToolTip("Rejoins the current game")

SecMisc:CreateButton("Server Hop", function()
    local servers = game:GetService("HttpService"):JSONDecode(
        game:GetService("HttpService"):GetAsync("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100")
    )
    local current = game.JobId
    for _, s in pairs(servers.data) do
        if s.id ~= current and s.playing < s.maxPlayers then
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, s.id, lp)
            return
        end
    end
    print("no other servers found")
end):AddToolTip("Teleports you to a different server")

SecMisc:CreateButton("Copy Plot Name", function()
    setclipboard(tostring(lp) .. "'s Plot")
    print("copied!")
end):AddToolTip("Copies your plot name to clipboard")

SecMisc:CreateButton("Copy Job ID", function()
    setclipboard(game.JobId)
    print("copied!")
end):AddToolTip("Copies the current server ID to clipboard")

-- character

SecChar:CreateButton("Reset Character", function()
    lp.Character:FindFirstChildOfClass("Humanoid").Health = 0
end):AddToolTip("Resets your character")


local antiAfk = false
local afkConn

SecChar:CreateToggle("Anti-AFK", false, function(state)
    antiAfk = state
    if state then
        afkConn = game:GetService("RunService").Heartbeat:Connect(function()
            game:GetService("VirtualUser"):CaptureController()
            game:GetService("VirtualUser"):ClickButton2(Vector2.new())
        end)
    else
        if afkConn then afkConn:Disconnect() afkConn = nil end
    end
end):AddToolTip("Prevents you from being kicked for inactivity")

local walkspeedDefault = 21
SecChar:CreateSlider("Walk Speed", 1, 100, nil, true, function(v)
    if lp.Character and lp.Character:FindFirstChildOfClass("Humanoid") then
        lp.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = v
    end
end):SetValue(walkspeedDefault)

SecChar:CreateSlider("Jump Power", 1, 200, nil, true, function(v)
    if lp.Character and lp.Character:FindFirstChildOfClass("Humanoid") then
        lp.Character:FindFirstChildOfClass("Humanoid").JumpPower = v
    end
end):SetValue(50)

-- performance

SecPerf:CreateSlider("FPS Cap", 15, 240, nil, true, function(v)
    game:GetService("RunService"):Set3dRenderingEnabled(true)
    setfpscap(v)
end):SetValue(240)

SecPerf:CreateToggle("Low Latency Mode", false, function(state)
    game:GetService("RunService"):Set3dRenderingEnabled(not state)
end):AddToolTip("Disables 3D rendering to reduce lag while farming")

SecPerf:CreateSlider("Graphics Quality", 1, 21, nil, true, function(v)
    settings().Rendering.QualityLevel = v
end):SetValue(settings().Rendering.QualityLevel.Value)
