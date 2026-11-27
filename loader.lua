local URL = "https://raw.githubusercontent.com/contactforworkngocthuan-ai/urbanreload/refs/heads/main/Kxy"

local success, err = pcall(function()
    local source = game:HttpGet(URL)

    assert(source and #source > 0, "Empty source")

    local fn, compileError = loadstring(source)

    assert(fn, compileError)

    fn()
end)

if not success then
    warn("[UrbanReload] " .. tostring(err))
end
