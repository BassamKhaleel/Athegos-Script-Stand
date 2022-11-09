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
sversion = tonumber(0.6)                                            --Aktuelle Script Version
sprefix = "[Athego's Script " .. sversion .. "]"                    --So wird die Variable benutzt: "" .. sprefix .. " 
willkommensnachricht = "Athego's Script erfolgreich geladen!"       --Willkommensnachricht die beim Script Start angeziegt wird als Stand Benachrichtigung
local replayInterface = memory.read_long(memory.rip(memory.scan("48 8D 0D ? ? ? ? 48 8B D7 E8 ? ? ? ? 48 8D 0D ? ? ? ? 8A D8 E8 ? ? ? ? 84 DB 75 13 48 8D 0D") + 3))
local pedInterface = memory.read_long(replayInterface + 0x0018)
local vehInterface = memory.read_long(replayInterface + 0x0010)
local objectInterface = memory.read_long(replayInterface + 0x0028)
local pickupInterface = memory.read_long(replayInterface + 0x0020)
local playerid = players.user()
local requestModel = STREAMING.REQUEST_MODEL

---------------------
---------------------
-- function zum Spawnen von verschiedenen Objekten
---------------------
---------------------

local function request_model(hash, timeout)
    timeout = timeout or 3
    STREAMING.REQUEST_MODEL(hash)
    local end_time = os.time() + timeout
    repeat
        util.yield()
    until STREAMING.HAS_MODEL_LOADED(hash) or os.time() >= end_time
    return STREAMING.HAS_MODEL_LOADED(hash)
end

---------------------
---------------------
-- function für player_toggle_loop
---------------------
---------------------

local function player_toggle_loop(root, pid, menu_name, command_names, help_text, callback)
    return menu.toggle_loop(root, menu_name, command_names, help_text, function()
        if not players.exists(pid) then util.stop_thread() end
        callback()
    end)
end

---------------------
---------------------
-- function für Godmode Check
---------------------
---------------------

local function get_transition_state(pid)
    return memory.read_int(memory.script_global(((0x2908D3 + 1) + (pid * 0x1C5)) + 230))
end

local function get_interior_player_is_in(pid)
    return memory.read_int(memory.script_global(((0x2908D3 + 1) + (pid * 0x1C5)) + 243)) 
end

local function is_player_in_interior(pid)
    return (memory.read_int(memory.script_global(0x2908D3 + 1 + (pid * 0x1C5) + 243)) ~= 0)
end

---------------------
---------------------
-- Checks/Variablen für Loadout
---------------------
---------------------

local STOREDIR = filesystem.store_dir() --- not using this much, consider moving it to the 2 locations it's used in..
local LIBDIR = filesystem.scripts_dir() .. "lib\\Athegos-loadout\\"
local do_autoload = false
local wpcmpTable = {}
local weapons_table = {}
if filesystem.exists(LIBDIR .. "component_resources.lua") then
    wpcmpTable = require("lib.Athegos-loadout.component_resources")
    weapons_table = util.get_weapons()
else
    util.toast(sprefix .. " You didn't install the resources properly.\nMake sure component-resources.lua is in the " .. LIBDIR .. " directory")
    util.stop_script()
end
local attachments_dict = wpcmpTable[1]
local liveries_dict = wpcmpTable[2]

---------------------
---------------------
-- Checks/Variablen für IngameKonsole
---------------------
---------------------

local log_dir = filesystem.stand_dir() .. '\\Log.txt'
local full_stdout = ""
local disp_stdout = ""
local max_chars = 200
local max_lines = 20
local font_size = 0.35
local timestamp_toggle = false

local text_color = {r = 1, g = 1, b = 1, a = 1}
local bg_color = {r = 0, g = 0, b = 0, a = 0.5}

