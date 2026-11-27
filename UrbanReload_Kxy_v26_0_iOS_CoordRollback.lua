--[[
  KXY — URBAN RELOAD
  KeyGate  → getkey-kxy.vercel.app
  Verify   → kxypanelkey.vercel.app
  v26.0 | Rolled back unverified iOS overlay scaling; use raw viewport coordinates.
  v25.8 | iOS overlay-to-viewport scaling for ESP/FOV canvas alignment.
  v25.7 | Removed GroundLoot auto loot; added native HoodNPC corpse auto loot gated to FarmZone and 0-50 stud farm distance.
  v25.5 | iOS FOV center fix: use Camera.ViewportSize / 2 and raw WorldToViewportPoint coordinates; remove inset remapping.
  v25.3 | iOS touch handling: exact Fire button bounds, processed-touch support, mobile diagnostics.
  v25.2 | Platform detection: GetPlatform when permitted, explicit executor OS markers, generic touch fallback; mobile is never silently labelled PC.
  v25.0 | Sticky Lock fix: hard snap (camera is rebuilt from your own look every frame, so the old per-frame lerp left a residual that changed with FPS and recoil),
          wall check no longer blocked by the game's own ClientHitboxes / FX parts (same Bullet collision group as real shots),
          aim point moved into the middle of the head hitbox, target lead cut from ~65 ms to one frame.
          Corner Assist: numeric settings removed from the menu (fixed defaults), only 3 plain toggles left.
  v24.9 | Corner Assist: stable lock + fallback aim points + auto shoulder swap + turn to close enemies when the crosshair cannot reach
  v24.8 | ESP split into its own render step + per-player pcall, camera refresh, draw shim verifies GUI parent renders, iOS prefers shim
  v24.7 | iOS: Instance-based Drawing shim (full ESP without native Drawing), fallback error reporting
  v24.5 | Kamui key gate redesign: fixed black panel (UIGradient on CanvasGroup/buttons), spiral vortex, Sharingan emblem
  v24.4 | New GetKey server + Kamui animated key gate
  v24.3 | Far loot works without getupvalues (event route, for iOS executors); no walking unless allowed in the menu
  v24.2 | Far loot: inside the farm zone, bot bodies and cash bags are taken from any distance (no walking, no pause in aim/fire)
  v24.1 | Light animated Farm HUD | Auto loot bot money | Auto equip gun | FPS Boost re-applies on boot + menu open
  v24 | Auto Farm (bot lock + auto fire + wall check + stats HUD) | Controls-based fire/ADS (iOS) | Drawing guard
  v23 | Sticky aim + auto re-acquire | Random AD strafe | ESP line/corner box/name/head dot | New GUI
  Platform: Auto-detect Android / iOS / PC
]]


-- ═══════════════════════════════════════════════════════════
--  v24.6 COMPAT SHIM — runs first, never errors
--  Normalises the executor API names that differ between Android / iOS
--  executors, and records what is really available (printed at boot).
--  Missing natives cannot be emulated in pure Luau; features that need them
--  take their existing fallback route instead.
-- ═══════════════════════════════════════════════════════════
local CAPS = {}
do
    local function try(f, ...) local ok, r = pcall(f, ...) return ok and r or nil end
    local env = try(function() return getgenv and getgenv() end)

    -- name aliases used by different executors
    local aliases = {
        { "setclipboard",  { "toclipboard", "set_clipboard" } },
        { "getupvalues",   { "debug.getupvalues" } },
        { "getupvalue",    { "debug.getupvalue" } },
        { "request",       { "http_request", "syn.request", "http.request", "fluxus.request" } },
        { "gethui",        { "get_hidden_gui" } },
        { "delfile",       { "deletefile" } },
    }
    local function resolve(path)
        local cur = (env or _G)
        local root = try(function() return getfenv(0) end) or {}
        local first = true
        for part in string.gmatch(path, "[^%.]+") do
            local nxt = first and (try(function() return cur[part] end) or try(function() return root[part] end))
                              or try(function() return cur[part] end)
            if nxt == nil then return nil end
            cur = nxt first = false
        end
        return cur
    end
    for _, a in ipairs(aliases) do
        local name = a[1]
        if type(resolve(name)) ~= "function" then
            for _, alt in ipairs(a[2]) do
                local f = resolve(alt)
                if type(f) == "function" then
                    pcall(function() (env or _G)[name] = f end)
                    break
                end
            end
        end
    end

    local function has(name) return type(resolve(name)) == "function" end
    CAPS.drawing  = (function() local ok, o = pcall(function() return Drawing.new("Line") end)
                       if ok and o then pcall(function() o:Remove() end) return true end return false end)()
    CAPS.files    = has("writefile") and has("readfile")
    CAPS.http     = has("request") or has("http_request")
    CAPS.upvalues = has("getupvalues") or has("getupvalue")
    CAPS.hui      = has("gethui")
    CAPS.clip     = has("setclipboard")
    CAPS.hook     = has("hookfunction") and has("hookmetamethod")
    CAPS.vim      = (pcall(function() return game:GetService("VirtualInputManager") end))
    CAPS.name     = try(function() return (identifyexecutor and select(1, identifyexecutor())) end) or "unknown"
end

-- ═══════════════════════════════════════════════════════════
--  PLATFORM DETECTION
--  Runs first — everything downstream uses PLATFORM.
-- ═══════════════════════════════════════════════════════════
local PLATFORM = (function()
    local uis = game:GetService("UserInputService")
    local hasTouch    = uis.TouchEnabled
    local hasMouse    = uis.MouseEnabled
    local hasKeyboard = uis.KeyboardEnabled
    local hasGamepad  = uis.GamepadEnabled

    local execName = tostring(CAPS.name or ""):lower()
    local execVer = type(EXECUTOR_VERSION) == "string" and EXECUTOR_VERSION:lower() or ""
    local identity = execName .. " " .. execVer
    local manualOverride = ""
    pcall(function()
        local genv = getgenv and getgenv()
        if genv and type(genv.KXY_PLATFORM) == "string" then
            manualOverride = genv.KXY_PLATFORM:lower()
        end
    end)

    -- 1) Ask the client platform first. GetPlatform can be security-restricted
    --    in some Roblox/executor contexts, so this call is always protected.
    local platformToken = ""
    local platformSource = "input fallback"
    local platformCallOK, platformValue = pcall(function()
        return uis:GetPlatform()
    end)
    if platformCallOK and platformValue ~= nil then
        platformToken = tostring(platformValue):lower()
        platformSource = "UserInputService:GetPlatform"
    end

    local engineAndroid = platformToken:find("android", 1, true) ~= nil
    local engineIOS = platformToken:find("ios", 1, true) ~= nil
    local engineDesktop = platformToken:find("windows", 1, true) ~= nil
        or platformToken:find("osx", 1, true) ~= nil
        or platformToken:find("linux", 1, true) ~= nil
        or platformToken:find("steamos", 1, true) ~= nil
        or platformToken:find("uwp", 1, true) ~= nil

    -- 2) Executor-provided OS markers are a secondary source only.
    --    Names such as Delta, Solara, Hydrogen and Fluxus are NOT operating
    --    systems; never infer Android/iOS from those names alone.
    local markerIOS = identity:find("ios", 1, true) ~= nil
        or identity:find("iphone", 1, true) ~= nil
        or identity:find("ipad", 1, true) ~= nil
        or type(ios) == "table"
        or type(IOS_EXECUTOR) == "string"
        or IOS_EXECUTOR == true
    local markerAndroid = identity:find("android", 1, true) ~= nil
        or type(ANDROID_EXECUTOR) == "string"
        or ANDROID_EXECUTOR == true

    local isAndroidExec, isIOSExec, isMobile, isPC = false, false, false, false

    if manualOverride == "android" then
        isAndroidExec, isMobile = true, true
        platformSource = "manual override (KXY_PLATFORM)"
    elseif manualOverride == "ios" or manualOverride == "iphone" or manualOverride == "ipad" then
        isIOSExec, isMobile = true, true
        platformSource = "manual override (KXY_PLATFORM)"
    elseif manualOverride == "pc" or manualOverride == "desktop" then
        isPC = true
        platformSource = "manual override (KXY_PLATFORM)"
    elseif engineAndroid then
        isAndroidExec, isMobile = true, true
        platformSource = "client platform"
    elseif engineIOS then
        isIOSExec, isMobile = true, true
        platformSource = "client platform"
    elseif engineDesktop then
        isPC = true
        platformSource = "client platform"
    elseif markerIOS then
        isIOSExec, isMobile = true, true
        platformSource = "executor OS marker"
    elseif markerAndroid then
        isAndroidExec, isMobile = true, true
        platformSource = "executor OS marker"
    elseif hasTouch then
        -- Safe fallback: when OS identity is unavailable, a touch-capable
        -- client is treated as generic mobile, NEVER as PC. This avoids
        -- mislabelling Android/iPhone devices as PC just because the on-screen
        -- keyboard is reported as available. Do not guess Android vs iOS from
        -- screen orientation, executor brand, mouse or keyboard flags.
        isMobile = true
        platformSource = "touch fallback (OS unknown)"
    else
        isPC = true
        platformSource = "no touch input"
    end

    local platformName = isIOSExec and "iOS"
        or isAndroidExec and "Android"
        or isMobile and "Mobile (OS chưa xác định)"
        or "PC"

    return {
        isIOS = isIOSExec,
        isAndroid = isAndroidExec,
        isMobile = isMobile,
        isPC = isPC,
        name = platformName,
        source = platformSource,
        isGenericMobile = isMobile and not isIOSExec and not isAndroidExec,
        hasTouch = hasTouch,
        hasMouse = hasMouse,
        hasKeyboard = hasKeyboard,
        hasGamepad = hasGamepad,
        defaultStretchX = isAndroidExec and 0.92 or 1.0,
    }
end)()

