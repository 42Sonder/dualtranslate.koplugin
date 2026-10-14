local settings = {}
local function gettext(s) return s end
local function template(fmt, ...)
    local n = select("#", ...)
    local out = fmt
    for i = 1, n do out = out:gsub("%%" .. i, tostring(select(i, ...) or "")) end
    return out
end
local stubs = {
    ["logger"] = { warn = function() end, err = function() end, info = function() end, dbg = function() end },
    ["dispatcher"] = {
        actions = {},
        registerAction = function(self, name, value) self.actions[name] = value end,
    },
    ["gettext"] = gettext,
    ["datastorage"] = { getDataDir = function() return "/tmp/dt_data" end },
    ["util"] = { makePath = function() return true end, trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end, removeFile = function() end },
    ["ffi/util"] = { template = template, md5 = function() return "x" end },
    ["ffi/archiver"] = {},
    ["device"] = { screen = { getWidth = function() return 600 end, getHeight = function() return 800 end }, hasClipboard = function() return false end, input = { setClipboardText = function() end } },
    ["libs/libkoreader-lfs"] = { attributes = function() return nil end, mkdir = function() return true end, rmdir = function() return true end, remove = function() return true end, dir = function() end },
    ["json"] = { encode = function() return "{}" end, decode = function() return {} end },
    ["socket.http"] = {}, ["ltn12"] = {}, ["socketutil"] = { request = function() return false end, set_timeout = function() end, reset_timeout = function() end },
    ["socket.url"] = { escape = function(s) return s end, unescape = function(s) return s end },
    ["lua-ljsqlite3/init"] = {},
    ["ui/uimanager"] = { show = function() end, close = function() end, setDirty = function() end, scheduleIn = function() end, nextTick = function() end },
    ["ui/widget/notification"] = { Notification = {} },
    ["ui/widget/textviewer"] = {}, ["ui/widget/buttondialog"] = {}, ["ui/widget/menu"] = {},
    ["ui/widget/progressbardialog"] = {}, ["ui/widget/inputdialog"] = {}, ["ui/widget/spinwidget"] = {},
    ["ui/widget/container/widgetcontainer"] = { extend = function(self, o) o = o or {}; o.__index = o; setmetatable(o, { __index = self }) return o end },
    ["ui/trapper"] = { dismissableRunInSubprocess = function() end, wrap = function() end },
    ["ui/event"] = { new = function() return {} end },
    ["fontlist"] = { getLocalizedFontName = function(n) return n end },
    ["document/credocument"] = { engineInit = function() return {} end },
    ["dump"] = function() return "{}" end,
}
for k, v in pairs(stubs) do package.preload[k] = function() return v end end
_G.G_reader_settings = {
    readSetting = function(self, key) return settings[key] end,
    saveSetting = function(self, key, value) settings[key] = value end,
}
_G.UIManager = stubs["ui/uimanager"]
local source_path = debug.getinfo(1, "S").source:gsub("^@", "")
local plugin_dir = source_path:match("^(.*)/tests/[^/]+$") or "."
package.path = plugin_dir .. "/?.lua;" .. package.path
local dualtranslate = dofile(plugin_dir .. "/main.lua")
dualtranslate.ui = { menu = { registerToMainMenu = function(self, plugin) plugin:addToMainMenu({}) end }, document = nil }
local ok, err = pcall(function() dualtranslate:init() end)
assert(ok, "init failed: " .. tostring(err))
print("init: true")
-- 设置读写验证
dualtranslate:saveSetting("test_key", 123)
assert(dualtranslate:getSetting("test_key") == 123, "settings roundtrip failed")
assert(dualtranslate:getSetting("nonexistent", "default") == "default")
assert(type(dualtranslate.cancelTranslation) == "function", "cancelTranslation not attached")
assert(type(dualtranslate.buildTranslationQueueMenu) == "function", "buildTranslationQueueMenu not attached")
assert(type(dualtranslate.reopenTranslationProgress) == "function", "reopenTranslationProgress missing")

local dispatcher_actions = stubs["dispatcher"].actions
local expected_actions = {
    dualtranslate_translate_current_chapter = "DualTranslateTranslateCurrentChapter",
    dualtranslate_translate_book = "DualTranslateTranslateBook",
    dualtranslate_toggle_translation = "DualTranslateToggleTranslation",
}
for action, event in pairs(expected_actions) do
    assert(dispatcher_actions[action], "missing Dispatcher action: " .. action)
    assert(dispatcher_actions[action].event == event, "wrong event for " .. action)
    assert(dispatcher_actions[action].category == "none", "wrong category for " .. action)
    assert(dispatcher_actions[action].reader == true, "action is not reader-only: " .. action)
    assert(type(dispatcher_actions[action].condition_func) == "function",
        "missing EPUB condition for " .. action)
end
print("Dispatcher actions: true")

local action_calls = {}
local original_translate_book = dualtranslate.translateBook
dualtranslate.translateBook = function(self, ...)
    action_calls[#action_calls + 1] = { ... }
end
dualtranslate:onDualTranslateTranslateCurrentChapter()
dualtranslate:onDualTranslateTranslateBook()
assert(action_calls[1][1] == false, "current-chapter action did not request one chapter")
assert(action_calls[2][1] == true and action_calls[2][5] == true,
    "whole-book action did not force whole-book mode")
dualtranslate.translateBook = original_translate_book
local toggled = false
local original_toggle = dualtranslate.toggleTranslationVisible
dualtranslate.toggleTranslationVisible = function() toggled = true end
dualtranslate:onDualTranslateToggleTranslation()
assert(toggled, "toggle action did not call toggleTranslationVisible")
dualtranslate.toggleTranslationVisible = original_toggle
print("Dispatcher handlers: true")
local menu_items = {}
local ok2, err2 = pcall(function() dualtranslate:addToMainMenu(menu_items) end)
assert(ok2, "menu build failed: " .. tostring(err2))
print("addToMainMenu: true")
local sub = menu_items.dualtranslate.sub_item_table
local provider_names = {}
local function walk(items, depth)
    for _, item in ipairs(items) do
        if item.text_func then item.text_func() end
        if item.checked_func then item.checked_func() end
        if item.enabled_func then item.enabled_func() end
        local t = item.text_func and item.text_func() or item.text
        if item.radio and t and (t:match("KOReader") or t:match("Microsoft")) then
            provider_names[t] = true
        end
        if item.sub_item_table then walk(item.sub_item_table, depth + 1) end
        if item.sub_item_table_func then walk(item.sub_item_table_func(), depth + 1) end
    end
end
local ok3, err3 = pcall(function() walk(sub, 0) end)
assert(ok3, "menu walk failed: " .. tostring(err3))
print("walk menu: true")
local n = 0
for _ in pairs(provider_names) do n = n + 1 end
assert(n == 2, "provider names not distinct: " .. tostring(n))
print("provider names distinct: true")
