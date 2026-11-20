--[[
  KXY — URBAN RELOAD
  KeyGate  → getkeybackend.vercel.app
  Verify   → adminpanel-kxy.vercel.app
  v19.0 | Weapon Under Box (CS2-style) + Minimap Removed + FPS Boost Rework (no-lag)
]]

local GETKEY_SERVER = "https://getkeybackend.vercel.app"
local VERIFY_SERVER = "https://adminpanel-kxy.vercel.app"
local DISCORD_LINK  = "https://discord.gg/YxpZy2Nrj8"

-- ═══════════════════════════════════════════════════════════
--  KEY GATE
-- ═══════════════════════════════════════════════════════════
local function runKeyGate()
    local Players          = game:GetService("Players")
    local HttpService      = game:GetService("HttpService")
    local UserInputService = game:GetService("UserInputService")
    local lp               = Players.LocalPlayer or Players.PlayerAdded:Wait()

    local httpRequest = (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
    if type(httpRequest) ~= "function" then
        warn("[KeyGate] No HTTP function available.")
        return false
    end

    local function apiPost(base, route, payload)
        local ok, res = pcall(httpRequest, {
            Url     = base .. route,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(payload),
        })
        if not ok or type(res) ~= "table" then return nil, "Network error." end
        local dok, data = pcall(function()
            return HttpService:JSONDecode(res.Body or res.body or "")
        end)
        if not dok or type(data) ~= "table" then return nil, "Bad server response." end
        local code = tonumber(res.StatusCode or res.Status or 200) or 200
        if code < 200 or code >= 300 then
            return nil, data.error or data.reason or ("HTTP " .. code)
        end
        return data
    end

    local uiParent
    if type(gethui) == "function" then
        local ok, r = pcall(gethui)
        if ok and r then uiParent = r end
    end
    uiParent = uiParent or lp:WaitForChild("PlayerGui")

    local SG = Instance.new("ScreenGui")
    SG.Name = "CortexKeyGate" SG.ResetOnSpawn = false
    SG.IgnoreGuiInset = true SG.DisplayOrder = 999999
    SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling SG.Parent = uiParent

    -- panel cao hơn 1 chút để chứa nút Discord
    local panel = Instance.new("Frame")
    panel.Name = "Panel" panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5) panel.Size = UDim2.new(0, 340, 0, 345)
    panel.BackgroundColor3 = Color3.fromRGB(14, 12, 28) panel.BorderSizePixel = 0
    panel.ClipsDescendants = true panel.Parent = SG
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
    local stroke = Instance.new("UIStroke", panel)
    stroke.Color = Color3.fromRGB(120, 90, 220) stroke.Transparency = 0.4 stroke.Thickness = 1.5
    local bg = Instance.new("UIGradient", panel)
    bg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(18,14,40)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(26,20,58)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14,18,46)),
    }) bg.Rotation = 135
    local accentBar = Instance.new("Frame", panel)
    accentBar.Size = UDim2.new(1,0,0,3) accentBar.Position = UDim2.new(0,0,0,0)
    accentBar.BorderSizePixel = 0 accentBar.BackgroundColor3 = Color3.fromRGB(130,90,255)
    local abg = Instance.new("UIGradient", accentBar)
    abg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(80,60,200)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160,90,255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80,60,200)),
    }) abg.Rotation = 0
    local logo = Instance.new("TextLabel", panel)
    logo.Size = UDim2.new(1,0,0,44) logo.Position = UDim2.new(0,0,0,10)
    logo.BackgroundTransparency = 1 logo.Text = "KXY"
    logo.TextColor3 = Color3.fromRGB(255,255,255) logo.Font = Enum.Font.GothamBold
    logo.TextSize = 26 logo.TextXAlignment = Enum.TextXAlignment.Center logo.ZIndex = 4
    local sub = Instance.new("TextLabel", panel)
    sub.Size = UDim2.new(1,0,0,20) sub.Position = UDim2.new(0,0,0,52)
    sub.BackgroundTransparency = 1 sub.Text = "KEY AUTHENTICATION"
    sub.TextColor3 = Color3.fromRGB(140,110,220) sub.Font = Enum.Font.Gotham
    sub.TextSize = 11 sub.TextXAlignment = Enum.TextXAlignment.Center sub.ZIndex = 4
    local div = Instance.new("Frame", panel)
    div.Size = UDim2.new(1,-48,0,1) div.Position = UDim2.new(0,24,0,76)
    div.BorderSizePixel = 0 div.BackgroundColor3 = Color3.fromRGB(90,70,160)
    div.BackgroundTransparency = 0.5

    local function mkBox(placeholder, posY)
        local box = Instance.new("TextBox", panel)
        box.Size = UDim2.new(1,-48,0,40) box.Position = UDim2.new(0,24,0,posY)
        box.BackgroundColor3 = Color3.fromRGB(22,18,48) box.BorderSizePixel = 0
        box.PlaceholderText = placeholder box.PlaceholderColor3 = Color3.fromRGB(100,85,150)
        box.Text = "" box.TextColor3 = Color3.fromRGB(230,220,255)
        box.TextSize = 13 box.Font = Enum.Font.Gotham box.ClearTextOnFocus = false
        box.TextXAlignment = Enum.TextXAlignment.Left box.TextWrapped = false box.ZIndex = 5
        Instance.new("UICorner", box).CornerRadius = UDim.new(0,10)
        local s = Instance.new("UIStroke", box)
        s.Color = Color3.fromRGB(100,75,200) s.Transparency = 0.55 s.Thickness = 1
        local p = Instance.new("UIPadding", box)
        p.PaddingLeft = UDim.new(0,12) p.PaddingRight = UDim.new(0,12)
        return box
    end
    local function mkBtn(text, posY, primary)
        local c = primary and Color3.fromRGB(100,65,220) or Color3.fromRGB(50,42,100)
        local btn = Instance.new("TextButton", panel)
        btn.Size = UDim2.new(1,-48,0,40) btn.Position = UDim2.new(0,24,0,posY)
        btn.BackgroundColor3 = c btn.BorderSizePixel = 0 btn.Text = text
        btn.TextColor3 = Color3.fromRGB(255,255,255) btn.TextSize = 13
        btn.Font = Enum.Font.GothamBold btn.AutoButtonColor = false btn.ZIndex = 5
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,10)
        local g = Instance.new("UIGradient", btn)
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, c:Lerp(Color3.new(1,1,1),0.15)),
            ColorSequenceKeypoint.new(1, c),
        }) g.Rotation = 90
        local s = Instance.new("UIStroke", btn)
        s.Color = primary and Color3.fromRGB(160,120,255) or Color3.fromRGB(90,80,150)
        s.Transparency = 0.5 s.Thickness = 1
        btn.MouseEnter:Connect(function() btn.BackgroundColor3 = c:Lerp(Color3.new(1,1,1),0.12) end)
        btn.MouseLeave:Connect(function() btn.BackgroundColor3 = c end)
        return btn
    end
    local function mkStatus(posY)
        local f = Instance.new("Frame", panel)
        f.Size = UDim2.new(1,-48,0,36) f.Position = UDim2.new(0,24,0,posY)
        f.BackgroundColor3 = Color3.fromRGB(16,13,36) f.BorderSizePixel = 0 f.ZIndex = 4
        Instance.new("UICorner", f).CornerRadius = UDim.new(0,10)
        local s = Instance.new("UIStroke", f)
        s.Color = Color3.fromRGB(80,60,160) s.Transparency = 0.6 s.Thickness = 1
        local lbl = Instance.new("TextLabel", f)
        lbl.Size = UDim2.fromScale(1,1) lbl.BackgroundTransparency = 1
        lbl.Text = "Waiting for key..." lbl.TextColor3 = Color3.fromRGB(180,160,240)
        lbl.Font = Enum.Font.Gotham lbl.TextSize = 11 lbl.TextWrapped = true
        lbl.TextXAlignment = Enum.TextXAlignment.Center lbl.TextYAlignment = Enum.TextYAlignment.Center
        lbl.ZIndex = 5
        return lbl
    end

    local keyBox     = mkBox("Paste your key here...", 90)
    local getBtn     = mkBtn("GET KEY", 140, false)
    local verifyBtn  = mkBtn("VERIFY KEY", 190, true)
    local statusLabel = mkStatus(242)

    -- ── Discord button ──
    local discordBtn = Instance.new("TextButton", panel)
    discordBtn.Size = UDim2.new(1,-48,0,36)
    discordBtn.Position = UDim2.new(0,24,0,290)
    discordBtn.BackgroundColor3 = Color3.fromRGB(88,101,242)  -- Discord blurple
    discordBtn.BorderSizePixel = 0
    discordBtn.Text = ""
    discordBtn.AutoButtonColor = false
    discordBtn.ZIndex = 5
    Instance.new("UICorner", discordBtn).CornerRadius = UDim.new(0,10)
    local dg = Instance.new("UIGradient", discordBtn)
    dg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(100,115,255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(70,82,210)),
    }) dg.Rotation = 90
    local ds = Instance.new("UIStroke", discordBtn)
    ds.Color = Color3.fromRGB(130,145,255) ds.Transparency = 0.4 ds.Thickness = 1
    discordBtn.MouseEnter:Connect(function()
        discordBtn.BackgroundColor3 = Color3.fromRGB(100,115,255)
    end)
    discordBtn.MouseLeave:Connect(function()
        discordBtn.BackgroundColor3 = Color3.fromRGB(88,101,242)
    end)

    -- Discord logo (SVG-như dùng ImageLabel) + text
    local discordLayout = Instance.new("Frame", discordBtn)
    discordLayout.Size = UDim2.fromScale(1,1)
    discordLayout.BackgroundTransparency = 1
    discordLayout.ZIndex = 6
    -- Logo Discord dùng ImageLabel (Roblox asset của Discord icon)
    local dIcon = Instance.new("ImageLabel", discordLayout)
    dIcon.Size = UDim2.new(0,22,0,22)
    dIcon.Position = UDim2.new(0,12,0.5,-11)
    dIcon.BackgroundTransparency = 1
    -- Asset ID Discord logo trên Roblox catalog
    dIcon.Image = "rbxassetid://7733960981"
    dIcon.ImageColor3 = Color3.fromRGB(255,255,255)
    dIcon.ZIndex = 7
    local dText = Instance.new("TextLabel", discordLayout)
    dText.Size = UDim2.new(1,-42,1,0)
    dText.Position = UDim2.new(0,42,0,0)
    dText.BackgroundTransparency = 1
    dText.Text = "SERVER DISCORD"
    dText.TextColor3 = Color3.fromRGB(255,255,255)
    dText.Font = Enum.Font.GothamBold
    dText.TextSize = 13
    dText.TextXAlignment = Enum.TextXAlignment.Center
    dText.ZIndex = 7

    discordBtn.Activated:Connect(function()
        local ok = pcall(function()
            game:GetService("GuiService"):OpenBrowserWindow(DISCORD_LINK)
        end)
        if not ok then
            local clip = setclipboard or toclipboard
            if clip then pcall(function() clip(DISCORD_LINK) end) end
        end
    end)

    -- ── Drag ──
    local dragInput, dragStart, startPos
    logo.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragInput = inp dragStart = inp.Position startPos = panel.Position
        end
    end)
    logo.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement
        or inp.UserInputType == Enum.UserInputType.Touch then dragInput = inp end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragInput and inp == dragInput and dragStart and startPos then
            local d = inp.Position - dragStart
            panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragInput, dragStart, startPos = nil, nil, nil
        end
    end)

    local authorized = false
    local busy = false

    getBtn.Activated:Connect(function()
        if busy then return end
        busy = true getBtn.Text = "CREATING LINK..."
        statusLabel.Text = "Connecting to key server..."
        task.spawn(function()
            local data, err = apiPost(GETKEY_SERVER, "/api/start", { userId = tostring(lp.UserId) })
            if data and data.ok and data.shortUrl then
                local clip = setclipboard or toclipboard
                local copied = clip and pcall(function() clip(data.shortUrl) end)
                local opened = pcall(function() game:GetService("GuiService"):OpenBrowserWindow(data.shortUrl) end)
                if copied then statusLabel.Text = "Link copied! Complete in browser."
                elseif opened then statusLabel.Text = "Browser opened. Copy clipboard manually."
                else statusLabel.Text = "Link: " .. tostring(data.shortUrl) end
            else statusLabel.Text = err or "Failed to create key link." end
            getBtn.Text = "GET KEY" busy = false
        end)
    end)

    verifyBtn.Activated:Connect(function()
        if busy then return end
        local key = (keyBox.Text or ""):match("^%s*(.-)%s*$")
        if key == "" then statusLabel.Text = "Paste your key first." return end
        busy = true verifyBtn.Text = "VERIFYING..." statusLabel.Text = "Checking key..."
        task.spawn(function()
            local data, err = apiPost(VERIFY_SERVER, "/api/public/verify", { key = key })
            local valid = data and data.valid == true
            local reason = data and (data.reason or data.error) or err
            if not valid and data and data.reason == "not_found" then
                local ld, le = apiPost(GETKEY_SERVER, "/api/validate", { key=key, userId=tostring(lp.UserId) })
                if ld and ld.ok then valid = true
                else reason = (ld and ld.error) or le or reason end
            end
            if valid then
                authorized = true statusLabel.Text = "Key accepted. Loading..." SG:Destroy()
            else statusLabel.Text = "Rejected: " .. tostring(reason or "unknown") end
            verifyBtn.Text = "VERIFY KEY" busy = false
        end)
    end)

    while not authorized do
        if not SG.Parent then return false end
        task.wait(0.15)
    end
    return true