-- ═══════════════════════════════════════════════════════════
--  COMPAT v24.7 — Drawing guard + Instance-based Drawing shim
--  Native Drawing is used when it exists. Executors without it (common on
--  iOS) get a Frame/TextLabel implementation of Line/Text/Circle so the full
--  ESP (box, corner box, skeleton, tracer, head dot, bars, texts) still works.
--  Only if no GUI parent can be created does the old Highlight fallback run.
-- ═══════════════════════════════════════════════════════════
local HAS_DRAWING = false
local DRAW_MODE   = "none"      -- "native" | "shim" | "none"
local DRAW_INFO   = { parent = "-", abs = "-", vp = "-", players = 0, drawn = 0, noBox = 0, frames = 0, err = nil }
local Drawing = Drawing
do
    -- Instance-based Drawing replacement (Line / Text / Circle only — the only
    -- types this script creates). Properties are buffered and written to the
    -- GUI objects once per frame by a late RenderStep, so From+To or
    -- Position+Text cost one update, and unchanged values are not rewritten.
    local function buildDrawingShim()
        local Players_    = game:GetService("Players")
        local RunService_ = game:GetService("RunService")
        local lpl         = Players_.LocalPlayer

        local parents = {
            { "gethui",    function() return gethui and gethui() end },
            { "CoreGui",   function() return game:GetService("CoreGui") end },
            { "PlayerGui", function() return lpl and lpl:FindFirstChildOfClass("PlayerGui") end },
        }
        local pidx, rootBornAt = 0, 0

        local root = nil
        local function makeRoot(from)
            for i = from, #parents do
                local okP, parent = pcall(parents[i][2])
                if okP and parent then
                    local okG, gui = pcall(function()
                        local g = Instance.new("ScreenGui")
                        g.Name = "KXY_DRAW"
                        g.IgnoreGuiInset = true
                        g.ResetOnSpawn = false
                        g.DisplayOrder = 100
                        g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                        pcall(function() g.ScreenInsets = Enum.ScreenInsets.None end)
                        if type(syn) == "table" and type(syn.protect_gui) == "function" then
                            pcall(syn.protect_gui, g)
                        end
                        g.Parent = parent
                        return g
                    end)
                    if okG and typeof(gui) == "Instance" then
                        if gui.Parent then
                            pidx, rootBornAt = i, os.clock()
                            DRAW_INFO.parent = parents[i][1]
                            return gui
                        end
                        pcall(function() gui:Destroy() end)
                    end
                end
            end
            return nil
        end
        local function ensureRoot()
            if root and root.Parent then return root end
            root = makeRoot(math.max(pidx, 1))
            return root
        end
        if not ensureRoot() then return nil end

        local FONT_MAP = {
            [0] = Enum.Font.GothamMedium, [1] = Enum.Font.GothamMedium,
            [2] = Enum.Font.RobotoMono,   [3] = Enum.Font.RobotoMono,
        }
        local function finite(n) return n == n and n > -1e5 and n < 1e5 end
        local function round(n) return math.floor(n + 0.5) end

        local function buildInst(kind)
            local r = ensureRoot()
            if not r then return nil end
            local fr
            if kind == "Text" then
                fr = Instance.new("TextLabel")
                fr.BackgroundTransparency = 1
                fr.TextYAlignment = Enum.TextYAlignment.Top
                fr.TextStrokeColor3 = Color3.new(0, 0, 0)
                fr.TextWrapped = false
                fr.Text = ""
                fr.Size = UDim2.fromOffset(260, 16)
            else
                fr = Instance.new("Frame")
                fr.AnchorPoint = Vector2.new(0.5, 0.5)
                if kind == "Circle" then
                    local c = Instance.new("UICorner")
                    c.CornerRadius = UDim.new(1, 0)
                    c.Parent = fr
                    local st = Instance.new("UIStroke")
                    st.Name = "S"
                    st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                    st.Parent = fr
                end
            end
            fr.BorderSizePixel = 0
            fr.Active = false
            fr.Visible = false
            fr.Parent = r
            return fr
        end

        local dirty, all = {}, {}
        local errShown = false

        local function newObject(kind)
            local s = {
                Visible = false, Color = Color3.new(1, 1, 1), Transparency = 1, ZIndex = 1,
                Thickness = 1, From = Vector2.new(0, 0), To = Vector2.new(0, 0),
                Text = "", Size = 13, Center = false, Outline = false, Font = 2,
                Position = Vector2.new(0, 0), Radius = 8, Filled = false, NumSides = 16,
            }
            local inst, last, removed = nil, {}, false

            local function render()
                if removed then return end
                if not s.Visible then
                    if inst and last.vis ~= false then
                        last.vis = false
                        pcall(function() inst.Visible = false end)
                    end
                    return
                end
                local r = ensureRoot()
                if not r then return end
                if not inst or inst.Parent ~= r then
                    inst = buildInst(kind)
                    last = {}
                    if not inst then return end
                end

                local col = s.Color
                local alpha = math.clamp(s.Transparency, 0, 1)

                -- Keep Drawing shim coordinates 1:1 with Camera:WorldToViewportPoint.
                -- Scaling by ScreenGui.AbsoluteSize / ViewportSize is unsafe on iOS: the
                -- executor GUI may include safe-area or letterbox space and has a different origin.
                local uniformScale = 1

                if kind == "Line" then
                    local a, b = s.From, s.To
                    local x1, y1, x2, y2 = a.X, a.Y, b.X, b.Y
                    if not (finite(x1) and finite(y1) and finite(x2) and finite(y2)) then
                        if last.vis ~= false then last.vis = false inst.Visible = false end
                        return
                    end
                    local dx, dy = x2 - x1, y2 - y1
                    local len = round(math.sqrt(dx * dx + dy * dy))
                    local th  = math.max(1, round(s.Thickness * uniformScale))
                    local mx, my = round((x1 + x2) * 0.5), round((y1 + y2) * 0.5)
                    local rot = math.deg(math.atan2(dy, dx))
                    if last.len ~= len or last.th ~= th then
                        last.len, last.th = len, th
                        inst.Size = UDim2.fromOffset(len, th)
                    end
                    if last.mx ~= mx or last.my ~= my then
                        last.mx, last.my = mx, my
                        inst.Position = UDim2.fromOffset(mx, my)
                    end
                    if last.rot ~= rot then last.rot = rot inst.Rotation = rot end
                    if last.col ~= col then last.col = col inst.BackgroundColor3 = col end
                    if last.alpha ~= alpha then last.alpha = alpha inst.BackgroundTransparency = 1 - alpha end
                elseif kind == "Text" then
                    local p = s.Position
                    if not (finite(p.X) and finite(p.Y)) then
                        if last.vis ~= false then last.vis = false inst.Visible = false end
                        return
                    end
                    local px, py = round(p.X), round(p.Y)
                    local sz = math.max(8, round(s.Size * uniformScale))
                    local txt = tostring(s.Text)
                    if last.px ~= px or last.py ~= py then
                        last.px, last.py = px, py
                        inst.Position = UDim2.fromOffset(px, py)
                    end
                    if last.txt ~= txt then last.txt = txt inst.Text = txt end
                    if last.sz ~= sz then
                        last.sz = sz
                        inst.TextSize = sz
                        inst.Size = UDim2.fromOffset(260, sz + 4)
                    end
                    if last.center ~= s.Center then
                        last.center = s.Center
                        inst.AnchorPoint = s.Center and Vector2.new(0.5, 0) or Vector2.new(0, 0)
                        inst.TextXAlignment = s.Center and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
                    end
                    if last.font ~= s.Font then
                        last.font = s.Font
                        inst.Font = FONT_MAP[s.Font] or Enum.Font.GothamMedium
                    end
                    if last.col ~= col then last.col = col inst.TextColor3 = col end
                    if last.alpha ~= alpha then last.alpha = alpha inst.TextTransparency = 1 - alpha end
                    local so = s.Outline and (1 - alpha) or 1
                    if last.so ~= so then last.so = so inst.TextStrokeTransparency = so end
                else -- Circle
                    local p = s.Position
                    if not (finite(p.X) and finite(p.Y)) then
                        if last.vis ~= false then last.vis = false inst.Visible = false end
                        return
                    end
                    local rad = math.max(1, round(s.Radius * uniformScale))
                    inst.Size = UDim2.fromOffset(rad * 2, rad * 2)
                    inst.Position = UDim2.fromOffset(round(p.X), round(p.Y))
                    local st = inst:FindFirstChild("S")
                    if s.Filled then
                        inst.BackgroundColor3 = col
                        inst.BackgroundTransparency = 1 - alpha
                        if st then st.Enabled = false end
                    else
                        inst.BackgroundTransparency = 1
                        if st then
                            st.Enabled = true
                            st.Color = col
                            st.Thickness = math.max(1, s.Thickness * uniformScale)
                            st.Transparency = 1 - alpha
                        end
                    end
                end

                if last.z ~= s.ZIndex then last.z = s.ZIndex inst.ZIndex = s.ZIndex end
                if last.vis ~= true then last.vis = true inst.Visible = true end
            end

            all[render] = true
            local function remove()
                removed = true
                all[render], dirty[render] = nil, nil
                if inst then pcall(function() inst:Destroy() end) inst = nil end
            end
            return setmetatable({}, {
                __index = function(_, k)
                    if k == "Remove" or k == "Destroy" then return remove end
                    return s[k]
                end,
                __newindex = function(_, k, v)
                    if s[k] ~= v then
                        s[k] = v
                        if not removed then dirty[render] = true end
                    end
                end,
            })
        end

        local nextCheck = 0
        RunService_:BindToRenderStep("KXYDrawFlush", Enum.RenderPriority.Last.Value, function()
            local nowT = os.clock()
            if nowT >= nextCheck then
                nextCheck = nowT + 0.5
                if root and root.Parent then
                    local sz = root.AbsoluteSize
                    DRAW_INFO.abs = math.floor(sz.X) .. "x" .. math.floor(sz.Y)
                    local cam = workspace.CurrentCamera
                    local vp = cam and cam.ViewportSize
                    DRAW_INFO.vp = (vp and (math.floor(vp.X) .. "x" .. math.floor(vp.Y))) or "-"
                    -- A GUI parent that never lays out (size 0) is not rendering: move to the next one
                    if (nowT - rootBornAt) > 1 and (sz.X < 1 or sz.Y < 1) and pidx < #parents then
                        local old, oldName = root, parents[pidx][1]
                        root = nil
                        pcall(function() old:Destroy() end)
                        root = makeRoot(pidx + 1) or makeRoot(pidx)
                        warn("[KXY] draw shim: '" .. oldName .. "' is not rendering, switched to '" .. DRAW_INFO.parent .. "'")
                        for fn in pairs(all) do dirty[fn] = true end
                    end
                end
            end
            if not (root and root.Parent) then
                if ensureRoot() then
                    for fn in pairs(all) do dirty[fn] = true end   -- root was destroyed: rebuild everything
                end
            end
            for fn in pairs(dirty) do
                dirty[fn] = nil
                local ok, err = pcall(fn)
                if not ok and not errShown then
                    errShown = true
                    warn("[KXY] draw shim error: " .. tostring(err))
                end
            end
        end)

        local noopObj = setmetatable({}, {
            __index = function() return function() end end,
            __newindex = function() end,
        })
        return {
            new = function(kind)
                if kind == "Line" or kind == "Text" or kind == "Circle" then return newObject(kind) end
                return noopObj
            end,
        }
    end

    local function tryNative()
        local made = {}
        for _, kind in ipairs({ "Line", "Text", "Circle" }) do
            local okD, obj = pcall(function() return Drawing.new(kind) end)
            if not okD or not obj then
                for _, old in ipairs(made) do pcall(function() old:Remove() end) end
                return false
            end
            made[#made + 1] = obj
        end
        for _, obj in ipairs(made) do pcall(function() obj:Remove() end) end
        return true
    end
    local function tryShim()
        local okS, shim = pcall(buildDrawingShim)
        if okS and shim then
            Drawing = shim
            return true
        end
        if not okS then warn("[KXY] draw shim failed: " .. tostring(shim)) end
        return false
    end

    -- iOS executors: native Drawing is missing or unreliable, so the Instance shim is preferred.
    -- Override with getgenv().KXY_DRAW_MODE = "native" or "shim" before running the script.
    local forced = nil
    pcall(function() forced = getgenv().KXY_DRAW_MODE end)
    local preferShim = (forced == "shim") or ((PLATFORM.isIOS or PLATFORM.isGenericMobile) and forced ~= "native")

    if preferShim then
        if tryShim() then
            HAS_DRAWING, DRAW_MODE = true, "shim"
        elseif tryNative() then
            HAS_DRAWING, DRAW_MODE = true, "native"
        end
    else
        if tryNative() then
            HAS_DRAWING, DRAW_MODE = true, "native"
        elseif tryShim() then
            HAS_DRAWING, DRAW_MODE = true, "shim"
        end
    end
    if not HAS_DRAWING then
        local noop = function() end
        local dummy = setmetatable({}, {
            __index = function() return noop end,
            __newindex = function() end,
        })
        Drawing = { new = function() return dummy end }
    end
end

-- ═══════════════════════════════════════════════════════════
--  KEY GATE
-- ═══════════════════════════════════════════════════════════
local GETKEY_SERVER = "https://getkey-kxy.vercel.app"
local VERIFY_SERVER = "https://kxypanelkey.vercel.app"
local DISCORD_LINK  = "https://kxypanelkey.vercel.app"
local KEY_FILE      = "kxy_saved_key.txt"

local function runKeyGate()
    local Players          = game:GetService("Players")
    local HttpService      = game:GetService("HttpService")
    local UserInputService = game:GetService("UserInputService")
    local lp               = Players.LocalPlayer or Players.PlayerAdded:Wait()

    -- ── iOS PATCH v22.1: HTTP function resolution + Delta response normalizer ─
    -- Delta/Solara on iOS expose `request` but their response uses .StatusCode
    -- as a string like "200 OK", and body key may be lowercase `.body`
    local _rawHttp = (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
    if type(_rawHttp) ~= "function" then
        warn("[KeyGate] No HTTP function available.")
        return false
    end
    -- Wrap to normalize iOS executor quirks (safe no-op on Android/PC)
    local httpRequest = function(opts)
        local ok, res = pcall(_rawHttp, opts)
        if not ok then return nil end
        if type(res) ~= "table" then return nil end
        -- Normalize status code: Delta returns "200 OK" as string
        if type(res.StatusCode) == "string" then
            res.StatusCode = tonumber(res.StatusCode:match("^%d+")) or 200
        end
        -- Normalize body: some iOS executors use lowercase `.body`
        if res.Body == nil and res.body ~= nil then res.Body = res.body end
        return res
    end
    -- ─────────────────────────────────────────────────────────────────────────

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

    -- Auto-login from saved key
    if type(readfile) == "function" and type(writefile) == "function" then
        local ok, raw = pcall(readfile, KEY_FILE)
        if ok and type(raw) == "string" and raw:match("%S") then
            local savedKey = raw:match("^%s*(.-)%s*$")
            if savedKey ~= "" then
                local vd = apiPost(VERIFY_SERVER, "/api/public/verify", { key = savedKey })
                local valid = vd and vd.valid == true
                if not valid and vd and vd.reason == "not_found" then
                    local ld = apiPost(GETKEY_SERVER, "/api/validate", { key=savedKey, userId=tostring(lp.UserId) })
                    if ld and ld.ok then valid = true end
                end
                if valid then
                    print("[KXY] Auto-login OK.")
                    return true
                else
                    pcall(function()
                        if type(delfile) == "function" then delfile(KEY_FILE)
                        else writefile(KEY_FILE, "") end
                    end)
                end
            end
        end
    end


    -- ═══════════════════════════════════════════════════════════
    --  KAMUI KEY GATE UI (v24.5)
    --  Pure Frame/UIStroke/UIGradient — no asset ids, nothing to download.
    --  One Heartbeat connection drives every animation; it is
    --  disconnected when the ScreenGui is destroyed.
    --
    --  Why v24.4 rendered almost black:
    --    * a UIGradient parented to a CanvasGroup tints EVERYTHING inside it
    --    * a UIGradient on a TextButton also tints its text
    --  v24.5 keeps the background gradient in a child Frame and puts all
    --  button text in separate TextLabels with no gradient.
    -- ═══════════════════════════════════════════════════════════
    local USE_CANVASGROUP = true   -- set to false if the panel still looks wrong on your executor

    local TweenService = game:GetService("TweenService")
    local RunService   = game:GetService("RunService")
    local camera       = workspace.CurrentCamera

    local uiParent
    if type(gethui) == "function" then
        local ok, r = pcall(gethui)
        if ok and r then uiParent = r end
    end
    uiParent = uiParent or lp:WaitForChild("PlayerGui")

    local C = {
        void    = Color3.fromRGB(6, 3, 10),
        panel   = Color3.fromRGB(20, 10, 28),
        field   = Color3.fromRGB(36, 19, 46),
        crimson = Color3.fromRGB(232, 32, 58),
        blood   = Color3.fromRGB(135, 10, 32),
        violet  = Color3.fromRGB(150, 86, 240),
        mist    = Color3.fromRGB(176, 164, 214),
        ember   = Color3.fromRGB(255, 120, 100),
        hot     = Color3.fromRGB(255, 226, 214),
        text    = Color3.fromRGB(252, 240, 246),
        dim     = Color3.fromRGB(208, 172, 196),
        ok      = Color3.fromRGB(120, 235, 170),
        bad     = Color3.fromRGB(255, 95, 110),
        ink     = Color3.fromRGB(8, 2, 6),
    }

    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        o.Parent = parent
        return o
    end

    local function kp(t, c) return ColorSequenceKeypoint.new(t, c) end
    local function nk(t, v) return NumberSequenceKeypoint.new(t, v) end

    local function tween(o, t, props, style, dir, delay)
        local tw = TweenService:Create(o, TweenInfo.new(t,
            style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
        tw:Play()
        return tw
    end

    local function copyText(s)
        local clip = setclipboard or toclipboard
            or (type(deltaclipboard) == "function" and deltaclipboard)
            or (type(rbxclipboard) == "function" and rbxclipboard)
        if clip then pcall(clip, s) end
    end

    local function openUrl(url)
        pcall(function() game:GetService("GuiService"):OpenBrowserWindow(url) end)
    end

    local function viewport()
        return camera and camera.ViewportSize or Vector2.new(800, 400)
    end
    local VH = math.max(viewport().Y, 200)

    local SG = new("ScreenGui", {
        Name = "KXYKeyGate", ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 999999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, uiParent)

    local fxAlpha, fxTarget = 0, 1      -- global fade of vortex / glow / embers
    local warp, warpTarget  = 1, 1      -- global speed multiplier

    -- ── Layer 1: dim ──
    local overlay = new("Frame", {
        Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.void,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
    }, SG)

    -- ── Layer 2: soft radial glow (stacked discs, no hard edge) ──
    local glowHolder = new("Frame", {
        Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1.25, 1.25), SizeConstraint = Enum.SizeConstraint.RelativeYY,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
    }, SG)
    local glowScale = new("UIScale", { Scale = 1 }, glowHolder)
    local GLOW_N, GLOW_BASE = 12, 0.975
    local glowDiscs = {}
    for i = 1, GLOW_N do
        local k = (i - 1) / GLOW_N
        local d = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(1 - k * 0.92, 1 - k * 0.92),
            BackgroundColor3 = C.violet:Lerp(C.crimson, k), BackgroundTransparency = 1,
            BorderSizePixel = 0, ZIndex = 2,
        }, glowHolder)
        new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, d)
        glowDiscs[i] = d
    end

    -- ── Layer 3: Kamui spiral — streaks fall along a logarithmic spiral into the centre ──
    local spiralHolder = new("Frame", {
        Name = "Spiral", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(2.4, 2.4), SizeConstraint = Enum.SizeConstraint.RelativeYY,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
    }, SG)

    local ARMS, PER_ARM = 6, 14
    local spiralDots = {}
    for a = 1, ARMS do
        for j = 1, PER_ARM do
            local f = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1),
                BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(2, 10),
            }, spiralHolder)
            new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
            spiralDots[#spiralDots + 1] = {
                f = f,
                arm = (a - 1) / ARMS * math.pi * 2,
                off = (j - 1) / PER_ARM + (a % 2) * 0.5 / PER_ARM,
            }
        end
    end

    local K_SWIRL = 1.05
    local flow, spin = 0, 0

    -- k: 0 = outer edge, 1 = centre
    local function spiralColor(k)
        if k < 0.4 then return C.mist:Lerp(C.violet, k / 0.4) end
        if k < 0.8 then return C.violet:Lerp(C.crimson, (k - 0.4) / 0.4) end
        return C.crimson:Lerp(C.hot, (k - 0.8) / 0.2)
    end

    local function stepSpiral(dt)
        flow = (flow + dt * 0.11 * warp) % 1
        spin = spin + dt * 0.16 * math.min(warp, 6)
        local lenMul = 0.8 + 0.16 * math.min(warp, 14)
        for _, d in ipairs(spiralDots) do
            local u = (d.off + flow) % 1
            local s = 1 - u ^ 1.6                      -- 1 = outer, 0 = centre, accelerates inward
            local th = d.arm + spin + K_SWIRL * math.log(1 / (s + 0.06))
            local rad = s * 0.5
            local f = d.f
            f.Position = UDim2.fromScale(0.5 + math.cos(th) * rad, 0.5 + math.sin(th) * rad)
            local psi = math.atan(K_SWIRL * s / (s + 0.06))
            f.Rotation = math.deg(th - psi) + 90
            local len = (0.010 + 0.040 * (1 - s)) * VH * lenMul
            local wid = math.max(1.5, VH * 0.004 * (0.6 + 0.8 * s))
            f.Size = UDim2.fromOffset(wid, len)
            local a = math.clamp(u * 6, 0, 1) * math.clamp(s * 7, 0, 1)
            f.BackgroundTransparency = 1 - a * 0.85 * fxAlpha
            f.BackgroundColor3 = spiralColor(1 - s)
        end
    end

    -- ── Layer 3b: big comet rings (Mangekyō-style sweeping arcs) ──
    local ringHolder = new("Frame", {
        Name = "Rings", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1.45, 1.45), SizeConstraint = Enum.SizeConstraint.RelativeYY,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
    }, SG)

    local function cometGradient(parentStroke, rot)
        return new("UIGradient", {
            Color = ColorSequence.new({ kp(0, C.violet), kp(0.5, C.crimson), kp(1, C.ember) }),
            Transparency = NumberSequence.new({
                nk(0, 1), nk(0.18, 0), nk(0.5, 0.45), nk(0.72, 1), nk(1, 1),
            }),
            Rotation = rot or 0,
        }, parentStroke)
    end

    local bigRings = {}
    for i = 1, 5 do
        local f = new("Frame", {
            Name = "Ring" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        }, ringHolder)
        new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
        local st = new("UIStroke", {
            Thickness = 5, Color = Color3.new(1, 1, 1), Transparency = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, f)
        bigRings[i] = {
            f = f, st = st, g = cometGradient(st, (i * 67) % 360), thick = 5,
            dir = (i % 2 == 0) and -1 or 1, speed = 60 + i * 21, phase = (i - 1) / 5,
        }
    end

    local function stepRings(rings, dt, minScale)
        for _, r in ipairs(rings) do
            r.phase = (r.phase + dt * 0.14 * warp) % 1
            local p = r.phase
            local s = minScale + (1 - minScale) * (1 - p)
            r.f.Size = UDim2.fromScale(s, s)
            local a = math.sin(p * math.pi)
            r.st.Transparency = 1 - a * 0.9 * fxAlpha
            r.st.Thickness = math.max(1, r.thick * (0.35 + 0.65 * s))
            r.g.Rotation = (r.g.Rotation + r.dir * r.speed * dt * warp) % 360
        end
    end

    -- ── Layer 4: embers spiralling inward ──
    local fx = new("Frame", {
        Name = "Embers", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 4,
    }, SG)
    local rng = Random.new()
    local embers = {}
    local function respawn(e, anywhere)
        local vp = viewport()
        local maxR = math.max(vp.X, vp.Y) * 0.55
        e.maxR = maxR
        e.r = anywhere and (maxR * (0.3 + rng:NextNumber() * 0.7)) or maxR
        e.a = rng:NextNumber() * math.pi * 2
        local sz = rng:NextInteger(2, 4)
        e.f.Size = UDim2.fromOffset(sz, sz)
        e.f.BackgroundColor3 = (rng:NextNumber() < 0.65) and C.ember or C.violet
    end
    for i = 1, 16 do
        local f = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0,
        }, fx)
        new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
        local e = { f = f }
        respawn(e, true)
        embers[i] = e
    end
    local function stepEmbers(dt)
        for _, e in ipairs(embers) do
            e.a = e.a + dt * (2.6 * 130 / (e.r + 70)) * warp
            e.r = e.r - dt * (45 + 0.22 * e.r) * warp
            if e.r < 14 then respawn(e, false) end
            local k = math.clamp(e.r / e.maxR, 0, 1)
            e.f.Position = UDim2.new(0.5, math.cos(e.a) * e.r, 0.5, math.sin(e.a) * e.r)
            e.f.BackgroundTransparency = 1 - math.sin(k * math.pi) * 0.9 * fxAlpha
        end
    end

    -- ── Panel ──
    local PANEL_W, PANEL_H = 340, 400
    local panel
    if USE_CANVASGROUP then
        local okCG, cg = pcall(Instance.new, "CanvasGroup")
        if okCG and cg then panel = cg end
    end
    local canFade = panel ~= nil
    if not panel then panel = Instance.new("Frame") end
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
    panel.BackgroundColor3 = C.panel
    panel.BackgroundTransparency = 0
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.ZIndex = 10
    panel.Rotation = -120
    if canFade then panel.GroupTransparency = 1 end
    panel.Parent = SG

    new("UICorner", { CornerRadius = UDim.new(0, 18) }, panel)
    local fit = math.clamp((VH - 24) / PANEL_H, 0.55, 1)
    local pScale = new("UIScale", { Scale = 0.05 }, panel)
    local pStroke = new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.05 }, panel)
    local pStrokeG = new("UIGradient", {
        Color = ColorSequence.new({
            kp(0, C.crimson), kp(0.35, C.violet), kp(0.65, C.blood), kp(1, C.crimson),
        }),
    }, pStroke)

    -- Background lives in a child Frame. NEVER put this UIGradient on `panel` itself.
    local bg = new("Frame", {
        Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0, ZIndex = 0,
    }, panel)
    new("UIGradient", {
        Color = ColorSequence.new({
            kp(0, Color3.fromRGB(38, 15, 44)),
            kp(0.55, Color3.fromRGB(20, 10, 28)),
            kp(1, Color3.fromRGB(12, 7, 20)),
        }),
        Rotation = 100,
    }, bg)
    local topGlow = new("Frame", {
        Name = "TopGlow", Size = UDim2.new(1, 0, 0, 170), BackgroundColor3 = C.crimson,
        BorderSizePixel = 0, ZIndex = 0,
    }, panel)
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({ nk(0, 0.6), nk(1, 1) }),
    }, topGlow)

    -- Drag handle first so every other child draws above it.
    local header = new("Frame", {
        Name = "Header", Size = UDim2.new(1, 0, 0, 146), BackgroundTransparency = 1,
        BorderSizePixel = 0, Active = true, ZIndex = 1,
    }, panel)

    local accentBar = new("Frame", {
        Size = UDim2.new(1, 0, 0, 3), BorderSizePixel = 0,
        BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3,
    }, panel)
    local accentG = new("UIGradient", {
        Color = ColorSequence.new({ kp(0, C.blood), kp(0.5, C.ember), kp(1, C.blood) }),
    }, accentBar)

    -- Shine sweep (under the controls, over the background)
    local shine = new("Frame", {
        Name = "Shine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(-80, PANEL_H / 2),
        Size = UDim2.fromOffset(46, PANEL_H * 1.8), Rotation = 18,
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2,
    }, panel)
    new("UIGradient", {
        Transparency = NumberSequence.new({ nk(0, 1), nk(0.5, 0.9), nk(1, 1) }),
    }, shine)

    -- ── Sharingan emblem ──
    local EMB = 84
    local emblem = new("Frame", {
        Name = "Emblem", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(EMB, EMB), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
    }, panel)

    local halo = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1.5, 1.5), BackgroundColor3 = C.crimson,
        BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = 2,
    }, emblem)
    new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, halo)

    local iris = new("Frame", {
        Name = "Iris", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0, ZIndex = 3,
    }, emblem)
    new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, iris)
    new("UIGradient", {
        Color = ColorSequence.new({ kp(0, Color3.fromRGB(255, 72, 84)), kp(1, Color3.fromRGB(150, 6, 26)) }),
        Rotation = 90,
    }, iris)
    local irisStroke = new("UIStroke", { Color = C.ink, Thickness = 2.5 }, iris)

    local track = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.64, 0.64), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4,
    }, emblem)
    new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, track)
    new("UIStroke", { Color = C.ink, Thickness = 1.5, Transparency = 0.35 }, track)

    local pupil = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.2, 0.2), BackgroundColor3 = C.ink, BorderSizePixel = 0, ZIndex = 5,
    }, emblem)
    new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pupil)

    -- Three tomoe: comma shapes (head + two shrinking tail beads), head leads the orbit.
    local tomoe = {}
    local TOMOE_PARTS = { { 0.60, 0.62, 0.50 }, { 0.38, 0.30, 0.40 }, { 0.22, 0.08, 0.28 } }
    for i = 1, 3 do
        local t = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(25, 25),
            BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5,
        }, emblem)
        for _, p in ipairs(TOMOE_PARTS) do
            local c = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(p[2], p[3]),
                Size = UDim2.fromScale(p[1], p[1]), BackgroundColor3 = C.ink,
                BorderSizePixel = 0, ZIndex = 5,
            }, t)
            new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, c)
        end
        tomoe[i] = t
    end

    -- Two counter-rotating comet rings around the eye
    local auras = {}
    for i = 1, 2 do
        local sc = 1.14 + (i - 1) * 0.2
        local f = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(sc, sc), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4,
        }, emblem)
        new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
        local st = new("UIStroke", {
            Thickness = 2, Color = Color3.new(1, 1, 1), Transparency = 0.1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, f)
        auras[i] = { g = cometGradient(st, i * 120), dir = (i == 1) and 1 or -1, speed = 120 + i * 40 }
    end

    local function pulseRing(col, big)
        if not emblem.Parent then return end
        local r = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(0.9, 0.9), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6,
        }, emblem)
        new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, r)
        local st = new("UIStroke", { Color = col, Thickness = 3, Transparency = 0.05 }, r)
        local target = big and 6 or 3.4
        tween(r, 0.75, { Size = UDim2.fromScale(target, target) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        local tw = tween(st, 0.75, { Transparency = 1, Thickness = 0.5 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        tw.Completed:Connect(function() r:Destroy() end)
    end

    local title = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 102),
        BackgroundTransparency = 1, Text = "KXY", TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold, TextSize = 26, ZIndex = 3,
    }, panel)
    local titleG = new("UIGradient", {
        Color = ColorSequence.new({
            kp(0, Color3.fromRGB(255, 255, 255)), kp(0.5, Color3.fromRGB(255, 140, 156)), kp(1, C.crimson),
        }),
    }, title)
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 130),
        BackgroundTransparency = 1, Text = "KAMUI  ·  KEY AUTHENTICATION",
        TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 10, ZIndex = 3,
    }, panel)

    -- ── Inputs / buttons ──
    local function mkBox(placeholder, posY)
        local box = new("TextBox", {
            Size = UDim2.new(1, -48, 0, 40), Position = UDim2.new(0, 24, 0, posY),
            BackgroundColor3 = C.field, BorderSizePixel = 0,
            PlaceholderText = placeholder, PlaceholderColor3 = Color3.fromRGB(160, 120, 150),
            Text = "", TextColor3 = C.text, TextSize = 13, Font = Enum.Font.Gotham,
            ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = false, ZIndex = 3,
        }, panel)
        new("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
        local s = new("UIStroke", { Color = C.violet, Transparency = 0.45, Thickness = 1 }, box)
        new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)
        box.Focused:Connect(function()
            tween(s, 0.18, { Color = C.crimson, Transparency = 0.0, Thickness = 1.6 })
            pulseRing(C.violet, false)
        end)
        box.FocusLost:Connect(function()
            tween(s, 0.25, { Color = C.violet, Transparency = 0.45, Thickness = 1 })
        end)
        return box
    end

    -- Button text is a separate TextLabel: the UIGradient below would tint it otherwise.
    local function mkBtn(text, posY, colA, colB, strokeCol)
        local btn = new("TextButton", {
            Size = UDim2.new(1, -48, 0, 40), Position = UDim2.new(0, 24, 0, posY),
            BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Text = "",
            AutoButtonColor = false, ZIndex = 3,
        }, panel)
        new("UICorner", { CornerRadius = UDim.new(0, 10) }, btn)
        local g = new("UIGradient", {
            Color = ColorSequence.new({ kp(0, colA), kp(0.5, colB), kp(1, colA) }),
        }, btn)
        local s  = new("UIStroke", { Color = strokeCol, Transparency = 0.35, Thickness = 1 }, btn)
        local sc = new("UIScale", { Scale = 1 }, btn)
        local lbl = new("TextLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text,
            TextColor3 = C.text, TextSize = 13, Font = Enum.Font.GothamBold, ZIndex = 4,
        }, btn)
        local quick = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        btn.MouseEnter:Connect(function()
            TweenService:Create(s, quick, { Transparency = 0.0 }):Play()
            TweenService:Create(sc, quick, { Scale = 1.025 }):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(s, quick, { Transparency = 0.35 }):Play()
            TweenService:Create(sc, quick, { Scale = 1 }):Play()
        end)
        btn.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
                TweenService:Create(sc, TweenInfo.new(0.08), { Scale = 0.95 }):Play()
            end
        end)
        btn.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
                TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
            end
        end)
        return btn, g, lbl
    end

    local keyBox = mkBox("Paste your key here...", 158)
    local getBtn, _, getLbl = mkBtn("GET KEY", 206, Color3.fromRGB(70, 34, 100), Color3.fromRGB(116, 60, 168), C.violet)
    local verifyBtn, verifyG, verifyLbl = mkBtn("VERIFY KEY", 254, C.blood, Color3.fromRGB(240, 44, 78), C.ember)

    local statusLbl = new("TextLabel", {
        Size = UDim2.new(1, -48, 0, 34), Position = UDim2.new(0, 24, 0, 304),
        BackgroundColor3 = Color3.fromRGB(30, 14, 38), BorderSizePixel = 0, ZIndex = 3,
        Text = "Waiting for key...", TextColor3 = C.dim, Font = Enum.Font.Gotham,
        TextSize = 11, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
    }, panel)
    new("UICorner", { CornerRadius = UDim.new(0, 10) }, statusLbl)
    local statusStroke = new("UIStroke", { Color = C.dim, Transparency = 0.7, Thickness = 1 }, statusLbl)

    local discordBtn = new("TextButton", {
        Size = UDim2.new(1, -48, 0, 34), Position = UDim2.new(0, 24, 0, 348),
        BackgroundColor3 = Color3.fromRGB(88, 101, 242), BorderSizePixel = 0,
        Text = "JOIN DISCORD", TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = false, ZIndex = 3,
    }, panel)
    new("UICorner", { CornerRadius = UDim.new(0, 10) }, discordBtn)
    local dScale = new("UIScale", { Scale = 1 }, discordBtn)
    discordBtn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            TweenService:Create(dScale, TweenInfo.new(0.08), { Scale = 0.95 }):Play()
        end
    end)
    discordBtn.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            TweenService:Create(dScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
        end
    end)
    discordBtn.Activated:Connect(function()
        openUrl(DISCORD_LINK)
        copyText(DISCORD_LINK)
    end)

    -- ── Status text (typewriter) + shake ──
    local statusTok = 0
    local function setStatus(text, kind)
        statusTok = statusTok + 1
        local tok = statusTok
        local col = (kind == "ok" and C.ok) or (kind == "bad" and C.bad) or C.dim
        statusLbl.Text = text
        statusLbl.TextColor3 = col
        statusStroke.Color = col
        statusStroke.Transparency = (kind == "ok" or kind == "bad") and 0.3 or 0.7
        task.spawn(function()
            pcall(function()
                local n = utf8.len(text) or #text
                for i = 1, n do
                    if tok ~= statusTok or not statusLbl.Parent then return end
                    statusLbl.MaxVisibleGraphemes = i
                    task.wait(0.012)
                end
                if tok == statusTok then statusLbl.MaxVisibleGraphemes = -1 end
            end)
        end)
    end

    local function shake()
        local base = panel.Position
        task.spawn(function()
            for _, dx in ipairs({ 10, -9, 7, -5, 3, 0 }) do
                if not panel.Parent then return end
                panel.Position = UDim2.new(base.X.Scale, base.X.Offset + dx, base.Y.Scale, base.Y.Offset)
                task.wait(0.035)
            end
        end)
    end

    -- ── Drag (header only) ──
    local dragging, dStart, dStartPos = false, nil, nil
    local dragConns = {}
    header.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true dStart = inp.Position dStartPos = panel.Position
        end
    end)
    dragConns[#dragConns + 1] = UserInputService.InputChanged:Connect(function(inp)
        if dragging and dStart and dStartPos
        and (inp.UserInputType == Enum.UserInputType.MouseMovement
          or inp.UserInputType == Enum.UserInputType.Touch) then
            local d = inp.Position - dStart
            panel.Position = UDim2.new(dStartPos.X.Scale, dStartPos.X.Offset + d.X,
                                       dStartPos.Y.Scale, dStartPos.Y.Offset + d.Y)
        end
    end)
    dragConns[#dragConns + 1] = UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false dStart = nil dStartPos = nil
        end
    end)

    -- White flash used for the teleport in / out
    local flash = new("Frame", {
        Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.hot,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50,
    }, SG)

    -- ── Animation loop ──
    local orbitA, t0 = 0, os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        dt = math.min(dt, 0.05)
        warp    = warp + (warpTarget - warp) * math.min(1, dt * 3.5)
        fxAlpha = fxAlpha + (fxTarget - fxAlpha) * math.min(1, dt * 3)
        local t = os.clock() - t0

        stepSpiral(dt)
        stepRings(bigRings, dt, 0.10)
        stepEmbers(dt)

        local breathe = 0.85 + 0.15 * math.sin(t * 1.6)
        glowScale.Scale = 0.96 + 0.06 * math.sin(t * 1.2)
        local gT = 1 - (1 - GLOW_BASE) * fxAlpha * breathe
        for _, d in ipairs(glowDiscs) do d.BackgroundTransparency = gT end

        -- Sharingan: tomoe orbit (faster while the vortex is warping), halo pulse, aura rings
        orbitA = orbitA + dt * 1.8 * math.min(warp, 6)
        for i, tm in ipairs(tomoe) do
            local a = orbitA + (i - 1) * (math.pi * 2 / 3)
            tm.Position = UDim2.fromScale(0.5 + math.cos(a) * 0.32, 0.5 + math.sin(a) * 0.32)
            tm.Rotation = math.deg(a) + 90
        end
        halo.BackgroundTransparency = 0.84 + 0.08 * math.sin(t * 2.4)
        for _, au in ipairs(auras) do
            au.g.Rotation = (au.g.Rotation + au.dir * au.speed * dt * math.min(warp, 4)) % 360
        end

        pStrokeG.Rotation = (t * 60) % 360
        titleG.Rotation   = (t * 35) % 360
        accentG.Offset    = Vector2.new((t * 0.5 % 2) - 1, 0)
        verifyG.Offset    = Vector2.new((t * 0.55 % 2) - 1, 0)
        shine.Position    = UDim2.fromOffset(((t * 0.3) % 1.7 - 0.35) * PANEL_W, PANEL_H / 2)
    end)
    SG.Destroying:Connect(function()
        if conn then conn:Disconnect() end
        for _, c in ipairs(dragConns) do c:Disconnect() end
    end)

    -- ── Intro: teleport flash, panel spins out of the vortex, controls rise in one by one ──
    warp = 10
    flash.BackgroundTransparency = 0.45
    tween(flash, 0.6, { BackgroundTransparency = 1 })
    tween(overlay, 0.5, { BackgroundTransparency = 0.35 })
    tween(pScale, 0.8, { Scale = fit }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    tween(panel, 0.85, canFade and { Rotation = 0, GroupTransparency = 0 } or { Rotation = 0 },
        Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    for i, o in ipairs({ keyBox, getBtn, verifyBtn, statusLbl, discordBtn }) do
        local p = o.Position
        o.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + 22)
        tween(o, 0.55, { Position = p }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.3 + i * 0.07)
    end

    -- ── Outro: panel is pulled into the vortex centre, white flash, vortex fades ──
    local function playOutro()
        warpTarget = 16
        tween(pScale, 0.75, { Scale = 0.02 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
        tween(panel, 0.75, canFade
            and { Rotation = 400, GroupTransparency = 1, Position = UDim2.fromScale(0.5, 0.5) }
            or  { Rotation = 400, Position = UDim2.fromScale(0.5, 0.5) },
            Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        task.wait(0.62)
        tween(flash, 0.14, { BackgroundTransparency = 0.05 })
        task.wait(0.16)
        fxTarget = 0
        tween(overlay, 0.45, { BackgroundTransparency = 1 })
        tween(flash, 0.45, { BackgroundTransparency = 1 })
        task.wait(0.5)
    end

    -- ── Logic ──
    local authorized = false
    local busy = false
    local function setBusy(b)
        busy = b
        warpTarget = b and 3 or 1
    end

    getBtn.Activated:Connect(function()
        if busy then return end
        setBusy(true) getLbl.Text = "CREATING LINK..."
        setStatus("Connecting to key server...", "info")
        task.spawn(function()
            local data, err = apiPost(GETKEY_SERVER, "/api/start", { userId = tostring(lp.UserId) })
            if data and data.ok and data.shortUrl then
                openUrl(data.shortUrl)
                copyText(data.shortUrl)
                setStatus("Link opened! Complete in browser, then paste key.", "ok")
                pulseRing(C.ok, false)
            else
                -- API route not available on the server: open the GetKey site and
                -- copy the Roblox User ID, which the site asks for.
                openUrl(GETKEY_SERVER)
                copyText(tostring(lp.UserId))
                setStatus((err or "Key API unavailable") .. " — GetKey site opened, User ID " .. tostring(lp.UserId) .. " copied.", "info")
            end
            getLbl.Text = "GET KEY" setBusy(false)
        end)
    end)

    local function doVerify()
        if busy then return end
        local key = (keyBox.Text or ""):match("^%s*(.-)%s*$")
        if key == "" then
            setStatus("Paste your key first.", "bad")
            pulseRing(C.bad, false)
            shake()
            return
        end
        setBusy(true) verifyLbl.Text = "VERIFYING..." setStatus("Checking key...", "info")
        task.spawn(function()
            local data, err = apiPost(VERIFY_SERVER, "/api/public/verify", { key = key })
            local valid = data and data.valid == true
            local reason = data and (data.reason or data.error) or err
            if not valid and data and data.reason == "not_found" then
                local ld, le = apiPost(GETKEY_SERVER, "/api/validate", { key = key, userId = tostring(lp.UserId) })
                if ld and ld.ok then valid = true
                else reason = (ld and ld.error) or le or reason end
            end
            if valid then
                pcall(function()
                    if type(writefile) == "function" then writefile(KEY_FILE, key) end
                end)
                setStatus("Key accepted. Entering Kamui...", "ok")
                pulseRing(C.ok, true)
                playOutro()
                authorized = true
                SG:Destroy()
                return
            end
            setStatus("Rejected: " .. tostring(reason or "unknown"), "bad")
            pulseRing(C.bad, true)
            shake() warp = 9
            verifyLbl.Text = "VERIFY KEY" setBusy(false)
        end)
    end

    verifyBtn.Activated:Connect(doVerify)
    keyBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then doVerify() end
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
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local lp                = Players.LocalPlayer
local camera            = workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════
--  NON-WEAPON FILTER
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

-- ═══════════════════════════════════════════════════════════
--  CONFIG  — defaults, then overridden by saved file
-- ═══════════════════════════════════════════════════════════
local CFG = {
    -- Aim
    fov            = 150,
    aimDist        = 550,
    aimOn          = true,
    wallCheck      = true,
    foliageBypass  = true,
    stretchX       = PLATFORM.defaultStretchX,
    trackSpeed     = 0.45,
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
    -- SmoothShot
    smoothShot         = true,
    smoothShotAdsDelay = 0.06,
    recoilCounterStr   = 0.72,
    recoilCounterUp    = 0.055,
    recoilCounterSide  = 0.012,
    recoilDecay        = 0.14,
    -- ESP
    espOn        = true,
    espDist      = 650,
    espWeapon    = true,
    espSkeleton  = true,
    -- Aim v23
    stickOn        = true,      -- sticky lock: aim converges to the target and never trails it
    stickStrength  = 0.80,      -- 0..1, how far the track speed is pushed toward 1.0
    stickSnapDeg   = 1.5,       -- inside this angular error the camera snaps onto the target
    reacquire      = true,      -- while fire is held, look for a new target when the lock is lost
    reacquireGap   = 0.05,      -- seconds between re-acquire scans
    -- Corner Assist (v25: only the three toggles are in the menu; the numbers below are fixed defaults, not saved)
    cornerOn           = true,  -- master switch for everything below (false = plain aimbot)
    cornerSwap         = true,  -- press the shoulder swap itself when the other shoulder can reach the target
    cornerWide         = true,  -- turn the view to a close enemy outside the FOV ring / beside or behind the camera
    cornerRange        = 30,    -- fixed: studs from the camera, only used by cornerWide
    cornerGrace        = 0.35,  -- fixed: seconds the lock and the last aim point are held while the target is hidden
    cornerSwapDelay    = 0.12,  -- fixed: seconds a target must stay unreachable before the shoulder is swapped
    cornerSwapCooldown = 1.2,   -- fixed: seconds between two swaps
    cornerSettle       = 0.45,  -- fixed: seconds after a swap while the camera is still sliding
    -- ESP v23
    espBoxStyle  = "Corner",    -- "Corner" | "Full"
    espLine      = true,
    espLineFrom  = "Bottom",    -- "Bottom" | "Center" | "Top"
    espName      = true,
    espHeadDot   = true,
    esp = {
        box      = Color3.fromRGB(255, 255, 255),
        skeleton = Color3.fromRGB(80,  200, 255),
        barBg    = Color3.fromRGB(30,  30,  30),
        barAlive = Color3.fromRGB(80,  220, 80),
        barLow   = Color3.fromRGB(220, 60,  60),
        weapon   = Color3.fromRGB(255, 220, 80),
        line     = Color3.fromRGB(255, 90,  90),
        name     = Color3.fromRGB(255, 255, 255),
        thick    = 1,
        boneThick= 1,
    },
    fov_circle = {
        color = Color3.fromRGB(255, 255, 255),
        thick = 1,
        sides = 64,
    },
    -- Farm v24
    farmZoneOnly   = true,      -- only bots inside the farm zone, and only while you are inside it
    farmWall       = true,      -- bullet-style raycast from camera and from your head
    farmAim        = true,      -- lock the camera on the bot
    farmShoot      = true,      -- auto fire when the crosshair is on the bot
    farmSkipDowned = false,     -- skip bots with the HoodDowned attribute
    farmPart       = "Head",    -- "Head" | "Torso"
    farmDist       = 50,
    farmAimSpeed   = 0.85,
    farmAntiAfk    = true,
    farmHud        = true,
    farmAutoLoot   = true,      -- call the game's native HoodNPC corpse-loot action; FarmZone + farm distance gated
    farmAutoEquip  = true,
    farmBotESP     = false,     -- client-side BillboardGui + Highlight, no Drawing API
    farmZoneESP    = false,     -- client-side zone-volume adornments
    -- FPS Boost
    fpsBoost = {
        on             = false,
        shadowDisable  = true,
        textureQuality = true,
        particleOff    = true,
        decalOff       = false,
        lightingSimple = true,
    },
}

-- ═══════════════════════════════════════════════════════════
--  CONFIG PERSISTENCE
-- ═══════════════════════════════════════════════════════════
local CONFIG_FILE = "kxy_config.json"
local canSave = type(writefile) == "function" and type(readfile) == "function"

local function encodeColor(c)
    if typeof(c) ~= "Color3" then return {r=255,g=255,b=255} end
    return { r=math.round(c.R*255), g=math.round(c.G*255), b=math.round(c.B*255) }
end
local function decodeColor(t)
    if type(t) ~= "table" then return nil end
    return Color3.fromRGB(t.r or 255, t.g or 255, t.b or 255)
end

-- AntiAim forward-declare so serializeCFG can safely reference it
local AntiAim = {
    enabled         = true,
    adStrafeEnabled = true,
    adStrafeMinTime = 0.12,
    adStrafeMaxTime = 0.42,
    adFlipChance    = 0.85,   -- chance to reverse direction at each step (else keep going)
    adPauseChance   = 0.15,   -- chance of a short stop at each step
    adPauseMin      = 0.05,
    adPauseMax      = 0.16,
    _nextADStrafe   = 0,
    _pauseUntil     = 0,
    _adDir          = 1,
    _adVec          = nil,
}

local function serializeCFG()
    return {
        fov=CFG.fov, aimDist=CFG.aimDist, aimOn=CFG.aimOn,
        wallCheck=CFG.wallCheck, foliageBypass=CFG.foliageBypass,
        stretchX=CFG.stretchX, trackSpeed=CFG.trackSpeed,
        smoothShot=CFG.smoothShot, recoilCounterStr=CFG.recoilCounterStr,
        espOn=CFG.espOn, espDist=CFG.espDist,
        espWeapon=CFG.espWeapon, espSkeleton=CFG.espSkeleton,
        stickOn=CFG.stickOn, stickStrength=CFG.stickStrength, reacquire=CFG.reacquire,
        espBoxStyle=CFG.espBoxStyle, espLine=CFG.espLine, espLineFrom=CFG.espLineFrom,
        espName=CFG.espName, espHeadDot=CFG.espHeadDot,
        esp = {
            box=encodeColor(CFG.esp.box), skeleton=encodeColor(CFG.esp.skeleton),
            line=encodeColor(CFG.esp.line), name=encodeColor(CFG.esp.name),
            barAlive=encodeColor(CFG.esp.barAlive), barLow=encodeColor(CFG.esp.barLow),
            weapon=encodeColor(CFG.esp.weapon),
            thick=CFG.esp.thick, boneThick=CFG.esp.boneThick,
        },
        fpsBoost = {
            on=CFG.fpsBoost.on, shadowDisable=CFG.fpsBoost.shadowDisable,
            textureQuality=CFG.fpsBoost.textureQuality,
            particleOff=CFG.fpsBoost.particleOff,
            decalOff=CFG.fpsBoost.decalOff, lightingSimple=CFG.fpsBoost.lightingSimple,
        },
        farm = {
            zoneOnly=CFG.farmZoneOnly, wall=CFG.farmWall, aim=CFG.farmAim, shoot=CFG.farmShoot,
            skipDowned=CFG.farmSkipDowned, part=CFG.farmPart, dist=CFG.farmDist,
            aimSpeed=CFG.farmAimSpeed, antiAfk=CFG.farmAntiAfk, hud=CFG.farmHud,
            autoLoot=CFG.farmAutoLoot, autoEquip=CFG.farmAutoEquip,
            botESP=CFG.farmBotESP, zoneESP=CFG.farmZoneESP,
        },
        corner = { on=CFG.cornerOn, swap=CFG.cornerSwap, wide=CFG.cornerWide },
        antiAimEnabled = AntiAim.enabled,
        adStrafeEnabled = AntiAim.adStrafeEnabled,
        adStrafeMinTime = AntiAim.adStrafeMinTime, adStrafeMaxTime = AntiAim.adStrafeMaxTime,
        adPauseChance = AntiAim.adPauseChance,
    }
end

local function applySavedCFG(data)
    if type(data) ~= "table" then return end
    if type(data.fov)            == "number"  then CFG.fov            = data.fov            end
    if type(data.aimDist)        == "number"  then CFG.aimDist        = data.aimDist        end
    if type(data.aimOn)          == "boolean" then CFG.aimOn          = data.aimOn          end
    if type(data.wallCheck)      == "boolean" then CFG.wallCheck      = data.wallCheck      end
    if type(data.foliageBypass)  == "boolean" then CFG.foliageBypass  = data.foliageBypass  end
    if type(data.stretchX)       == "number"  then CFG.stretchX       = math.clamp(data.stretchX, 0.75, 1.00) end
    if type(data.trackSpeed)     == "number"  then CFG.trackSpeed     = data.trackSpeed     end
    if type(data.smoothShot)     == "boolean" then CFG.smoothShot     = data.smoothShot     end
    if type(data.recoilCounterStr)=="number"  then CFG.recoilCounterStr=data.recoilCounterStr end
    if type(data.espOn)          == "boolean" then CFG.espOn          = data.espOn          end
    if type(data.espDist)        == "number"  then CFG.espDist        = data.espDist        end
    if type(data.espWeapon)      == "boolean" then CFG.espWeapon      = data.espWeapon      end
    if type(data.espSkeleton)    == "boolean" then CFG.espSkeleton    = data.espSkeleton    end
    if type(data.stickOn)       == "boolean" then CFG.stickOn       = data.stickOn       end
    if type(data.stickStrength) == "number"  then CFG.stickStrength = math.clamp(data.stickStrength, 0, 1) end
    if type(data.reacquire)     == "boolean" then CFG.reacquire     = data.reacquire     end
    if type(data.espLine)       == "boolean" then CFG.espLine       = data.espLine       end
    if type(data.espName)       == "boolean" then CFG.espName       = data.espName       end
    if type(data.espHeadDot)    == "boolean" then CFG.espHeadDot    = data.espHeadDot    end
    if data.espBoxStyle == "Full" or data.espBoxStyle == "Corner" then CFG.espBoxStyle = data.espBoxStyle end
    if data.espLineFrom == "Bottom" or data.espLineFrom == "Center" or data.espLineFrom == "Top" then
        CFG.espLineFrom = data.espLineFrom
    end
    if type(data.esp) == "table" then
        local c=decodeColor(data.esp.box)       if c  then CFG.esp.box      = c  end
        local sk=decodeColor(data.esp.skeleton) if sk then CFG.esp.skeleton = sk end
        local ba=decodeColor(data.esp.barAlive) if ba then CFG.esp.barAlive = ba end
        local bl=decodeColor(data.esp.barLow)   if bl then CFG.esp.barLow   = bl end
        local wp=decodeColor(data.esp.weapon)   if wp then CFG.esp.weapon   = wp end
        if type(data.esp.thick)    =="number" then CFG.esp.thick    =data.esp.thick    end
        if type(data.esp.boneThick)=="number" then CFG.esp.boneThick=data.esp.boneThick end
    end
    if type(data.esp) == "table" then
        local ln = decodeColor(data.esp.line) if ln then CFG.esp.line = ln end
        local nm = decodeColor(data.esp.name) if nm then CFG.esp.name = nm end
    end
    if type(data.fpsBoost)=="table" then
        local fb=data.fpsBoost
        if type(fb.on)            =="boolean" then CFG.fpsBoost.on            =fb.on            end
        if type(fb.shadowDisable) =="boolean" then CFG.fpsBoost.shadowDisable =fb.shadowDisable end
        if type(fb.textureQuality)=="boolean" then CFG.fpsBoost.textureQuality=fb.textureQuality end
        if type(fb.particleOff)   =="boolean" then CFG.fpsBoost.particleOff   =fb.particleOff   end
        if type(fb.decalOff)      =="boolean" then CFG.fpsBoost.decalOff      =fb.decalOff      end
        if type(fb.lightingSimple)=="boolean" then CFG.fpsBoost.lightingSimple=fb.lightingSimple end
    end
    if type(data.farm) == "table" then
        local f = data.farm
        if type(f.zoneOnly)   == "boolean" then CFG.farmZoneOnly   = f.zoneOnly   end
        if type(f.wall)       == "boolean" then CFG.farmWall       = f.wall       end
        if type(f.aim)        == "boolean" then CFG.farmAim        = f.aim        end
        if type(f.shoot)      == "boolean" then CFG.farmShoot      = f.shoot      end
        if type(f.skipDowned) == "boolean" then CFG.farmSkipDowned = f.skipDowned end
        if type(f.antiAfk)    == "boolean" then CFG.farmAntiAfk    = f.antiAfk    end
        if type(f.hud)        == "boolean" then CFG.farmHud        = f.hud        end
        if type(f.autoLoot)   == "boolean" then CFG.farmAutoLoot   = f.autoLoot   end
        if type(f.autoEquip)  == "boolean" then CFG.farmAutoEquip  = f.autoEquip  end
        if type(f.botESP)     == "boolean" then CFG.farmBotESP     = f.botESP     end
        if type(f.zoneESP)    == "boolean" then CFG.farmZoneESP    = f.zoneESP    end
        if f.part == "Head" or f.part == "Torso" then CFG.farmPart = f.part end
        if type(f.dist)       == "number"  then CFG.farmDist       = math.clamp(f.dist, 0, 50) end
        if type(f.aimSpeed)   == "number"  then CFG.farmAimSpeed   = math.clamp(f.aimSpeed, 0.2, 0.99) end
    end
    if type(data.corner) == "table" then
        local c = data.corner
        if type(c.on)   == "boolean" then CFG.cornerOn   = c.on   end
        if type(c.swap) == "boolean" then CFG.cornerSwap = c.swap end
        if type(c.wide) == "boolean" then CFG.cornerWide = c.wide end
        -- v25: old saves may still carry range / grace / swapDelay / swapCooldown / settle; they are ignored on purpose
    end
    if type(data.antiAimEnabled)=="boolean" then AntiAim.enabled=data.antiAimEnabled end
    if type(data.adStrafeEnabled)=="boolean" then AntiAim.adStrafeEnabled=data.adStrafeEnabled end
    if type(data.adStrafeMinTime)=="number" then AntiAim.adStrafeMinTime=math.clamp(data.adStrafeMinTime,0.03,1.2) end
    if type(data.adStrafeMaxTime)=="number" then AntiAim.adStrafeMaxTime=math.clamp(data.adStrafeMaxTime,0.05,1.5) end
    if AntiAim.adStrafeMaxTime < AntiAim.adStrafeMinTime then AntiAim.adStrafeMaxTime = AntiAim.adStrafeMinTime end
    if type(data.adPauseChance)=="number" then AntiAim.adPauseChance=math.clamp(data.adPauseChance,0,0.5) end
end

-- Single debounced save function — the ONLY save entry point
local _saveDebounce = false
local function scheduleSave()
    if not canSave then return end
    if _saveDebounce then return end
    _saveDebounce = true
    task.delay(2, function()
        _saveDebounce = false
        pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(serializeCFG()))
        end)
    end)
end
-- alias kept for internal callers that used the old name
local saveConfig = scheduleSave

local function loadConfig()
    if not canSave then return end
    local ok, raw = pcall(readfile, CONFIG_FILE)
    if not ok or type(raw) ~= "string" or raw == "" then return end
    local dok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if dok and type(data) == "table" then applySavedCFG(data) end
end

local CFG_DEFAULTS = {
    fov=150, aimDist=550, aimOn=true, wallCheck=true, foliageBypass=true,
    stretchX=PLATFORM.defaultStretchX, trackSpeed=0.45,
    espOn=true, espDist=650, espWeapon=true, espSkeleton=true,
    stickOn=true, stickStrength=0.80, reacquire=true,
    espBoxStyle="Corner", espLine=true, espLineFrom="Bottom", espName=true, espHeadDot=true,
    esp={
        box=Color3.fromRGB(255,255,255), skeleton=Color3.fromRGB(80,200,255),
        barBg=Color3.fromRGB(30,30,30), barAlive=Color3.fromRGB(80,220,80),
        barLow=Color3.fromRGB(220,60,60), weapon=Color3.fromRGB(255,220,80),
        line=Color3.fromRGB(255,90,90), name=Color3.fromRGB(255,255,255),
        thick=1, boneThick=1,
    },
    fpsBoost={
        on=false, shadowDisable=true, textureQuality=true,
        particleOff=true,
        decalOff=false, lightingSimple=true,
    },
}
local function resetConfig()
    CFG.fov=CFG_DEFAULTS.fov CFG.aimDist=CFG_DEFAULTS.aimDist
    CFG.aimOn=CFG_DEFAULTS.aimOn CFG.wallCheck=CFG_DEFAULTS.wallCheck
    CFG.foliageBypass=CFG_DEFAULTS.foliageBypass
    CFG.stretchX=CFG_DEFAULTS.stretchX CFG.trackSpeed=CFG_DEFAULTS.trackSpeed
    CFG.espOn=CFG_DEFAULTS.espOn CFG.espDist=CFG_DEFAULTS.espDist
    CFG.espWeapon=CFG_DEFAULTS.espWeapon CFG.espSkeleton=CFG_DEFAULTS.espSkeleton
    CFG.stickOn=CFG_DEFAULTS.stickOn CFG.stickStrength=CFG_DEFAULTS.stickStrength
    CFG.reacquire=CFG_DEFAULTS.reacquire CFG.espBoxStyle=CFG_DEFAULTS.espBoxStyle
    CFG.espLine=CFG_DEFAULTS.espLine CFG.espLineFrom=CFG_DEFAULTS.espLineFrom
    CFG.espName=CFG_DEFAULTS.espName CFG.espHeadDot=CFG_DEFAULTS.espHeadDot
    for k,v in pairs(CFG_DEFAULTS.esp) do CFG.esp[k]=v end
    for k,v in pairs(CFG_DEFAULTS.fpsBoost) do CFG.fpsBoost[k]=v end
    CFG.farmZoneOnly=true CFG.farmWall=true CFG.farmAim=true CFG.farmShoot=true
    CFG.farmSkipDowned=false CFG.farmPart="Head" CFG.farmDist=50 CFG.farmAimSpeed=0.85
    CFG.farmAntiAfk=true CFG.farmHud=true
    CFG.farmAutoLoot=true CFG.farmAutoEquip=true
    CFG.farmBotESP=false CFG.farmZoneESP=false
    CFG.cornerOn=true CFG.cornerSwap=true CFG.cornerWide=true
    AntiAim.enabled = true
    AntiAim.adStrafeEnabled = true
    AntiAim.adStrafeMinTime = 0.12 AntiAim.adStrafeMaxTime = 0.42 AntiAim.adPauseChance = 0.15
    if canSave then pcall(delfile, CONFIG_FILE) end
end

loadConfig()

-- ═══════════════════════════════════════════════════════════
--  STRETCHX AUTO-DETECT (runs after loadConfig so saved value wins)
--  Only override if the saved value is still the default AND
--  we can detect a better value from the environment.
-- ═══════════════════════════════════════════════════════════
do
    -- Don't override if user has manually set a non-default value via slider
    local stillDefault = math.abs(CFG.stretchX - PLATFORM.defaultStretchX) < 0.01
    if stillDefault then
        -- Method 1: QualityLevel (reliable on PC / some Android executors)
        local ok, ql = pcall(function() return settings().Rendering.QualityLevel end)
        if ok and ql and not (PLATFORM.isIOS or PLATFORM.isGenericMobile) then
            local lvl = tonumber(tostring(ql):match("%d+")) or 10
            if lvl <= 4 then
                CFG.stretchX = PLATFORM.isAndroid and 0.88 or 0.82
            elseif lvl <= 8 then
                CFG.stretchX = PLATFORM.isAndroid and 0.94 or 0.90
            else
                CFG.stretchX = 1.0
            end
        end
        -- Method 2: iOS retina always 1.0
        if PLATFORM.isIOS or PLATFORM.isGenericMobile then CFG.stretchX = 1.0 end
        CFG.stretchX = math.clamp(CFG.stretchX, 0.75, 1.00)
    end
end

-- ═══════════════════════════════════════════════════════════
--  FPS BOOST ENGINE
-- ═══════════════════════════════════════════════════════════
local Lighting = game:GetService("Lighting")
local origSettings  = {}
local _descAddedCon = nil
local function applyStaticPass()
    local fb = CFG.fpsBoost
    if not origSettings._saved then
        origSettings.GlobalShadows            = Lighting.GlobalShadows
        origSettings.ShadowSoftness           = Lighting.ShadowSoftness
        origSettings.Technology               = Lighting.Technology
        origSettings.EnvironmentDiffuseScale  = Lighting.EnvironmentDiffuseScale
        origSettings.EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
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

local function applyFPSBoost()
    local fb = CFG.fpsBoost
    if not fb.on then return end
    applyStaticPass()
    if fb.particleOff then applyParticlePass() end
end

local function restoreFPSBoost()
    if origSettings._saved then
        Lighting.GlobalShadows            = origSettings.GlobalShadows
        Lighting.ShadowSoftness           = origSettings.ShadowSoftness
        Lighting.EnvironmentDiffuseScale  = origSettings.EnvironmentDiffuseScale
        Lighting.EnvironmentSpecularScale = origSettings.EnvironmentSpecularScale
        pcall(function() Lighting.Technology = origSettings.Technology end)
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end)
    end
    if _descAddedCon then _descAddedCon:Disconnect() _descAddedCon = nil end
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter") or v:IsA("Beam")
        or v:IsA("Trail") or v:IsA("Smoke")
        or v:IsA("Fire") or v:IsA("Sparkles") then
            pcall(function() v.Enabled = true end)
        end
        if v:IsA("Decal") or v:IsA("Texture") then
            pcall(function() v.Transparency = 0 end)
        end
    end
end

-- v24.1: the saved config can say fpsBoost.on = true while nothing was applied yet
-- (the toggle only called applyFPSBoost when clicked). This re-applies it on boot and
-- every time the menu opens. Safe to call repeatedly: original settings are saved once.
local function reapplyFPSBoost()
    if not CFG.fpsBoost.on then return end
    local ok, err = pcall(applyFPSBoost)
    if not ok then warn("[KXY FPS] " .. tostring(err)) end
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

-- Keep FOV math in the exact same coordinate space as WorldToViewportPoint
-- and the ESP overlay. Do not remap through GetInsetArea/GetGuiInset: on some
-- iOS executors those APIs report a different safe-area origin, shifting the
-- FOV ring away from the viewport center while ESP remains correctly aligned.
local function w2s(pos)
    if typeof(pos) ~= "Vector3" then return nil,false,-1,nil end
    local ok, sp = pcall(function() return camera:WorldToViewportPoint(pos) end)
    if not ok or not sp then return nil,false,-1,nil end
    local vp = camera.ViewportSize
    if vp.X < 1 or vp.Y < 1 then return nil,false,-1,nil end

    local rawPos = Vector2.new(math.round(sp.X), math.round(sp.Y))
    local cx = vp.X / 2
    local sx = CFG.stretchX
    local fixedX = sx >= 0.999 and sp.X or (cx + (sp.X - cx) / sx)
    return Vector2.new(math.round(fixedX), math.round(sp.Y)), sp.Z > 0, sp.Z, rawPos
end

-- The FOV circle and target-distance check share the camera viewport center.
local function screenCenter()
    local vp = camera and camera.ViewportSize or Vector2.new(800, 600)
    return vp / 2
end

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
wallParams.IgnoreWater = true
-- v25: same collision group the game's bullets use (WeaponClient: v_u_51.CollisionGroup = "Bullet")
pcall(function() wallParams.CollisionGroup = "Bullet" end)
local function hasLOSFrom(origin, targetPos, targetChar)
    if not CFG.wallCheck then return true end
    if typeof(origin) ~= "Vector3" then return false end
    if typeof(targetPos) ~= "Vector3" then return false end
    local fl = {workspace.Terrain}
    if lp.Character then table.insert(fl, lp.Character) end
    -- v25: HitboxClient parks one invisible box per body part around every player (CanQuery = true) in
    -- workspace.ClientHitboxes, and FX holds tracers / smoke. The game's own rays all exclude both; without
    -- this the ray to the target stopped on the target's own hitbox and the lock dropped at random.
    do
        local hb = workspace:FindFirstChild("ClientHitboxes")
        if hb then table.insert(fl, hb) end
        local fx = workspace:FindFirstChild("FX")
        if fx then table.insert(fl, fx) end
    end
    if targetChar then
        local hum = targetChar:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart then
            local veh = hum.SeatPart:FindFirstAncestorOfClass("Model")
            if veh then table.insert(fl, veh) end
        end
    end
    wallParams.FilterDescendantsInstances = fl
    local tv = targetPos - origin
    local total = tv.Magnitude
    if total < 0.5 then return true end
    local dir = tv.Unit
    local travelled = 0
    for _ = 1, 12 do
        local rem = total - travelled - 0.4
        if rem <= 0.1 then return true end
        local ok, hit = pcall(function() return workspace:Raycast(origin, dir*rem, wallParams) end)
        if not ok or not hit then return true end
        -- v25: glass ("Glass_*") does not stop the game's visibility cast (castVisible skips it), so it is not a wall here either
        if (CFG.foliageBypass and isFoliage(hit.Instance))
            or (hit.Instance and string.sub(hit.Instance.Name, 1, 6) == "Glass_") then
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

local function hasLOS(targetPos, targetChar)
    return hasLOSFrom(camera.CFrame.Position, targetPos, targetChar)
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
    local spTop,  _,depTop  = w2s(topPos)
    local spFeet, _,depFeet = w2s(feetPos)
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
    }
