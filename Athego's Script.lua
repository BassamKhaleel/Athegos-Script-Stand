---------------------
---------------------
-- Benötigte Natives
---------------------
---------------------

util.require_natives(1663599433)

---------------------
---------------------
-- Script geladen Notify
---------------------
---------------------

util.toast("Athego's Script erfolgreich geladen! DEV Version 1.88")

util.show_corner_help("~s~Viel Spaß mit~h~~b~ " .. SCRIPT_FILENAME)
util.on_stop(function()
    util.show_corner_help("~s~Bis zum nächsten mal.")
end)

---------------------
---------------------
-- Script Version Check / Script Auto Updater
---------------------
---------------------

local response = false
local localVer = 1.88
async_http.init("raw.githubusercontent.com", "/BassamKhaleel/Athegos-Skript-DEV-Stand/main/AthegosSkriptVersion", function(output)
    currentVer = tonumber(output)
    response = true
    if localVer ~= currentVer then
        util.toast("[Athego's Script] Eine neue Version von Athego‘s Skript ist verfügbar, bitte Update das Skript")
        menu.action(menu.my_root(), "Update Lua", {}, "", function()
            async_http.init('raw.githubusercontent.com','/BassamKhaleel/Athegos-Skript-DEV-Stand/main/Athegos_Script_DEV.lua',function(a)
                local err = select(2,load(a))
                if err then
                    util.toast("[Athego's Script] Fehler beim Updaten des Skript‘s. Probiere es später erneut. Sollte der Fehler weiterhin auftreten Update das Skript Manuell über GitHub.")
                return end
                local f = io.open(filesystem.scripts_dir()..SCRIPT_RELPATH, "wb")
                f:write(a)
                f:close()
                util.toast("[Athego's Script] Athego‘s Skript wurde erfolgreich Aktualisiert. Das SKript wird Automatisch neugestartet :)")
                util.restart_script()
            end)
            async_http.dispatch()
        end)
    end
end, function() response = true end)
async_http.dispatch()
repeat 
    util.yield()
until response