end

if not runKeyGate() then return end

-- ═══════════════════════════════════════════════════════════
--  CORE SERVICES
-- ═══════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp     = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════
--  WEAPON ICON SYSTEM
--  Dùng Drawing.Image + fetch ảnh thật từ web qua HttpService
--  Non-weapon (edrink, bandage...) → không hiện gì
--  Cache URL per tool name để không fetch lại
-- ═══════════════════════════════════════════════════════════
local NON_WEAPON_KW = {
    "edrink","drink","energy drink","bandage","heal","medkit","med","kit",
    "potion","food","water","boost","interact","throwable","binoculars",
    "phone","radio","map","flashlight","camera",
}
local function isNonWeapon(name)
    if not name then return true end
    local n = name:lower()
    for _, kw in ipairs(NON_WEAPON_KW) do
        if n:find(kw, 1, true) then return true end
    end
    return false
end

-- v19: weapon URL fetch system removed — weapon name shown as text label (CS2 style)

-- ═══════════════════════════════════════════════════════════
--  CONFIG
-- ═══════════════════════════════════════════════════════════
local CFG = {
    -- Aim
    fov           = 150,
    aimDist       = 550,
    aimOn         = true,
    wallCheck     = true,
    foliageBypass = true,
    stretchX      = 0.75,  -- auto-set sẽ override bên dưới (0.75–1.00)
    trackSpeed    = 0.45,
    flickThreshold = 55,
    flickSpeed     = 0.58,
    flickEaseTime  = 0.25,
    smoothSpeed    = 0.45,
    headOffsetY    = 1.107,
    neckOffsetY    = 0.673,
    neckOffsetX    = 0.020,
    neckOffsetZ    = -0.028,
    velPredScale   = 0.065,
    velPredFadeIn  = 15,
    velSmooth      = 0.18,
    tapGapWindow   = 0.18,
    adaptTrack     = true,
    adaptMaxBoost  = 0.50,
    adaptVelRef    = 16,
    distBoostMax   = 18,
    distMaxBoost   = 0.06,
    vehTrackSpeed  = 0.88,
    vehPredScale   = 0.065,
    vehPredMin     = 1.5,
    headTopBias    = 0.0,
    -- ESP
    espOn          = true,
    espDist        = 650,
    espWeapon      = true,
    espSkeleton    = true,
    esp = {
        box      = Color3.fromRGB(255, 255, 255),
        skeleton = Color3.fromRGB(80,  200, 255),
        barBg    = Color3.fromRGB(30,  30,  30),
        barAlive = Color3.fromRGB(80,  220, 80),
        barLow   = Color3.fromRGB(220, 60,  60),
        weapon   = Color3.fromRGB(255, 220, 80),
        thick    = 1,
        boneThick = 1,
    },
    fov_circle = {
        color = Color3.fromRGB(255, 255, 255),
        thick = 1,
        sides = 64,
    },
    -- FPS Boost
    fpsBoost = {
        on             = false,
        shadowDisable  = true,
        textureQuality = true,
        distCull       = true,
        cullDist       = 200,
        particleOff    = true,
        decalOff       = false,
        lightingSimple = true,
    },
}

-- ═══════════════════════════════════════════════════════════
--  CONFIG PERSISTENCE v19
--  Lưu/load setting qua writefile/readfile (executor API)
--  File: kxy_config.json trong executor workspace
--
--  Chỉ serialize field user-tunable — không lưu internal state,
--  aim vectors, hay AntiAim timing. Color3 encode thành {r,g,b}.
--  Save debounce 2 giây: slider drag không spam disk write.
-- ═══════════════════════════════════════════════════════════
local CONFIG_FILE = "kxy_config.json"
local HttpService = game:GetService("HttpService")

-- Kiểm tra executor có writefile/readfile không
local canSave = type(writefile) == "function" and type(readfile) == "function"

-- ── Serialize helpers ──
local function encodeColor(c)
    if typeof(c) ~= "Color3" then return {r=255,g=255,b=255} end
    return { r=math.round(c.R*255), g=math.round(c.G*255), b=math.round(c.B*255) }
end
local function decodeColor(t)
    if type(t) ~= "table" then return nil end
    return Color3.fromRGB(t.r or 255, t.g or 255, t.b or 255)
end

-- ── Trích xuất chỉ các field cần lưu từ CFG ──
local function serializeCFG()
    return {
        -- Aim
        fov            = CFG.fov,
        aimDist        = CFG.aimDist,
        aimOn          = CFG.aimOn,
        wallCheck      = CFG.wallCheck,
        foliageBypass  = CFG.foliageBypass,
        stretchX       = CFG.stretchX,
        trackSpeed     = CFG.trackSpeed,
        -- ESP
        espOn          = CFG.espOn,
        espDist        = CFG.espDist,
        espWeapon      = CFG.espWeapon,
        espSkeleton    = CFG.espSkeleton,
        esp = {
            box      = encodeColor(CFG.esp.box),
            skeleton = encodeColor(CFG.esp.skeleton),
            barAlive = encodeColor(CFG.esp.barAlive),
            barLow   = encodeColor(CFG.esp.barLow),
            weapon   = encodeColor(CFG.esp.weapon),
            thick    = CFG.esp.thick,
            boneThick= CFG.esp.boneThick,
        },
        -- FPS Boost
        fpsBoost = {
            on             = CFG.fpsBoost.on,
            shadowDisable  = CFG.fpsBoost.shadowDisable,
            textureQuality = CFG.fpsBoost.textureQuality,
            distCull       = CFG.fpsBoost.distCull,
            cullDist       = CFG.fpsBoost.cullDist,
            particleOff    = CFG.fpsBoost.particleOff,
            decalOff       = CFG.fpsBoost.decalOff,
            lightingSimple = CFG.fpsBoost.lightingSimple,
        },
        -- Anti-Aim
        antiAimEnabled = AntiAim and AntiAim.enabled or true,
    }
end

-- ── Apply data đã load vào CFG (merge, không replace toàn bộ) ──
local function applySavedCFG(data)
    if type(data) ~= "table" then return end
    -- Aim
    if type(data.fov)           == "number"  then CFG.fov           = data.fov           end
    if type(data.aimDist)       == "number"  then CFG.aimDist       = data.aimDist       end
    if type(data.aimOn)         == "boolean" then CFG.aimOn         = data.aimOn         end
    if type(data.wallCheck)     == "boolean" then CFG.wallCheck     = data.wallCheck     end
    if type(data.foliageBypass) == "boolean" then CFG.foliageBypass = data.foliageBypass end
    if type(data.stretchX)      == "number"  then CFG.stretchX      = math.clamp(data.stretchX, 0.75, 1.00) end
    if type(data.trackSpeed)    == "number"  then CFG.trackSpeed    = data.trackSpeed    end
    -- ESP
    if type(data.espOn)         == "boolean" then CFG.espOn         = data.espOn         end
    if type(data.espDist)       == "number"  then CFG.espDist       = data.espDist       end
    if type(data.espWeapon)     == "boolean" then CFG.espWeapon     = data.espWeapon     end
    if type(data.espSkeleton)   == "boolean" then CFG.espSkeleton   = data.espSkeleton   end
    if type(data.esp) == "table" then
        local c = decodeColor(data.esp.box)      if c then CFG.esp.box      = c end
        local sk= decodeColor(data.esp.skeleton) if sk then CFG.esp.skeleton= sk end
        local ba= decodeColor(data.esp.barAlive) if ba then CFG.esp.barAlive= ba end
        local bl= decodeColor(data.esp.barLow)   if bl then CFG.esp.barLow  = bl end
        local wp= decodeColor(data.esp.weapon)   if wp then CFG.esp.weapon  = wp end
        if type(data.esp.thick)    == "number" then CFG.esp.thick    = data.esp.thick    end
        if type(data.esp.boneThick)== "number" then CFG.esp.boneThick= data.esp.boneThick end
    end
    -- FPS Boost
    if type(data.fpsBoost) == "table" then
        local fb = data.fpsBoost
        if type(fb.on)             == "boolean" then CFG.fpsBoost.on             = fb.on             end
        if type(fb.shadowDisable)  == "boolean" then CFG.fpsBoost.shadowDisable  = fb.shadowDisable  end
        if type(fb.textureQuality) == "boolean" then CFG.fpsBoost.textureQuality = fb.textureQuality end
        if type(fb.distCull)       == "boolean" then CFG.fpsBoost.distCull       = fb.distCull       end
        if type(fb.cullDist)       == "number"  then CFG.fpsBoost.cullDist       = fb.cullDist       end
        if type(fb.particleOff)    == "boolean" then CFG.fpsBoost.particleOff    = fb.particleOff    end
        if type(fb.decalOff)       == "boolean" then CFG.fpsBoost.decalOff       = fb.decalOff       end
        if type(fb.lightingSimple) == "boolean" then CFG.fpsBoost.lightingSimple = fb.lightingSimple end
    end
    -- Anti-Aim (AntiAim chưa defined tại thời điểm load, set sau)
    if type(data.antiAimEnabled) == "boolean" then
        -- store tạm, apply sau khi AntiAim được khởi tạo
        CFG._pendingAntiAim = data.antiAimEnabled
    end