end

-- ═══════════════════════════════════════════════════════════
--  SKELETON
-- ═══════════════════════════════════════════════════════════
local BONE_PAIRS = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
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
    -- v25: the game registers hits against ClientHitboxes boxes that follow the visible parts
    -- (HitboxModel.SizeOf: Head = size*(1.3,1.1,1.3)*1.1, UpperTorso = size*(1.15,0.85,1.5)*1.1 shifted down 0.1).
    -- The old point (NeckRigAttachment) sat 0.13 studs above the bottom face of the head box and 0.2 above the
    -- torso box, so a 0.1-0.2 stud error turned a hit into a miss. Aim at the lower middle of the head box instead:
    -- ~0.5 stud of margin to the head box edge below and the whole torso box under it as backup.
    return head.Position - Vector3.new(0, head.Size.Y*0.25, 0), false, hrpVel
end

-- ═══════════════════════════════════════════════════════════
--  CONTROLS BRIDGE v24
--  ReplicatedStorage.Controls is what the game's own mobile HUD and
--  WeaponClient use: Press(action, down) / IsDown(action).
--  Used for fire detection (mobile), ADS and Farm auto fire.
-- ═══════════════════════════════════════════════════════════
local Ctl = nil
task.spawn(function()
    local m = ReplicatedStorage:WaitForChild("Controls", 20)
    if m then
        local ok, r = pcall(require, m)
        if ok and type(r) == "table" and type(r.Press) == "function" and type(r.IsDown) == "function" then
            Ctl = r
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  SMOOTHSHOT v21 — Pre-ADS + Recoil Counter
-- ═══════════════════════════════════════════════════════════
local _ssAimBtn       = nil
local _ssAimRemote    = nil
local _ssIsADS        = false
local _ssAdsStartedAt = 0
local _ssLastShotAt   = 0
local _ssRecoilBudget = Vector3.zero

-- Recursive search for a named GuiObject
local function findGuiDeep(parent, name, depth, buttonOnly)
    depth = depth or 0
    if depth > 12 then return nil end
    for _, c in ipairs(parent:GetChildren()) do
        local isButton = c:IsA("TextButton") or c:IsA("ImageButton")
        if c.Name == name and (isButton or (not buttonOnly and c:IsA("Frame"))) then
            return c
        end
        local found = findGuiDeep(c, name, depth + 1, buttonOnly)
        if found then return found end
    end
    return nil
end

local function hookAimButton()
    local gui = lp:FindFirstChild("PlayerGui")
    if not gui then task.delay(1.5, hookAimButton) return end
    local aimBtn = findGuiDeep(gui, "Aim", 0, true)
    if not aimBtn then task.delay(1.5, hookAimButton) return end
    _ssAimBtn = aimBtn
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then _ssAimRemote = remotes:FindFirstChild("AimFlag") end
end

-- simADS — unified Android + iOS approach
-- Android executors (Fluxus/Hydrogen): InputBegan:Fire() usually works
-- iOS (Delta/Solara): .Fire() blocked → use MouseButton1Down + remote
-- ── iOS PATCH v22.1: added CFrame FOV narrowing fallback + VirtualInputManager ─
local _ssIosFovNarrowActive = false  -- tracks if iOS FOV-narrow ADS sim is on
local function simADS(state)
    if not CFG.smoothShot then return end
    if Ctl then
        if pcall(Ctl.Press, "Aim", state and true or false) then
            _ssIsADS = state
            if state then _ssAdsStartedAt = os.clock() end
            return
        end
    end
    if _ssAimBtn then
        if PLATFORM.isAndroid then
            -- Android: try signal fire first
            local inputObj = {
                UserInputType = Enum.UserInputType.Touch,
                UserInputState = state and Enum.UserInputState.Begin or Enum.UserInputState.End,
                Position = Vector3.new(0,0,0),
                Delta = Vector3.new(0,0,0),
                KeyCode = Enum.KeyCode.Unknown,
            }
            pcall(function()
                if state then _ssAimBtn.InputBegan:Fire(inputObj)
                else _ssAimBtn.InputEnded:Fire(inputObj) end
            end)
        end
        -- Both platforms: try button event fire (Delta allows MouseButton1Down)
        pcall(function()
            if state then _ssAimBtn.MouseButton1Down:Fire()
            else _ssAimBtn.MouseButton1Up:Fire() end
        end)
        if state then
            pcall(function() _ssAimBtn.Activated:Fire() end)
        end
        -- ── iOS PATCH: VirtualInputManager touch simulation ───────────────────
        -- Delta 4.x+ exposes VirtualInputManager; simulate a touch on the ADS button
        if PLATFORM.isIOS or PLATFORM.isGenericMobile then
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                if state then
                    local ap = _ssAimBtn.AbsolutePosition
                    local as = _ssAimBtn.AbsoluteSize
                    local cx = ap.X + as.X * 0.5
                    local cy = ap.Y + as.Y * 0.5
                    vim:SendTouchEvent(0, Vector2.new(cx, cy), Enum.UserInputState.Begin)
                    task.delay(0.08, function()
                        vim:SendTouchEvent(0, Vector2.new(cx, cy), Enum.UserInputState.End)
                    end)
                end
            end)
        end
        -- ─────────────────────────────────────────────────────────────────────
    end
    -- Server remote — most reliable on both platforms
    if _ssAimRemote then
        pcall(function() _ssAimRemote:FireServer(state) end)
    end
    -- ── iOS PATCH: FOV narrowing fallback ─────────────────────────────────────
    -- If nothing above works (all signals blocked), simulate ADS by narrowing
    -- camera FOV — this is a visual-only fallback that still triggers
    -- the recoil counter and smooth-aim, reducing visible recoil on iOS.
    if PLATFORM.isIOS or PLATFORM.isGenericMobile then
        if state and not _ssIosFovNarrowActive then
            _ssIosFovNarrowActive = true
            pcall(function()
                -- Only narrow if camera FOV is at a normal ADS-able value
                local curFov = camera.FieldOfView
                if curFov >= 60 then
                    local targetFov = curFov * 0.72  -- approximate ADS zoom
                    local steps = 6
                    task.spawn(function()
                        for i = 1, steps do
                            if not _ssIosFovNarrowActive then break end
                            camera.FieldOfView = curFov + (targetFov - curFov) * (i/steps)
                            task.wait(0.016)
                        end
                    end)
                end
            end)
        elseif not state and _ssIosFovNarrowActive then
            _ssIosFovNarrowActive = false
            pcall(function()
                local curFov = camera.FieldOfView
                local targetFov = 70  -- standard Roblox FOV
                local steps = 5
                task.spawn(function()
                    for i = 1, steps do
                        if _ssIosFovNarrowActive then break end
                        camera.FieldOfView = curFov + (targetFov - curFov) * (i/steps)
                        task.wait(0.016)
                    end
                end)
            end)
        end
    end
    -- ─────────────────────────────────────────────────────────────────────────
    _ssIsADS = state
    if state then _ssAdsStartedAt = os.clock() end
