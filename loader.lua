local URL = "DAN_RAW_URL_VAO_DAY"

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