end

-- ── Save (ghi file) ──
local _saveDebounce = false
local function saveConfig()
    if not canSave then return end
    if _saveDebounce then return end
    _saveDebounce = true
    task.delay(2, function()
        _saveDebounce = false
        local ok, err = pcall(function()
            local encoded = HttpService:JSONEncode(serializeCFG())
            writefile(CONFIG_FILE, encoded)
        end)
        if not ok then
            warn("[KXY] Config save failed: " .. tostring(err))
        end
    end)
end

-- ── Load (đọc file, apply ngay) ──
local function loadConfig()
    if not canSave then return end
    local ok, raw = pcall(readfile, CONFIG_FILE)
    if not ok or type(raw) ~= "string" or raw == "" then return end
    local dok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not dok or type(data) ~= "table" then
        warn("[KXY] Config file corrupt, using defaults.")
        return
    end
    applySavedCFG(data)
    print("[KXY] Config loaded from " .. CONFIG_FILE)
end

-- ── Reset về default (xóa file, reload script không cần thiết) ──
local CFG_DEFAULTS = {
    fov=150, aimDist=550, aimOn=true, wallCheck=true, foliageBypass=true,
    stretchX=0.75, trackSpeed=0.45,
    espOn=true, espDist=650, espWeapon=true, espSkeleton=true,
    esp={
        box=Color3.fromRGB(255,255,255), skeleton=Color3.fromRGB(80,200,255),
        barBg=Color3.fromRGB(30,30,30), barAlive=Color3.fromRGB(80,220,80),
        barLow=Color3.fromRGB(220,60,60), weapon=Color3.fromRGB(255,220,80),
        thick=1, boneThick=1,
    },
    fpsBoost={
        on=false, shadowDisable=true, textureQuality=true,
        distCull=true, cullDist=200, particleOff=true,
        decalOff=false, lightingSimple=true,
    },
}
local function resetConfig()
    -- Deep copy defaults vào CFG
    CFG.fov=CFG_DEFAULTS.fov  CFG.aimDist=CFG_DEFAULTS.aimDist
    CFG.aimOn=CFG_DEFAULTS.aimOn  CFG.wallCheck=CFG_DEFAULTS.wallCheck
    CFG.foliageBypass=CFG_DEFAULTS.foliageBypass
    CFG.stretchX=CFG_DEFAULTS.stretchX  CFG.trackSpeed=CFG_DEFAULTS.trackSpeed
    CFG.espOn=CFG_DEFAULTS.espOn  CFG.espDist=CFG_DEFAULTS.espDist
    CFG.espWeapon=CFG_DEFAULTS.espWeapon  CFG.espSkeleton=CFG_DEFAULTS.espSkeleton
    for k,v in pairs(CFG_DEFAULTS.esp) do CFG.esp[k]=v end
    for k,v in pairs(CFG_DEFAULTS.fpsBoost) do CFG.fpsBoost[k]=v end
    if AntiAim then AntiAim.enabled = true end
    -- Xóa file lưu
    if canSave then pcall(delfile, CONFIG_FILE) end
end

-- Load ngay khi script chạy
loadConfig()

-- ── Auto-detect stretchX từ setting đồ họa của game ──
-- Quality cao → ảnh đầy đủ (stretchX=1.0), quality thấp → stretched (0.75)
do
    local ok, ql = pcall(function() return settings().Rendering.QualityLevel end)
    if ok and ql then
        local lvl = tonumber(tostring(ql):match("%d+")) or 10
        -- Level 1-4 → máy yếu, game thường render ở aspect khác → stretchX=0.75
        -- Level 5-8 → trung → 0.85
        -- Level 9-21/Auto → máy khỏe → 1.0
        if lvl <= 4 then
            CFG.stretchX = 0.75
        elseif lvl <= 8 then
            CFG.stretchX = 0.85
        else
            CFG.stretchX = 1.0
        end
    end
    -- clamp về 0.75–1.00
    CFG.stretchX = math.clamp(CFG.stretchX, 0.75, 1.00)
end

local AntiAim = {
    enabled         = true,
    adStrafeEnabled = true,
    adStrafeMinTime = 0.22,
    adStrafeMaxTime = 0.38,
    _nextADStrafe   = 0,
    _adDir          = 1,
    _adVec          = nil,
}
-- Apply Anti-Aim setting từ config (load xảy ra trước AntiAim được tạo)
if CFG._pendingAntiAim ~= nil then
    AntiAim.enabled    = CFG._pendingAntiAim
    CFG._pendingAntiAim = nil
end

-- ═══════════════════════════════════════════════════════════
--  FPS BOOST ENGINE v19 — REWORK
--
--  Prinsip baru:
--  · Static pass (shadow / lighting / quality / decal) → chạy 1 lần khi toggle ON,
--    không lặp lại mỗi frame → zero overhead sau khi apply
--  · Particle pass → chạy 1 lần saat toggle + hook DescendantAdded untuk objek baru
--  · Distance cull pass → TIDAK lagi iterate seluruh workspace tiap 2 detik.
--    Simpan tabel part statik satu kali, update LTM hanya kalau karakter berpindah
--    > CULL_MOVE_THRESHOLD studs dari update terakhir
--  Hasil: bisa nyalain semua toggle sekaligus tanpa frame drop
-- ═══════════════════════════════════════════════════════════
local Lighting = game:GetService("Lighting")
local origSettings  = {}
local _descAddedCon = nil   -- koneksi DescendantAdded untuk particle hook
local _staticParts  = nil   -- cache tabel part statis untuk distance cull
local _lastCullPos  = Vector3.zero
local CULL_MOVE_THRESHOLD = 8  -- studs — cull ulang kalau pindah > ini