end
-- ─────────────────────────────────────────────────────────────────────────────

local function tickRecoilCounter(dt)
    if not CFG.smoothShot then return end
    if _ssRecoilBudget.Magnitude < 0.0001 then return end
    local decay = math.clamp(dt / CFG.recoilDecay, 0, 1)
    local counter = _ssRecoilBudget * CFG.recoilCounterStr * decay
    local camCF = camera.CFrame
    local pitchDown = CFrame.Angles(-counter.Y, -counter.X, 0)
    camera.CFrame = camCF * pitchDown
    _ssRecoilBudget = _ssRecoilBudget * (1 - decay)
end

local function onShotFired()
    if not CFG.smoothShot then return end
    _ssLastShotAt = os.clock()
    local side = (math.random() - 0.5) * 2 * CFG.recoilCounterSide
    _ssRecoilBudget = _ssRecoilBudget + Vector3.new(side, CFG.recoilCounterUp, 0)
end

task.defer(hookAimButton)

-- ═══════════════════════════════════════════════════════════
--  FIRE DETECTION — Android + iOS unified
--  3 layers, platform-aware:
--    L1: Recursive button hook with Activated + InputBegan/Ended
--    L2: UIS global mouse (PC / Android emulator)
--    L3: TouchStarted/Ended zone (mobile fallback, 5s timeout)
--        Android zone: right half of screen lower 50%
--        iOS zone    : right half of screen lower 40% (taller UI safe area)
-- ═══════════════════════════════════════════════════════════
local isFiring      = false
local _fireTouchId  = nil
local _fireGuiButton = nil
local _fireHookDone = false

local function hookFireButton()
    if _fireHookDone then return end
    local gui = lp:FindFirstChild("PlayerGui")
    if not gui then task.delay(1.5, hookFireButton) return end
    local btn = findGuiDeep(gui, "Fire", 0, true)
    if not btn then task.delay(1.5, hookFireButton) return end
    _fireGuiButton = btn

    -- Touch hold is tracked globally against this button's exact screen bounds
    -- below; avoid duplicate InputBegan/Ended listeners that can cancel a second finger.
    -- Activated fires on tap — treat as single-shot pulse (tapGapWindow handles it)
    btn.Activated:Connect(function()
        isFiring = true
        task.delay(0.05, function() isFiring = false end)
    end)

    _fireHookDone = true
end

-- L2: PC / mouse fallback
UserInputService.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 then isFiring = true end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then isFiring = false end
end)

-- ── v25.3: mobile fire tracking ─────────────────────────────────────────────
-- Prefer the real in-game Fire GuiButton bounds. Touches on a GuiButton are
-- commonly marked gameProcessedEvent=true, so do not discard them when they
-- land inside that exact button. Only use a coarse zone if the button is absent.
if PLATFORM.isMobile then
    local _activeFireTouches = {}
    local function isInsideFireButton(pos)
        local btn = _fireGuiButton
        if not btn or not btn.Parent then return false end
        local ok, inside = pcall(function()
            local ap, as = btn.AbsolutePosition, btn.AbsoluteSize
            return pos.X >= ap.X and pos.X <= ap.X + as.X
                and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
        end)
        return ok and inside
    end
    local function hasFireButtonBounds()
        local btn = _fireGuiButton
        if not btn or not btn.Parent then return false end
        local ok, available = pcall(function()
            local size = btn.AbsoluteSize
            return btn.Visible and size.X > 1 and size.Y > 1
        end)
        return ok and available
    end
    local function updateFireState()
        isFiring = next(_activeFireTouches) ~= nil
    end
    UserInputService.TouchStarted:Connect(function(touch, gpe)
        local pos = Vector2.new(touch.Position.X, touch.Position.Y)
        local inside = isInsideFireButton(pos)
        if not inside and not hasFireButtonBounds() and not gpe then
            local vp = camera.ViewportSize
            inside = vp.X > 0 and vp.Y > 0
                and pos.X > vp.X * 0.50 and pos.Y > vp.Y * (PLATFORM.isIOS and 0.60 or 0.50)
        end
        if inside then
            _activeFireTouches[touch] = true
            _fireTouchId = touch
            updateFireState()
        end
    end)
    UserInputService.TouchEnded:Connect(function(touch)
        if _activeFireTouches[touch] then
            _activeFireTouches[touch] = nil
            if _fireTouchId == touch then _fireTouchId = nil end
            updateFireState()
        end
    end)
    UserInputService.TouchMoved:Connect(function(touch)
        if not _activeFireTouches[touch] then return end
        local pos = Vector2.new(touch.Position.X, touch.Position.Y)
        if hasFireButtonBounds() and not isInsideFireButton(pos) then
            _activeFireTouches[touch] = nil
            if _fireTouchId == touch then _fireTouchId = nil end
            updateFireState()
        end
    end)
end
-- ─────────────────────────────────────────────────────────────────────────────

-- v25.3: no second overlapping touch-zone listener. The mobile tracker above
-- remains active and switches to the real Fire button bounds when it appears.

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
--  CORNER ASSIST v24.9 — change the view when the crosshair cannot reach the target
--  What the place dump says (CameraClient / WeaponClient / ClientState):
--    * the camera is an over-the-shoulder rig (Config.Global.Camera: Distance 8, Side 1.6,
--      Height 1.7, AimDistance 4.3, pitch -75..70) rebuilt by GTACamera every frame, so a
--      frame without aim output snaps the view back to the player's own look direction
--    * ClientState.Shoulder (+1 / -1) is the camera side; the on-screen swap button only
--      does Shoulder = -Shoulder (WeaponClient OnInputBegan)
--    * a shot is the camera ray: it starts at the point of that ray closest to your head
--      and flies along the ray (WeaponClient shoot)
--  Not verified in game: how fast the camera slides to the other shoulder (cornerSettle),
--  and whether the server re-checks the camera origin that is sent with each shot.
-- ═══════════════════════════════════════════════════════════
local Corner = {
    cs = nil,                 -- ReplicatedStorage.Weapons.ClientState (same table the game uses)
    target = nil,             -- head the cached result below belongs to
    state = "idle",           -- "clear" | "grace" | "blocked" | "lost" | "idle"
    aimPos = nil,             -- reachable aim point (held while state == "grace")
    partIdx = 1,              -- index in the candidate list that is currently used
    blockedAt = nil, promoteAt = 0,
    lastSwapAt = -1e9, lastMirrorAt = 0, settleUntil = 0,
    swapTimes = {}, swaps = 0,
}
task.spawn(function()
    local w = ReplicatedStorage:WaitForChild("Weapons", 20)
    local m = w and w:WaitForChild("ClientState", 20)
    if m then
        local ok, r = pcall(require, m)
        if ok and type(r) == "table" and type(r.Shoulder) == "number" then Corner.cs = r end
    end
end)

local CORNER_PARTS = { "Head", "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart" }
local cornerPullParams = RaycastParams.new()
cornerPullParams.FilterType = Enum.RaycastFilterType.Exclude
cornerPullParams.IgnoreWater = true
cornerPullParams.RespectCanCollide = true

-- your own head, the same point WeaponClient uses (Head, else root + 1.5 up)
local function myHeadPos()
    local ch = lp.Character
    if not ch then return nil end
    local h = ch:FindFirstChild("Head")
    if h then return h.Position end
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    return hrp and (hrp.Position + Vector3.new(0, 1.5, 0)) or nil
end