local function get_stand_stdout(tbl, n)
    local all_lines = {}
    local disp_lines = {}
    local size = #tbl
    local index = 1
    if size >= n then 
        index = #tbl - n
    end

    for i=index, size do 
        local line = tbl[i]
        local line_copy = line
        if line ~= "" and line ~= '\n' then
            all_lines[#all_lines + 1] = line
            if not timestamp_toggle then
               -- at this point, the line is already added to all lines, so we can just customize it and it wont affect STDOUT clipboard copy
                local _, second_segment = string.partition(line, ']')
                if second_segment ~= nil then
                    line = second_segment
                end
            end
            if string.len(line) > max_chars then
                disp_lines[#disp_lines + 1] = line:sub(1, max_chars) .. ' ...'
            else
                disp_lines[#disp_lines + 1] = line
            end
        end
    end

    -- full_stdout exists so that we can copy the entire console output without "aesthetic" changes or trimming
    -- disp_stdout is the aesthetic, possibly-formatted version that you actually see in-game, WITH trimming
    full_stdout = table.concat(all_lines, '\n')
    disp_stdout = table.concat(disp_lines, '\n')
end

local function get_last_lines(file)
    local f = io.open(file, "r")
    local len = f:seek("end")
    f:seek("set", len - max_lines*1000)
    local text = f:read("*a")
    lines = string.split(text, '\n')
    f:close()
    get_stand_stdout(lines, max_lines)
end

---------------------
---------------------
-- On Chat function
---------------------
---------------------

local racist_dict = {"nigg", "jew", "nigga"}
local homophobic_dict = {"fag", "tranny"}
local stupid_detections_dict = {"Freeze from", "Vehicle takeover from", "Modded Event (", "triggered a detection:", "Model sync by"}

chat.on_message(function(packet_sender, message_sender, text, team_chat)
    text = string.lower(text)
    local name = players.get_name(message_sender)

    if not team_chat then
        if rassismus_beenden then 
            for _,word in pairs(racist_dict) do 
                if string.contains(text, word) then
                    menu.trigger_commands("kick " .. name)
                    util.toast(sprefix .. " " .. name .. " ist rassistisch und wurde deswegen gekickt")
                    util.log(sprefix .. " " .. name .. " ist rassistisch und wurde deswegen gekickt")
                end
            end
        end

        if homophobie_beenden then 
            for _,word in pairs(homophobic_dict) do 
                if string.contains(text, word) then
                    menu.trigger_commands("kick " .. name)
                    util.toast(sprefix .. " " .. name .. " ist homophob und wurde deswegen gekickt")
                    util.log(sprefix .. " " .. name .. " ist homophob und wurde deswegen gekickt")
                end
            end
        end
    end
end)

---------------------
---------------------
-- Unveröffentlichte Fahrzeuge
---------------------
---------------------

local unreleased_vehicles = {
    "Sentinel4",
}

---------------------
---------------------
-- Gemoddete Fahrzeuge
---------------------
---------------------

local modded_vehicles = {
    "dune2",
    "tractor",
    "dilettante2",
    "asea2",
    "cutter",
    "mesa2",
    "jet",
    "skylift",
    "policeold1",
    "policeold2",
    "armytrailer2",
    "towtruck",
    "towtruck2",
    "cargoplane",
}

---------------------
---------------------
-- Gemoddete Waffen
---------------------
---------------------

local modded_weapons = {
    "weapon_railgun",
    "weapon_stungun",
    "weapon_digiscanner",
}

---------------------
---------------------
-- Drogen Effekte
---------------------
---------------------

local drugged_effects = {
    "DRUG_2_drive",
    "drug_drive_blend01",
    "drug_flying_base",
    "DRUG_gas_huffin",
    "drug_wobbly",
    "NG_filmic02",
    "PPFilter",
    "spectator5",
}

---------------------
---------------------
-- Geschäftsimmobilien
---------------------
---------------------

local All_business_properties = {
    -- Clubhäuser
    "1334 Roy Lowenstein Blvd",
    "7 Del Perro Beach",
    "75 Elgin Avenue",
    "101 Route 68",
    "1 Paleto Blvd",
    "47 Algonquin Blvd",
    "137 Capital Blvd",
    "2214 Clinton Avenue",
    "1778 Hawick Avenue",
    "2111 East Joshua Road",
    "68 Paleto Blvd",
    "4 Goma Street",
    -- Facilities
    "Grand Senora Desert",
    "Route 68",
    "Sandy Shores",
    "Mount Gordo",
    "Paleto Bay",
    "Lago Zancudo",
    "Zancudo River",
    "Ron Alternates Wind Farm",
    "Land Act Reservoir",
    -- Arcades
    "Pixel Pete's - Paleto Bay",
    "Wonderama - Grapeseed",
    "Warehouse - Davis",
    "Eight-Bit - Vinewood",
    "Insert Coin - Rockford Hills",
    "Videogeddon - La Mesa",
}

local small_warehouses = {
    [1] = "Pacific Bait Storage", 
    [2] = "White Widow Garage", 
    [3] = "Celltowa Unit", 
    [4] = "Convenience Store Lockup", 
    [5] = "Foreclosed Garage", 
    [9] = "Pier 400 Utility Building", 
}

local medium_warehouses = {
    [7] = "Derriere Lingerie Backlot", 
    [10] = "GEE Warehouse", 
    [11] = "LS Marine Building 3", 
    [12] = "Railyard Warehouse", 
    [13] = "Fridgit Annexe",
    [14] = "Disused Factory Outlet", 
    [15] = "Discount Retail Unit", 
    [21] = "Old Power Station", 
}

local large_warehouses = {
    [6] = "Xero Gas Factory",  
    [8] = "Bilgeco Warehouse", 
    [16] = "Logistics Depot", 
    [17] = "Darnell Bros Warehouse", 
    [18] = "Wholesale Furniture", 
    [19] = "Cypress Warehouses", 
    [20] = "West Vinewood Backlot", 
    [22] = "Walker & Sons Warehouse"
}

---------------------
---------------------
-- Innenräume
---------------------
---------------------

local interiors = {
    {"Safe Space [AFK Raum]", {x=-158.71494, y=-982.75885, z=149.13135}},
    {"Torture Room", {x=147.170, y=-2201.804, z=4.688}},
    {"Mining Tunnels", {x=-595.48505, y=2086.4502, z=131.38136}},
    {"Omegas Garage", {x=2330.2573, y=2572.3005, z=46.679367}},
    {"Server Farm", {x=2155.077, y=2920.9417, z=-81.075455}},
    {"Character Creation", {x=402.91586, y=-998.5701, z=-99.004074}},
    {"Life Invader Building", {x=-1082.8595, y=-254.774, z=37.763317}},
    {"Mission End Garage", {x=405.9228, y=-954.1149, z=-99.6627}},
    {"Destroyed Hospital", {x=304.03894, y=-590.3037, z=43.291893}},
    {"Stadium", {x=-256.92334, y=-2024.9717, z=30.145584}},
    {"Comedy Club", {x=-430.00974, y=261.3437, z=83.00648}},
    {"Bahama Mamas Nightclub", {x=-1394.8816, y=-599.7526, z=30.319544}},
    {"Janitors House", {x=-110.20285, y=-8.6156025, z=70.51957}},
    {"Therapists House", {x=-1913.8342, y=-574.5799, z=11.435149}},
    {"Martin Madrazos House", {x=1395.2512, y=1141.6833, z=114.63437}},
    {"Floyds Apartment", {x=-1156.5099, y=-1519.0894, z=10.632717}},
    {"Michaels House", {x=-813.8814, y=179.07889, z=72.15914}},
    {"Franklins House (Alt)", {x=-14.239959, y=-1439.6913, z=31.101551}},
    {"Franklins House (Neu)", {x=7.3125067, y=537.3615, z=176.02803}},
    {"Trevors House", {x=1974.1617, y=3819.032, z=33.436287}},
    {"Lesters House", {x=1273.898, y=-1719.304, z=54.771}},
    {"Lesters Warehouse", {x=713.5684, y=-963.64795, z=30.39534}},
    {"Lesters Office", {x=707.2138, y=-965.5549, z=30.412853}},
    {"Meth Lab", {x=1391.773, y=3608.716, z=38.942}},
    {"Humane Labs", {x=3625.743, y=3743.653, z=28.69009}},
    {"Motel Room", {x=152.2605, y=-1004.471, z=-99.024}},
    {"Police Station", {x=443.4068, y=-983.256, z=30.689589}},
    {"Bank Vault", {x=263.39627, y=214.39891, z=101.68336}},
    {"Blaine County Bank", {x=-109.77874, y=6464.8945, z=31.626724}}, -- credit to fluidware for telling me about this one
    {"Tequi-La-La Bar", {x=-564.4645, y=275.5777, z=83.074585}},
    {"Scrapyard Body Shop", {x=485.46396, y=-1315.0614, z=29.2141}},
    {"The Lost MC Clubhouse", {x=980.8098, y=-101.96038, z=74.84504}},
    {"Vangelico Jewlery Store", {x=-629.9367, y=-236.41296, z=38.057056}},
    {"Airport Lounge", {x=-913.8656, y=-2527.106, z=36.331566}},
    {"Morgue", {x=240.94368, y=-1379.0645, z=33.74177}},
    {"Union Depository", {x=1.298771, y=-700.96967, z=16.131021}},
    {"Fort Zancudo Tower", {x=-2357.9187, y=3249.689, z=101.45073}},
    {"Agency Interior", {x=-1118.0181, y=-77.93254, z=-98.99977}},
    {"Avenger Interior", {x=518.6444, y=4750.4644, z=-69.3235}},
    {"Terrobyte Interior", {x=-1421.015, y=-3012.587, z=-80.000}},
    {"Bunker Interior", {x=899.5518,y=-3246.038, z=-98.04907}},
    {"IAA Office", {x=128.20, y=-617.39, z=206.04}},
    {"FIB Top Floor", {x=135.94359, y=-749.4102, z=258.152}},
    {"FIB Floor 47", {x=134.5835, y=-766.486, z=234.152}},
    {"FIB Floor 49", {x=134.635, y=-765.831, z=242.152}},
    {"Big Fat White Cock", {x=-31.007448, y=6317.047, z=40.04039}},
    {"Marijuana Shop", {x=-1170.3048, y=-1570.8246, z=4.663622}},
    {"Strip Club DJ Booth", {x=121.398254, y=-1281.0024, z=29.480522}},
}

local interior_stuff = {0, 233985, 169473, 169729, 169985, 170241, 177665, 177409, 185089, 184833, 184577, 163585, 167425, 167169}

---------------------
---------------------
-- Script geladen Notify
---------------------
---------------------

util.toast("" .. willkommensnachricht .. "")
util.log("" .. willkommensnachricht .. "")                        --Die Willkommensnachricht

util.show_corner_help("~s~Viel Spaß mit~h~~b~ " .. SCRIPT_FILENAME)
util.on_stop(function()
    util.show_corner_help("~s~Danke fürs benutzen von~h~~b~ " .. SCRIPT_FILENAME)
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
        util.toast(sprefix .. " Version " .. currentVer .. " von Athego‘s Script ist verfügbar, bitte Update das Script")
        menu.action(menu.my_root(), "Update Lua", {}, "", function()
            async_http.init('raw.githubusercontent.com','/BassamKhaleel/Athegos-Script-Stand/main/AthegosScript.lua',function(a)
                local err = select(2,load(a))
                if err then
                    util.toast(sprefix .. " Fehler beim Updaten des Script‘s. Probiere es später erneut. Sollte der Fehler weiterhin auftreten Update das Script Manuell über GitHub.")
                return end
                local f = io.open(filesystem.scripts_dir()..SCRIPT_RELPATH, "wb")
                f:write(a)
                f:close()
                util.toast(sprefix .. " Athego‘s Script wurde erfolgreich Aktualisiert. Das Script wird Automatisch neugestartet :)")
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
-- Menü Ordner
---------------------
---------------------

menu.divider(menu.my_root(), "Athego's Script - " .. sversion)
local self <const> = menu.list(menu.my_root(), "Selbst", {}, "")
    menu.divider(self, "Athego's Script - Selbst")
local online <const> = menu.list(menu.my_root(), "Online", {}, "")
    menu.divider(online, "Athego's Script - Online")
local loadout <const> = menu.list(menu.my_root(), "Loadout", {}, "")
    menu.divider(loadout, "Athego's Script - Loadout")
local sonstiges <const> = menu.list(menu.my_root(), "Sonstiges", {}, "")
    menu.divider(sonstiges, "Athego's Script - Sonstiges")

---------------------
---------------------
-- Selbst
---------------------
---------------------

menu.toggle(self, "Leiser Schritt", {}, "Entfernt die Geräusche die du beim gehen machst", function (toggle)
    AUDIO.SET_PED_FOOTSTEPS_EVENTS_ENABLED(players.user_ped(), not toggle)
end)

---------------------
---------------------
-- Selbst/Unlocks
---------------------
---------------------

---------------------
---------------------
-- Online
---------------------
---------------------

---------------------
---------------------
-- Online/Erkennungen
---------------------
---------------------

local detections = menu.list(online, "Erkennungen", {}, "")
    menu.divider(detections, "Athego's Script - Erkennungen")

menu.toggle_loop(detections, "Godmode", {}, "Erkennt ob jemand Godmode benutzt", function()
    for _, pid in ipairs(players.list(false, true, true)) do
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local pos = ENTITY.GET_ENTITY_COORDS(ped, false)
        for i, interior in ipairs(interior_stuff) do
            if (players.is_godmode(pid) or not ENTITY.GET_ENTITY_CAN_BE_DAMAGED(ped)) and not NETWORK.NETWORK_IS_PLAYER_FADING(pid) and ENTITY.IS_ENTITY_VISIBLE(ped) and get_transition_state(pid) == 99 and get_interior_player_is_in(pid) == interior then
                util.draw_debug_text("[Athego's Script] " .. players.get_name(pid) .. " benutzt Godmode")
                util.toast(sprefix .. " " .. players.get_name(pid) .. " benutzt Godmode")
                util.log(sprefix .. " " .. players.get_name(pid) .. " benutzt Godmode")
                break
            end
        end
    end
end)

---------------------
---------------------
-- Online/Protections
---------------------
---------------------

local protections = menu.list(online, "Schutzmaßnahmen", {}, "")
    menu.divider(protections, "Athego's Script - Schutzmaßnahmen")

rassismus_beenden = false
menu.toggle(protections, "Rassimus beenden", {}, "Kickt Rassistische Spieler", function(on)
    rassismus_beenden = on
end)

homophobie_beenden = false
menu.toggle(protections, "Homophobie beenden", {}, "Kickt Homophobe Spieler", function(on)
    homophobie_beenden = on
end)

---------------------
---------------------
-- Online
---------------------
---------------------

menu.action(online, 'Schneeballschlacht', {}, 'Schenkt allen in der Lobby Schneebälle und benachrichtigt sie per SMS', function ()
    local plist = players.list()
    local snowballs = util.joaat('WEAPON_SNOWBALL')
    for i = 1, #plist do
        local plyr = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(plist[i])
        WEAPON.GIVE_DELAYED_WEAPON_TO_PED(plyr, snowballs, 20, true)
        WEAPON.SET_PED_AMMO(plyr, snowballs, 20)
        players.send_sms(plist[i], playerid, 'Snowball Fight! You now have snowballs')
        util.yield()
    end
end)

---------------------
---------------------
-- Loadout
---------------------
---------------------

local save_loadout_liste = menu.list(loadout, "Loadout speichern", {}, "")
    menu.divider(save_loadout_liste, "Athego's Script - Loadout speichern")

save_loadout = menu.action(save_loadout_liste, "Loadout speichern", {"loadoutspeichern"}, "Speichert alle aktuell ausgerüsteten Waffen und Aufsätze um sie in Zukunft zu laden.",
        function()
            util.toast(sprefix .. " Loadout wird gespeichert...")
            util.log(sprefix .. " Loadout wird gespeichert...")
            local charS,charE = "   ","\n"
            local player = players.user_ped()
            file = io.open(STOREDIR .. "AthegosLoadout.lua", "wb")
            file:write("return {" .. charE)
            local num_weapons = 0
            for _, weapon in weapons_table do
                local weapon_hash = weapon.hash
                if WEAPON.HAS_PED_GOT_WEAPON(player, weapon_hash, false) then
                    num_weapons = num_weapons + 1
                    if num_weapons > 1 then
                        file:write("," .. charE)
                    end
                    file:write(charS .. "[" .. weapon_hash .. "] = ")
                    --WEAPON.SET_CURRENT_PED_WEAPON(player, weapon_hash, true)
                    local num_attachments = 0
                    for attachment_hash, _ in attachments_dict do
                        if (WEAPON.DOES_WEAPON_TAKE_WEAPON_COMPONENT(weapon_hash, attachment_hash)) then
                            --util.yield(10)
                            if WEAPON.HAS_PED_GOT_WEAPON_COMPONENT(player, weapon_hash, attachment_hash) then
                                num_attachments = num_attachments + 1
                                if num_attachments == 1 then
                                    file:write("{")
                                    file:write(charE .. charS .. charS .. "[\"attachments\"] = {")
                                else
                                    file:write(",")
                                end
                                file:write(charE .. charS .. charS .. charS .. "[" .. num_attachments .. "] = " .. attachment_hash)
                            end
                        end
                    end
                    local cur_tint = WEAPON.GET_PED_WEAPON_TINT_INDEX(player, weapon_hash)
                    if num_attachments > 0 then
                        file:write(charE .. charS .. charS .. "},")
                    else
                        file:write("{")
                    end
                    file:write(charE .. charS .. charS .. "[\"tint\"] = " .. cur_tint)
                    --- Livery
                    for livery_hash, _ in liveries_dict do
                        if WEAPON.HAS_PED_GOT_WEAPON_COMPONENT(player, weapon_hash, livery_hash) then
                            local colour = WEAPON.GET_PED_WEAPON_COMPONENT_TINT_INDEX(player, weapon_hash, livery_hash)
                            file:write("," .. charE .. charS .. charS .. "[\"livery\"] = {")
                            file:write(charE .. charS .. charS .. charS .. "[\"hash\"] = " .. livery_hash .. ",")
                            file:write(charE .. charS .. charS .. charS .. "[\"colour\"] = " .. colour)
                            file:write(charE .. charS .. charS .. "}")
                            break
                        end
                    end
                    file:write(charE .. charS .. "}")
                end
            end
            file:write(charE .. "}")
            file:close()
            util.toast(sprefix .. " Speichern erfolgreich!")
            util.log(sprefix .. " Speichern erfolgreich!")
        end
)

load_loadout = menu.action(loadout, "Loadout laden", {"loadoutladen"}, "Equippt dein Loadout aus der letzten Speicherung",
        function()
            if filesystem.exists(STOREDIR .. "AthegosLoadout.lua") then
                util.toast(sprefix .. " Loadout wird geladen...")
                util.log(sprefix .. " Loadout wird geladen...")
                player = players.user_ped()
                WEAPON.REMOVE_ALL_PED_WEAPONS(player, false)
                WEAPON.SET_CAN_PED_SELECT_ALL_WEAPONS(player, true)
                local loadout = require("store\\" .. "AthegosLoadout")
                for w_hash, attach_dict in loadout do
                    WEAPON.GIVE_WEAPON_TO_PED(player, w_hash, 10, false, true)
                    if attach_dict.attachments ~= nil then
                        for _, hash in attach_dict.attachments do
                            WEAPON.GIVE_WEAPON_COMPONENT_TO_PED(player, w_hash, hash)
                        end
                    end
                    WEAPON.SET_PED_WEAPON_TINT_INDEX(player, w_hash, attach_dict["tint"])
                    if attach_dict.livery ~= nil then
                        WEAPON.GIVE_WEAPON_COMPONENT_TO_PED(player, w_hash, attach_dict.livery.hash)
                        WEAPON.SET_PED_WEAPON_COMPONENT_TINT_INDEX(player, w_hash, attach_dict.livery.hash, attach_dict.livery.colour)
                    end
                end
                regen_menu()
                util.toast(sprefix .. " Loadout erfolgreich geladen!")
                util.log(sprefix .. " Loadout erfolgreich geladen!")
            else
                util.toast(sprefix .. " Du hast noch kein Loadout gespeichert.")
            util.log(sprefix .. " Du hast noch kein Loadout gespeichert.")
            end
            package.loaded["store\\AthegosLoadout"] = nil --- load_loadout should always get the current state of loadout.lua, therefore always load it again or else the last required table would be taken, as it has already been loaded before..
        end
)

auto_load = menu.toggle(loadout, "Auto-Load", {}, "Lädt deine Waffen bei jedem Sitzungswechsel neu.", function(on)
	do_autoload = on
end)

from_scratch = menu.action(loadout, "Fang von Vorne an", {}, "Löscht jede Waffe damit du dein Loadout so einrichten kannst wie du magst.",
        function()
            WEAPON.REMOVE_ALL_PED_WEAPONS(PLAYER.GET_PLAYER_PED(players.user()), false)
            regen_menu()
            util.toast(sprefix .. " Deine Waffen wurde gelöscht!")
            util.log(sprefix .. " Deine Waffen wurde gelöscht!")
        end)

menu.divider(loadout, "Waffen bearbeiten")

function regen_menu()
    for _, weapon in weapons_table do
        if weapons_action[weapon.hash] ~= nil then
            if weapons_action[weapon.hash]:isValid() then
                weapons_action[weapon.hash]:delete()
            end
        end
    end
    weapons_action = {}
    attachments_action = {}
    weapon_deletes = {}
    cosmetics_list = {}
    tints_slider = {}
    livery_action_divider = {}
    livery_actions = {}
    livery_colour_slider = {}
    livery = {}

    for _, weapon in weapons_table do
        local category = weapon.category
        local weapon_name = util.get_label_text(weapon.label_key)
        local weapon_hash = weapon.hash
        if WEAPON.HAS_PED_GOT_WEAPON(players.user_ped(), weapon_hash, false) then
            generate_for_new_weapon(category, weapon_name, weapon_hash, false)
        else
            weapons_action[weapon_hash] = categories[category]:action(weapon_name .. " (nicht ausgerüstet)", {}, "Ausrüsten " .. weapon_name,
                    function()
                        weapons_action[weapon_hash]:delete()
                        equip_weapon(category, weapon_name, weapon_hash)
                    end
            )
        end
        WEAPON.ADD_AMMO_TO_PED(players.user_ped(), weapon_hash, 10) --- if a special ammo type has been equipped.. it should get some ammo
    end
end

function equip_comp(category, weapon_name, weapon_hash, attachment_hash)
    WEAPON.GIVE_WEAPON_COMPONENT_TO_PED(players.user_ped(), weapon_hash, attachment_hash)
end

function equip_weapon(category, weapon_name, weapon_hash)
    WEAPON.GIVE_WEAPON_TO_PED(players.user_ped(), weapon_hash, 10, false, true)
    util.yield(10)
    weapon_deletes[weapon_name] = nil
    generate_for_new_weapon(category, weapon_name, weapon_hash, true)
end

function generate_for_new_weapon(category, weapon_name, weapon_hash, focus)
    weapons_action[weapon_hash] = categories[category]:list(weapon_name, {}, "Bearbeite Aufsätze für " .. weapon_name,
            function()
                WEAPON.SET_CURRENT_PED_WEAPON(players.user_ped(), weapon_hash, true)
                generate_attachments(category, weapon_name, weapon_hash)
            end
    )
    if focus then
        weapons_action[weapon_hash]:trigger()
    end
end

function generate_cosmetics(weapon_hash, weapon_name)
    -- clear old cosmetic stuff
    livery_action_divider = {}
    livery_colour_slider = {}
    livery = {}
    tints_slider = {}
    livery_actions = {}

    if cosmetics_list[weapon_hash] ~= nil then
        if cosmetics_list[weapon_hash]:isValid() then
            cosmetics_list[weapon_hash]:delete()
        end
        regenerated_cosmetics = true
    end
    cosmetics_list[weapon_hash] = weapons_action[weapon_hash]:list("Design", {}, "",
            function()
                local tint_count = WEAPON.GET_WEAPON_TINT_COUNT(weapon_hash)
                local cur_tint = WEAPON.GET_PED_WEAPON_TINT_INDEX(player, weapon_hash)

                if tints_slider[weapon_hash] == nil then
                    tints_slider[weapon_hash] = cosmetics_list[weapon_hash]:slider("Lackierung", {}, "Wähl die Lackierung für " .. weapon_name, 0, tint_count - 1, cur_tint, 1,
                            function(change)
                                WEAPON.SET_PED_WEAPON_TINT_INDEX(player, weapon_hash, change)
                            end
                    )
                end

                --- livery colour
                local has_liveries = false
                for livery_hash, _ in liveries_dict do
                    if WEAPON.DOES_WEAPON_TAKE_WEAPON_COMPONENT(weapon_hash, livery_hash) then
                        has_liveries = true
                        break
                    end
                end


                if has_liveries then
                    --- get current camo component
                    for hash, _ in liveries_dict do
                        if WEAPON.HAS_PED_GOT_WEAPON_COMPONENT(player, weapon_hash, hash) then
                            livery[weapon_hash] = hash
                            break
                        end
                    end
                    --- livery colour slider
                    if livery_colour_slider[weapon_hash] == nil then
                        local cur_ctint_colour = WEAPON.GET_PED_WEAPON_COMPONENT_TINT_INDEX(player, weapon_hash, livery[weapon_hash])
                        if cur_ctint_colour == -1 then cur_ctint_colour = 0 end
                        livery_colour_slider[weapon_hash] = cosmetics_list[weapon_hash]:slider("Farbe der Lackierung", {}, "Ändert die Farbe deiner Lackierung", 0, 31, cur_ctint_colour, 1,
                                function(index)
                                    if livery[weapon_hash] == nil then
                                        util.toast(sprefix .. " Auf deiner Waffe ist keine Lackierung")
                                    else
                                        WEAPON.SET_PED_WEAPON_COMPONENT_TINT_INDEX(player, weapon_hash, livery[weapon_hash], index)
                                    end
                                end
                        )
                    end

                    if livery_action_divider[weapon_hash] == nil then
                        livery_action_divider[weapon_hash] = cosmetics_list[weapon_hash]:divider("Lackierungen")
                    end
                    --- livery equip actions
                    for livery_hash, label in liveries_dict do
                        if WEAPON.DOES_WEAPON_TAKE_WEAPON_COMPONENT(weapon_hash, livery_hash) and livery_actions[weapon_hash..livery_hash] == nil then
                            livery_actions[weapon_hash .. livery_hash] = cosmetics_list[weapon_hash]:action(util.get_label_text(label), {}, "",
                                    function()
                                        livery[weapon_hash] = livery_hash
                                        equip_comp(category, weapon_name, weapon_hash, livery_hash)
                                        WEAPON.SET_PED_WEAPON_COMPONENT_TINT_INDEX(player, weapon_hash, livery[weapon_hash], livery_colour_slider[weapon_hash].value)
                                    end
                            )
                        end
                    end
                end
            end
    )
end

function generate_attachments(category, weapon_name, weapon_hash)
    if weapon_deletes[weapon_name] == nil then
        weapon_deletes[weapon_name] = weapons_action[weapon_hash]:action("Lösche " .. weapon_name, {}, "",
                function()
                    WEAPON.REMOVE_WEAPON_FROM_PED(players.user_ped(), weapon_hash)
                    cosmetics_list[weapon_hash]:delete()
                    cosmetics_list[weapon_hash] = nil
                    livery_action_divider[weapon_hash] = nil
                    weapons_action[weapon_hash]:delete()

                    util.toast(weapon_name .. " wurde gelöscht")
                    weapons_action[weapon_hash] = categories[category]:action(weapon_name .. " (nicht ausgerüstet)", {}, "Ausrüsten " .. weapon_name,
                            function()
                                for a_key, _ in attachments_action do
                                    if string.find(a_key, weapon_hash) ~= nil then
                                        attachments_action[a_key] = nil
                                    end
                                end
                                menu.delete(weapons_action[weapon_hash])
                                equip_weapon(category, weapon_name, weapon_hash)
                                weapon_deletes[weapon_name] = nil
                            end
                    )
                    weapons_action[weapon_hash]:focus()
                end
        )
    end

    local has_attachments = false
    for livery_hash, _ in attachments_dict do
        if WEAPON.DOES_WEAPON_TAKE_WEAPON_COMPONENT(weapon_hash, livery_hash) then
            has_attachments = true
            break
        end
    end

    if cosmetics_list[weapon_hash] == nil then
        generate_cosmetics(weapon_hash, weapon_name)
        if has_attachments then
            weapons_action[weapon_hash]:divider("Aufsätze")
        end
    end

    for attachment_hash, attachment_label in attachments_dict do
        local attachment_name = util.get_label_text(attachment_label)
        if (WEAPON.DOES_WEAPON_TAKE_WEAPON_COMPONENT(weapon_hash, attachment_hash)) then
            if (attachments_action[weapon_hash .. " " .. attachment_hash] ~= nil) then attachments_action[weapon_hash .. " " .. attachment_hash]:delete() end
            attachments_action[weapon_hash .. " " .. attachment_hash] = weapons_action[weapon_hash]:action(attachment_name, {}, "Rüste deine Waffe " .. weapon_name .. " mit " .. attachment_name .. " aus ",
                    function()
                        equip_comp(category, weapon_name, weapon_hash, attachment_hash)
                        if (string.find(attachment_label, "CLIP") ~= nil or string.find(attachment_label, "SHELL") ~= nil) and WEAPON.HAS_PED_GOT_WEAPON_COMPONENT(players.user_ped(), weapon_hash, attachment_hash) then --last condition could be unnecessary
                            --- if the type of rounds is changed, the player needs some bullets of the new type to be able to use them
                            WEAPON.ADD_AMMO_TO_PED(players.user_ped(), weapon_hash, 10)
                            --util.toast("gave " .. weapon_name .. " some rounds because an ammo type was equipped")
                        end
                    end
            )
        end
    end
end

categories = {}
weapons_action = {}
attachments_action = {}
weapon_deletes = {}
cosmetics_list = {}
tints_slider = {}
livery_action_divider = {}
livery_actions = {}
livery_colour_slider = {}
livery = {}
for _, weapon in weapons_table do
    local category = weapon.category
    if categories[category] == nil then
        categories[category] = menu.list(loadout, category, {}, "Edit weapons of the " .. category .. " category")
    end
end
regen_menu()

util.yield(1000)--testing has shown: needs a small delay.. ok then, but that should finally work for people directly loading into online
if do_autoload then
    load_loadout:trigger()
end

---------------------
---------------------
-- Sonstiges
---------------------
---------------------

local ingame_konsole = menu.list(sonstiges, "Ingame Konsole", {}, "")
    menu.divider(ingame_konsole, "Athego's Script - Ingame Konsole")

--menu.action(ingame_konsole, "Output in Zwischenablage", {}, "Copy the full, untrimmed last x lines of the STDOUT to clipboard.", function()
--    util.copy_to_clipboard(full_stdout, true)
--end)

menu.slider(ingame_konsole, "Maximale Zeichenanzahl", {}, "", 1, 1000, 200, 1, function(s)
    max_chars = s
end)

menu.slider(ingame_konsole, "Maximal angezeigte Zeilen", {}, "", 1, 60, 20, 1, function(s)
    max_lines = s
end)

menu.slider_float(ingame_konsole, "Schriftgröße", {}, "", 1, 1000, 35, 1, function(s)
    font_size = s*0.01
end)

menu.toggle(ingame_konsole, "Zeitstempel", {"konsolezeitstempel"}, "", function(on)
    timestamp_toggle = on
end, false)

draw_toggle = false
menu.toggle(ingame_konsole, "Konsole einblenden", {"konsoleeinblenden"}, "", function(on)
    draw_toggle = on
end, false)

menu.colour(ingame_konsole, "Text Farbe", {}, "", 1, 1, 1, 1, true, function(on_change)
    text_color = on_change
end)

menu.colour(ingame_konsole, "Hintergrund Farbe", {}, "", 0, 0, 0, 0.5, true, function(on_change)
    bg_color = on_change
end)

util.create_tick_handler(function()
    local text = get_last_lines(log_dir)
    if draw_toggle then
        local size_x, size_y = directx.get_text_size(disp_stdout, font_size)
        size_x += 0.01
        size_y += 0.01
        directx.draw_rect(0.0, 0.06, size_x, size_y, bg_color)
        directx.draw_text(0.0, 0.06, disp_stdout, 0, font_size, text_color, true)
    end
end)

---------------------
---------------------
-- Spieler Liste
---------------------
---------------------

local function player(pid)
    menu.divider(menu.player_root(pid), "Athego's Script")

    ---------------------
    ---------------------
    -- Spieler Liste/Anti Modder
    ---------------------
    ---------------------

    local friendly = menu.list(menu.player_root(pid), "Athego's Script: Freundlich", {}, "")
        menu.divider(friendly, "Freundlich")

    ---------------------
    ---------------------
    -- Spieler Liste/Anti Modder
    ---------------------
    ---------------------

    local anti_modder = menu.list(menu.player_root(pid), "Athego's Script: Anti Modder", {}, "")
        menu.divider(anti_modder, "Anti-Modder")

    player_toggle_loop(anti_modder, pid, "Entferne Godmode", {}, "Wird von den meisten Menüs gegblockt", function()
        util.trigger_script_event(1 << pid, {0xAD36AA57, pid, 0x96EDB12F, math.random(0, 0x270F)})
    end)

    player_toggle_loop(anti_modder, pid, "Entferne Fahrzeug Godmode", {}, "Wird von den meisten Menüs gegblockt", function()
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        if PED.IS_PED_IN_ANY_VEHICLE(ped, false) and not PED.IS_PED_DEAD_OR_DYING(ped) then
            local veh = PED.GET_VEHICLE_PED_IS_IN(ped, false)
            ENTITY.SET_ENTITY_CAN_BE_DAMAGED(veh, true)
            ENTITY.SET_ENTITY_INVINCIBLE(veh, false)
            ENTITY.SET_ENTITY_PROOFS(veh, false, false, false, false, false, 0, 0, false)
        end
    end)

    ---------------------
    ---------------------
    -- Spieler Liste/Anti Modder/Kill Godmode
    ---------------------
    ---------------------

    local kill_godmode = menu.list(anti_modder, "Töte Godmode Spieler", {}, "")
        menu.divider(kill_godmode, "Töte Godmode Spieler")

    player_toggle_loop(kill_godmode, pid, "Stun", {}, "Funktioniert bei Menüs, die Proofs für den Godmode verwenden", function()
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local pos = ENTITY.GET_ENTITY_COORDS(ped)
        MISC.SHOOT_SINGLE_BULLET_BETWEEN_COORDS(pos.x, pos.y, pos.z + 1, pos.x, pos.y, pos.z, 99999, true, util.joaat("weapon_stungun"), players.user_ped(), false, true, 1.0)
    end)

    menu.slider_text(kill_godmode, "Zerdrücken", {}, "", {"Khanjali", "APC"}, function(index, veh)
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local pos = ENTITY.GET_ENTITY_COORDS(ped)
        local vehicle = util.joaat(veh)
        request_model(vehicle)

        pluto_switch veh do
            case "Khanjali":
            height = 2.8
            offset = 0
            break
            case "APC":
            height = 3.4
            offset = -1.5
            break
        end

        if TASK.IS_PED_STILL(ped) then
            distance = 0
        elseif not TASK.IS_PED_STILL(ped) then
            distance = 3
        end

        local vehicle1 = entities.create_vehicle(vehicle, ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(ped, offset, distance, height), ENTITY.GET_ENTITY_HEADING(ped))
        local vehicle2 = entities.create_vehicle(vehicle, pos, 0)
        local vehicle3 = entities.create_vehicle(vehicle, pos, 0)
        local vehicle4 = entities.create_vehicle(vehicle, pos, 0)
        local spawned_vehs = {vehicle4, vehicle3, vehicle2, vehicle1}
        ENTITY.ATTACH_ENTITY_TO_ENTITY(vehicle2, vehicle1, 0, 0, 3, 0, 0, 0, -180, 0, false, true, false, 0, true)
        ENTITY.ATTACH_ENTITY_TO_ENTITY(vehicle3, vehicle1, 0, 3, 3, 0, 0, 0, -180, 0, false, true, false, 0, true)
        ENTITY.ATTACH_ENTITY_TO_ENTITY(vehicle4, vehicle1, 0, 3, 0, 0, 0, 0, 0, 0, false, true, false, 0, true)
        ENTITY.SET_ENTITY_VISIBLE(vehicle1, false)
        util.yield(5000)
        for i = 1, #spawned_vehs do
            entities.delete_by_handle(spawned_vehs[i])
        end
    end)

    -- player_toggle_loop(kill_godmode, pid, "Explodieren", {}, "Wird von den meisten Menüs gegblockt", function()
    --     local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
    --     local pos = ENTITY.GET_ENTITY_COORDS(ped)
    --     if not PED.IS_PED_DEAD_OR_DYING(ped) and not NETWORK.NETWORK_IS_PLAYER_FADING(pid) then
    --         util.trigger_script_event(1 << pid, {0xAD36AA57, pid, 0x96EDB12F, math.random(0, 0x270F)})
    --         FIRE.ADD_OWNED_EXPLOSION(players.user_ped(), pos, 2, 50, true, false, 0.0)
    --     end
    -- end)



end

players.on_join(player)
players.dispatch_on_join()

---------------------
---------------------
-- Funktion das das Script weiter läuft
---------------------
---------------------

util.keep_running()

---------------------
---------------------
-- While schleife für autoload des Loadouts -- Muss ganz unten stehen da sonst anderer Code nicht funktioniert
---------------------
---------------------

while true do
    if NETWORK.NETWORK_IS_IN_SESSION() == false then
        while NETWORK.NETWORK_IS_IN_SESSION() == false or util.is_session_transition_active() do
            util.yield(1000)
        end
        util.yield(1000)
        -- people didn't like the long loading time, but weapons/attachments don't seem to properly get deleted and loaded directly on spawn. So we'll just wait for them to do their first step
		spawnpos = players.get_position(players.user())
        repeat
            local pos = players.get_position(players.user())
            util.yield(500)
        until spawnpos.x ~= pos.x and spawnpos.y ~= pos.y
        if do_autoload then
            load_loadout:trigger()
        else
            regen_menu()
        end
    end
    util.yield(100)
end