-- ── Helper: build tabel part statis (map geometry, bukan karakter) ──
local function buildStaticPartCache()
    _staticParts = {}
    -- Kumpulkan semua BasePart yang bukan milik player
    local playerChars = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then playerChars[pl.Character] = true end
    end
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") and not playerChars[v:FindFirstAncestorOfClass("Model")] then
            _staticParts[#_staticParts+1] = v
        end
    end
end

-- ── Pass: shadow + lighting + quality + decal (static, run-once) ──
local function applyStaticPass()
    local fb = CFG.fpsBoost
    -- save originals hanya sekali
    if not origSettings._saved then
        origSettings.GlobalShadows             = Lighting.GlobalShadows
        origSettings.ShadowSoftness            = Lighting.ShadowSoftness
        origSettings.Technology                = Lighting.Technology
        origSettings.EnvironmentDiffuseScale   = Lighting.EnvironmentDiffuseScale
        origSettings.EnvironmentSpecularScale  = Lighting.EnvironmentSpecularScale
        origSettings._saved = true
    end
    if fb.shadowDisable then
        Lighting.GlobalShadows  = false
        Lighting.ShadowSoftness = 0
    end
    if fb.lightingSimple then
        pcall(function() Lighting.Technology = Enum.Technology.Compatibility end)
        Lighting.EnvironmentDiffuseScale  = 0
        Lighting.EnvironmentSpecularScale = 0
    end
    if fb.textureQuality then
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    end
    if fb.decalOff then
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("Decal") or v:IsA("Texture") then
                pcall(function() v.Transparency = 1 end)
            end
        end
    end
end

-- ── Pass: particle off — run-once + DescendantAdded hook ──
local function applyParticlePass()
    local function killFX(v)
        if v:IsA("ParticleEmitter") or v:IsA("Beam")
        or v:IsA("Trail") or v:IsA("Smoke")
        or v:IsA("Fire") or v:IsA("Sparkles") then
            pcall(function() v.Enabled = false end)
        end
    end
    for _, v in ipairs(workspace:GetDescendants()) do killFX(v) end
    if _descAddedCon then _descAddedCon:Disconnect() end
    _descAddedCon = workspace.DescendantAdded:Connect(function(v)
        if CFG.fpsBoost.on and CFG.fpsBoost.particleOff then
            task.defer(function() killFX(v) end)
        end
    end)
end

-- ── Pass: distance cull — hanya re-iterate kalau karakter pindah cukup jauh ──
-- Panggil ini dari render loop, bukan applyFPSBoost
local function tickDistCull()
    local fb = CFG.fpsBoost
    if not fb.on or not fb.distCull then return end
    local myHRP = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    local myPos = myHRP.Position
    if (myPos - _lastCullPos).Magnitude < CULL_MOVE_THRESHOLD then return end
    _lastCullPos = myPos
    -- Build cache jika belum ada atau stale
    if not _staticParts then buildStaticPartCache() end
    local cullD = fb.cullDist
    local playerChars = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then playerChars[pl.Character] = true end
    end
    for i = #_staticParts, 1, -1 do
        local v = _staticParts[i]
        if not v or not v.Parent then
            -- sudah dihapus dari workspace, buang dari cache
            _staticParts[i] = _staticParts[#_staticParts]
            _staticParts[#_staticParts] = nil
        else
            -- jangan cull part yang baru jadi Character (spawn/despawn)
            if not playerChars[v:FindFirstAncestorOfClass("Model")] then
                pcall(function()
                    v.LocalTransparencyModifier = (v.Position - myPos).Magnitude > cullD and 1 or 0
                end)
            end
        end
    end
end

-- ── Master toggle ON ──
local function applyFPSBoost()
    local fb = CFG.fpsBoost
    if not fb.on then return end
    applyStaticPass()
    if fb.particleOff then applyParticlePass() end
    -- reset cull position agar pass pertama langsung jalan
    _lastCullPos = Vector3.zero
    _staticParts = nil   -- force rebuild cache
end

-- ── Master toggle OFF — restore semua ──
local function restoreFPSBoost()
    -- Static settings
    if origSettings._saved then
        Lighting.GlobalShadows            = origSettings.GlobalShadows
        Lighting.ShadowSoftness           = origSettings.ShadowSoftness
        Lighting.EnvironmentDiffuseScale  = origSettings.EnvironmentDiffuseScale
        Lighting.EnvironmentSpecularScale = origSettings.EnvironmentSpecularScale
        pcall(function() Lighting.Technology = origSettings.Technology end)
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end)
    end
    -- Particle restore
    if _descAddedCon then _descAddedCon:Disconnect() _descAddedCon = nil end
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter") or v:IsA("Beam")
        or v:IsA("Trail") or v:IsA("Smoke")
        or v:IsA("Fire") or v:IsA("Sparkles") then
            pcall(function() v.Enabled = true end)
        end
    end
    -- Decal restore
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Decal") or v:IsA("Texture") then
            pcall(function() v.Transparency = 0 end)
        end
    end
    -- Cull restore — pakai cache kalau ada, biar cepat
    local parts = _staticParts or workspace:GetDescendants()
    for _, v in ipairs(parts) do
        if v and v.Parent and v:IsA("BasePart") then
            pcall(function() v.LocalTransparencyModifier = 0 end)
        end
    end
    _staticParts = nil
    _lastCullPos = Vector3.zero
end

-- ═══════════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════════
local FOLIAGE_KW = { "feuillage","bush","grass","leaf","leaves","foliage","plant","herbe","buisson","arbre","tree" }
local function isFoliage(part)
    if not part then return false end
    if part.CollisionGroup == "Feuillage" then return true end
    local m = part.Material
    if m == Enum.Material.Grass or m == Enum.Material.LeafyGrass then return true end
    local n = string.lower(part.Name)
    for _,k in ipairs(FOLIAGE_KW) do
        if string.find(n, k, 1, true) then return true end
    end
    return false
end

local function w2s(pos)
    if typeof(pos) ~= "Vector3" then return nil,false,-1,nil end
    local ok, sp = pcall(function() return camera:WorldToViewportPoint(pos) end)
    if not ok or not sp then return nil,false,-1,nil end
    local vp = camera.ViewportSize
    local cx = vp.X/2
    local rawPos = Vector2.new(math.round(sp.X), math.round(sp.Y))
    local fixedX = cx + (sp.X - cx) / CFG.stretchX
    return Vector2.new(math.round(fixedX), math.round(sp.Y)), sp.Z > 0, sp.Z, rawPos
end

local function screenCenter() return camera.ViewportSize/2 end

local function getCharParts(char)
    if not char then return nil,nil,nil end
    return char:FindFirstChild("HumanoidRootPart"),
           char:FindFirstChild("Head"),
           char:FindFirstChild("Humanoid")
end

local function isAlive(hum)
    return hum and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead
end

local function getWeaponName(char)
    if not char then return nil end
    local t = char:FindFirstChildOfClass("Tool")
    return t and t.Name or nil
end

-- ═══════════════════════════════════════════════════════════
--  WALLCHECK
-- ═══════════════════════════════════════════════════════════
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
local function hasLOS(targetPos, targetChar)
    if not CFG.wallCheck then return true end
    if typeof(targetPos) ~= "Vector3" then return false end
    local fl = {workspace.Terrain}
    if lp.Character then table.insert(fl, lp.Character) end
    if targetChar then
        local hum = targetChar:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart then
            local veh = hum.SeatPart:FindFirstAncestorOfClass("Model")
            if veh then table.insert(fl, veh) end
        end
    end
    wallParams.FilterDescendantsInstances = fl
    local origin = camera.CFrame.Position
    local tv = targetPos - origin
    local total = tv.Magnitude
    if total < 0.5 then return true end
    local dir = tv.Unit
    local travelled = 0
    for _ = 1, CFG.foliageBypass and 12 or 1 do
        local rem = total - travelled - 0.4
        if rem <= 0.1 then return true end
        local ok, hit = pcall(function() return workspace:Raycast(origin, dir*rem, wallParams) end)
        if not ok or not hit then return true end
        if CFG.foliageBypass and isFoliage(hit.Instance) then
            travelled = travelled + hit.Distance + 0.15
            origin = hit.Position + dir*0.15
        else
            local hc = hit.Instance and hit.Instance:FindFirstAncestorOfClass("Model")
            if hc then
                for _,p in ipairs(Players:GetPlayers()) do
                    if p.Character == hc then return true end
                end
            end
            return false
        end
    end
    return true
end

-- ═══════════════════════════════════════════════════════════
--  ESP BOX POINTS
-- ═══════════════════════════════════════════════════════════
local function getBoxPoints(char, hrp, head, hum)
    if not char or not hrp or not head or not hum then return nil end
    local topPos  = head.Position + Vector3.new(0, head.Size.Y*0.6, 0)
    local hipH    = hum.HipHeight
    if hipH == 0 then hipH = (hum.RigType==Enum.HumanoidRigType.R6) and 2.5 or 2 end
    local feetPos = hrp.Position - Vector3.new(0, hipH + hrp.Size.Y*0.5, 0)
    local spTop,  _,depTop,  _ = w2s(topPos)
    local spFeet, _,depFeet, _ = w2s(feetPos)
    if not spTop  or depTop  <= 0 then return nil end
    if not spFeet or depFeet <= 0 then return nil end
    local boxH = math.abs(spFeet.Y - spTop.Y)
    if boxH < 2 then return nil end
    local boxW = boxH*0.42
    local cx = (spTop.X + spFeet.X)/2
    return {
        tl=Vector2.new(cx-boxW/2, spTop.Y),
        tr=Vector2.new(cx+boxW/2, spTop.Y),
        bl=Vector2.new(cx-boxW/2, spFeet.Y),
        br=Vector2.new(cx+boxW/2, spFeet.Y),
        cx=cx, boxH=boxH,
        topSP = spTop,
    }
end

-- ═══════════════════════════════════════════════════════════
--  SKELETON — bone pairs R15
-- ═══════════════════════════════════════════════════════════
local BONE_PAIRS = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
}

-- ═══════════════════════════════════════════════════════════
--  AIM POSITION
-- ═══════════════════════════════════════════════════════════
local function getAimPos(head)
    if not head or not head.Parent then return nil,false,Vector3.zero end
    local char = head.Parent
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local hrpVel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
    local inVehicle, vehVel = false, hrpVel
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        inVehicle = true
        local vm = hum.SeatPart:FindFirstAncestorOfClass("Model")
        if vm then
            local vr = vm:FindFirstChild("VehicleRoot")
            if vr then vehVel = vr.AssemblyLinearVelocity end
        end
    end
    if inVehicle then return head.Position + Vector3.new(0, head.Size.Y*CFG.headTopBias, 0), true, vehVel end
    local ut = char:FindFirstChild("UpperTorso")
    if ut then
        local na = ut:FindFirstChild("NeckRigAttachment")
        if na then return na.WorldPosition, false, hrpVel end
    end
    if hrp then
        return hrp.CFrame:PointToWorldSpace(Vector3.new(CFG.neckOffsetX, CFG.neckOffsetY, CFG.neckOffsetZ)), false, hrpVel
    end
    return head.Position - Vector3.new(0, head.Size.Y*0.3, 0), false, hrpVel
end

-- ═══════════════════════════════════════════════════════════
--  FIRE DETECTION
-- ═══════════════════════════════════════════════════════════
local isFiring = false
local function hookFireButton()
    local gui = lp:FindFirstChild("PlayerGui")
    if not gui then task.delay(2, hookFireButton) return end
    local btn = gui:FindFirstChild("MobileGui")
        and gui.MobileGui:FindFirstChild("Moved")
        and gui.MobileGui.Moved:FindFirstChild("Fire")
    if not btn then task.delay(2, hookFireButton) return end
    btn.InputBegan:Connect(function() isFiring = true  end)
    btn.InputEnded:Connect(function() isFiring = false end)
end
UserInputService.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 then isFiring = true end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then isFiring = false end
end)
task.defer(hookFireButton)

-- ═══════════════════════════════════════════════════════════
--  ALLY DETECTION
-- ═══════════════════════════════════════════════════════════
local allySet  = {}
local myClanId = nil
task.spawn(function()
    local ok, r = pcall(function()
        local cq = ReplicatedStorage:FindFirstChild("ClanQuery")
        if not cq then return nil end
        return cq:InvokeServer("GetMyClan")
    end)
    if ok and type(r)=="table" and r.id then myClanId = r.id end
end)
local clanCache = {}
local CLAN_TTL  = 30
local function getClanId(player)
    local now = os.clock()
    local cached = clanCache[player]
    if cached and (now - cached.fetchedAt) < CLAN_TTL then return cached.id end
    task.spawn(function()
        local ok, r = pcall(function()
            local cq = ReplicatedStorage:FindFirstChild("ClanQuery")
            if not cq then return nil end
            return cq:InvokeServer("GetPlayerClan", player.UserId)
        end)
        clanCache[player] = { id=(ok and type(r)=="table") and r.id or nil, fetchedAt=os.clock() }
    end)
    return cached and cached.id or nil
end
local function isCrewMate(char)
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.CollisionGroup == "CrewChar"
end
local function isClanMate(player)
    if not myClanId then return false end
    local id = getClanId(player)
    return id and id == myClanId
end
local function isAllyPlayer(player, char)
    return allySet[player] or isCrewMate(char) or isClanMate(player)
end
Players.PlayerRemoving:Connect(function(pl)
    clanCache[pl] = nil allySet[pl] = nil
end)

-- ═══════════════════════════════════════════════════════════
--  TARGET LOCK
-- ═══════════════════════════════════════════════════════════
local lockedTarget = nil
local wasFireing   = false
local lockExpireAt = 0
local smoothedVel  = Vector3.zero
local flickState   = { active=false, startAt=0 }