-- aim points in priority order: the usual neck point first, then head, chest, belly, root
local function cornerCandidates(head)
    local list = {}
    local neck = getAimPos(head)
    if neck then list[1] = neck end
    local char = head.Parent
    if char then
        for _, n in ipairs(CORNER_PARTS) do
            local p = char:FindFirstChild(n)
            if p and p:IsA("BasePart") then list[#list + 1] = p.Position end
        end
    end
    return list
end

-- true when a shot taken with the camera at camPos and aimed at p can reach p.
-- The bullet starts at the point of the camera ray closest to your head, so only the line
-- from there to the target has to be clear (the part between camera and head does not matter).
-- If the target is not past that start point the plain camera line is used (old behaviour).
local function cornerReach(camPos, p, char, headPos)
    if not CFG.wallCheck then return true end
    local v = p - camPos
    if v.Magnitude < 0.5 then return true end
    local dir = v.Unit
    local o = camPos + dir * math.max(0, (headPos - camPos):Dot(dir))
    if (p - o):Dot(dir) <= 0.5 then o = camPos end
    return hasLOSFrom(o, p, char)
end

-- camera position after a wall pushes it towards you (the game does a 0.35 stud spherecast)
local function cornerPullIn(pivot, camP)
    local v = camP - pivot
    if v.Magnitude < 0.1 then return camP end
    local ign = { camera }
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then ign[#ign + 1] = pl.Character end
    end
    local hb = workspace:FindFirstChild("ClientHitboxes")
    if hb then ign[#ign + 1] = hb end
    local fx = workspace:FindFirstChild("FX")
    if fx then ign[#ign + 1] = fx end
    cornerPullParams.FilterDescendantsInstances = ign
    local ok, hit = pcall(function() return workspace:Raycast(pivot, v, cornerPullParams) end)
    if ok and hit then return pivot + v.Unit * math.max(hit.Distance - 0.4, 0) end
    return camP
end

-- everything isTargetValid checks except screen position and walls
local function cornerHardValid(head)
    if not head or not head.Parent then return false end
    local char = head.Parent
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character == char then
            if isAllyPlayer(pl, char) then return false end
            break
        end
    end
    local _, _, hum = getCharParts(char)
    if not isAlive(hum) then return false end
    if (camera.CFrame.Position - head.Position).Magnitude > CFG.aimDist then return false end
    return true
end

-- on screen, or close enough that the view will simply turn to it
local function cornerScreenOk(head)
    if CFG.cornerWide and (camera.CFrame.Position - head.Position).Magnitude <= CFG.cornerRange then
        return true
    end
    local sp, onScreen, depth = w2s(head.Position)
    return sp ~= nil and onScreen and depth > 0
end

function Corner.reset()
    Corner.target = nil Corner.state = "idle" Corner.aimPos = nil
    Corner.partIdx = 1 Corner.blockedAt = nil
end

-- any aim point reachable from the current camera
function Corner.reachable(head)
    local char = head.Parent
    if not CFG.wallCheck then return true end
    local headPos = myHeadPos()
    if not headPos then return hasLOS(head.Position, char) end
    local camPos = camera.CFrame.Position
    local cands = cornerCandidates(head)
    for i = 1, #cands do
        if cornerReach(camPos, cands[i], char, headPos) then return true end
    end
    return false
end

-- nearest enemy within cornerRange studs that can be hit, wherever it is on screen
function Corner.pickWide()
    if not (CFG.cornerOn and CFG.cornerWide) then return nil end
    local camPos = camera.CFrame.Position
    local best, bestD = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player == lp then continue end
        local char = player.Character
        if not char then continue end
        if isAllyPlayer(player, char) then continue end
        local hrp, head, hum = getCharParts(char)
        if not head or not hum or not hrp then continue end
        if not isAlive(hum) then continue end
        local d = (camPos - head.Position).Magnitude
        if d > CFG.cornerRange or d > CFG.aimDist or d >= bestD then continue end
        if Corner.reachable(head) then best, bestD = head, d end
    end
    return best, bestD
end

-- press the shoulder swap (ClientState.Shoulder = -Shoulder) when the mirrored camera can reach
-- the target. The mirrored camera is an estimate: the current camera reflected across your
-- root's vertical plane along the camera's right vector, then pulled in by walls.
function Corner.trySwap(cands, char, headPos, camPos, now)
    local cs = Corner.cs
    if not cs or cs.CursorFree or cs.Vehicle then return false end
    local cur = cs.Shoulder
    if type(cur) ~= "number" or cur == 0 or cur ~= cur then return false end
    if now < Corner.settleUntil then return false end
    if now - Corner.lastSwapAt < CFG.cornerSwapCooldown then return false end
    if now - Corner.lastMirrorAt < 0.05 then return false end
    Corner.lastMirrorAt = now
    local recent = 0
    for i = #Corner.swapTimes, 1, -1 do
        if now - Corner.swapTimes[i] > 4 then table.remove(Corner.swapTimes, i) else recent = recent + 1 end
    end
    if recent >= 2 then return false end      -- at most 2 swaps per 4 s: no flip-flop
    local me = lp.Character
    local hrp = me and me:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local right = camera.CFrame.RightVector
    local side = (camPos - hrp.Position):Dot(right)
    if math.abs(side) < 0.3 then return false end
    local mirror = cornerPullIn(headPos, camPos - right * (2 * side))
    local ok = false
    for i = 1, #cands do
        if cornerReach(mirror, cands[i], char, headPos) then ok = true break end
    end
    if not ok then return false end
    cs.Shoulder = -cur
    Corner.lastSwapAt = now
    Corner.swapTimes[#Corner.swapTimes + 1] = now
    Corner.swaps = Corner.swaps + 1
    Corner.settleUntil = now + CFG.cornerSettle
    Corner.blockedAt = now
    return true
end

-- once per frame for the locked head; caches Corner.state / Corner.aimPos
function Corner.update(head, now)
    if Corner.target ~= head then
        Corner.reset()
        Corner.target = head
    end
    if not cornerHardValid(head) then Corner.state = "lost" return "lost" end
    local cands = cornerCandidates(head)
    if #cands == 0 then Corner.state = "lost" return "lost" end
    local char = head.Parent
    local headPos = myHeadPos()
    local camPos = camera.CFrame.Position
    local screenOk = cornerScreenOk(head)

    if not CFG.wallCheck or not headPos then
        if screenOk then
            Corner.aimPos = cands[1] Corner.blockedAt = nil Corner.state = "clear"
        else
            Corner.state = "lost"
        end
        return Corner.state
    end

    local pick = nil
    if screenOk then
        local idx = Corner.partIdx
        if idx > #cands then idx = 1 end
        -- stay on the current point while it is reachable; look at the best point again every 0.4 s
        if idx > 1 and (now - Corner.promoteAt) >= 0.4 then
            Corner.promoteAt = now
            if cornerReach(camPos, cands[1], char, headPos) then pick = 1 end
        end
        if not pick and cornerReach(camPos, cands[idx], char, headPos) then pick = idx end
        if not pick then
            for i = 1, #cands do
                if i ~= idx and cornerReach(camPos, cands[i], char, headPos) then pick = i break end
            end
        end
    end
    if pick then
        Corner.partIdx = pick
        Corner.aimPos = cands[pick]
        Corner.blockedAt = nil
        Corner.state = "clear"
        return "clear"
    end

    -- nothing reachable from this shoulder: hold the last good point for a moment, try the other shoulder
    if not Corner.blockedAt then Corner.blockedAt = now end
    local blockedFor = now - Corner.blockedAt
    local grace = CFG.cornerGrace
    if now < Corner.settleUntil then grace = grace + CFG.cornerSettle end
    if Corner.aimPos and blockedFor <= grace then Corner.state = "grace" else Corner.state = "blocked" end
    if Corner.state == "grace" and CFG.cornerSwap and blockedFor >= CFG.cornerSwapDelay then
        Corner.trySwap(cands, char, headPos, camPos, now)
    end
    return Corner.state
end

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
        if CFG.cornerOn then
            if not Corner.reachable(head) then continue end
        elseif not hasLOS(head.Position, char) then
            continue
        end
        if screenDist < bestDist then bestDist = screenDist bestHead = head end
    end
    return bestHead, bestDist
end

-- v24.9: validity of the current lock. With Corner Assist off this is exactly isTargetValid.
local function lockStillOk(head, now)
    if not CFG.cornerOn then return isTargetValid(head) end
    local st = Corner.update(head, now)
    if st == "clear" or st == "grace" then return true end
    Corner.reset()
    return false
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

local weaponLabelPool = {}
local function getWeaponLabel(player)
    if weaponLabelPool[player] then return weaponLabelPool[player] end
    local t = Drawing.new("Text")
    t.Visible = false t.Size = 11 t.Font = 2
    t.Color = Color3.fromRGB(255,220,80) t.Outline = true t.Center = true t.ZIndex = 4
    weaponLabelPool[player] = t
    return t
end
local function hideWeaponLabel(player)
    local t = weaponLabelPool[player]
    if t then t.Visible = false end
end
local function removeWeaponLabel(player)
    local t = weaponLabelPool[player]
    if t then pcall(function() t:Remove() end) end
    weaponLabelPool[player] = nil
end

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
        corners = {},
        line    = mkLine(E.line, 1),
        name    = mkText(12, 3),
        dot     = nil,
    }
    b.weapon.Color = E.weapon
    b.name.Color   = E.name
    for i = 1, 8 do b.corners[i] = mkLine(E.box, E.thick) end
    pcall(function()
        local d = Drawing.new("Circle")
        d.Visible = false d.Filled = true d.NumSides = 16 d.Radius = 3
        d.Color = E.line d.ZIndex = 3
        b.dot = d
    end)
    for i = 1, #BONE_PAIRS do b.bones[i] = mkLine(E.skeleton, E.boneThick) end
    espPool[player] = b
    return b
end

local function hideBundle(b, player)
    for _,l in ipairs(b.box)   do l.Visible = false end
    for _,l in ipairs(b.bones) do l.Visible = false end
    b.barBg.Visible  = false b.barFill.Visible = false
    b.dist.Visible   = false b.weapon.Visible  = false
    for _,l in ipairs(b.corners) do l.Visible = false end
    b.line.Visible = false b.name.Visible = false
    if b.dot then b.dot.Visible = false end
    if player then hideWeaponLabel(player) end
end

local function removeBundle(player)
    local b = espPool[player]
    if not b then return end
    for _,l in ipairs(b.box)   do pcall(function() l:Remove() end) end
    for _,l in ipairs(b.bones) do pcall(function() l:Remove() end) end
    pcall(function() b.barBg:Remove() end)   pcall(function() b.barFill:Remove() end)
    pcall(function() b.dist:Remove() end)    pcall(function() b.weapon:Remove() end)
    for _,l in ipairs(b.corners) do pcall(function() l:Remove() end) end
    pcall(function() b.line:Remove() end)    pcall(function() b.name:Remove() end)
    if b.dot then pcall(function() b.dot:Remove() end) end
    espPool[player] = nil
    removeWeaponLabel(player)
end
Players.PlayerRemoving:Connect(removeBundle)


-- ═══════════════════════════════════════════════════════════
--  v24.6 iOS FIX — Instance-based ESP fallback (no Drawing needed)
--  Used only when the executor has no Drawing API.
--  Highlight (chams) + BillboardGui (name / distance / weapon / hp).
-- ═══════════════════════════════════════════════════════════
local FB = { folder = nil, pool = {} }
do
    local function pickParent()
        local cands = {
            function() return gethui and gethui() end,
            function() return game:GetService("CoreGui") end,
            function() return lp:FindFirstChildOfClass("PlayerGui") end,
        }
        for _, f in ipairs(cands) do
            local ok, r = pcall(f)
            if ok and r then
                local ok2, folder = pcall(function()
                    local fo = Instance.new("Folder")
                    fo.Name = "KXY_ESP"
                    fo.Parent = r
                    return fo
                end)
                if ok2 and folder and folder.Parent then return folder end
            end
        end
        return nil
    end

    function FB.ensure()
        if FB.folder and FB.folder.Parent then return FB.folder end
        FB.folder = pickParent()
        FB.pool = {}
        if not FB.folder and not FB.noParentShown then
            FB.noParentShown = true
            warn("[KXY] FB: no GUI parent accepted the ESP folder (gethui / CoreGui / PlayerGui all failed)")
        end
        return FB.folder
    end

    function FB.hide(player)
        local e = FB.pool[player]
        if e then
            if e.hl then e.hl.Enabled = false end
            if e.bb then e.bb.Enabled = false end
        end
    end

    function FB.remove(player)
        local e = FB.pool[player]
        if not e then return end
        pcall(function() if e.hl then e.hl:Destroy() end end)
        pcall(function() if e.bb then e.bb:Destroy() end end)
        FB.pool[player] = nil
    end
    Players.PlayerRemoving:Connect(FB.remove)

    local function build(player, char, head)
        local folder = FB.ensure()
        if not folder then return nil end
        local e = {}
        local okH = pcall(function()
            local hl = Instance.new("Highlight")
            hl.Name = "H"
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.FillTransparency = 0.55
            hl.OutlineTransparency = 0
            hl.Adornee = char
            hl.Parent = folder
            e.hl = hl
        end)
        local okB = pcall(function()
            local bb = Instance.new("BillboardGui")
            bb.Name = "B"
            bb.AlwaysOnTop = true
            bb.Size = UDim2.fromOffset(160, 54)
            bb.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
            bb.MaxDistance = math.huge
            bb.Adornee = head
            bb.Parent = folder
            local function lbl(y, h)
                local t = Instance.new("TextLabel")
                t.BackgroundTransparency = 1
                t.Size = UDim2.new(1, 0, 0, h)
                t.Position = UDim2.fromOffset(0, y)
                t.Font = Enum.Font.GothamBold
                t.TextSize = 12
                t.TextStrokeTransparency = 0.3
                t.TextColor3 = Color3.new(1, 1, 1)
                t.Text = ""
                t.Parent = bb
                return t
            end
            e.name   = lbl(0, 14)
            e.info   = lbl(14, 14)
            e.weapon = lbl(28, 14)
            local bg = Instance.new("Frame")
            bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            bg.BorderSizePixel = 0
            bg.Size = UDim2.new(0.6, 0, 0, 4)
            bg.Position = UDim2.new(0.2, 0, 0, 44)
            bg.Parent = bb
            local fill = Instance.new("Frame")
            fill.BorderSizePixel = 0
            fill.Size = UDim2.fromScale(1, 1)
            fill.Parent = bg
            e.hpFill = fill
            e.bb = bb
        end)
        if not okH and not okB then return nil end
        FB.pool[player] = e
        return e
    end

    function FB.update(player, char, hrp, head, hum, dist)
        local E = CFG.esp
        local e = FB.pool[player]
        if e and ((e.hl and e.hl.Adornee ~= char) or (e.bb and e.bb.Adornee ~= head)) then
            FB.remove(player)   -- respawned: rebuild on the new character
            e = nil
        end
        e = e or build(player, char, head)
        if not e then return end
        if e.hl then
            e.hl.Enabled = true
            e.hl.FillColor = E.line
            e.hl.OutlineColor = E.box
        end
        if e.bb then
            e.bb.Enabled = true
            e.name.Visible = CFG.espName
            e.name.Text = (player.DisplayName ~= "" and player.DisplayName or player.Name)
            e.name.TextColor3 = E.name
            e.info.Text = tostring(dist) .. "m"
            local wn = CFG.espWeapon and getWeaponName(char) or nil
            if wn and not isNonWeapon(wn) then
                e.weapon.Text = "[ " .. wn .. " ]"
                e.weapon.TextColor3 = E.weapon
                e.weapon.Visible = true
            else
                e.weapon.Visible = false
            end
            local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            e.hpFill.Size = UDim2.fromScale(hp, 1)
            e.hpFill.BackgroundColor3 = hp > 0.4 and E.barAlive or E.barLow
        end
    end
end

-- FOV ring fallback (Frame + UIStroke) so the aim FOV is still visible without Drawing
local function makeFovFallback()
    local folder = FB.ensure()
    if not folder then return nil end
    local ok, obj = pcall(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "KXY_FOV"
        sg.IgnoreGuiInset = true
        pcall(function() sg.ScreenInsets = Enum.ScreenInsets.None end)
        sg.ResetOnSpawn = false
        sg.DisplayOrder = 5
        sg.Parent = folder
        local fr = Instance.new("Frame")
        fr.AnchorPoint = Vector2.new(0.5, 0.5)
        fr.BackgroundTransparency = 1
        fr.BorderSizePixel = 0
        fr.Parent = sg
        Instance.new("UICorner", fr).CornerRadius = UDim.new(1, 0)
        local st = Instance.new("UIStroke", fr)
        st.Thickness = CFG.fov_circle.thick
        st.Color = CFG.fov_circle.color
        local proxy = {}
        return setmetatable(proxy, {
            __newindex = function(_, k, v)
                if k == "Radius" then fr.Size = UDim2.fromOffset(v * 2, v * 2)
                elseif k == "Position" then fr.Position = UDim2.fromOffset(v.X, v.Y)
                elseif k == "Visible" then sg.Enabled = v and true or false
                elseif k == "Color" then st.Color = v
                elseif k == "Thickness" then st.Thickness = v end
            end,
            __index = function(_, k)
                if k == "Remove" then return function() sg:Destroy() end end
                return nil
            end,
        })
    end)
    return ok and obj or nil
end

-- FOV Circle — guarded for executors that lack Drawing.Circle
local fovCircle = nil
if not HAS_DRAWING then fovCircle = makeFovFallback() end
if HAS_DRAWING then pcall(function()
    fovCircle = Drawing.new("Circle")
    fovCircle.Visible   = true
    fovCircle.Color     = CFG.fov_circle.color
    fovCircle.Thickness = CFG.fov_circle.thick
    fovCircle.Filled    = false
    fovCircle.NumSides  = CFG.fov_circle.sides
    fovCircle.Radius    = CFG.fov
    fovCircle.ZIndex    = 1
end) end

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
    local camCF  = camera.CFrame
    local camPos = camCF.Position
    local aimAt  = targetPos
    local speed  = forceSpeed or currentAimSpeed()
    if CFG.stickOn then
        -- Sticky mode: no humanize noise, track speed pushed toward 1.0
        speed = speed + (1 - speed) * math.clamp(CFG.stickStrength, 0, 1)
    else
        local t = os.clock()
        local nx = math.noise(t*1.7,  _aimNoise)     * 0.006
        local ny = math.noise(t*2.1,  _aimNoise+100) * 0.006
        aimAt = targetPos + camCF.RightVector*nx + camCF.UpVector*ny
    end
    if (aimAt - camPos).Magnitude < 0.05 then return end
    local targetCF = CFrame.lookAt(camPos, aimAt, Vector3.new(0,1,0))
    if CFG.stickOn then
        -- v25 Sticky Lock = hard lock. CameraClient (GTACamera) rebuilds camera.CFrame from the player's own
        -- yaw/pitch at the start of EVERY frame, so a lerp here always starts from where the player is looking
        -- (not from last frame's aim) and stops short by (1-alpha) of the angle: that left error grew with recoil
        -- and changed with FPS (alpha = 1-(1-speed)^(dt*60)), which is why the lock hit only some of the time.
        -- WeaponClient fires at Camera-1 from the CFrame we left last frame, so it must be exactly on target.
        camera.CFrame = targetCF
        return
    end
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
            local lo = AntiAim.adStrafeMinTime
            local hi = math.max(AntiAim.adStrafeMaxTime, lo)
            AntiAim._nextADStrafe = now + lo + math.random()*(hi-lo)
            if math.random() < AntiAim.adFlipChance then AntiAim._adDir = -AntiAim._adDir end
            if math.random() < AntiAim.adPauseChance then
                AntiAim._pauseUntil = now + AntiAim.adPauseMin
                    + math.random()*(AntiAim.adPauseMax - AntiAim.adPauseMin)
            end
        end
        -- Keep the strafe perpendicular to the view while the camera tracks the target
        local right = camera.CFrame.RightVector
        local fr = Vector3.new(right.X, 0, right.Z)
        if fr.Magnitude > 0.01 then AntiAim._adVec = fr.Unit*AntiAim._adDir end
        if now >= AntiAim._pauseUntil and AntiAim._adVec then
            hum:Move(AntiAim._adVec, false)
        end
        return
    end
    AntiAim._adVec = nil
end

-- ═══════════════════════════════════════════════════════════
--  FARM v24 — auto lock + auto fire on HoodNPC bots
--  Sources (place dump): Workspace.HoodLocal (client-side bots),
--  ReplicatedStorage.FarmZone (Contains), LocalPlayer attribute "Money",
--  ReplicatedStorage.Controls (Press / IsDown), Weapons.WeaponData.
-- ═══════════════════════════════════════════════════════════
local Farm = {
    active = false, status = "OFF", firing = false,
    kills = 0, looted = 0, earned = 0, money = nil, lastMoney = nil,
    runAt = 0, accTime = 0,
    target = nil, targetDist = nil,
    holdFire = false, holdAim = false, lastPulse = 0,
    lastErr = nil, ui = nil, onToggle = nil, _afkCon = nil, _lastWarn = nil,
}
do
    local WeaponData, FarmZoneMod = nil, nil
    task.spawn(function()
        local w = ReplicatedStorage:WaitForChild("Weapons", 20)
        local wd = w and w:WaitForChild("WeaponData", 20)
        if wd then
            local ok, r = pcall(require, wd)
            if ok and type(r) == "table" then WeaponData = r end
        end
    end)
    task.spawn(function()
        local fz = ReplicatedStorage:WaitForChild("FarmZone", 20)
        if fz then
            local ok, r = pcall(require, fz)
            if ok and type(r) == "table" and type(r.Contains) == "function" then FarmZoneMod = r end
        end
    end)
    function Farm.diag() return FarmZoneMod ~= nil, WeaponData ~= nil end

    -- ── formatting ───────────────────────────────────────────
    function Farm.fmtInt(n)
        n = math.floor((tonumber(n) or 0) + 0.5)
        local neg = n < 0
        local out = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
        if out:sub(1, 1) == "," then out = out:sub(2) end
        return (neg and "-" or "") .. out
    end
    function Farm.fmtCompact(n)
        n = tonumber(n) or 0
        local a = math.abs(n)
        local sign = n < 0 and "-" or ""
        if a >= 1e9 then return sign .. string.format("%.2fB", a / 1e9) end
        if a >= 1e6 then return sign .. string.format("%.2fM", a / 1e6) end
        if a >= 1e4 then return sign .. string.format("%.1fK", a / 1e3) end
        return sign .. Farm.fmtInt(a)
    end
    function Farm.fmtTime(sec)
        sec = math.max(0, math.floor(sec or 0))
        return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
    end
    function Farm.elapsed(now)
        return Farm.accTime + (Farm.active and (now - Farm.runAt) or 0)
    end

    -- ── money ────────────────────────────────────────────────
    function Farm.readMoney()
        local v = lp:GetAttribute("Money")
        if type(v) == "number" then return v end
        local ls = lp:FindFirstChild("leaderstats")
        if ls then
            for _, n in ipairs({ "Money", "Cash", "Argent" }) do
                local o = ls:FindFirstChild(n)
                if o and (o:IsA("NumberValue") or o:IsA("IntValue")) then return o.Value end
            end
        end
        return nil
    end

    -- ── farm zone ────────────────────────────────────────────
    local zoneParts, zoneScanAt = {}, 0
    local function scanZone(now)
        if now < zoneScanAt then return end
        zoneScanAt = now + 5
        local list = {}
        local zs = workspace:FindFirstChild("Zones")
        local root = zs and zs:FindFirstChild("FarmZones")
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("BasePart") and d:GetAttribute("FarmZone") then list[#list + 1] = d end
            end
        end
        zoneParts = list
    end
    -- true / false, or nil when the zone cannot be read at all
    local function inZone(pos, now)
        if FarmZoneMod then
            local ok, r = pcall(FarmZoneMod.Contains, pos)
            if ok then return r == true end
        end
        scanZone(now)
        if #zoneParts == 0 then return nil end
        for _, p in ipairs(zoneParts) do
            local o = p.CFrame:PointToObjectSpace(pos)
            local h = p.Size * 0.5
            if math.abs(o.X) <= h.X and math.abs(o.Y) <= h.Y and math.abs(o.Z) <= h.Z then return true end
        end
        return false
    end

    -- ── bots ─────────────────────────────────────────────────
    -- dead: HoodClient sets CanQuery=false on every part and Lootable=true
    local function botDead(m, head)
        if m:GetAttribute("Lootable") then return true end
        if head.CanQuery == false then return true end
        local hum = m:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return true end
        return false
    end
    local function botAlive(m, head)
        if botDead(m, head) then return false end
        if head.Position.Y < -1000 then return false end   -- parked pool model
        if CFG.farmSkipDowned and m:GetAttribute("HoodDowned") then return false end
        return true
    end
    local function aimPoint(m, head)
        if CFG.farmPart == "Torso" then
            local t = m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
            if t then return t.Position end
        end
        return head.Position
    end

    -- same collision group the game's bullets use
    local losParams = RaycastParams.new()
    losParams.FilterType = Enum.RaycastFilterType.Exclude
    losParams.IgnoreWater = true
    pcall(function() losParams.CollisionGroup = "Bullet" end)
    local function clearLine(from, to, ign)
        local d = to - from
        local len = d.Magnitude
        if len < 0.6 then return true end
        losParams.FilterDescendantsInstances = ign
        local ok, hit = pcall(function() return workspace:Raycast(from, d.Unit * (len - 0.4), losParams) end)
        if not ok then return true end
        return hit == nil
    end

    -- ── auto equip (v24.1) ──────────────────────────────────
    -- Same call the game's own hotbar uses: Humanoid:EquipTool(tool from lp.Backpack).
    -- A gun is a Tool whose "Weapon" attribute exists in WeaponData and has a Fire table.
    local lastGun, noGunSince, equipAt = nil, nil, 0
    local function isGunTool(t)
        if not t:IsA("Tool") then return false end
        local key = t:GetAttribute("Weapon")
        if key == nil then return false end
        if WeaponData then
            local wd = WeaponData[key]
            return wd ~= nil and wd.Fire ~= nil
        end
        return not isNonWeapon(t.Name)
    end
    function Farm.tryEquip(hum, now)
        if now - equipAt < 0.8 then return false end
        local bp = lp:FindFirstChildOfClass("Backpack")
        if not bp then return false end
        local pick, pickScore = nil, -1
        for _, t in ipairs(bp:GetChildren()) do
            if isGunTool(t) then
                local ammo = tonumber(t:GetAttribute("Ammo")) or 0
                local reserve = tonumber(t:GetAttribute("Reserve")) or 0
                local score = (ammo + reserve > 0) and 2 or 0
                if t.Name == lastGun then score = score + 1 end
                if score > pickScore then pick, pickScore = t, score end
            end
        end
        if not pick then return false end
        equipAt = now
        return (pcall(function() hum:EquipTool(pick) end))
    end

    -- ── native HoodNPC corpse auto loot ──────────────────────
    -- Dump-confirmed API: ReplicatedStorage.Weapons.ClientState.HoodLootNear()
    -- returns the game's nearest eligible corpse distance; HoodLootNow() calls
    -- the same native path as the game's interact key. No fabricated remote args.
    local ClientState = nil
    local corpseLootAt = 0
    task.spawn(function()
        local weapons = ReplicatedStorage:WaitForChild("Weapons", 20)
        local module = weapons and weapons:WaitForChild("ClientState", 20)
        if module then
            local ok, result = pcall(require, module)
            if ok and type(result) == "table"
                and type(result.HoodLootNear) == "function"
                and type(result.HoodLootNow) == "function" then
                ClientState = result
            end
        end
    end)

    function Farm.diagLoot()
        return ClientState ~= nil,
            ClientState and type(ClientState.HoodLootNear) == "function" or false,
            ClientState and type(ClientState.HoodLootNow) == "function" or false
    end

    function Farm.tryLootCorpse(folder, hrp, now)
        if not CFG.farmAutoLoot or not ClientState or now < corpseLootAt then return false end
        -- Both the player and the candidate corpse must be inside a known FarmZone.
        if inZone(hrp.Position, now) ~= true then return false end

        local nearestZoneCorpse = math.huge
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model.Parent == folder and model:GetAttribute("Lootable") == true then
                local torso = model:FindFirstChild("UpperTorso")
                    or model:FindFirstChild("HumanoidRootPart")
                    or model:FindFirstChild("Torso")
                if torso and torso:IsA("BasePart") then
                    local distance = (torso.Position - hrp.Position).Magnitude
                    if distance <= CFG.farmDist and inZone(torso.Position, now) == true then
                        if distance < nearestZoneCorpse then nearestZoneCorpse = distance end
                    end
                end
            end
        end
        if nearestZoneCorpse == math.huge then return false end

        -- HoodLootNear only exposes distance, not the selected model. Require its
        -- nearest eligible corpse distance to match our nearest in-zone corpse;
        -- this avoids calling the native action when a closer out-of-zone corpse
        -- would be selected. The game's own proximity/height checks still apply.
        local okNear, nativeDistance = pcall(ClientState.HoodLootNear)
        if not okNear or type(nativeDistance) ~= "number" then return false end
        if nativeDistance > CFG.farmDist or math.abs(nativeDistance - nearestZoneCorpse) > 1.25 then
            return false
        end

        corpseLootAt = now + 0.35
        local okLoot, didLoot = pcall(ClientState.HoodLootNow)
        if not okLoot then
            if Farm._corpseLootWarn ~= tostring(didLoot) then
                Farm._corpseLootWarn = tostring(didLoot)
                warn("[KXY Farm] corpse loot: " .. tostring(didLoot))
            end
            return false
        end
        if didLoot == true then
            Farm.looted = Farm.looted + 1
            Farm.status = "LOOT"
            return true
        end
        return false
    end

    -- ── Farm ESP: native Roblox instances, no Drawing/getupvalue dependency ──
    local botESPRecords = setmetatable({}, { __mode = "k" })
    local zoneESPRecords = setmetatable({}, { __mode = "k" })
    local espRefreshAt = 0

    local function destroyRecord(rec)
        if not rec then return end
        if rec.gui then pcall(function() rec.gui:Destroy() end) end
        if rec.highlight then pcall(function() rec.highlight:Destroy() end) end
        if rec.box then pcall(function() rec.box:Destroy() end) end
    end

    local function makeBotESP(model, head)
        local rec = {}
        local okH, hi = pcall(function()
            local h = Instance.new("Highlight")
            h.Name = "KXY_FarmBot_Highlight"
            h.Adornee = model
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.FillColor = Color3.fromRGB(44, 210, 145)
            h.FillTransparency = 0.84
            h.OutlineColor = Color3.fromRGB(92, 255, 190)
            h.OutlineTransparency = 0.05
            h.Parent = model
            return h
        end)
        if okH then rec.highlight = hi end

        local playerGui = lp:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            local okG, gui = pcall(function()
                local b = Instance.new("BillboardGui")
                b.Name = "KXY_FarmBot_Label"
                b.Adornee = head
                b.Size = UDim2.fromOffset(154, 30)
                b.StudsOffset = Vector3.new(0, 2.5, 0)
                b.AlwaysOnTop = true
                b.LightInfluence = 0
                local label = Instance.new("TextLabel")
                label.Name = "Label"
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundColor3 = Color3.fromRGB(9, 22, 20)
                label.BackgroundTransparency = 0.22
                label.BorderSizePixel = 0
                label.Font = Enum.Font.GothamBold
                label.TextSize = 12
                label.TextColor3 = Color3.fromRGB(224, 255, 239)
                label.TextStrokeTransparency = 0.55
                label.Text = "BOT"
                label.Parent = b
                local c = Instance.new("UICorner")
                c.CornerRadius = UDim.new(0, 7)
                c.Parent = label
                local st = Instance.new("UIStroke")
                st.Color = Color3.fromRGB(75, 230, 160)
                st.Thickness = 1
                st.Transparency = 0.15
                st.Parent = label
                b.Parent = playerGui
                return b
            end)
            if okG then rec.gui = gui end
        end
        rec.head = head
        return rec
    end

    local function makeZoneESP(part)
        local cameraNow = workspace.CurrentCamera
        local ok, box = pcall(function()
            local b = Instance.new("BoxHandleAdornment")
            b.Name = "KXY_FarmZone_Box"
            b.Adornee = part
            b.Size = part.Size
            b.CFrame = CFrame.new()
            b.AlwaysOnTop = true
            b.ZIndex = 6
            b.Color3 = Color3.fromRGB(80, 165, 255)
            b.Transparency = 0.82
            b.Parent = cameraNow or workspace
            return b
        end)
        return ok and box or nil
    end

    function Farm.updateESP(now)
        if now < espRefreshAt then return end
        espRefreshAt = now + 0.2

        local folder = workspace:FindFirstChild("HoodLocal")
        if CFG.farmBotESP and folder then
            local seen = {}
            local char = lp.Character
            local myRoot = char and char:FindFirstChild("HumanoidRootPart")
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") then
                    local head = model:FindFirstChild("Head")
                    local hum = model:FindFirstChildOfClass("Humanoid")
                    local alive = head and head:IsA("BasePart") and botAlive(model, head)
                        and head.CanQuery ~= false
                        and (not hum or hum.Health > 0)
                        and (not CFG.farmZoneOnly or inZone(head.Position, now) == true)
                    if alive then
                        seen[model] = true
                        local rec = botESPRecords[model]
                        local playerGuiReady = lp:FindFirstChildOfClass("PlayerGui") ~= nil
                        if not rec or rec.head ~= head or (playerGuiReady and not rec.gui) then
                            destroyRecord(rec)
                            rec = makeBotESP(model, head)
                            botESPRecords[model] = rec
                        end
                        if rec.gui then
                            local dist = myRoot and (head.Position - myRoot.Position).Magnitude or 0
                            local hpText = hum and string.format("%d HP", math.max(0, math.floor(hum.Health + 0.5))) or "BOT"
                            local label = rec.gui:FindFirstChild("Label")
                            if label then label.Text = string.format("BOT  •  %s  •  %dm", hpText, math.floor(dist + 0.5)) end
                            rec.gui.Enabled = true
                        end
                    end
                end
            end
            for model, rec in pairs(botESPRecords) do
                if not seen[model] then destroyRecord(rec) botESPRecords[model] = nil end
            end
        else
            for model, rec in pairs(botESPRecords) do destroyRecord(rec) botESPRecords[model] = nil end
        end

        scanZone(now)
        if CFG.farmZoneESP then
            local seen = {}
            for _, part in ipairs(zoneParts) do
                if part and part.Parent then
                    seen[part] = true
                    local box = zoneESPRecords[part]
                    if not box or not box.Parent then
                        box = makeZoneESP(part)
                        zoneESPRecords[part] = box
                    end
                    if box then box.Size = part.Size box.Adornee = part end
                end
            end
            for part, box in pairs(zoneESPRecords) do
                if not seen[part] then
                    if box then pcall(function() box:Destroy() end) end
                    zoneESPRecords[part] = nil
                end
            end
        else
            for part, box in pairs(zoneESPRecords) do
                if box then pcall(function() box:Destroy() end) end
                zoneESPRecords[part] = nil
            end
        end
    end

    -- ── input ────────────────────────────────────────────────
    function Farm.release()
        if Ctl then
            if Farm.holdFire then pcall(Ctl.Press, "Fire", false) end
            if Farm.holdAim then pcall(Ctl.Press, "Aim", false) end
        end
        Farm.holdFire = false
        Farm.holdAim = false
        Farm.firing = false
    end

    function Farm.setAntiAfk(on)
        if Farm._afkCon then Farm._afkCon:Disconnect() Farm._afkCon = nil end
        if on then
            Farm._afkCon = lp.Idled:Connect(function()
                local okVU = pcall(function()
                    local vu = game:GetService("VirtualUser")
                    vu:CaptureController()
                    vu:ClickButton2(Vector2.new(0, 0))
                end)
                if not okVU then
                    pcall(function()
                        local vim = game:GetService("VirtualInputManager")
                        local c = camera.ViewportSize / 2
                        vim:SendMouseButtonEvent(c.X, c.Y, 1, true, game, 0)
                        task.wait(0.05)
                        vim:SendMouseButtonEvent(c.X, c.Y, 1, false, game, 0)
                    end)
                end
            end)
        end
    end

    function Farm.set(on)
        on = on and true or false
        if on == Farm.active then return end
        local now = os.clock()
        Farm.active = on
        if on then
            Farm.runAt = now
            Farm.lastMoney = Farm.readMoney()
            Farm.status = "SEARCH"
            Farm.lastErr = nil
            if CFG.farmAntiAfk then Farm.setAntiAfk(true) end
        else
            Farm.accTime = Farm.accTime + (now - Farm.runAt)
            Farm.release()
            Farm.target = nil
            Farm.status = "OFF"
            Farm.setAntiAfk(false)
        end
    end

    function Farm.resetStats()
        Farm.earned = 0
        Farm.kills = 0
        Farm.looted = 0
        Farm.accTime = 0
        Farm.runAt = os.clock()
        Farm.lastMoney = Farm.readMoney()
    end

    function Farm.fail(err)
        Farm.release()
        Farm.status = "ERR"
        Farm.lastErr = tostring(err)
        if Farm._lastWarn ~= Farm.lastErr then
            Farm._lastWarn = Farm.lastErr
            warn("[KXY Farm] " .. Farm.lastErr)
        end
    end

    -- ── main tick (called every render step, inside a pcall) ─
    function Farm.tick(dt, now)
        pcall(Farm.updateESP, now)
        local m = Farm.readMoney()
        if m then
            if Farm.active and Farm.lastMoney and m > Farm.lastMoney then
                Farm.earned = Farm.earned + (m - Farm.lastMoney)
            end
            Farm.lastMoney = m
            Farm.money = m
        end
        if Farm.ui then Farm.ui.update(dt, now) end
        if not Farm.active then
            if Farm.holdFire or Farm.holdAim then Farm.release() end
            return
        end

        local ch = lp.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if not (hum and hrp) or hum.Health <= 0 or ch:GetAttribute("Downed") or hum.SeatPart then
            Farm.status = "BUSY" Farm.target = nil Farm.release()
            return
        end

        -- Corpse pickup is independent of weapon state; it still uses the game's
        -- native proximity check and is strictly gated to in-zone bodies.
        local folder = workspace:FindFirstChild("HoodLocal")
        if folder then pcall(Farm.tryLootCorpse, folder, hrp, now) end

        -- weapon: a gun is a Tool whose "Weapon" attribute exists in WeaponData (same test WeaponClient uses)
        local tool = ch:FindFirstChildOfClass("Tool")
        local gun, auto, rpm = false, false, nil
        if tool then
            if WeaponData then
                local key = tool:GetAttribute("Weapon")
                local wd = key and WeaponData[key]
                if wd and wd.Fire then
                    gun = true
                    auto = (wd.Fire.Mode == "Auto")
                    rpm = tonumber(wd.Fire.RPM)
                end
            else
                gun = not isNonWeapon(tool.Name)
            end
        end
        if gun then
            lastGun = tool.Name
            noGunSince = nil
        else
            Farm.target = nil
            Farm.release()
            if CFG.farmAutoEquip then
                noGunSince = noGunSince or now
                if now - noGunSince >= 0.35 and Farm.tryEquip(hum, now) then
                    Farm.status = "EQUIP"
                    return
                end
            end
            Farm.status = "NOGUN"
            return
        end

        if CFG.farmZoneOnly then
            local pin = inZone(hrp.Position, now)
            if pin == nil then Farm.status = "NOZONEDATA" Farm.target = nil Farm.release() return end
            if not pin then Farm.status = "NOZONE" Farm.target = nil Farm.release() return end
        end

        if not folder then
            Farm.status = "SEARCH" Farm.target = nil Farm.release()
            return
        end

        local camCF = camera.CFrame
        local camPos = camCF.Position
        local headC = ch:FindFirstChild("Head")
        local eye = headC and headC.Position or (hrp.Position + Vector3.new(0, 1.5, 0))
        local ign = { camera, ch, folder }
        local fx = workspace:FindFirstChild("FX")
        if fx then ign[#ign + 1] = fx end

        local function visible(p)
            if not CFG.farmWall then return true end
            return clearLine(camPos, p, ign) and clearLine(eye, p, ign)
        end
        local function evaluate(mdl)
            local head = mdl:FindFirstChild("Head")
            if not head or not botAlive(mdl, head) then return nil end
            local p = aimPoint(mdl, head)
            local d = (p - camPos).Magnitude
            if d > CFG.farmDist then return nil end
            if CFG.farmZoneOnly and inZone(p, now) ~= true then return nil end
            if not visible(p) then return nil end
            return p, d
        end

        -- bookkeeping: did the locked bot die? (before looting, so a looted body still counts as a kill)
        do
            local c0 = Farm.target
            if c0 then
                local h0 = c0:FindFirstChild("Head")
                if (not c0.Parent) or not h0 then
                    Farm.target = nil
                elseif botDead(c0, h0) then
                    if h0.Position.Y > -1000 then Farm.kills = Farm.kills + 1 end
                    Farm.target = nil
                end
            end
        end

        local cur = Farm.target

        local tpos, tdist
        if cur then tpos, tdist = evaluate(cur) end
        if not tpos then
            cur = nil
            local list = {}
            for _, mdl in ipairs(folder:GetChildren()) do
                if mdl:IsA("Model") then
                    local head = mdl:FindFirstChild("Head")
                    if head and botAlive(mdl, head) then
                        list[#list + 1] = { m = mdl, d = (head.Position - camPos).Magnitude }
                    end
                end
            end
            table.sort(list, function(a, b) return a.d < b.d end)
            for i = 1, math.min(#list, 6) do
                local p, d = evaluate(list[i].m)
                if p then cur, tpos, tdist = list[i].m, p, d break end
            end
        end
        Farm.target = cur
        Farm.targetDist = tdist

        if not cur then
            Farm.status = "SEARCH"
            Farm.release()
            return
        end

        Farm.status = "LOCK"
        local dirv = tpos - camPos
        if CFG.farmAim and dirv.Magnitude > 0.05 then
            local targetCF = CFrame.lookAt(camPos, tpos, Vector3.new(0, 1, 0))
            local dot = math.clamp(camCF.LookVector:Dot(dirv.Unit), -1, 1)
            local alpha = math.clamp(1 - (1 - CFG.farmAimSpeed) ^ (dt * 60), 0, 1)
            if math.acos(dot) < math.rad(2) then alpha = 1 end
            camera.CFrame = CFrame.new(camPos) * camCF.Rotation:Lerp(targetCF.Rotation, alpha)
        end
        local look = camera.CFrame.LookVector
        local ang = math.acos(math.clamp(look:Dot(dirv.Unit), -1, 1))
        local allow = math.clamp(math.deg(math.atan(0.7 / math.max(tdist, 1))), 1, 5)
        local aligned = ang <= math.rad(allow)

        if not Ctl then
            Farm.firing = false
            return
        end
        -- WeaponClient only fires while ClientState.Aiming is true
        if not Farm.holdAim then
            if pcall(Ctl.Press, "Aim", true) then Farm.holdAim = true end
        end
        if CFG.farmShoot and aligned then
            if auto then
                if not Farm.holdFire then
                    if pcall(Ctl.Press, "Fire", true) then Farm.holdFire = true end
                end
            else
                local gap = math.max(60 / (rpm or 600), 0.07)
                if now - Farm.lastPulse >= gap then
                    pcall(Ctl.Press, "Fire", false)
                    if pcall(Ctl.Press, "Fire", true) then Farm.holdFire = true end
                    Farm.lastPulse = now
                end
            end
            Farm.firing = true
        else
            if Farm.holdFire then pcall(Ctl.Press, "Fire", false) Farm.holdFire = false end
            Farm.firing = false
        end
    end
end

-- ═══════════════════════════════════════════════════════════
--  MENU
-- ═══════════════════════════════════════════════════════════
local function buildMenu()
    local TweenService    = game:GetService("TweenService")
    local ContentProvider = game:GetService("ContentProvider")
    local GuiService      = game:GetService("GuiService")
    local uiParent
    if type(gethui)=="function" then
        local ok,r = pcall(gethui)
        if ok and r then uiParent = r end
    end
    uiParent = uiParent or lp:WaitForChild("PlayerGui")

    -- ── Chỉnh nhanh: ảnh nút minisize + link kênh ────────────────────────
    -- Ảnh nút minisize "KXY on top" được nhúng sẵn trong script (JPEG 256x256, vuông, vừa nút 50x50).
    -- Script ghi ảnh ra file MINI_FILE rồi nạp bằng getcustomasset (cần executor hỗ trợ).
    -- Muốn dùng ảnh đã upload lên Roblox: điền MINI_IMAGE_ID = "rbxassetid://<ID của ẢNH, không phải Decal>".
    -- Nếu không nạp được ảnh nào, nút tự hiện chữ "KXY".
    local MINI_IMAGE_ID = ""
    local MINI_FILE     = "kxy_mini_logo_sq.jpg"
    local MINI_W, MINI_H = 50, 50
    local DISCORD_URL   = "https://discord.gg/YxpZy2Nrj8"
    local DISCORD_SHOW  = "discord.gg/YxpZy2Nrj8"
    local TIKTOK_URL    = "https://www.tiktok.com/@kxybruh"
    local TIKTOK_SHOW   = "tiktok.com/@kxybruh"
    local VERSION_TAG   = "v26.0"

    -- ── Theme (nền trắng) ────────────────────────────────────────────────
    local T = {
        bg     = Color3.fromRGB(255,255,255),
        panel  = Color3.fromRGB(244,245,251),
        row    = Color3.fromRGB(247,248,252),
        rowHi  = Color3.fromRGB(233,235,247),
        stroke = Color3.fromRGB(214,217,233),
        text   = Color3.fromRGB(30,32,48),
        sub    = Color3.fromRGB(104,108,136),
        accent = Color3.fromRGB(124,72,240),
        accent2= Color3.fromRGB(236,72,168),
        off    = Color3.fromRGB(200,203,220),
        good   = Color3.fromRGB(22,140,84),
        warn   = Color3.fromRGB(150,84,0),
        warnBg = Color3.fromRGB(255,244,226),
        bad    = Color3.fromRGB(190,48,60),
        white  = Color3.new(1,1,1),
    }
    -- SourceSans hỗ trợ dấu tiếng Việt. Muốn đổi font chỉ sửa 3 dòng này.
    local F_REG  = Enum.Font.SourceSans
    local F_SEMI = Enum.Font.SourceSansSemibold
    local F_BOLD = Enum.Font.SourceSansBold

    local function mk(class, props, parent)
        local o = Instance.new(class)
        for k,v in pairs(props) do o[k] = v end
        o.Parent = parent
        return o
    end
    local function corner(o, r)
        return mk("UICorner", {CornerRadius = UDim.new(0, r)}, o)
    end
    local function stroke(o, col, th, tr)
        return mk("UIStroke", {
            Color = col, Thickness = th or 1, Transparency = tr or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, o)
    end
    local function tween(o, props, t, style, dir)
        local tw = TweenService:Create(o,
            TweenInfo.new(t or 0.15, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
            props)
        tw:Play()
        return tw
    end
    local function isPointer(inp)
        return inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch
    end
    local function copyText(s)
        local clip = setclipboard or toclipboard
            or (type(deltaclipboard)=="function" and deltaclipboard)
            or (type(rbxclipboard)=="function" and rbxclipboard)
        if type(clip) ~= "function" then return false end
        return (pcall(clip, s))
    end
    local function openUrl(url)
        return (pcall(function() GuiService:OpenBrowserWindow(url) end))
    end

    -- ── Ảnh nút minisize: giải mã base64 nhúng sẵn -> file -> getcustomasset ──
    local function miniB64()
        return table.concat({
            "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",
        })
    end
    local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local function b64decode(data)
        local map = {}
        for i = 1, #B64_CHARS do map[B64_CHARS:byte(i)] = i - 1 end
        local out, n, buf, bits = {}, 0, 0, 0
        for i = 1, #data do
            local v = map[data:byte(i)]
            if v then
                buf = buf * 64 + v
                bits = bits + 6
                if bits >= 8 then
                    bits = bits - 8
                    local div = 2 ^ bits
                    local byte = math.floor(buf / div)
                    buf = buf - byte * div
                    n = n + 1
                    out[n] = string.char(byte)
                end
            end
        end
        return table.concat(out)
    end
    local function resolveMiniImage()
        if MINI_IMAGE_ID ~= "" then return MINI_IMAGE_ID end
        local getAsset = getcustomasset or getsynasset
        if type(writefile) == "function" and type(getAsset) == "function" then
            local ok, res = pcall(function()
                writefile(MINI_FILE, b64decode(miniB64()))
                return getAsset(MINI_FILE)
            end)
            if ok and type(res) == "string" and res ~= "" then return res end
        end
        return ""
    end

    -- ── Hiệu ứng dùng chung: nhấn (co nhẹ), hover (PC), flash khi bấm ────
    local pressed = {}
    local function attachPress(host, scaleObj, amount)
        host.InputBegan:Connect(function(inp)
            if isPointer(inp) then
                pressed[scaleObj] = true
                tween(scaleObj, {Scale = amount or 0.97}, 0.07)
            end
        end)
    end
    UserInputService.InputEnded:Connect(function(inp)
        if isPointer(inp) then
            for sc in pairs(pressed) do
                pressed[sc] = nil
                tween(sc, {Scale = 1}, 0.22, Enum.EasingStyle.Back)
            end
        end
    end)
    local function attachHover(host, base, hi)
        host.MouseEnter:Connect(function() tween(host, {BackgroundColor3 = hi}, 0.12) end)
        host.MouseLeave:Connect(function() tween(host, {BackgroundColor3 = base}, 0.12) end)
    end
    local function flash(host, col, startT, radius)
        local f = mk("Frame", {
            Size = UDim2.fromScale(1,1), BackgroundColor3 = col or T.accent,
            BackgroundTransparency = startT or 0.78, BorderSizePixel = 0, ZIndex = 0,
        }, host)
        corner(f, radius or 10)
        tween(f, {BackgroundTransparency = 1}, 0.45).Completed:Connect(function() f:Destroy() end)
    end

    local SG = Instance.new("ScreenGui")
    SG.Name = "KXYMenu" SG.ResetOnSpawn = false
    SG.IgnoreGuiInset = true SG.DisplayOrder = 999998
    SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    SG.Parent = uiParent

    -- ── Nút minisize (dùng ảnh) ──────────────────────────────────────────
    local miniImage = resolveMiniImage()
    local mini = mk("ImageButton", {
        Name = "MiniButton",
        Size = UDim2.new(0,MINI_W,0,MINI_H), Position = UDim2.new(0,8,0.5,-math.floor(MINI_H/2)),
        BackgroundColor3 = T.bg, BorderSizePixel = 0,
        Image = miniImage, ScaleType = Enum.ScaleType.Fit,
        AutoButtonColor = false, ZIndex = 5,
    }, SG)
    corner(mini, 12)
    local miniStroke = stroke(mini, T.accent, 2, 0.1)
    local miniScale  = mk("UIScale", {Scale = 1}, mini)
    attachPress(mini, miniScale, 0.88)
    local miniFallback = mk("TextLabel", {
        Size = UDim2.fromScale(1,1), BackgroundTransparency = 1, Text = "KXY",
        TextColor3 = T.accent, Font = F_BOLD, TextSize = 14, Visible = false,
    }, mini)
    local function miniImageLoaded()
        local ok, v = pcall(function() return mini.IsLoaded end)
        return (not ok) or v
    end
    if miniImage == "" then
        miniFallback.Visible = true
    else
        task.spawn(function()
            pcall(function() ContentProvider:PreloadAsync({mini}) end)
            if not miniImageLoaded() then task.wait(2) end
            if mini.Parent and not miniImageLoaded() then miniFallback.Visible = true end
        end)
    end
    -- vòng viền nhấp nháy nhẹ khi menu đang đóng
    local pulse = TweenService:Create(miniStroke,
        TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Transparency = 0.8, Thickness = 3.5})

    -- ── Cửa sổ ───────────────────────────────────────────────────────────
    local vp = camera.ViewportSize
    local W = math.clamp(math.floor(vp.X * 0.60), 340, 520)
    local H = math.clamp(math.floor(vp.Y * 0.80), 240, 360)
    if vp.X > 100 then W = math.min(W, vp.X - 12) end
    if vp.Y > 100 then H = math.min(H, vp.Y - 12) end
    local px = MINI_W + 16
    if vp.X > 100 and (W + px) > vp.X then px = math.floor((vp.X - W) / 2) end

    local HDR_H, FTR_H = 46, 20

    local holder = mk("Frame", {
        Name = "Window", AnchorPoint = Vector2.new(0.5,0.5),
        Size = UDim2.new(0,W,0,H),
        Position = UDim2.new(0, px + math.floor(W/2), 0.5, 0),
        BackgroundTransparency = 1, Visible = false,
    }, SG)
    local winScale = mk("UIScale", {Scale = 1}, holder)
    local shadow = mk("Frame", {
        Size = UDim2.new(1,10,1,10), Position = UDim2.new(0,-5,0,-3),
        BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 0.86,
        BorderSizePixel = 0, ZIndex = 0,
    }, holder)
    corner(shadow, 17)
    -- CanvasGroup: cho phép làm mờ cả cửa sổ khi đóng/mở
    local mf = mk("CanvasGroup", {
        Name = "MainFrame", Size = UDim2.fromScale(1,1),
        BackgroundColor3 = T.bg, BorderSizePixel = 0, GroupTransparency = 0,
    }, holder)
    corner(mf, 14)
    local ring = mk("Frame", {
        Size = UDim2.fromScale(1,1), BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 20,
    }, holder)
    corner(ring, 14)
    local ringStroke = stroke(ring, T.accent, 1.5, 0.35)

    -- Header
    local hdr = mk("Frame", {
        Size = UDim2.new(1,0,0,HDR_H), BackgroundColor3 = T.bg, BorderSizePixel = 0,
    }, mf)
    local hline = mk("Frame", {
        Size = UDim2.new(1,0,0,2), Position = UDim2.new(0,0,1,-2),
        BackgroundColor3 = T.white, BorderSizePixel = 0,
    }, hdr)
    local hGrad = mk("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   T.accent),
            ColorSequenceKeypoint.new(0.5, T.accent2),
            ColorSequenceKeypoint.new(1,   T.accent),
        }),
        Offset = Vector2.new(-0.5, 0),
    }, hline)
    TweenService:Create(hGrad,
        TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Offset = Vector2.new(0.5, 0)}):Play()
    local titleLbl = mk("TextLabel", {
        Size = UDim2.new(0,170,0,22), Position = UDim2.new(0,14,0,5),
        BackgroundTransparency = 1, Text = "KXY HUB",
        TextColor3 = T.white, Font = F_BOLD, TextSize = 22,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, hdr)
    mk("UIGradient", {Color = ColorSequence.new(T.accent, T.accent2)}, titleLbl)
    local platformTag = PLATFORM.name
    mk("TextLabel", {
        Size = UDim2.new(1,-70,0,14), Position = UDim2.new(0,14,0,27),
        BackgroundTransparency = 1, Text = "Urban Reload  •  " .. VERSION_TAG .. "  •  " .. platformTag,
        TextColor3 = T.sub, Font = F_REG, TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, hdr)
    local minBtn = mk("TextButton", {
        Size = UDim2.new(0,32,0,32), Position = UDim2.new(1,-42,0.5,-17),
        BackgroundColor3 = T.panel, BorderSizePixel = 0, Text = "–",
        TextColor3 = T.text, Font = F_BOLD, TextSize = 22, AutoButtonColor = false,
    }, hdr)
    corner(minBtn, 9)
    attachHover(minBtn, T.panel, T.rowHi)
    attachPress(minBtn, mk("UIScale", {}, minBtn), 0.88)

    -- Sidebar + nội dung
    local SIDE_W = (W < 400) and 78 or 108
    local side = mk("ScrollingFrame", {
        Size = UDim2.new(0,SIDE_W,1,-(HDR_H+FTR_H)), Position = UDim2.new(0,0,0,HDR_H),
        BackgroundColor3 = T.panel, BorderSizePixel = 0, ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, mf)
    mk("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,5)}, side)
    mk("UIPadding", {
        PaddingTop = UDim.new(0,8), PaddingBottom = UDim.new(0,8),
        PaddingLeft = UDim.new(0,6), PaddingRight = UDim.new(0,6),
    }, side)
    mk("Frame", {
        Size = UDim2.new(0,1,1,-(HDR_H+FTR_H)), Position = UDim2.new(0,SIDE_W,0,HDR_H),
        BackgroundColor3 = T.stroke, BorderSizePixel = 0,
    }, mf)

    local content = mk("Frame", {
        Size = UDim2.new(1,-(SIDE_W+1),1,-(HDR_H+FTR_H)), Position = UDim2.new(0,SIDE_W+1,0,HDR_H),
        BackgroundTransparency = 1, ClipsDescendants = true,
    }, mf)

    mk("TextLabel", {
        Size = UDim2.new(1,0,0,FTR_H), Position = UDim2.new(0,0,1,-FTR_H),
        BackgroundColor3 = T.panel, BorderSizePixel = 0,
        Text = "KXY " .. VERSION_TAG .. "  •  " .. DISCORD_SHOW .. "  •  " .. TIKTOK_SHOW,
        TextColor3 = T.sub, Font = F_REG, TextSize = 13,
    }, mf)

    -- Thông báo nhỏ (toast) — dùng cho sao chép link, lưu, đặt lại
    local TOAST_COL = {good = T.good, warn = Color3.fromRGB(176,96,0), bad = T.bad}
    local toastTok = 0
    local toastBox = mk("TextLabel", {
        AnchorPoint = Vector2.new(0.5,1),
        Position = UDim2.new(0.5,0,1,-(FTR_H-8)),
        Size = UDim2.new(0,0,0,0), AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundColor3 = T.text, BackgroundTransparency = 1, BorderSizePixel = 0,
        Text = "", TextColor3 = T.white, TextTransparency = 1,
        Font = F_SEMI, TextSize = 15, TextWrapped = true, ZIndex = 30,
    }, mf)
    corner(toastBox, 14)
    mk("UIPadding", {
        PaddingLeft = UDim.new(0,14), PaddingRight = UDim.new(0,14),
        PaddingTop = UDim.new(0,7), PaddingBottom = UDim.new(0,7),
    }, toastBox)
    mk("UISizeConstraint", {MaxSize = Vector2.new(math.max(W-40, 120), 90)}, toastBox)
    local function toast(msg, kind)
        toastTok = toastTok + 1
        local my = toastTok
        toastBox.Text = msg
        toastBox.BackgroundColor3 = TOAST_COL[kind] or T.text
        toastBox.Position = UDim2.new(0.5,0,1,-(FTR_H-8))
        toastBox.BackgroundTransparency = 1
        toastBox.TextTransparency = 1
        tween(toastBox, {
            Position = UDim2.new(0.5,0,1,-(FTR_H+8)),
            BackgroundTransparency = 0.04, TextTransparency = 0,
        }, 0.22)
        task.delay(2.4, function()
            if toastTok == my then
                tween(toastBox, {
                    Position = UDim2.new(0.5,0,1,-(FTR_H-8)),
                    BackgroundTransparency = 1, TextTransparency = 1,
                }, 0.2)
            end
        end)
    end

    -- ── Tabs ─────────────────────────────────────────────────────────────
    local tabs = {
        { id = "AIM",  label = "NGẮM" },
        { id = "FARM", label = "FARM" },
        { id = "ESP",  label = "ESP" },
        { id = "MOVE", label = "DI CHUYỂN" },
        { id = "FPS",  label = "FPS" },
        { id = "SET",  label = "CÀI ĐẶT" },
        { id = "INFO", label = "INFO" },
    }
    local pages, tabBtns = {}, {}
    local currentTab = nil
    for i, t in ipairs(tabs) do
        local sf = mk("ScrollingFrame", {
            Size = UDim2.fromScale(1,1), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 4, ScrollBarImageColor3 = T.accent,
            CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
        }, content)
        mk("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,7)}, sf)
        mk("UIPadding", {
            PaddingTop = UDim.new(0,8), PaddingBottom = UDim.new(0,10),
            PaddingLeft = UDim.new(0,8), PaddingRight = UDim.new(0,10),
        }, sf)
        pages[t.id] = sf

        local tb = mk("TextButton", {
            Size = UDim2.new(1,0,0,36), BackgroundColor3 = T.panel,
            BorderSizePixel = 0, Text = t.label, AutoButtonColor = false,
            TextColor3 = T.sub, Font = F_BOLD, TextSize = 15, TextScaled = true, LayoutOrder = i,
        }, side)
        mk("UITextSizeConstraint", {MaxTextSize = 15, MinTextSize = 9}, tb)
        mk("UIPadding", {PaddingLeft = UDim.new(0,8), PaddingRight = UDim.new(0,4)}, tb)
        corner(tb, 9)
        local bar = mk("Frame", {
            Size = UDim2.new(0,3,0,0), AnchorPoint = Vector2.new(0,0.5),
            Position = UDim2.new(0,0,0.5,0),
            BackgroundColor3 = T.accent, BorderSizePixel = 0,
        }, tb)
        corner(bar, 2)
        tabBtns[t.id] = { btn = tb, bar = bar }
        attachPress(tb, mk("UIScale", {}, tb), 0.94)
        tb.MouseEnter:Connect(function()
            if currentTab ~= t.id then tween(tb, {BackgroundColor3 = T.rowHi}, 0.12) end
        end)
        tb.MouseLeave:Connect(function()
            if currentTab ~= t.id then tween(tb, {BackgroundColor3 = T.panel}, 0.12) end
        end)
    end
    local function switchTab(id, instant)
        if currentTab == id then return end
        currentTab = id
        for _, t in ipairs(tabs) do
            local on = (t.id == id)
            local b = tabBtns[t.id]
            tween(b.btn, {
                BackgroundColor3 = on and T.bg or T.panel,
                TextColor3 = on and T.accent or T.sub,
            }, 0.15)
            tween(b.bar, {Size = UDim2.new(0,3,on and 0.6 or 0,0)}, 0.2)
            local pg = pages[t.id]
            if on then
                pg.CanvasPosition = Vector2.new(0,0)
                pg.Position = UDim2.new(0, instant and 0 or 18, 0, 0)
                pg.Visible = true
                if not instant then tween(pg, {Position = UDim2.new(0,0,0,0)}, 0.24) end
            else
                pg.Visible = false
            end
        end
    end
    for _, t in ipairs(tabs) do
        tabBtns[t.id].btn.Activated:Connect(function() switchTab(t.id) end)
    end

    -- ── Widget ───────────────────────────────────────────────────────────
    local orders = {}
    local function ord(page)
        orders[page] = (orders[page] or 0) + 1
        return orders[page]
    end

    local function mkSection(page, text)
        local f = mk("Frame", {
            Size = UDim2.new(1,0,0,24), BackgroundTransparency = 1, LayoutOrder = ord(page),
        }, page)
        local b = mk("Frame", {
            Size = UDim2.new(0,3,0,13), Position = UDim2.new(0,2,0.5,-6),
            BackgroundColor3 = T.accent, BorderSizePixel = 0,
        }, f)
        corner(b, 2)
        mk("TextLabel", {
            Size = UDim2.new(1,-12,1,0), Position = UDim2.new(0,11,0,0),
            BackgroundTransparency = 1, Text = text, TextColor3 = T.accent,
            Font = F_BOLD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
        }, f)
        return f
    end

    local function mkRow(page, class)
        local r = mk(class or "Frame", {
            Size = UDim2.new(1,0,0,40), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = T.row, BorderSizePixel = 0, LayoutOrder = ord(page),
        }, page)
        if class == "TextButton" then r.Text = "" r.AutoButtonColor = false end
        corner(r, 10)
        stroke(r, T.stroke, 1, 0.25)
        return r
    end

    -- Nhãn + mô tả nhỏ bên dưới (tự giãn chiều cao)
    local function textStack(row, label, desc, rightPad)
        local st = mk("Frame", {
            Size = UDim2.new(1,-rightPad,0,0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, row)
        mk("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,2)}, st)
        mk("UIPadding", {
            PaddingTop = UDim.new(0,9), PaddingBottom = UDim.new(0,9), PaddingLeft = UDim.new(0,12),
        }, st)
        mk("TextLabel", {
            Size = UDim2.new(1,0,0,0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1, Text = label, TextColor3 = T.text,
            Font = F_SEMI, TextSize = 17, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 1,
        }, st)
        if desc and desc ~= "" then
            mk("TextLabel", {
                Size = UDim2.new(1,0,0,0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, Text = desc, TextColor3 = T.sub,
                Font = F_REG, TextSize = 14, TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                LayoutOrder = 2,
            }, st)
        end
        return st
    end

    local function mkToggle(page, label, desc, getter, setter)
        local row = mkRow(page, "TextButton")
        attachPress(row, mk("UIScale", {}, row), 0.97)
        attachHover(row, T.row, T.rowHi)
        textStack(row, label, desc, 68)
        local track = mk("Frame", {
            Size = UDim2.new(0,42,0,24), Position = UDim2.new(1,-54,0.5,-12),
            BackgroundColor3 = T.off, BorderSizePixel = 0,
        }, row)
        corner(track, 12)
        local thumb = mk("Frame", {
            Size = UDim2.new(0,18,0,18), Position = UDim2.new(0,3,0.5,-9),
            BackgroundColor3 = T.white, BorderSizePixel = 0,
        }, track)
        corner(thumb, 9)
        stroke(thumb, Color3.new(0,0,0), 1, 0.85)
        local function refresh(animate)
            local on = getter() and true or false
            local pos = on and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)
            local col = on and T.accent or T.off
            if animate then
                tween(thumb, {Position = pos}, 0.24, Enum.EasingStyle.Back)
                tween(track, {BackgroundColor3 = col}, 0.18)
            else
                thumb.Position = pos
                track.BackgroundColor3 = col
            end
        end
        refresh(false)
        row.Activated:Connect(function()
            setter(not getter())
            refresh(true)
            flash(row, T.accent, 0.8, 10)
            scheduleSave()
        end)
        return row, refresh
    end

    -- options: giá trị thật lưu trong CFG; display: chữ hiển thị cho từng giá trị
    local function mkCycle(page, label, desc, options, display, getter, setter)
        local row = mkRow(page, "Frame")
        textStack(row, label, desc, 126)
        local function shown(v) return (display and display[v]) or tostring(v) end
        local btn = mk("TextButton", {
            Size = UDim2.new(0,106,0,32), Position = UDim2.new(1,-116,0.5,-16),
            BackgroundColor3 = T.rowHi, BorderSizePixel = 0, Text = shown(getter()),
            TextColor3 = T.accent, Font = F_BOLD, TextSize = 16, AutoButtonColor = false,
        }, row)
        corner(btn, 9)
        stroke(btn, T.accent, 1, 0.55)
        attachPress(btn, mk("UIScale", {}, btn), 0.92)
        attachHover(btn, T.rowHi, Color3.fromRGB(220,223,243))
        btn.Activated:Connect(function()
            local cur = getter()
            local idx = 1
            for i, o in ipairs(options) do
                if o == cur then idx = i break end
            end
            local nxt = options[(idx % #options) + 1]
            setter(nxt)
            btn.Text = shown(nxt)
            flash(btn, T.accent, 0.78, 9)
            scheduleSave()
        end)
        return row
    end

    -- Slider: một cặp kết nối toàn cục cho thao tác kéo
    local activeSlider = nil
    UserInputService.InputChanged:Connect(function(inp)
        if activeSlider and (inp.UserInputType == Enum.UserInputType.MouseMovement
        or inp.UserInputType == Enum.UserInputType.Touch) then
            activeSlider.update(inp.Position)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if activeSlider and isPointer(inp) then
            activeSlider.stop()
            activeSlider = nil
        end
    end)

    local function mkSlider(page, label, desc, minV, maxV, getter, setter, dp)
        dp = dp or 0
        local mult = 10 ^ dp
        local function fmt(v)
            return dp == 0 and tostring(math.floor(v + 0.5)) or string.format("%." .. dp .. "f", v)
        end
        local row = mkRow(page, "Frame")
        local st = mk("Frame", {
            Size = UDim2.new(1,0,0,0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, row)
        mk("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,2)}, st)
        mk("UIPadding", {
            PaddingTop = UDim.new(0,8), PaddingBottom = UDim.new(0,9),
            PaddingLeft = UDim.new(0,12), PaddingRight = UDim.new(0,12),
        }, st)
        local head = mk("Frame", {
            Size = UDim2.new(1,0,0,22), BackgroundTransparency = 1, LayoutOrder = 1,
        }, st)
        mk("TextLabel", {
            Size = UDim2.new(1,-70,1,0), BackgroundTransparency = 1, Text = label,
            TextColor3 = T.text, Font = F_SEMI, TextSize = 17,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, head)
        local valLbl = mk("TextLabel", {
            Size = UDim2.new(0,66,1,0), Position = UDim2.new(1,-66,0,0),
            BackgroundTransparency = 1, Text = fmt(getter()), TextColor3 = T.accent,
            Font = F_BOLD, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right,
        }, head)
        local hit = mk("TextButton", {
            Size = UDim2.new(1,0,0,24), BackgroundTransparency = 1, Text = "",
            AutoButtonColor = false, LayoutOrder = 2,
        }, st)
        local bar = mk("Frame", {
            Size = UDim2.new(1,0,0,6), Position = UDim2.new(0,0,0.5,-3),
            BackgroundColor3 = T.off, BorderSizePixel = 0,
        }, hit)
        corner(bar, 3)
        local fill = mk("Frame", {
            Size = UDim2.new(0,0,1,0), BackgroundColor3 = T.white, BorderSizePixel = 0,
        }, bar)
        corner(fill, 3)
        mk("UIGradient", {Color = ColorSequence.new(T.accent, T.accent2)}, fill)
        local knob = mk("Frame", {
            Size = UDim2.new(0,16,0,16), Position = UDim2.new(1,-8,0.5,-8),
            BackgroundColor3 = T.white, BorderSizePixel = 0, ZIndex = 2,
        }, fill)
        corner(knob, 8)
        stroke(knob, T.accent, 2, 0)
        local knobScale = mk("UIScale", {}, knob)
        if desc and desc ~= "" then
            mk("TextLabel", {
                Size = UDim2.new(1,0,0,0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, Text = desc, TextColor3 = T.sub,
                Font = F_REG, TextSize = 14, TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                LayoutOrder = 3,
            }, st)
        end
        local function setVisual(t)
            fill.Size = UDim2.new(math.clamp(t,0,1), 0, 1, 0)
        end
        setVisual((getter() - minV) / math.max(maxV - minV, 1e-6))
        local function update(pos)
            local sz = bar.AbsoluteSize
            if sz.X < 1 then return end
            local t = math.clamp((pos.X - bar.AbsolutePosition.X) / sz.X, 0, 1)
            local v = math.floor((minV + t * (maxV - minV)) * mult + 0.5) / mult
            setter(v)
            setVisual(t)
            valLbl.Text = fmt(v)
            scheduleSave()
        end
        hit.InputBegan:Connect(function(inp)
            if isPointer(inp) then
                page.ScrollingEnabled = false
                tween(knobScale, {Scale = 1.35}, 0.14, Enum.EasingStyle.Back)
                activeSlider = {
                    update = update,
                    stop = function()
                        page.ScrollingEnabled = true
                        tween(knobScale, {Scale = 1}, 0.16)
                    end,
                }
                update(inp.Position)
            end
        end)
        return row
    end

    -- Khung ghi chú / lưu ý (tự giãn chiều cao)
    local function mkNote(page, text, col, bgCol, strokeCol)
        local f = mk("Frame", {
            Size = UDim2.new(1,0,0,0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = bgCol or T.row, BorderSizePixel = 0, LayoutOrder = ord(page),
        }, page)
        corner(f, 10)
        stroke(f, strokeCol or T.stroke, 1, 0.3)
        mk("UIPadding", {
            PaddingTop = UDim.new(0,9), PaddingBottom = UDim.new(0,9),
            PaddingLeft = UDim.new(0,12), PaddingRight = UDim.new(0,12),
        }, f)
        mk("TextLabel", {
            Size = UDim2.new(1,0,0,0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1, Text = text, TextColor3 = col or T.sub,
            Font = F_REG, TextSize = 15, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        }, f)
        return f
    end

    -- Nút bấm (có hover, nhấn co, flash)
    local function mkButton(parent, text, bg, fg, props, onClick)
        props = props or {}
        local outline = props.outline
        props.outline = nil
        local b = mk("TextButton", {
            BackgroundColor3 = bg, BorderSizePixel = 0, Text = text, TextColor3 = fg,
            Font = F_BOLD, TextSize = 16, AutoButtonColor = false,
        }, parent)
        for k, v in pairs(props) do b[k] = v end
        corner(b, 9)
        if outline then stroke(b, fg, 1.5, 0.3) end
        attachPress(b, mk("UIScale", {}, b), 0.95)
        attachHover(b, bg, bg:Lerp(Color3.new(0,0,0), 0.08))
        b.Activated:Connect(function()
            flash(b, outline and T.accent or T.white, outline and 0.8 or 0.55, 9)
            if onClick then onClick() end
        end)
        return b
    end

    -- Thẻ liên kết (Discord / TikTok)
    local function mkLinkCard(page, badgeText, badgeCol, title, shown, url, what)
        local row = mkRow(page, "Frame")
        local st = mk("Frame", {
            Size = UDim2.new(1,0,0,0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, row)
        mk("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,9)}, st)
        mk("UIPadding", {
            PaddingTop = UDim.new(0,10), PaddingBottom = UDim.new(0,10),
            PaddingLeft = UDim.new(0,12), PaddingRight = UDim.new(0,12),
        }, st)
        local head = mk("Frame", {
            Size = UDim2.new(1,0,0,40), BackgroundTransparency = 1, LayoutOrder = 1,
        }, st)
        local badge = mk("TextLabel", {
            Size = UDim2.new(0,40,0,40), BackgroundColor3 = badgeCol, BorderSizePixel = 0,
            Text = badgeText, TextColor3 = T.white, Font = F_BOLD, TextSize = 17,
        }, head)
        corner(badge, 11)
        mk("TextLabel", {
            Size = UDim2.new(1,-50,0,21), Position = UDim2.new(0,50,0,0),
            BackgroundTransparency = 1, Text = title, TextColor3 = T.text,
            Font = F_BOLD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
        }, head)
        mk("TextLabel", {
            Size = UDim2.new(1,-50,0,19), Position = UDim2.new(0,50,0,21),
            BackgroundTransparency = 1, Text = shown, TextColor3 = T.accent,
            Font = F_SEMI, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
        }, head)
        local btns = mk("Frame", {
            Size = UDim2.new(1,0,0,36), BackgroundTransparency = 1, LayoutOrder = 2,
        }, st)
        mk("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,8),
        }, btns)
        mkButton(btns, "Sao chép link", T.bg, T.accent,
            {Size = UDim2.new(0.5,-4,1,0), LayoutOrder = 1, outline = true},
            function()
                if copyText(url) then toast("Đã sao chép link " .. what, "good")
                else toast("Executor không hỗ trợ sao chép — gõ tay: " .. shown, "warn") end
            end)
        mkButton(btns, "Mở link", T.accent, T.white,
            {Size = UDim2.new(0.5,-4,1,0), LayoutOrder = 2},
            function()
                local opened = openUrl(url)
                local copied = copyText(url)
                if opened then
                    toast("Đã gửi lệnh mở " .. what .. (copied and " (link đã được sao chép)" or ""), "good")
                elseif copied then
                    toast("Không mở được trình duyệt — link " .. what .. " đã được sao chép", "warn")
                else
                    toast("Không mở/sao chép được — gõ tay: " .. shown, "warn")
                end
            end)
        return row
    end

    -- ══ TAB NGẮM ═════════════════════════════════════════════════════════
    local aimPage = pages["AIM"]
    mkSection(aimPage, "AIMBOT")
    mkToggle(aimPage, "Aimbot", "Tự ngắm vào mục tiêu khi bạn giữ nút bắn. Không ngắm đồng đội (crew / clan).",
        function() return CFG.aimOn end, function(v) CFG.aimOn = v end)
    mkToggle(aimPage, "Tự tìm mục tiêu mới", "Đang giữ nút bắn mà mất mục tiêu thì tự chuyển sang người khác.",
        function() return CFG.reacquire end, function(v) CFG.reacquire = v end)
    mkToggle(aimPage, "Kiểm tra vật cản (Wall Check)", "Chỉ ngắm người không bị tường hoặc vật cản che.",
        function() return CFG.wallCheck end, function(v) CFG.wallCheck = v end)
    mkToggle(aimPage, "Xuyên bụi cây (Foliage Bypass)", "Bỏ qua bụi cây, lá khi kiểm tra vật cản.",
        function() return CFG.foliageBypass end, function(v) CFG.foliageBypass = v end)

    mkSection(aimPage, "BÁM MỤC TIÊU")
    mkToggle(aimPage, "Khóa bám (Sticky Lock)", "Bật: tâm dính cứng vào địch khi giữ nút bắn, trúng ổn định. Tắt: tâm xoay mượt theo tốc độ bên dưới (dễ trượt hơn).",
        function() return CFG.stickOn end, function(v) CFG.stickOn = v end)
    mkSlider(aimPage, "Tốc độ ngắm (x100)", "Chỉ có tác dụng khi TẮT Khóa bám. Thấp = mượt hơn, cao = nhanh hơn.", 10, 95,
        function() return math.floor(CFG.trackSpeed * 100 + 0.5) end,
        function(v) CFG.trackSpeed = v / 100 CFG.smoothSpeed = v / 100 end)

    mkSection(aimPage, "PHẠM VI NGẮM")
    mkSlider(aimPage, "Vùng ngắm - FOV (px)", "Bán kính vòng FOV tính từ giữa màn hình. Chỉ ngắm người nằm trong vòng.", 20, 350,
        function() return CFG.fov end,
        function(v)
            CFG.fov = v
            if fovCircle then fovCircle.Radius = v end
        end)
    mkSlider(aimPage, "Khoảng cách ngắm (studs)", "Người ở xa hơn mức này sẽ không bị ngắm.", 100, 800,
        function() return CFG.aimDist end, function(v) CFG.aimDist = v end)

    mkSection(aimPage, "GÓC HẸP (TỰ ĐỔI GÓC NHÌN)")
    mkToggle(aimPage, "Hỗ trợ góc hẹp", "Địch núp sát góc tường: tự giữ khóa, tự đổi điểm ngắm và đổi góc nhìn để bắn trúng. Bật lên là chơi, không cần chỉnh gì thêm.",
        function() return CFG.cornerOn end, function(v) CFG.cornerOn = v if not v then Corner.reset() end end)
    mkToggle(aimPage, "Tự đổi vai camera", "Bị tường chắn thì tự bấm nút ⇄ để camera nhìn sang vai bên kia. Tắt nếu bạn muốn tự đổi vai.",
        function() return CFG.cornerSwap end, function(v) CFG.cornerSwap = v end)
    mkToggle(aimPage, "Tự quay tới địch ở gần", "Địch đứng gần (trong khoảng 30 studs) nhưng ngoài vòng FOV hoặc sau lưng thì tự xoay tâm về phía địch.",
        function() return CFG.cornerWide end, function(v) CFG.cornerWide = v end)

    mkSection(aimPage, "SMOOTHSHOT (GIẢM GIẬT)")
    mkToggle(aimPage, "SmoothShot", "Tự vào chế độ ngắm (ADS) trước khi bắn và bù giật súng.",
        function() return CFG.smoothShot end,
        function(v)
            CFG.smoothShot = v
            if not v and _ssIsADS then simADS(false) end
        end)
    mkSlider(aimPage, "Chống giật (%)", "Mức bù giật súng. 0 = không bù, 100 = bù tối đa.", 0, 100,
        function() return math.floor(CFG.recoilCounterStr * 100 + 0.5) end,
        function(v) CFG.recoilCounterStr = v / 100 end)

    -- ══ TAB FARM ═════════════════════════════════════════════════════════
    local farmPage = pages["FARM"]
    mkSection(farmPage, "AUTO FARM")
    local _, farmToggleRefresh = mkToggle(farmPage, "Bật Auto Farm",
        "Khóa tâm và tự bắn bot trong FarmZone. Cần có súng và đứng trong vùng farm.",
        function() return Farm.active end, function(v) Farm.set(v) end)
    Farm.onToggle = function() farmToggleRefresh(true) end
    mkNote(farmPage, "Farm không tự hồi máu hoặc tự đưa nhân vật vào khu farm. Khi nhân vật hồi sinh, hãy kiểm tra lại trạng thái farm.")

    mkSection(farmPage, "FARM ESP")
    mkToggle(farmPage, "ESP Bot Farm", "Hiện viền Highlight và nhãn BOT / HP / khoảng cách trên bot HoodLocal.",
        function() return CFG.farmBotESP end, function(v) CFG.farmBotESP = v end)
    mkToggle(farmPage, "ESP FarmZone", "Hiện khung thể tích của các BasePart có attribute FarmZone trong Workspace.Zones.FarmZones.",
        function() return CFG.farmZoneESP end, function(v) CFG.farmZoneESP = v end)

    mkSection(farmPage, "MỤC TIÊU & HÀNH ĐỘNG")
    mkToggle(farmPage, "Chỉ bot trong khu farm", "Chỉ nhắm bot trong FarmZone và chỉ hoạt động khi nhân vật cũng ở trong vùng.",
        function() return CFG.farmZoneOnly end, function(v) CFG.farmZoneOnly = v end)
    mkToggle(farmPage, "Wall Check", "Không chọn bot bị che bởi vật cản theo raycast của game.",
        function() return CFG.farmWall end, function(v) CFG.farmWall = v end)
    mkToggle(farmPage, "Bỏ qua bot bị hạ", "Không nhắm bot có attribute HoodDowned.",
        function() return CFG.farmSkipDowned end, function(v) CFG.farmSkipDowned = v end)
    mkCycle(farmPage, "Vị trí ngắm", "Chọn điểm ngắm trên bot.",
        { "Head", "Torso" }, { Head = "Đầu", Torso = "Thân" },
        function() return CFG.farmPart end, function(v) CFG.farmPart = v end)
    mkSlider(farmPage, "Khoảng cách farm (studs)", "Chỉ nhận bot và xác trong FarmZone ở khoảng cách 0–50 studs.", 0, 50,
        function() return CFG.farmDist end, function(v) CFG.farmDist = v end)
    mkToggle(farmPage, "Tự khóa tâm", "Xoay camera về phía bot đã chọn.",
        function() return CFG.farmAim end, function(v) CFG.farmAim = v end)
    mkToggle(farmPage, "Tự bắn", "Giữ nút bắn khi tâm đã căn trúng bot.",
        function() return CFG.farmShoot end, function(v) CFG.farmShoot = v end)
    mkSlider(farmPage, "Tốc độ khóa (x100)", "Cao hơn thì camera bám bot nhanh hơn.", 20, 99,
        function() return math.floor(CFG.farmAimSpeed * 100 + 0.5) end,
        function(v) CFG.farmAimSpeed = v / 100 end)
    mkToggle(farmPage, "Chống AFK", "Dùng fallback input nếu executor cho phép; một số iOS executor không hỗ trợ API này.",
        function() return CFG.farmAntiAfk end,
        function(v) CFG.farmAntiAfk = v if Farm.active then Farm.setAntiAfk(v) end end)
    mkToggle(farmPage, "Tự trang bị súng", "Tự lấy súng từ Backpack khi nhân vật chưa cầm súng.",
        function() return CFG.farmAutoEquip end, function(v) CFG.farmAutoEquip = v end)

    mkSection(farmPage, "AUTO LOOT XÁC BOT")
    mkNote(farmPage, "Tự nhặt xác HoodNPC có Lootable=true khi người chơi và xác đều nằm trong FarmZone, trong khoảng cách farm 0–50 studs. Dùng ClientState.HoodLootNow() của game; không teleport, không loot Cash Bag và không vượt giới hạn nhặt gốc.")
    mkToggle(farmPage, "Auto Loot xác bot", "Chỉ nhặt xác hợp lệ trong FarmZone và trong khoảng cách farm đã đặt.",
        function() return CFG.farmAutoLoot end,
        function(v) CFG.farmAutoLoot = v end)

    mkSection(farmPage, "THỐNG KÊ")
    mkToggle(farmPage, "Hiện bảng thống kê", "Chỉ hiển thị thời gian treo, số dư hiện tại và tổng tiền kiếm được.",
        function() return CFG.farmHud end, function(v) CFG.farmHud = v end)
    do
        local fr = mk("Frame", {
            Size = UDim2.new(1,0,0,40), BackgroundTransparency = 1, LayoutOrder = ord(farmPage),
        }, farmPage)
        mkButton(fr, "ĐẶT LẠI THỐNG KÊ", Color3.fromRGB(205,66,78), T.white,
            {Size = UDim2.new(1,0,1,0)},
            function()
                Farm.resetStats()
                toast("Đã đặt lại thống kê", "good")
            end)
    end
    mkNote(farmPage, "Tiền kiếm được chỉ tăng khi số dư thực tế tăng trong lúc Auto Farm đang bật.")

    -- ── Farm HUD (bảng thống kê): nền sáng + hiệu ứng ────────────────────
    do
        local vpH = camera.ViewportSize
        local HW = math.clamp(math.floor(vpH.X * 0.62), 270, 360)
        local FULL_H, COMPACT_H = 132, 40

        local hud = mk("CanvasGroup", {
            Name = "FarmHud", AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.new(0, HW, 0, FULL_H),
            BackgroundColor3 = T.bg, BorderSizePixel = 0,
            GroupTransparency = 1, Visible = false, ZIndex = 20,
        }, SG)
        corner(hud, 16)
        local hudStroke = stroke(hud, T.accent, 1.5, 0.35)
        local hudScale = mk("UIScale", {Scale = 1}, hud)
        local basePos = hud.Position

        -- nền trắng -> xanh xám rất nhạt (frame con, để gradient không đụng tới chữ)
        local bgFill = mk("Frame", {
            Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.white,
            BorderSizePixel = 0, ZIndex = 20,
        }, hud)
        mk("UIGradient", {
            Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(241, 243, 252)),
            Rotation = 90,
        }, bgFill)

        -- thanh màu trên cùng: dải gradient chạy qua lại
        local topBar = mk("Frame", {
            Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = T.white, BorderSizePixel = 0, ZIndex = 21,
        }, hud)
        local topGrad = mk("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,   T.accent),
                ColorSequenceKeypoint.new(0.5, T.accent2),
                ColorSequenceKeypoint.new(1,   T.accent),
            }),
            Offset = Vector2.new(-0.5, 0),
        }, topBar)
        TweenService:Create(topGrad,
            TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            {Offset = Vector2.new(0.5, 0)}):Play()

        local hdr = mk("Frame", {
            Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 3),
            BackgroundTransparency = 1, ZIndex = 21,
        }, hud)
        local dot = mk("Frame", {
            Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0, 14, 0, 12),
            BackgroundColor3 = T.off, BorderSizePixel = 0, ZIndex = 22,
        }, hdr)
        corner(dot, 5)
        mk("TextLabel", {
            Size = UDim2.new(1, -140, 0, 22), Position = UDim2.new(0, 32, 0, 6),
            BackgroundTransparency = 1, Text = "KXY • AUTO FARM", TextColor3 = T.text,
            Font = F_BOLD, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22,
        }, hdr)
        local collapseBtn = mk("TextButton", {
            Size = UDim2.new(0, 24, 0, 22), Position = UDim2.new(1, -86, 0, 6),
            BackgroundColor3 = T.panel, BorderSizePixel = 0, Text = "–",
            TextColor3 = T.text, Font = F_BOLD, TextSize = 16, AutoButtonColor = false, ZIndex = 23,
        }, hdr)
        corner(collapseBtn, 7)
        stroke(collapseBtn, T.stroke, 1, 0.2)
        attachHover(collapseBtn, T.panel, T.rowHi)
        attachPress(collapseBtn, mk("UIScale", {}, collapseBtn), 0.88)
        local STOP_COL, STOP_HI = Color3.fromRGB(214, 66, 82), Color3.fromRGB(232, 88, 102)
        local stopBtn = mk("TextButton", {
            Size = UDim2.new(0, 50, 0, 22), Position = UDim2.new(1, -58, 0, 6),
            BackgroundColor3 = STOP_COL, BorderSizePixel = 0, Text = "DỪNG",
            TextColor3 = T.white, Font = F_BOLD, TextSize = 13, AutoButtonColor = false, ZIndex = 23,
        }, hdr)
        corner(stopBtn, 7)
        attachHover(stopBtn, STOP_COL, STOP_HI)
        attachPress(stopBtn, mk("UIScale", {}, stopBtn), 0.9)

        -- Three compact live values only: earned, current balance, and uptime.
        local statsRow = mk("Frame", {
            Size = UDim2.new(1, 0, 0, 76), Position = UDim2.new(0, 0, 0, 42),
            BackgroundTransparency = 1, ZIndex = 21,
        }, hud)
        local tileW = math.floor((HW - 28 - 16) / 3)
        local function mkStatTile(idx, caption)
            local tile = mk("Frame", {
                Size = UDim2.new(0, tileW, 0, 66),
                Position = UDim2.new(0, 14 + (idx - 1) * (tileW + 8), 0, 4),
                BackgroundColor3 = T.panel, BorderSizePixel = 0, ZIndex = 22,
            }, statsRow)
            corner(tile, 11)
            stroke(tile, T.stroke, 1, 0.18)
            mk("TextLabel", {
                Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 0, 7),
                BackgroundTransparency = 1, Text = caption, TextColor3 = T.sub,
                Font = F_SEMI, TextSize = 10, ZIndex = 23,
            }, tile)
            local value = mk("TextLabel", {
                Size = UDim2.new(1, -8, 0, 27), Position = UDim2.new(0, 4, 0, 29),
                BackgroundTransparency = 1, Text = "-", TextColor3 = T.text,
                Font = Enum.Font.GothamBold, TextSize = 15, TextScaled = true, ZIndex = 23,
            }, tile)
            mk("UITextSizeConstraint", {MaxTextSize = 16, MinTextSize = 9}, value)
            local scale = mk("UIScale", {Scale = 1}, value)
            return value, tile, scale
        end
        local earnedLbl, earnedTile, earnedScale = mkStatTile(1, "ĐÃ KIẾM")
        local balLbl, balTile, balScale = mkStatTile(2, "SỐ DƯ HIỆN TẠI")
        local timeLbl, timeTile, timeScale = mkStatTile(3, "THỜI GIAN TREO")

        -- kéo bảng bằng thanh tiêu đề; nhớ vị trí để hiệu ứng hiện/ẩn bám theo
        local dragging, dStart, dPos = false, nil, nil
        hdr.InputBegan:Connect(function(inp)
            if isPointer(inp) then dragging = true dStart = inp.Position dPos = hud.Position end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if dragging and dStart and dPos
            and (inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch) then
                local d = inp.Position - dStart
                hud.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset + d.X, dPos.Y.Scale, dPos.Y.Offset + d.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if isPointer(inp) then
                if dragging then basePos = hud.Position end
                dragging = false
            end
        end)

        local compact = false
        collapseBtn.Activated:Connect(function()
            compact = not compact
            collapseBtn.Text = compact and "+" or "–"
            statsRow.Visible = not compact
            tween(hud, {Size = UDim2.new(0, HW, 0, compact and COMPACT_H or FULL_H)}, 0.28, Enum.EasingStyle.Quint)
        end)
        stopBtn.Activated:Connect(function()
            Farm.set(false)
            if Farm.onToggle then Farm.onToggle() end
        end)

        local shown, hudOn = 0, false
        local last = {}
        local prevEarned, prevMoney = 0, nil
        local function setTxt(key, lbl, value)
            if last[key] ~= value then last[key] = value lbl.Text = value end
        end

        local function showHud()
            hud.Visible = true
            hudScale.Scale = 0.84
            hud.GroupTransparency = 1
            hud.Position = UDim2.new(basePos.X.Scale, basePos.X.Offset, basePos.Y.Scale, basePos.Y.Offset - 24)
            tween(hud, {Position = basePos}, 0.42, Enum.EasingStyle.Back)
            tween(hud, {GroupTransparency = 0}, 0.24)
            tween(hudScale, {Scale = 1}, 0.42, Enum.EasingStyle.Elastic)
            for _, scale in ipairs({ earnedScale, balScale, timeScale }) do
                scale.Scale = 0.82
                tween(scale, {Scale = 1}, 0.42, Enum.EasingStyle.Back)
            end
        end
        local function hideHud()
            tween(hud, {
                GroupTransparency = 1,
                Position = UDim2.new(basePos.X.Scale, basePos.X.Offset, basePos.Y.Scale, basePos.Y.Offset - 16),
            }, 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            tween(hudScale, {Scale = 0.9}, 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            task.delay(0.24, function()
                if not hudOn then
                    hud.Visible = false
                    hud.Position = basePos
                end
            end)
        end

        Farm.ui = {
            update = function(dt, now)
                local want = CFG.farmHud and (Farm.active or Farm.earned > 0 or Farm.accTime > 0)
                if want ~= hudOn then
                    hudOn = want
                    if want then showHud() else hideHud() end
                end
                if not hudOn then return end

                shown = shown + (Farm.earned - shown) * math.min(1, dt * 8)
                if math.abs(Farm.earned - shown) < 1 then shown = Farm.earned end
                setTxt("earned", earnedLbl, "+$" .. Farm.fmtInt(shown))
                setTxt("balance", balLbl, Farm.money and ("$" .. Farm.fmtInt(Farm.money)) or "-")
                setTxt("uptime", timeLbl, Farm.fmtTime(Farm.elapsed(now)))

                if Farm.earned > prevEarned then
                    earnedScale.Scale = 1.16
                    tween(earnedScale, {Scale = 1}, 0.38, Enum.EasingStyle.Elastic)
                    flash(earnedTile, T.good, 0.68, 12)
                end
                if Farm.money and prevMoney and Farm.money > prevMoney then
                    balScale.Scale = 1.12
                    tween(balScale, {Scale = 1}, 0.34, Enum.EasingStyle.Back)
                    flash(balTile, T.good, 0.7, 10)
                end
                prevEarned = Farm.earned
                prevMoney = Farm.money

                -- Quiet breathing accents; no extra status, kill, loot, or rate fields.
                if Farm.active then
                    dot.BackgroundTransparency = 0.08 + 0.42 * (0.5 + 0.5 * math.sin(now * 4.5))
                    hudStroke.Transparency = 0.34 + 0.18 * math.sin(now * 2.4)
                    topGrad.Offset = Vector2.new(math.sin(now * 1.5) * 0.5, 0)
                else
                    dot.BackgroundTransparency = 0.25
                    hudStroke.Transparency = 0.35
                end
            end,
        }
    end

    -- ══ TAB ESP ══════════════════════════════════════════════════════════
    local espPage = pages["ESP"]
    mkSection(espPage, "HIỂN THỊ NGƯỜI CHƠI")
    mkToggle(espPage, "ESP", "Công tắc tổng: bật để thấy người chơi xuyên tường.",
        function() return CFG.espOn end, function(v) CFG.espOn = v end)
    mkCycle(espPage, "Kiểu hộp", "Hộp góc nhìn gọn, hộp đầy dễ thấy hơn.",
        { "Corner", "Full" }, { Corner = "Hộp góc", Full = "Hộp đầy" },
        function() return CFG.espBoxStyle end, function(v) CFG.espBoxStyle = v end)
    mkToggle(espPage, "Đường kẻ (Line)", "Kẻ một đường từ màn hình tới từng người.",
        function() return CFG.espLine end, function(v) CFG.espLine = v end)
    mkCycle(espPage, "Đường kẻ xuất phát từ", "Vị trí đầu đường kẻ trên màn hình.",
        { "Bottom", "Center", "Top" }, { Bottom = "Dưới", Center = "Giữa", Top = "Trên" },
        function() return CFG.espLineFrom end, function(v) CFG.espLineFrom = v end)
    mkToggle(espPage, "Khung xương (Skeleton)", "Vẽ bộ xương của người chơi.",
        function() return CFG.espSkeleton end, function(v) CFG.espSkeleton = v end)
    mkToggle(espPage, "Tên người chơi", "Hiện tên phía trên mỗi người.",
        function() return CFG.espName end, function(v) CFG.espName = v end)
    mkToggle(espPage, "Chấm đầu (Head Dot)", "Chấm một điểm tại đầu để dễ canh.",
        function() return CFG.espHeadDot end, function(v) CFG.espHeadDot = v end)
    mkToggle(espPage, "Tên súng (Weapon)", "Hiện vũ khí mà người đó đang cầm.",
        function() return CFG.espWeapon end, function(v) CFG.espWeapon = v end)

    mkSection(espPage, "TÙY CHỈNH HIỂN THỊ")
    mkToggle(espPage, "Vòng FOV", "Hiện vòng tròn vùng ngắm trên màn hình.",
        function() return fovCircle ~= nil and fovCircle.Visible end,
        function(v) if fovCircle then fovCircle.Visible = v end end)
    mkSlider(espPage, "Khoảng cách ESP (studs)", "Người ở xa hơn mức này sẽ không được hiển thị.", 100, 900,
        function() return CFG.espDist end, function(v) CFG.espDist = v end)
    mkSlider(espPage, "StretchX (75-100)", nil, 75, 100,
        function() return math.floor(CFG.stretchX * 100 + 0.5) end,
        function(v) CFG.stretchX = math.clamp(v / 100, 0.75, 1.00) end)
    mkNote(espPage,
        "Lưu ý: Phần Stretch để trong game là bao nhiêu thì ở đây chỉnh như vậy để không bị lỗi ESP.\n(Thanh kéo 75-100 tương ứng 0.75-1.00)",
        T.warn, T.warnBg, Color3.fromRGB(230,170,90))

    -- ══ TAB DI CHUYỂN ════════════════════════════════════════════════════
    local movePage = pages["MOVE"]
    mkSection(movePage, "CHỐNG NGẮM (ANTI-AIM)")
    mkToggle(movePage, "Anti-Aim (công tắc tổng)", "Bật thì các tùy chọn bên dưới mới hoạt động.",
        function() return AntiAim.enabled end, function(v) AntiAim.enabled = v end)
    mkToggle(movePage, "Lách trái/phải ngẫu nhiên (AD Strafe)",
        "Chỉ hoạt động khi đang bắn, Aimbot bật và đã khóa mục tiêu. Nhân vật tự lách trái/phải để khó bị bắn trúng.",
        function() return AntiAim.adStrafeEnabled end,
        function(v) AntiAim.adStrafeEnabled = v end)
    mkSlider(movePage, "Lách ngắn nhất (x0.01 giây)", "Mỗi lần đổi hướng kéo dài ít nhất khoảng này. Ví dụ 12 = 0.12 giây.", 5, 80,
        function() return math.floor(AntiAim.adStrafeMinTime * 100 + 0.5) end,
        function(v) AntiAim.adStrafeMinTime = math.min(v / 100, AntiAim.adStrafeMaxTime) end)
    mkSlider(movePage, "Lách dài nhất (x0.01 giây)", "Mỗi lần đổi hướng kéo dài nhiều nhất khoảng này.", 10, 120,
        function() return math.floor(AntiAim.adStrafeMaxTime * 100 + 0.5) end,
        function(v) AntiAim.adStrafeMaxTime = math.max(v / 100, AntiAim.adStrafeMinTime) end)
    mkSlider(movePage, "Xác suất đứng yên (%)", "Khả năng dừng lại một chút giữa các lần lách để khó đoán hơn.", 0, 50,
        function() return math.floor(AntiAim.adPauseChance * 100 + 0.5) end,
        function(v) AntiAim.adPauseChance = v / 100 end)

    -- ══ TAB FPS ══════════════════════════════════════════════════════════
    local fpsPage = pages["FPS"]
    local fb = CFG.fpsBoost
    mkNote(fpsPage, "FPS Boost giảm đồ họa để game mượt hơn: tắt bóng, giảm chất lượng texture, đơn giản hóa ánh sáng và tắt hiệu ứng hạt. Hãy bật công tắc tổng trước.")
    mkSection(fpsPage, "CÔNG TẮC TỔNG")
    mkToggle(fpsPage, "FPS Boost", "Bật mới áp dụng các tùy chọn bên dưới. Tắt sẽ trả lại đồ họa cũ.",
        function() return fb.on end,
        function(v) fb.on = v if v then applyFPSBoost() else restoreFPSBoost() end end)
    mkSection(fpsPage, "TÙY CHỌN GIẢM ĐỒ HỌA")
    mkToggle(fpsPage, "Tắt bóng đổ", "Giảm tải GPU đáng kể.",
        function() return fb.shadowDisable end,
        function(v) fb.shadowDisable = v if fb.on then applyFPSBoost() end end)
    mkToggle(fpsPage, "Ánh sáng đơn giản", "Dùng ánh sáng nhẹ hơn, hình ảnh bớt đẹp nhưng mượt hơn.",
        function() return fb.lightingSimple end,
        function(v) fb.lightingSimple = v if fb.on then applyFPSBoost() end end)
    mkToggle(fpsPage, "Giảm chất lượng texture", "Hạ chất lượng hình ảnh để tiết kiệm bộ nhớ.",
        function() return fb.textureQuality end,
        function(v) fb.textureQuality = v if fb.on then applyFPSBoost() end end)
    mkToggle(fpsPage, "Tắt hạt, lửa, khói", "Tắt particle, fire, smoke và các hiệu ứng tương tự.",
        function() return fb.particleOff end,
        function(v) fb.particleOff = v if fb.on then applyFPSBoost() end end)
    mkToggle(fpsPage, "Tắt decal / texture dán", "Ẩn các hình dán trên bề mặt. Có thể làm map trông trống hơn.",
        function() return fb.decalOff end,
        function(v) fb.decalOff = v if fb.on then applyFPSBoost() end end)
    -- ══ TAB CÀI ĐẶT ══════════════════════════════════════════════════════
    local setPage = pages["SET"]
    mkSection(setPage, "LƯU CẤU HÌNH")
    if canSave then
        mkNote(setPage, "Tự động lưu: BẬT  •  file kxy_config.json", T.good, Color3.fromRGB(231,247,239), Color3.fromRGB(120,200,160))
    else
        mkNote(setPage, "Executor không có writefile — cấu hình sẽ không được lưu.", T.warn, T.warnBg, Color3.fromRGB(230,170,90))
    end
    local btnRow = mk("Frame", {
        Size = UDim2.new(1,0,0,40), BackgroundTransparency = 1, LayoutOrder = ord(setPage),
    }, setPage)
    mk("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0,8),
    }, btnRow)
    mkButton(btnRow, "LƯU NGAY", Color3.fromRGB(34,160,98), T.white,
        {Size = UDim2.new(0.5,-4,1,0), LayoutOrder = 1},
        function()
            if not canSave then
                toast("Executor không hỗ trợ writefile", "warn")
                return
            end
            local ok, err = pcall(function()
                writefile(CONFIG_FILE, HttpService:JSONEncode(serializeCFG()))
            end)
            if ok then toast("Đã lưu vào kxy_config.json", "good")
            else toast("Lưu lỗi: " .. tostring(err):sub(1,40), "bad") end
        end)
    mkButton(btnRow, "ĐẶT LẠI", Color3.fromRGB(205,66,78), T.white,
        {Size = UDim2.new(0.5,-4,1,0), LayoutOrder = 2},
        function()
            resetConfig()
            toast("Đã đặt lại — chạy lại script để menu cập nhật", "warn")
        end)
    mkNote(setPage, "LƯU NGAY: ghi cấu hình hiện tại ra file.\nĐẶT LẠI: xóa file cấu hình và trả mọi thiết lập về mặc định.")
    mkSection(setPage, "THIẾT BỊ")
    local platStr = "Nền tảng: " .. PLATFORM.name .. "\nNhận diện: " .. PLATFORM.source
    mkNote(setPage, platStr)
    local diagNote = mkNote(setPage, "Chẩn đoán v26.0: đang kiểm tra...")
    task.delay(5, function()
        local lbl = diagNote:FindFirstChildOfClass("TextLabel")
        if not lbl then return end
        local zm, wd = Farm.diag()
        local function yn(b) return b and "CÓ" or "KHÔNG" end
        local clientStateReady, nearReady, nowReady = Farm.diagLoot()
        lbl.Text = "Chẩn đoán v26.0\n" ..
            "Drawing (ESP / vòng FOV): " .. yn(HAS_DRAWING) .. " [" .. DRAW_MODE .. "]\n" ..
            "Controls của game (bắn / ADS): " .. yn(Ctl ~= nil) .. "\n" ..
            "Module FarmZone: " .. yn(zm) .. "  •  WeaponData: " .. yn(wd) .. "\n" ..
            "Hood ClientState: " .. yn(clientStateReady) .. "  •  HoodLootNear: " .. yn(nearReady) .. "  •  HoodLootNow: " .. yn(nowReady)
        local baseTxt = lbl.Text
        while lbl.Parent do
            local D = DRAW_INFO
            lbl.Text = baseTxt .. "\nESP: " .. DRAW_MODE .. "/" .. tostring(D.parent) .. " canvas " .. tostring(D.abs)
                .. " / viewport " .. tostring(D.vp)
                .. " • người " .. D.players .. " • vẽ " .. D.drawn .. " • noBox " .. D.noBox
                .. (D.err and (" • lỗi: " .. D.err:sub(1, 60)) or "")
            task.wait(1)
        end
    end)

    -- ══ TAB INFO ═════════════════════════════════════════════════════════
    local infoPage = pages["INFO"]
    do
        local row = mkRow(infoPage, "Frame")
        local st = mk("Frame", {
            Size = UDim2.new(1,0,0,0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, row)
        mk("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,1)}, st)
        mk("UIPadding", {
            PaddingTop = UDim.new(0,10), PaddingBottom = UDim.new(0,10),
            PaddingLeft = UDim.new(0,12), PaddingRight = UDim.new(0,12),
        }, st)
        local t1 = mk("TextLabel", {
            Size = UDim2.new(1,0,0,28), BackgroundTransparency = 1, Text = "KXY HUB",
            TextColor3 = T.white, Font = F_BOLD, TextSize = 26,
            TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1,
        }, st)
        mk("UIGradient", {Color = ColorSequence.new(T.accent, T.accent2)}, t1)
        mk("TextLabel", {
            Size = UDim2.new(1,0,0,18), BackgroundTransparency = 1,
            Text = "Urban Reload  •  " .. VERSION_TAG .. "  •  " .. platformTag,
            TextColor3 = T.sub, Font = F_REG, TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2,
        }, st)
    end
    mkSection(infoPage, "CẬP NHẬT " .. VERSION_TAG)
    mkNote(infoPage,
        "•  v25.7: Farm HUD hiệu ứng mới, chỉ có thời gian treo / số dư / tiền kiếm được\n" ..
        "•  Auto Loot xác HoodNPC qua ClientState gốc, chỉ trong FarmZone và khoảng cách farm 0–50 studs\n" ..
        "•  Farm ESP: Highlight + nhãn bot và khung thể tích FarmZone, không phụ thuộc Drawing\n" ..
        "•  Auto Farm bot: khóa tâm + tự bắn trong khu farm, có wall check, bỏ qua bot đã chết\n" ..
        "•  iOS: đọc nút bắn và ADS qua Controls của game, không còn đoán vùng chạm\n" ..
        "•  Sticky Lock: tâm bám chặt mục tiêu, không bị trễ\n" ..
        "•  Tự tìm mục tiêu mới khi mất khóa lúc đang giữ nút bắn\n" ..
        "•  AD Strafe ngẫu nhiên khi bắn\n" ..
        "•  ESP: line, hộp góc / hộp đầy, tên, chấm đầu\n" ..
        "•  Menu mới: nền trắng, hiệu ứng đóng/mở, mô tả từng chức năng, tab Info",
        T.text)
    mkSection(infoPage, "KÊNH & SERVER")
    mkLinkCard(infoPage, "DC", Color3.fromRGB(88,101,242), "Server Discord", DISCORD_SHOW, DISCORD_URL, "Discord")
    mkLinkCard(infoPage, "TT", Color3.fromRGB(20,20,28), "Kênh TikTok", TIKTOK_SHOW, TIKTOK_URL, "TikTok")
    mkNote(infoPage, "Vào Discord để nhận bản cập nhật mới và báo lỗi. Theo dõi TikTok để xem video hướng dẫn.")

    -- ── Kéo cửa sổ bằng header ───────────────────────────────────────────
    local dragging, dragStart, dragStartPos = false, nil, nil
    hdr.InputBegan:Connect(function(inp)
        if isPointer(inp) then
            dragging = true dragStart = inp.Position dragStartPos = holder.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and dragStart and dragStartPos
        and (inp.UserInputType == Enum.UserInputType.MouseMovement
        or inp.UserInputType == Enum.UserInputType.Touch) then
            local d = inp.Position - dragStart
            holder.Position = UDim2.new(dragStartPos.X.Scale, dragStartPos.X.Offset + d.X,
                                        dragStartPos.Y.Scale, dragStartPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if isPointer(inp) then dragging = false end
    end)

    -- ── Đóng / mở (có hiệu ứng) ──────────────────────────────────────────
    local isOpen = false
    local openTok = 0
    local function setOpen(v)
        isOpen = v
        openTok = openTok + 1
        local my = openTok
        if v then
            task.defer(reapplyFPSBoost)   -- v24.1: re-apply FPS Boost whenever the menu opens
            holder.Visible = true
            winScale.Scale = 0.88
            mf.GroupTransparency = 1
            ringStroke.Transparency = 1
            shadow.BackgroundTransparency = 1
            tween(winScale, {Scale = 1}, 0.3, Enum.EasingStyle.Back)
            tween(mf, {GroupTransparency = 0}, 0.2)
            tween(ringStroke, {Transparency = 0.35}, 0.2)
            tween(shadow, {BackgroundTransparency = 0.86}, 0.25)
            pulse:Cancel()
            tween(miniStroke, {Transparency = 0.1, Thickness = 2}, 0.2)
        else
            tween(winScale, {Scale = 0.9}, 0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            tween(mf, {GroupTransparency = 1}, 0.17)
            tween(ringStroke, {Transparency = 1}, 0.17)
            tween(shadow, {BackgroundTransparency = 1}, 0.17)
            task.delay(0.19, function()
                if openTok == my then holder.Visible = false end
            end)
            task.delay(0.2, function()
                if openTok == my then pulse:Play() end
            end)
        end
        -- hiệu ứng nút minisize: nghiêng nhẹ rồi nảy về
        mini.Rotation = v and -6 or 6
        tween(mini, {Rotation = 0}, 0.4, Enum.EasingStyle.Back)
        miniScale.Scale = 1.15
        tween(miniScale, {Scale = 1}, 0.3, Enum.EasingStyle.Back)
    end
    minBtn.Activated:Connect(function() setOpen(false) end)
    mini.Activated:Connect(function() setOpen(not isOpen) end)

    switchTab("AIM", true)
    setOpen(true)
end

-- ═══════════════════════════════════════════════════════════
--  MAIN RENDER LOOP
--  Guard: wait until camera ViewportSize is non-zero.
--  This prevents Drawing objects being hidden due to bad w2s
--  on the first frames of Delta / Fluxus injection.
-- ═══════════════════════════════════════════════════════════
local _renderReady = false
task.spawn(function()
    local waited = 0
    while waited < 10 do
        local vp = camera.ViewportSize
        if vp.X > 10 and vp.Y > 10 then break end
        task.wait(0.1)
        waited = waited + 0.1
    end
    _renderReady = true
end)

local _lastAcquireAt = 0
local function acquireTarget(now)
    _lastAcquireAt = now
    smoothedVel = Vector3.zero
    Corner.reset()
    local t, sdist = pickTarget()
    if not t and CFG.cornerOn and CFG.cornerWide then
        t = Corner.pickWide()
        if t then sdist = math.huge end   -- far from the crosshair: start with the flick turn
    end
    lockedTarget = t
    if t and sdist and sdist > CFG.flickThreshold then
        flickState.active = true flickState.startAt = os.clock()
    else
        flickState.active = false
    end
    return t
end

local function espOne(player, myPos, camPos)
                        local char = player.Character
            if not char then
                if espPool[player] then removeBundle(player) end
                if not HAS_DRAWING then FB.hide(player) end
                return
            end
            local hrp, head, hum = getCharParts(char)
            local alive = hrp and head and hum and isAlive(hum)
            if not HAS_DRAWING then
                -- v24.6: Instance-based ESP for executors without Drawing (iOS)
                local fdist = hrp and math.floor((camPos - hrp.Position).Magnitude) or math.huge
                if alive and CFG.espOn and fdist <= (CFG.espDist + 15) then
                    local okE, errE = pcall(FB.update, player, char, hrp, head, hum, fdist)
                    if not okE then
                        if not FB.errShown then FB.errShown = true warn("[KXY] FB.update: " .. tostring(errE)) end
                        FB.hide(player)
                    end
                else
                    FB.hide(player)
                end
                return
            end
            if not alive or not CFG.espOn then
                if espPool[player] then hideBundle(espPool[player], player) end
                return
            end
            local dist = math.floor((camPos - hrp.Position).Magnitude)
            if dist > (CFG.espDist + 15) then
                if espPool[player] then hideBundle(espPool[player], player) end
                return
            end
            local box = getBoxPoints(char, hrp, head, hum)
            if not box then
                DRAW_INFO.noBox = DRAW_INFO.noBox + 1
                if espPool[player] then hideBundle(espPool[player], player) end
                return
            end

            DRAW_INFO.drawn = DRAW_INFO.drawn + 1
            local b = getBundle(player)
            local E = CFG.esp

            if CFG.espBoxStyle == "Corner" then
                for _,l in ipairs(b.box) do l.Visible = false end
                local cw = math.max(4, (box.tr.X - box.tl.X) * 0.28)
                local ch = math.max(4, box.boxH * 0.20)
                local c  = b.corners
                c[1].From=box.tl c[1].To=box.tl + Vector2.new(cw,0)
                c[2].From=box.tl c[2].To=box.tl + Vector2.new(0,ch)
                c[3].From=box.tr c[3].To=box.tr - Vector2.new(cw,0)
                c[4].From=box.tr c[4].To=box.tr + Vector2.new(0,ch)
                c[5].From=box.bl c[5].To=box.bl + Vector2.new(cw,0)
                c[6].From=box.bl c[6].To=box.bl - Vector2.new(0,ch)
                c[7].From=box.br c[7].To=box.br - Vector2.new(cw,0)
                c[8].From=box.br c[8].To=box.br - Vector2.new(0,ch)
                for _,l in ipairs(c) do l.Color=E.box l.Visible=true end
            else
                for _,l in ipairs(b.corners) do l.Visible = false end
                b.box[1].From=box.tl ; b.box[1].To=box.tr
                b.box[2].From=box.bl ; b.box[2].To=box.br
                b.box[3].From=box.tl ; b.box[3].To=box.bl
                b.box[4].From=box.tr ; b.box[4].To=box.br
                for _,l in ipairs(b.box) do l.Color=E.box l.Visible=true end
            end

            if CFG.espLine then
                local vpSize = camera.ViewportSize
                local from, to
                if CFG.espLineFrom == "Top" then
                    from = Vector2.new(vpSize.X/2, 0)
                    to   = Vector2.new(box.cx, box.tl.Y)
                elseif CFG.espLineFrom == "Center" then
                    from = Vector2.new(vpSize.X/2, vpSize.Y/2)
                    to   = Vector2.new(box.cx, box.br.Y)
                else
                    from = Vector2.new(vpSize.X/2, vpSize.Y)
                    to   = Vector2.new(box.cx, box.br.Y)
                end
                b.line.From = from b.line.To = to
                b.line.Color = E.line b.line.Visible = true
            else
                b.line.Visible = false
            end

            if CFG.espName then
                b.name.Text = player.DisplayName ~= "" and player.DisplayName or player.Name
                b.name.Position = Vector2.new(box.cx, box.tl.Y - 15)
                b.name.Color = E.name b.name.Visible = true
            else
                b.name.Visible = false
            end

            if b.dot then
                if CFG.espHeadDot then
                    local hsp, _, hdep = w2s(head.Position)
                    if hsp and hdep > 0 then
                        b.dot.Position = hsp
                        b.dot.Radius   = math.max(2, box.boxH * 0.03)
                        b.dot.Color    = E.line
                        b.dot.Visible  = true
                    else
                        b.dot.Visible = false
                    end
                else
                    b.dot.Visible = false
                end
            end

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

            b.weapon.Visible = false
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

            if CFG.espSkeleton then
                for i, pair in ipairs(BONE_PAIRS) do
                    local boneA = char:FindFirstChild(pair[1])
                    local boneB = char:FindFirstChild(pair[2])
                    local line  = b.bones[i]
                    if boneA and boneB then
                        local spA, visA, dA = w2s(boneA.Position)
                        local spB, visB, dB = w2s(boneB.Position)
                        if spA and spB and dA > 0 and dB > 0 then
                            line.From=spA line.To=spB line.Color=E.skeleton line.Visible=true
                        else line.Visible=false end
                    else line.Visible=false end
                end
            else
                for _, l in ipairs(b.bones) do l.Visible = false end
            end
        
end

local function espTick()
    local c = workspace.CurrentCamera
    if c and c ~= camera then camera = c end
    local myChar = lp.Character
    local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myPos  = myHRP and myHRP.Position
    local camPos = camera.CFrame.Position
    DRAW_INFO.players, DRAW_INFO.drawn = 0, 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= lp then
            DRAW_INFO.players = DRAW_INFO.players + 1
            local ok, err = pcall(espOne, player, myPos, camPos)
            if not ok then
                DRAW_INFO.err = tostring(err)
                if not DRAW_INFO.errWarned then
                    DRAW_INFO.errWarned = true
                    warn("[KXY] ESP error: " .. DRAW_INFO.err)
                end
            end
        end
    end
end

-- ESP runs in its own render step: an error in aim / farm code can no longer kill it
RunService:BindToRenderStep("KXYESP", Enum.RenderPriority.Camera.Value + 2, function()
    if not _renderReady then return end
    DRAW_INFO.frames = DRAW_INFO.frames + 1
    local ok, err = pcall(espTick)
    if not ok then
        DRAW_INFO.err = tostring(err)
        if not DRAW_INFO.loopWarned then
            DRAW_INFO.loopWarned = true
            warn("[KXY] ESP loop error: " .. DRAW_INFO.err)
        end
    end
end)

RunService:BindToRenderStep("KXYMain", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not _renderReady then return end
    do local c = workspace.CurrentCamera if c and c ~= camera then camera = c end end
    pcall(function()
        local now = os.clock()
        -- v24: on mobile the game's own Controls state is the source of truth for "fire held"
        if Ctl and Ctl.IsVirtualDown and PLATFORM.isMobile and not Farm.holdFire then
            local okC, down = pcall(Ctl.IsVirtualDown, "Fire")
            if okC then isFiring = (down == true) end
        end
        tickAntiAim(dt)
        if fovCircle then
            fovCircle.Radius   = CFG.fov
            fovCircle.Position = screenCenter()
        end

        -- SmoothShot: Pre-ADS sync
        if CFG.smoothShot and CFG.aimOn then
            if isFiring and not _ssIsADS then
                simADS(true)
            elseif not isFiring and _ssIsADS then
                simADS(false)
            end
        end

        -- Aim logic (v23: auto-acquire on fire, re-acquire when the lock is lost)
        local fireStarted = isFiring and not wasFireing
        local fireEnded   = not isFiring and wasFireing
        if fireEnded then
            if lockedTarget then lockExpireAt = now + CFG.tapGapWindow end
            flickState.active = false
            Corner.reset()
        end
        if isFiring then
            if fireStarted then
                onShotFired()
                if lockedTarget and now < lockExpireAt and lockStillOk(lockedTarget, now) then
                    lockExpireAt = 0 flickState.active = false
                else
                    lockExpireAt = 0
                    acquireTarget(now)
                end
            else
                if lockedTarget and not lockStillOk(lockedTarget, now) then
                    lockedTarget = nil flickState.active = false lockExpireAt = 0
                end
                if not lockedTarget and CFG.reacquire and (now - _lastAcquireAt) >= CFG.reacquireGap then
                    acquireTarget(now)
                end
                if lockedTarget and CFG.smoothShot and (now - _ssLastShotAt) > 0.08 then
                    onShotFired()
                end
            end
        else
            if lockExpireAt > 0 and now >= lockExpireAt then lockedTarget = nil lockExpireAt = 0 end
            flickState.active = false
        end
        wasFireing = isFiring

        tickRecoilCounter(dt)

        if CFG.aimOn and isFiring and lockedTarget then
            local selfChar = lp.Character
            if selfChar then
                local _,_,selfHum = getCharParts(selfChar)
                if isAlive(selfHum) then
                    local aimPos, inVehicle, velForPred = getAimPos(lockedTarget)
                    if aimPos and CFG.cornerOn and Corner.target == lockedTarget and Corner.aimPos
                        and (Corner.state == "clear" or Corner.state == "grace") then
                        aimPos = Corner.aimPos   -- reachable point chosen by Corner Assist (held while hidden)
                    end
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
                            -- v25: hits are decided on the client against hitboxes that follow the visible parts at the
                            -- moment WeaponClient fires, one frame after this aim. So the right lead is ONE frame of
                            -- target movement. The old 65-90 ms lead (1.0-1.5 studs at run speed) was wider than the
                            -- head box half-width (~0.86), so it hit standing targets and missed running ones.
                            local lead = smoothedVel * math.clamp(dt, 0.008, 0.04)
                            if lead.Magnitude > 0.5 then lead = lead.Unit * 0.5 end
                            predPos = aimPos + lead
                        end
                        local horizMag = velForPred and Vector3.new(velForPred.X,0,velForPred.Z).Magnitude or 0
                        local tDist = (camera.CFrame.Position - aimPos).Magnitude
                        smoothLookAt(predPos, dt, computeAimSpeed(inVehicle, horizMag, tDist))
                    end
                end
            end
        end

        local okF, errF = pcall(Farm.tick, dt, now)
        if not okF then Farm.fail(errF) end

    end)
end)

-- ═══════════════════════════════════════════════════════════
--  BOOT
-- ═══════════════════════════════════════════════════════════
task.spawn(function()
    repeat task.wait() until lp:FindFirstChild("PlayerGui")
    buildMenu()
    task.delay(4, reapplyFPSBoost)   -- v24.1: the game may reset Lighting / quality while it loads
    local platStr = PLATFORM.name
    print("[KXY v26.0] loaded on " .. platStr .. " (" .. PLATFORM.source .. ")")
    print("  drawing  = " .. tostring(HAS_DRAWING) .. "  mode = " .. DRAW_MODE .. (HAS_DRAWING and "" or "  (Highlight ESP fallback)"))
    task.delay(5, function()
        local zm, wd = Farm.diag()
        print("  controls = " .. tostring(Ctl ~= nil) .. "  farmzone = " .. tostring(zm) .. "  weapondata = " .. tostring(wd))
        local clientState, nearFn, nowFn = Farm.diagLoot()
        print("  corpseLoot ClientState=" .. tostring(clientState) .. " HoodLootNear=" .. tostring(nearFn) .. " HoodLootNow=" .. tostring(nowFn))
    end)
    print("  stretchX = " .. CFG.stretchX)
    print("  canSave  = " .. tostring(canSave))
    print("  mobileTouch = " .. tostring(PLATFORM.hasTouch) .. " | Controls = " .. tostring(Ctl ~= nil))
    print(string.format("  executor = %s | files=%s http=%s upvalues=%s gethui=%s clipboard=%s hooks=%s vim=%s",
        tostring(CAPS.name), tostring(CAPS.files), tostring(CAPS.http), tostring(CAPS.upvalues),
        tostring(CAPS.hui), tostring(CAPS.clip), tostring(CAPS.hook), tostring(CAPS.vim)))
    print("  discord.gg/YxpZy2Nrj8")
end)
