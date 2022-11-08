---------------------
---------------------
-- Benötigte Natives
---------------------
---------------------

util.require_natives(1663599433)

---------------------
---------------------
-- Diverse Variablen
---------------------
---------------------
sversion = 0.2                                                      --Aktuelle Script Version
sprefix = "[Athego's Script " .. sversion .. "]"                    --So wird die Variable benutzt: "" .. sprefix .. " 
willkommensnachricht = "Athego's Script erfolgreich geladen!"       --Willkommensnachricht die beim Script Start angeziegt wird als Stand Benachrichtigung

---------------------
---------------------
-- Script geladen Notify
---------------------
---------------------

util.toast("" .. willkommensnachricht .. "")                        --Die Willkommensnachricht

util.show_corner_help("~s~Viel Spaß mit~h~~b~ " .. SCRIPT_FILENAME)
util.on_stop(function()
    util.show_corner_help("~s~Danke fürs benutzen von Athego's Script.")
end)

---------------------
---------------------
-- Script Version Check / Script Auto Updater
---------------------
---------------------

local response = false
local localVer = sversion
async_http.init("raw.githubusercontent.com", "/BassamKhaleel/Athegos-Script-Stand/main/VersionCheck", function(output)
    currentVer = tonumber(output)
    response = true
    if localVer ~= currentVer then
        util.toast("" .. sprefix .. " Version " .. currentVer .. " von Athego‘s Script ist verfügbar, bitte Update das Script")
        menu.action(menu.my_root(), "Update Lua", {}, "", function()
            async_http.init('raw.githubusercontent.com','/BassamKhaleel/Athegos-Script-Stand/main/AthegosScript.lua',function(a)
                local err = select(2,load(a))
                if err then
                    util.toast("" .. sprefix .. " Fehler beim Updaten des Script‘s. Probiere es später erneut. Sollte der Fehler weiterhin auftreten Update das Script Manuell über GitHub.")
                return end
                local f = io.open(filesystem.scripts_dir()..SCRIPT_RELPATH, "wb")
                f:write(a)
                f:close()
                util.toast("" .. sprefix .. " Athego‘s Script wurde erfolgreich Aktualisiert. Das Script wird Automatisch neugestartet :)")
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

---------------------
---------------------
-- Funktion das das Script weiter läuft
---------------------
---------------------

util.keep_running()