local function isTargetValid(head)
    if not head or not head.Parent then return false end
    local char = head.Parent
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl.Character == char then
            if isAllyPlayer(pl, char) then return false end
            break
        end
    end
    local _,_,hum = getCharParts(char)
    if not isAlive(hum) then return false end
    if (camera.CFrame.Position - head.Position).Magnitude > CFG.aimDist then return false end
    local sp, onScreen, depth = w2s(head.Position)
    if not sp or not onScreen or depth <= 0 then return false end
    return hasLOS(head.Position, char)
end

local function pickTarget()
    local center = screenCenter()
    local camPos = camera.CFrame.Position
    local bestHead, bestDist = nil, math.huge
    for _,player in ipairs(Players:GetPlayers()) do
        if player == lp then continue end
        local char = player.Character
        if not char then continue end
        if isAllyPlayer(player, char) then continue end
        local hrp, head, hum = getCharParts(char)
        if not head or not hum or not hrp then continue end
        if not isAlive(hum) then continue end
        if (camPos - head.Position).Magnitude > CFG.aimDist then continue end
        local sp, onScreen, depth, rawSp = w2s(head.Position)
        if not sp or not onScreen or depth <= 0 then continue end
        local rawPt = rawSp or sp
        local screenDist = (rawPt - center).Magnitude
        if screenDist > CFG.fov then continue end
        if not hasLOS(head.Position, char) then continue end
        if screenDist < bestDist then bestDist = screenDist bestHead = head end
    end
    return bestHead, bestDist
end

-- ═══════════════════════════════════════════════════════════
--  ESP DRAWING POOL
-- ═══════════════════════════════════════════════════════════
local espPool = {}

local function mkLine(color, thick)
    local l = Drawing.new("Line")
    l.Visible = false l.Color = color l.Thickness = thick or 1 l.ZIndex = 2
    return l
end
local function mkText(size, zidx)
    local t = Drawing.new("Text")
    t.Visible = false t.Size = size or 11 t.Color = Color3.fromRGB(255,255,255)
    t.Outline = true t.Center = true t.Font = 2 t.ZIndex = zidx or 3
    return t
end

-- ═══════════════════════════════════════════════════════════
--  WEAPON LABEL — CS2 STYLE
--  Drawing.Text di bawah box (box.br.Y + offset), center di cx
--  Tidak ada BillboardGui, tidak ada 3D attachment, tidak ada occlusion
--  Format: [ AK-47 ] — nama tool langsung, sama persis CS2
-- ═══════════════════════════════════════════════════════════
-- pool: player → Drawing.Text (weapon label bawah box)
-- Note: ini berbeda dari b.weapon (legacy, selalu Visible=false di v19)
local weaponLabelPool = {}

local function getWeaponLabel(player)
    if weaponLabelPool[player] then return weaponLabelPool[player] end
    local t = Drawing.new("Text")
    t.Visible  = false
    t.Size     = 11
    t.Font     = 2          -- UI (monospace-ish, sama dengan label lain)
    t.Color    = Color3.fromRGB(255, 220, 80)
    t.Outline  = true
    t.Center   = true
    t.ZIndex   = 4
    weaponLabelPool[player] = t
    return t
end

local function hideWeaponLabel(player)
    local t = weaponLabelPool[player]
    if t then t.Visible = false end
end

local function removeWeaponLabel(player)
    local t = weaponLabelPool[player]
    if t then t:Remove() end
    weaponLabelPool[player] = nil
end

-- stub compat untuk removeBundle yang masih panggil removeWeaponBB
local function removeWeaponBB(player) removeWeaponLabel(player) end
local function hideWeaponBB(player)   hideWeaponLabel(player)   end

local function getBundle(player)
    if espPool[player] then return espPool[player] end
    local E = CFG.esp
    local b = {
        box = {
            mkLine(E.box, E.thick), mkLine(E.box, E.thick),
            mkLine(E.box, E.thick), mkLine(E.box, E.thick),
        },
        barBg   = mkLine(E.barBg, 2),
        barFill = mkLine(E.barAlive, 2),
        dist    = mkText(11, 3),
        weapon  = mkText(11, 3),
        bones   = {},
    }
    b.weapon.Color = E.weapon
    for i = 1, #BONE_PAIRS do
        b.bones[i] = mkLine(E.skeleton, E.boneThick)
    end
    espPool[player] = b
    return b
end

local function hideBundle(b, player)
    for _,l in ipairs(b.box)   do l.Visible = false end
    for _,l in ipairs(b.bones) do l.Visible = false end
    b.barBg.Visible  = false
    b.barFill.Visible = false
    b.dist.Visible   = false
    b.weapon.Visible = false
    if player then hideWeaponBB(player) end
end

local function removeBundle(player)
    local b = espPool[player]
    if not b then return end
    for _,l in ipairs(b.box)   do l:Remove() end
    for _,l in ipairs(b.bones) do l:Remove() end
    b.barBg:Remove() b.barFill:Remove()
    b.dist:Remove()  b.weapon:Remove()
    espPool[player] = nil
    removeWeaponBB(player)
end
Players.PlayerRemoving:Connect(removeBundle)

-- Avatar system removed (v18)

-- ═══════════════════════════════════════════════════════════
--  FOV CIRCLE
-- ═══════════════════════════════════════════════════════════
local fovCircle = Drawing.new("Circle")
fovCircle.Visible   = true
fovCircle.Color     = CFG.fov_circle.color
fovCircle.Thickness = CFG.fov_circle.thick
fovCircle.Filled    = false
fovCircle.NumSides  = CFG.fov_circle.sides
fovCircle.Radius    = CFG.fov
fovCircle.ZIndex    = 1

-- Minimap removed in v19

-- ═══════════════════════════════════════════════════════════
--  AIM MATH
-- ═══════════════════════════════════════════════════════════
local _aimNoise = math.random()*1000

local function currentAimSpeed()
    if flickState.active then
        local elapsed = os.clock() - flickState.startAt
        if elapsed >= CFG.flickEaseTime then
            flickState.active = false
            return CFG.trackSpeed
        end
        local t = elapsed / CFG.flickEaseTime
        return CFG.trackSpeed + (CFG.flickSpeed - CFG.trackSpeed)*(1-t)*(1-t)
    end
    return CFG.trackSpeed
end

local function computeAimSpeed(inVehicle, horizVelMag, targetDist)
    if inVehicle then return CFG.vehTrackSpeed end
    local base = currentAimSpeed()
    if not CFG.adaptTrack then return base end
    local t = math.clamp(horizVelMag / CFG.adaptVelRef, 0, 1)
    local boost = t*t*CFG.adaptMaxBoost
    local distBonus = targetDist
        and math.clamp(1 - targetDist/CFG.distBoostMax, 0, 1)*CFG.distMaxBoost or 0
    return math.clamp(base + boost + distBonus, 0, 1)
end

local function smoothLookAt(targetPos, dt, forceSpeed)
    local camCF = camera.CFrame
    local camPos = camCF.Position
    local t = os.clock()
    local nx = math.noise(t*1.7,  _aimNoise)     * 0.006
    local ny = math.noise(t*2.1,  _aimNoise+100) * 0.006
    local humanizedPos = targetPos + camCF.RightVector*nx + camCF.UpVector*ny
    local targetCF = CFrame.lookAt(camPos, humanizedPos, Vector3.new(0,1,0))
    local speed = forceSpeed or currentAimSpeed()
    local alpha = math.clamp(1-(1-speed)^(dt*60), 0, 1)
    camera.CFrame = CFrame.new(camPos) * camCF.Rotation:Lerp(targetCF.Rotation, alpha)
end

-- ═══════════════════════════════════════════════════════════
--  ANTI-AIM
-- ═══════════════════════════════════════════════════════════
local function tickAntiAim(dt)
    if not AntiAim.enabled then return end
    local char = lp.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health<=0 then return end
    if hum.SeatPart then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local st = hum:GetState()
    if st==Enum.HumanoidStateType.Dead or st==Enum.HumanoidStateType.Physics
    or st==Enum.HumanoidStateType.Ragdoll then return end
    local now = os.clock()
    if AntiAim.adStrafeEnabled and isFiring and CFG.aimOn and lockedTarget then
        if now >= AntiAim._nextADStrafe or not AntiAim._adVec then
            AntiAim._nextADStrafe = now
                + math.random()*(AntiAim.adStrafeMaxTime-AntiAim.adStrafeMinTime)
                + AntiAim.adStrafeMinTime
            AntiAim._adDir = -AntiAim._adDir
            local right = camera.CFrame.RightVector
            local fr = Vector3.new(right.X, 0, right.Z)
            if fr.Magnitude > 0.01 then AntiAim._adVec = fr.Unit*AntiAim._adDir end
        end
        if AntiAim._adVec then hum:Move(AntiAim._adVec, false) end
        return
    end
    AntiAim._adVec = nil
end

-- ═══════════════════════════════════════════════════════════
--  MENU
-- ═══════════════════════════════════════════════════════════
local function buildMenu()
    local uiParent
    if type(gethui)=="function" then
        local ok,r = pcall(gethui)
        if ok and r then uiParent = r end
    end
    uiParent = uiParent or lp:WaitForChild("PlayerGui")

    local SG = Instance.new("ScreenGui")
    SG.Name = "CortexMenu" SG.ResetOnSpawn = false
    SG.IgnoreGuiInset = true SG.DisplayOrder = 999998 SG.Parent = uiParent

    -- Toggle button — dùng ImageLabel icon (≡ / ✕) thay text chữ C
    local toggleBtn = Instance.new("TextButton", SG)
    toggleBtn.Size = UDim2.new(0,44,0,44) toggleBtn.Position = UDim2.new(0,10,0.5,-22)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(90,60,200) toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = "" toggleBtn.AutoButtonColor = false toggleBtn.ZIndex = 20
    Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,12)
    local ts = Instance.new("UIStroke", toggleBtn)
    ts.Color = Color3.fromRGB(160,120,255) ts.Transparency=0.4 ts.Thickness=1.5
    -- Icon hamburger / arrow dùng ImageLabel
    local toggleIcon = Instance.new("ImageLabel", toggleBtn)
    toggleIcon.Size = UDim2.new(0,26,0,26)
    toggleIcon.Position = UDim2.new(0.5,-13,0.5,-13)
    toggleIcon.BackgroundTransparency = 1
    toggleIcon.Image = "rbxassetid://7733694430"  -- hamburger menu icon
    toggleIcon.ImageColor3 = Color3.fromRGB(255,255,255)
    toggleIcon.ZIndex = 21
    toggleBtn.MouseEnter:Connect(function()
        toggleBtn.BackgroundColor3 = Color3.fromRGB(110,75,230)
    end)
    toggleBtn.MouseLeave:Connect(function()
        toggleBtn.BackgroundColor3 = Color3.fromRGB(90,60,200)
    end)

    local W, H = 270, 480
    local mf = Instance.new("Frame", SG)
    mf.Name = "MainFrame" mf.Size = UDim2.new(0,W,0,H)
    mf.Position = UDim2.new(0,62,0.5,-(H/2)) mf.BackgroundColor3 = Color3.fromRGB(12,10,26)
    mf.BorderSizePixel = 0 mf.ClipsDescendants = true mf.ZIndex = 10
    Instance.new("UICorner", mf).CornerRadius = UDim.new(0,16)
    local mstroke = Instance.new("UIStroke", mf)
    mstroke.Color = Color3.fromRGB(100,70,220) mstroke.Transparency = 0.4 mstroke.Thickness = 1.5
    local mbg = Instance.new("UIGradient", mf)
    mbg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(16,12,36)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(22,16,50)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(14,16,42)),
    }) mbg.Rotation = 135
    local mab = Instance.new("Frame", mf)
    mab.Size = UDim2.new(1,0,0,3) mab.Position = UDim2.new(0,0,0,0)
    mab.BorderSizePixel = 0 mab.BackgroundColor3 = Color3.fromRGB(120,80,255) mab.ZIndex = 11
    local mabg = Instance.new("UIGradient", mab)
    mabg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(70,50,180)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150,90,255)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(70,50,180)),
    })

    local hdr = Instance.new("Frame", mf)
    hdr.Size = UDim2.new(1,0,0,52) hdr.Position = UDim2.new(0,0,0,3)
    hdr.BackgroundTransparency = 1 hdr.ZIndex = 11
    local title = Instance.new("TextLabel", hdr)
    title.Size = UDim2.new(1,-16,0,28) title.Position = UDim2.new(0,14,0,6)
    title.BackgroundTransparency = 1 title.Text = "KXY  //  URBAN RELOAD"
    title.TextColor3 = Color3.fromRGB(255,255,255) title.Font = Enum.Font.GothamBold
    title.TextSize = 14 title.TextXAlignment = Enum.TextXAlignment.Left title.ZIndex = 12
    local ver = Instance.new("TextLabel", hdr)
    ver.Size = UDim2.new(1,-16,0,16) ver.Position = UDim2.new(0,14,0,32)
    ver.BackgroundTransparency = 1 ver.Text = "v19.0  •  WEAPON LABEL  •  BONE  •  FPS BOOST"
    ver.TextColor3 = Color3.fromRGB(120,95,200) ver.Font = Enum.Font.Gotham
    ver.TextSize = 10 ver.TextXAlignment = Enum.TextXAlignment.Left ver.ZIndex = 12
    local hdiv = Instance.new("Frame", mf)
    hdiv.Size = UDim2.new(1,-28,0,1) hdiv.Position = UDim2.new(0,14,0,55)
    hdiv.BorderSizePixel = 0 hdiv.BackgroundColor3 = Color3.fromRGB(80,55,160)
    hdiv.BackgroundTransparency = 0.5 hdiv.ZIndex = 11

    -- Tabs — thêm FPS tab
    local tabs = { "AIM", "ESP", "FPS", "MISC" }
    local activeTab  = "AIM"
    local tabButtons = {}
    local tabPages   = {}
    local tabBar = Instance.new("Frame", mf)
    tabBar.Size = UDim2.new(1,-28,0,32) tabBar.Position = UDim2.new(0,14,0,62)
    tabBar.BackgroundColor3 = Color3.fromRGB(18,14,40) tabBar.BorderSizePixel = 0
    tabBar.ZIndex = 11
    Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0,8)
    local tabLayout = Instance.new("UIListLayout", tabBar)
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0,0)

    local contentArea = Instance.new("Frame", mf)
    contentArea.Size = UDim2.new(1,-28,1,-106) contentArea.Position = UDim2.new(0,14,0,100)
    contentArea.BackgroundTransparency = 1 contentArea.ClipsDescendants = true contentArea.ZIndex = 11

    for _, tabName in ipairs(tabs) do
        local sf = Instance.new("ScrollingFrame", contentArea)
        sf.Size = UDim2.fromScale(1,1) sf.BackgroundTransparency = 1
        sf.BorderSizePixel = 0 sf.ScrollBarThickness = 3
        sf.ScrollBarImageColor3 = Color3.fromRGB(100,70,200)
        sf.CanvasSize = UDim2.new(0,0,0,0)
        sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
        sf.Visible = (tabName == activeTab) sf.ZIndex = 12
        tabPages[tabName] = sf
        local layout = Instance.new("UIListLayout", sf)
        layout.SortOrder = Enum.SortOrder.LayoutOrder layout.Padding = UDim.new(0,6)
        local pad = Instance.new("UIPadding", sf)
        pad.PaddingTop = UDim.new(0,4) pad.PaddingBottom = UDim.new(0,8)
        pad.PaddingLeft = UDim.new(0,0) pad.PaddingRight = UDim.new(0,6)
    end
    for i, tabName in ipairs(tabs) do
        local tb = Instance.new("TextButton", tabBar)
        tb.Size = UDim2.new(1/#tabs,0,1,0)
        tb.BackgroundColor3 = (tabName==activeTab) and Color3.fromRGB(90,60,200) or Color3.fromRGB(18,14,40)
        tb.BorderSizePixel = 0 tb.Text = tabName
        tb.TextColor3 = (tabName==activeTab) and Color3.fromRGB(255,255,255) or Color3.fromRGB(120,100,180)
        tb.Font = Enum.Font.GothamBold tb.TextSize = 10 tb.ZIndex = 12 tb.LayoutOrder = i
        Instance.new("UICorner", tb).CornerRadius = UDim.new(0,8)
        tabButtons[tabName] = tb
    end
    local function switchTab(name)
        activeTab = name
        for _, tn in ipairs(tabs) do
            local isActive = tn == name
            tabButtons[tn].BackgroundColor3 = isActive and Color3.fromRGB(90,60,200) or Color3.fromRGB(18,14,40)
            tabButtons[tn].TextColor3 = isActive and Color3.fromRGB(255,255,255) or Color3.fromRGB(120,100,180)
            tabPages[tn].Visible = isActive
        end
    end
    for _, tabName in ipairs(tabs) do
        tabButtons[tabName].Activated:Connect(function() switchTab(tabName) end)
    end

    -- Toggle factory
    -- FIX v18: dùng TextButton thay Frame + Activated thay InputBegan
    -- InputBegan trên Frame ăn scroll event của ScrollingFrame → scroll không hoạt động
    -- Activated chỉ fire khi click/tap thật, không ăn scroll
    local function mkToggle(parent, label, getter, setter, order)
        local row = Instance.new("TextButton", parent)
        row.Size = UDim2.new(1,0,0,38) row.BackgroundColor3 = Color3.fromRGB(20,16,44)
        row.BorderSizePixel = 0 row.ZIndex = 13 row.LayoutOrder = order or 0
        row.Text = "" row.AutoButtonColor = false
        Instance.new("UICorner", row).CornerRadius = UDim.new(0,10)
        local rstroke = Instance.new("UIStroke", row)
        rstroke.Color = Color3.fromRGB(70,50,140) rstroke.Transparency = 0.65 rstroke.Thickness = 1
        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(1,-58,1,0) lbl.Position = UDim2.new(0,12,0,0)
        lbl.BackgroundTransparency = 1 lbl.Text = label lbl.TextColor3 = Color3.fromRGB(210,200,240)
        lbl.Font = Enum.Font.Gotham lbl.TextSize = 12 lbl.TextXAlignment = Enum.TextXAlignment.Left lbl.ZIndex = 14
        local track = Instance.new("Frame", row)
        track.Size = UDim2.new(0,40,0,20) track.Position = UDim2.new(1,-50,0.5,-10)
        track.BackgroundColor3 = getter() and Color3.fromRGB(90,60,200) or Color3.fromRGB(40,34,70)
        track.BorderSizePixel = 0 track.ZIndex = 14
        Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)
        local thumb = Instance.new("Frame", track)
        thumb.Size = UDim2.new(0,16,0,16)
        thumb.Position = getter() and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
        thumb.BackgroundColor3 = Color3.fromRGB(255,255,255) thumb.BorderSizePixel = 0 thumb.ZIndex = 15
        Instance.new("UICorner", thumb).CornerRadius = UDim.new(1,0)
        local function refresh()
            local on = getter()
            track.BackgroundColor3 = on and Color3.fromRGB(90,60,200) or Color3.fromRGB(40,34,70)
            thumb.Position = on and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
        end
        -- Activated không block scroll, InputBegan trên Frame thì có
        row.Activated:Connect(function()
            setter(not getter()) refresh()
            saveConfig()   -- auto-save mỗi khi toggle thay đổi
        end)
        return row
    end

    -- Slider factory
    -- FIX v18: track là TextButton thay Frame để không eat scroll trên ScrollingFrame
    -- dragging flag chỉ set khi click, InputChanged global chỉ update khi dragging=true
    local function mkSlider(parent, label, minVal, maxVal, getter, setter, order, dp)
        dp = dp or 0
        local mult = 10^dp
        local row = Instance.new("Frame", parent)
        row.Size = UDim2.new(1,0,0,52) row.BackgroundColor3 = Color3.fromRGB(20,16,44)
        row.BorderSizePixel = 0 row.ZIndex = 13 row.LayoutOrder = order or 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0,10)
        local rstroke = Instance.new("UIStroke", row)
        rstroke.Color = Color3.fromRGB(70,50,140) rstroke.Transparency = 0.65 rstroke.Thickness = 1
        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(1,-60,0,20) lbl.Position = UDim2.new(0,12,0,6)
        lbl.BackgroundTransparency = 1 lbl.Text = label lbl.TextColor3 = Color3.fromRGB(210,200,240)
        lbl.Font = Enum.Font.Gotham lbl.TextSize = 12 lbl.TextXAlignment = Enum.TextXAlignment.Left lbl.ZIndex = 14
        local function fmt(v)
            return dp == 0 and tostring(math.floor(v)) or string.format("%."..dp.."f", v)
        end
        local valLbl = Instance.new("TextLabel", row)
        valLbl.Size = UDim2.new(0,46,0,20) valLbl.Position = UDim2.new(1,-54,0,6)
        valLbl.BackgroundTransparency = 1 valLbl.Text = fmt(getter())
        valLbl.TextColor3 = Color3.fromRGB(150,110,240) valLbl.Font = Enum.Font.GothamBold
        valLbl.TextSize = 12 valLbl.TextXAlignment = Enum.TextXAlignment.Right valLbl.ZIndex = 14
        -- TextButton: Activated/InputBegan không eat scroll nếu chỉ dùng MouseButton1 drag
        local track = Instance.new("TextButton", row)
        track.Size = UDim2.new(1,-24,0,16) track.Position = UDim2.new(0,12,0,28)
        track.BackgroundColor3 = Color3.fromRGB(40,32,80) track.BorderSizePixel = 0
        track.ZIndex = 14 track.Text = "" track.AutoButtonColor = false
        Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)
        local trackInner = Instance.new("Frame", track)
        trackInner.Size = UDim2.new(1,0,0,6) trackInner.Position = UDim2.new(0,0,0.5,-3)
        trackInner.BackgroundColor3 = Color3.fromRGB(40,32,80) trackInner.BorderSizePixel = 0 trackInner.ZIndex = 14
        Instance.new("UICorner", trackInner).CornerRadius = UDim.new(1,0)
        local fill = Instance.new("Frame", trackInner)
        fill.Size = UDim2.new((getter()-minVal)/(maxVal-minVal),0,1,0)
        fill.BackgroundColor3 = Color3.fromRGB(100,65,220) fill.BorderSizePixel = 0 fill.ZIndex = 15
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)
        local thumb = Instance.new("Frame", fill)
        thumb.Size = UDim2.new(0,14,0,14) thumb.Position = UDim2.new(1,-7,0.5,-7)
        thumb.BackgroundColor3 = Color3.fromRGB(255,255,255) thumb.BorderSizePixel = 0 thumb.ZIndex = 16
        Instance.new("UICorner", thumb).CornerRadius = UDim.new(1,0)
        local dragging = false
        local function update(inputPos)
            local abs = trackInner.AbsolutePosition local sz = trackInner.AbsoluteSize
            local t = math.clamp((inputPos.X - abs.X) / sz.X, 0, 1)
            local v = math.floor((minVal + t*(maxVal-minVal)) * mult + 0.5) / mult
            setter(v) fill.Size = UDim2.new(t,0,1,0) valLbl.Text = fmt(v)
            saveConfig()   -- debounced — slider drag tidak spam disk
        end
        track.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true update(inp.Position)
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch) then update(inp.Position) end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
        return row
    end

    -- AIM tab
    local aimPage = tabPages["AIM"]
    mkToggle(aimPage, "Aimbot",          function() return CFG.aimOn end,          function(v) CFG.aimOn=v end, 1)
    mkToggle(aimPage, "Wall Check",      function() return CFG.wallCheck end,      function(v) CFG.wallCheck=v end, 2)
    mkToggle(aimPage, "Foliage Bypass",  function() return CFG.foliageBypass end,  function(v) CFG.foliageBypass=v end, 3)
    mkSlider(aimPage, "FOV Radius", 20, 350,
        function() return CFG.fov end,
        function(v) CFG.fov=v fovCircle.Radius=v end, 4)
    mkSlider(aimPage, "Aim Distance (studs)", 100, 800,
        function() return CFG.aimDist end,
        function(v) CFG.aimDist=v end, 5)
    mkSlider(aimPage, "Track Speed x100", 10, 95,
        function() return math.floor(CFG.trackSpeed*100) end,
        function(v) CFG.trackSpeed=v/100 CFG.smoothSpeed=v/100 end, 6)

    -- ESP tab
    local espPage = tabPages["ESP"]
    mkToggle(espPage, "ESP Boxes",           function() return CFG.espOn end,       function(v) CFG.espOn=v end, 1)
    mkToggle(espPage, "FOV Circle",          function() return fovCircle.Visible end, function(v) fovCircle.Visible=v end, 2)
    mkToggle(espPage, "Weapon Icon (súng)",  function() return CFG.espWeapon end,   function(v) CFG.espWeapon=v end, 3)
    mkToggle(espPage, "Skeleton Bone",       function() return CFG.espSkeleton end, function(v) CFG.espSkeleton=v end, 4)
    mkSlider(espPage, "ESP Distance (studs)", 100, 900,
        function() return CFG.espDist end,
        function(v) CFG.espDist=v end, 6)
    mkSlider(espPage, "StretchX (75–100)", 75, 100,
        function() return math.floor(CFG.stretchX*100) end,
        function(v) CFG.stretchX = math.clamp(v/100, 0.75, 1.00) end, 7)

    -- FPS BOOST tab
    local fpsPage = tabPages["FPS"]

    -- Header mô tả
    local fpsDesc = Instance.new("TextLabel", fpsPage)
    fpsDesc.Size = UDim2.new(1,0,0,46) fpsDesc.BackgroundColor3 = Color3.fromRGB(14,10,32)
    fpsDesc.BorderSizePixel = 0 fpsDesc.ZIndex = 13 fpsDesc.LayoutOrder = 0
    Instance.new("UICorner", fpsDesc).CornerRadius = UDim.new(0,10)
    fpsDesc.Text = "⚡  FPS BOOST — Tối ưu cho máy yếu\nGiảm đồ họa, tắt bóng, cull xa"
    fpsDesc.TextColor3 = Color3.fromRGB(180,160,255) fpsDesc.Font = Enum.Font.Gotham
    fpsDesc.TextSize = 11 fpsDesc.TextWrapped = true
    fpsDesc.TextXAlignment = Enum.TextXAlignment.Center fpsDesc.TextYAlignment = Enum.TextYAlignment.Center

    local fb = CFG.fpsBoost
    mkToggle(fpsPage, "FPS Boost (master)",
        function() return fb.on end,
        function(v)
            fb.on = v
            if v then applyFPSBoost() else restoreFPSBoost() end
        end, 1)
    mkToggle(fpsPage, "Tắt bóng (Shadow Off)",
        function() return fb.shadowDisable end,
        function(v) fb.shadowDisable=v if fb.on then applyFPSBoost() end end, 2)
    mkToggle(fpsPage, "Lighting đơn giản",
        function() return fb.lightingSimple end,
        function(v) fb.lightingSimple=v if fb.on then applyFPSBoost() end end, 3)
    mkToggle(fpsPage, "Giảm texture quality",
        function() return fb.textureQuality end,
        function(v) fb.textureQuality=v if fb.on then applyFPSBoost() end end, 4)
    mkToggle(fpsPage, "Tắt particle/fire/smoke",
        function() return fb.particleOff end,
        function(v) fb.particleOff=v if fb.on then applyFPSBoost() end end, 5)
    mkToggle(fpsPage, "Tắt decal/texture",
        function() return fb.decalOff end,
        function(v) fb.decalOff=v if fb.on then applyFPSBoost() end end, 6)
    mkToggle(fpsPage, "Cull mesh xa",
        function() return fb.distCull end,
        function(v) fb.distCull=v end, 7)
    mkSlider(fpsPage, "Cull Distance (studs)", 50, 500,
        function() return fb.cullDist end,
        function(v) fb.cullDist=v end, 8)

    -- MISC tab
    local miscPage = tabPages["MISC"]
    mkToggle(miscPage, "Anti-Aim (AD Strafe)", function() return AntiAim.enabled end, function(v) AntiAim.enabled=v end, 1)

    -- ── Config status banner ──
    local cfgBanner = Instance.new("TextLabel", miscPage)
    cfgBanner.Size = UDim2.new(1,0,0,36) cfgBanner.BackgroundColor3 = Color3.fromRGB(14,10,32)
    cfgBanner.BorderSizePixel = 0 cfgBanner.ZIndex = 13 cfgBanner.LayoutOrder = 2
    Instance.new("UICorner", cfgBanner).CornerRadius = UDim.new(0,10)
    cfgBanner.Text = canSave
        and "💾  Config: auto-save ON  •  kxy_config.json"
        or  "⚠️  Executor không có writefile — config không được lưu"
    cfgBanner.TextColor3 = canSave
        and Color3.fromRGB(80,220,120)
        or  Color3.fromRGB(220,120,60)
    cfgBanner.Font = Enum.Font.Gotham cfgBanner.TextSize = 10 cfgBanner.TextWrapped = true
    cfgBanner.TextXAlignment = Enum.TextXAlignment.Center
    cfgBanner.TextYAlignment = Enum.TextYAlignment.Center

    -- Feedback label (hiện "Saved!" / "Reset!" tạm 2 giây)
    local cfgFeedback = Instance.new("TextLabel", miscPage)
    cfgFeedback.Size = UDim2.new(1,0,0,24) cfgFeedback.BackgroundTransparency = 1
    cfgFeedback.BorderSizePixel = 0 cfgFeedback.ZIndex = 13 cfgFeedback.LayoutOrder = 3
    cfgFeedback.Text = "" cfgFeedback.TextColor3 = Color3.fromRGB(100,220,255)
    cfgFeedback.Font = Enum.Font.GothamBold cfgFeedback.TextSize = 11
    cfgFeedback.TextXAlignment = Enum.TextXAlignment.Center
    local _feedbackThread = nil
    local function showFeedback(msg, col)
        cfgFeedback.Text = msg
        cfgFeedback.TextColor3 = col or Color3.fromRGB(100,220,255)
        if _feedbackThread then task.cancel(_feedbackThread) end
        _feedbackThread = task.delay(2, function() cfgFeedback.Text = "" end)
    end

    -- Button row: SAVE | RESET
    local btnRow = Instance.new("Frame", miscPage)
    btnRow.Size = UDim2.new(1,0,0,40) btnRow.BackgroundTransparency = 1
    btnRow.BorderSizePixel = 0 btnRow.ZIndex = 13 btnRow.LayoutOrder = 4
    local btnLayout = Instance.new("UIListLayout", btnRow)
    btnLayout.FillDirection = Enum.FillDirection.Horizontal
    btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
    btnLayout.Padding = UDim.new(0,8)

    local function mkCfgBtn(text, color, layoutOrder)
        local btn = Instance.new("TextButton", btnRow)
        btn.Size = UDim2.new(0.5,-4,1,0)
        btn.BackgroundColor3 = color btn.BorderSizePixel = 0
        btn.Text = text btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.Font = Enum.Font.GothamBold btn.TextSize = 12
        btn.AutoButtonColor = false btn.ZIndex = 14 btn.LayoutOrder = layoutOrder
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,10)
        local g = Instance.new("UIGradient", btn)
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1,1,1),0.18)),
            ColorSequenceKeypoint.new(1, color),
        }) g.Rotation = 90
        local s = Instance.new("UIStroke", btn)
        s.Color = color:Lerp(Color3.new(1,1,1),0.3) s.Transparency=0.4 s.Thickness=1
        btn.MouseEnter:Connect(function() btn.BackgroundColor3=color:Lerp(Color3.new(1,1,1),0.14) end)
        btn.MouseLeave:Connect(function() btn.BackgroundColor3=color end)
        return btn
    end

    local saveBtn  = mkCfgBtn("💾  SAVE NOW",  Color3.fromRGB(50,140,80),  1)
    local resetBtn = mkCfgBtn("↺  RESET",      Color3.fromRGB(140,50,50),  2)

    saveBtn.Activated:Connect(function()
        if not canSave then
            showFeedback("⚠ Executor không hỗ trợ writefile", Color3.fromRGB(220,120,60))
            return
        end
        local ok, err = pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(serializeCFG()))
        end)
        if ok then
            showFeedback("✓  Saved → kxy_config.json", Color3.fromRGB(80,220,120))
        else
            showFeedback("✗  Save failed: " .. tostring(err):sub(1,40), Color3.fromRGB(220,80,80))
        end
    end)

    resetBtn.Activated:Connect(function()
        resetConfig()
        -- Reload UI state — cần rebuild menu để reflect defaults
        -- Thay vì rebuild toàn bộ, chỉ show thông báo và suggest rejoin
        showFeedback("↺  Reset xong — rerun script để UI reload", Color3.fromRGB(220,180,80))
        if canSave then pcall(delfile, CONFIG_FILE) end
    end)

    -- status bar
    local statusBar = Instance.new("TextLabel", mf)
    statusBar.Size = UDim2.new(1,0,0,20) statusBar.Position = UDim2.new(0,0,1,-20)
    statusBar.BackgroundColor3 = Color3.fromRGB(20,14,50) statusBar.BorderSizePixel = 0
    statusBar.Text = "KXY v19.0  |  Urban Reload  |  discord.gg/YxpZy2Nrj8"
    statusBar.TextColor3 = Color3.fromRGB(80,60,140) statusBar.Font = Enum.Font.Gotham
    statusBar.TextSize = 9 statusBar.TextXAlignment = Enum.TextXAlignment.Center statusBar.ZIndex = 11

    -- Drag main frame
    local mdragInput, mdragStart, mdragStartPos
    hdr.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            mdragInput = inp mdragStart = inp.Position mdragStartPos = mf.Position
        end
    end)
    hdr.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement
        or inp.UserInputType == Enum.UserInputType.Touch then mdragInput = inp end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if mdragInput and inp == mdragInput and mdragStart and mdragStartPos then
            local d = inp.Position - mdragStart
            mf.Position = UDim2.new(mdragStartPos.X.Scale, mdragStartPos.X.Offset+d.X,
                                     mdragStartPos.Y.Scale, mdragStartPos.Y.Offset+d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            mdragInput = nil mdragStart = nil mdragStartPos = nil
        end
    end)

    local open = true
    toggleBtn.Activated:Connect(function()
        open = not open
        mf.Visible = open
        -- đổi icon: hamburger khi mở, arrow khi đóng
        toggleIcon.Image = open
            and "rbxassetid://7733694430"   -- hamburger
            or  "rbxassetid://7734027567"   -- chevron right / collapse
    end)
end

-- Minimap drag removed in v19

-- ═══════════════════════════════════════════════════════════
--  MAIN RENDER LOOP
-- ═══════════════════════════════════════════════════════════
RunService:BindToRenderStep("CortexMain", Enum.RenderPriority.Camera.Value + 1, function(dt)
    pcall(function()
        local now = os.clock()
        tickAntiAim(dt)
        fovCircle.Radius   = CFG.fov
        fovCircle.Position = screenCenter()

        -- FPS boost distance cull — movement-gated, zero overhead khi diam
        tickDistCull()

        -- ── Aim logic ──
        local fireStarted = isFiring and not wasFireing
        local fireEnded   = not isFiring and wasFireing
        if fireEnded then
            if lockedTarget then lockExpireAt = now + CFG.tapGapWindow end
            flickState.active = false
        end
        if isFiring then
            if fireStarted then
                if lockedTarget and now < lockExpireAt and isTargetValid(lockedTarget) then
                    lockExpireAt = 0 flickState.active = false
                else
                    lockExpireAt = 0 smoothedVel = Vector3.zero
                    local t, sdist = pickTarget()
                    lockedTarget = t
                    if lockedTarget then
                        if sdist and sdist > CFG.flickThreshold then
                            flickState.active = true flickState.startAt = os.clock()
                        else flickState.active = false end
                    end
                end
            elseif lockedTarget then
                if not isTargetValid(lockedTarget) then
                    lockedTarget = nil flickState.active = false lockExpireAt = 0
                end
            end
        else
            if lockExpireAt > 0 and now >= lockExpireAt then lockedTarget = nil lockExpireAt = 0 end
            flickState.active = false
        end
        wasFireing = isFiring

        if CFG.aimOn and isFiring and lockedTarget then
            local selfChar = lp.Character
            if selfChar then
                local _,_,selfHum = getCharParts(selfChar)
                if isAlive(selfHum) then
                    local aimPos, inVehicle, velForPred = getAimPos(lockedTarget)
                    if aimPos then
                        local predPos = aimPos
                        if inVehicle and velForPred then
                            if velForPred.Magnitude > CFG.vehPredMin then
                                predPos = aimPos + velForPred * CFG.vehPredScale
                            end
                        elseif not inVehicle and velForPred then
                            local rawMag = velForPred.Magnitude
                            local ema = rawMag > smoothedVel.Magnitude and 0.45 or CFG.velSmooth
                            smoothedVel = smoothedVel:Lerp(velForPred, ema)
                            local velMag = smoothedVel.Magnitude
                            local fade = math.clamp(velMag / CFG.velPredFadeIn, 0, 1)
                            local sRatio = math.clamp(velMag / CFG.adaptVelRef, 0, 1.5)
                            local dynPS = CFG.velPredScale * (1 + sRatio * 0.4)
                            if dynPS * fade > 0 then predPos = aimPos + smoothedVel*(dynPS*fade) end
                        end
                        local horizMag = velForPred and Vector3.new(velForPred.X,0,velForPred.Z).Magnitude or 0
                        local tDist = (camera.CFrame.Position - aimPos).Magnitude
                        smoothLookAt(predPos, dt, computeAimSpeed(inVehicle, horizMag, tDist))
                    end
                end
            end
        end

        -- ── ESP + Weapon + Bone ──
        local myChar = lp.Character
        local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local myPos  = myHRP and myHRP.Position
        local camPos = camera.CFrame.Position

        for _, player in ipairs(Players:GetPlayers()) do
            if player == lp then continue end
            local char = player.Character
            if not char then
                if espPool[player] then removeBundle(player) end
                continue
            end

            local hrp, head, hum = getCharParts(char)
            local alive = hrp and head and hum and isAlive(hum)

            -- ── ESP box + weapon + skeleton ──
            if not alive or not CFG.espOn then
                if espPool[player] then hideBundle(espPool[player], player) end
                continue
            end

            local dist = math.floor((camPos - hrp.Position).Magnitude)
            if dist > (CFG.espDist + 15) then
                if espPool[player] then hideBundle(espPool[player], player) end
                continue
            end

            local box = getBoxPoints(char, hrp, head, hum)
            if not box then
                if espPool[player] then hideBundle(espPool[player], player) end
                continue
            end

            local b = getBundle(player)
            local E = CFG.esp

            b.box[1].From=box.tl ; b.box[1].To=box.tr
            b.box[2].From=box.bl ; b.box[2].To=box.br
            b.box[3].From=box.tl ; b.box[3].To=box.bl
            b.box[4].From=box.tr ; b.box[4].To=box.br
            for _,l in ipairs(b.box) do l.Color=E.box l.Visible=true end

            local dd = myPos and math.floor((myPos - hrp.Position).Magnitude) or dist
            b.dist.Text     = dd.."m"
            b.dist.Position = Vector2.new(box.cx, box.br.Y + 2)
            b.dist.Visible  = true

            local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            local barX = box.tl.X - 4
            b.barBg.From=Vector2.new(barX,box.tl.Y) b.barBg.To=Vector2.new(barX,box.br.Y)
            b.barBg.Color=E.barBg b.barBg.Visible=true
            b.barFill.From=Vector2.new(barX,box.br.Y)
            b.barFill.To=Vector2.new(barX, box.br.Y - box.boxH*hp)
            b.barFill.Color = hp>0.4 and E.barAlive or E.barLow b.barFill.Visible=true

            -- ── Weapon Label — CS2 style, dưới box ──
            -- Drawing.Text di box.br.Y + 14, center di box.cx
            -- Format "[ AK-47 ]" — cực kỳ readable, không ada occlusion
            b.weapon.Visible = false   -- legacy text label selalu off
            local wLabel = getWeaponLabel(player)
            if CFG.espWeapon then
                local wn = getWeaponName(char)
                if wn and not isNonWeapon(wn) then
                    wLabel.Text     = "[ " .. wn .. " ]"
                    wLabel.Position = Vector2.new(box.cx, box.br.Y + 14)
                    wLabel.Visible  = true
                else
                    wLabel.Visible = false
                end
            else
                wLabel.Visible = false
            end

            -- ── Skeleton Bone ──
            if CFG.espSkeleton then
                for i, pair in ipairs(BONE_PAIRS) do
                    local boneA = char:FindFirstChild(pair[1])
                    local boneB = char:FindFirstChild(pair[2])
                    local line  = b.bones[i]
                    if boneA and boneB then
                        local spA, visA, dA = w2s(boneA.Position)
                        local spB, visB, dB = w2s(boneB.Position)
                        if spA and spB and dA > 0 and dB > 0 then
                            line.From    = spA
                            line.To      = spB
                            line.Color   = E.skeleton
                            line.Visible = true
                        else
                            line.Visible = false
                        end
                    else
                        line.Visible = false
                    end
                end
            else
                for _, l in ipairs(b.bones) do l.Visible = false end
            end
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════
--  BOOT
-- ═══════════════════════════════════════════════════════════
task.spawn(function()
    repeat task.wait() until lp:FindFirstChild("PlayerGui")
    buildMenu()
    print("[KXY Urban Reload v19.0] loaded")
    print("  → NEW: Weapon label CS2-style (Drawing.Text dưới box)")
    print("  → NEW: Minimap removed")
    print("  → NEW: FPS Boost rework — no-lag static+movement-gated cull")
    print("  → NEW: Config persistence — auto-save kxy_config.json")
    print("  → Config save: " .. (canSave and "YES (writefile available)" or "NO (executor lacks writefile)"))
    print("  → Discord: discord.gg/YxpZy2Nrj8")
end)
