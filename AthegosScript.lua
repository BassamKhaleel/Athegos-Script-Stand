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
sversion = tonumber(0.13)                                           --Aktuelle Script Version
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
-- functions für Entity Controll
---------------------
---------------------

local function BlockSyncs(pid, callback)
    for _, i in ipairs(players.list(false, true, true)) do
        if i ~= pid then
            local outSync = menu.ref_by_rel_path(menu.player_root(i), "Outgoing Syncs>Block")
            menu.trigger_command(outSync, "on")
        end
    end
    util.yield(10)
    callback()
    for _, i in ipairs(players.list(false, true, true)) do
        if i ~= pid then
            local outSync = menu.ref_by_rel_path(menu.player_root(i), "Outgoing Syncs>Block")
            menu.trigger_command(outSync, "off")
        end
    end
end

local function set_entity_face_entity(entity, target, usePitch)
    local pos1 = ENTITY.GET_ENTITY_COORDS(entity, false)
    local pos2 = ENTITY.GET_ENTITY_COORDS(target, false)
    local rel = v3.new(pos2)
    rel:sub(pos1)
    local rot = rel:toRot()
    if not usePitch then
        ENTITY.SET_ENTITY_HEADING(entity, rot.z)
    else
        ENTITY.SET_ENTITY_ROTATION(entity, rot.x, rot.y, rot.z, 2, 0)
    end
end

local function request_control_of_entity(ent)
    if not NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(ent) and util.is_session_started() then
        local netid = NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(ent)
        NETWORK.SET_NETWORK_ID_CAN_MIGRATE(netid, true)
        local st_time = os.time()
        while not NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(ent) do
            -- intentionally silently fail, otherwise we are gonna spam the everloving shit out of the user
            if os.time() - st_time >= 5 then
                util.log("Failed to request entity control in 5 seconds (entity " .. ent .. ")")
                break
            end
            NETWORK.NETWORK_REQUEST_CONTROL_OF_ENTITY(ent)
            util.yield()
        end
    end
end

local function request_control_of_entity_once(ent)
    if not NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(ent) and util.is_session_started() then
        local netid = NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(ent)
        NETWORK.SET_NETWORK_ID_CAN_MIGRATE(netid, true)
        NETWORK.NETWORK_REQUEST_CONTROL_OF_ENTITY(ent)
    end
end

local function request_model_load(hash)
    request_time = os.time()
    if not STREAMING.IS_MODEL_VALID(hash) then
        return
    end
    STREAMING.REQUEST_MODEL(hash)
    while not STREAMING.HAS_MODEL_LOADED(hash) do
        if os.time() - request_time >= 10 then
            break
        end
        util.yield()
    end
end

local function ram_ped_with(ped, vehicle, offset, sog)
    request_model_load(vehicle)
    local front = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(ped, 0.0, offset, 0.0)
    local veh = entities.create_vehicle(vehicle, front, ENTITY.GET_ENTITY_HEADING(ped)+180)
    set_entity_face_entity(veh, ped, true)
    if ram_onground then
        OBJECT.PLACE_OBJECT_ON_GROUND_PROPERLY(veh)
    end
    VEHICLE.SET_VEHICLE_ENGINE_ON(veh, true, true, true)
    VEHICLE.SET_VEHICLE_FORWARD_SPEED(veh, 100.0)
end

function mod_uses(type, incr)
    -- this func is a patch. every time the script loads, all the toggles load and set their state. in some cases this makes the _uses optimization negative and breaks things. this prevents that.
    if incr < 0 and is_loading then
        -- ignore if script is still loading
        return
    end
    if type == "vehicle" then
        if vehicle_uses <= 0 and incr < 0 then
            return
        end
        vehicle_uses = vehicle_uses + incr
    elseif type == "pickup" then
        if pickup_uses <= 0 and incr < 0 then
            return
        end
        pickup_uses = pickup_uses + incr
    elseif type == "ped" then
        if ped_uses <= 0 and incr < 0 then
            return
        end
        ped_uses = ped_uses + incr
    elseif type == "player" then
        if player_uses <= 0 and incr < 0 then
            return
        end
        player_uses = player_uses + incr
    elseif type == "object" then
        if object_uses <= 0 and incr < 0 then
            return
        end
        object_uses = object_uses + incr
    end
end

local function IsPlayerUsingOrbitalCannon(player)
    return BitTest(memory.read_int(memory.script_global((2657589 + (player * 466 + 1) + 427))), 0) -- Global_2657589[PLAYER::PLAYER_ID() /*466*/].f_427), 0
end

---------------------
---------------------
-- functions für Farhzeug Mods
---------------------
---------------------

local function kick_from_veh(pid)
    menu.trigger_commands("vehkick" .. players.get_name(pid))
end

local function npc_jack(target, nearest)
    npc_jackthr = util.create_thread(function(thr)
        local player_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(target)
        local last_veh = PED.GET_VEHICLE_PED_IS_IN(player_ped, true)
        kick_from_veh(target)
        local st = os.time()
        while not VEHICLE.IS_VEHICLE_SEAT_FREE(last_veh, -1) do 
            if os.time() - st >= 10 then
                notify(translations.failed_to_free_seat)
                util.stop_thread()
            end
            util.yield()
        end
        local hash = 0x9C9EFFD8
        request_model_load(hash)
        local coords = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(player_ped, -2.0, 0.0, 0.0)
        local ped = entities.create_ped(28, hash, coords, 30.0)
        ENTITY.SET_ENTITY_INVINCIBLE(ped, true)
        PED.SET_BLOCKING_OF_NON_TEMPORARY_EVENTS(ped, true)
        PED.SET_PED_FLEE_ATTRIBUTES(ped, 0, false)
        PED.SET_PED_COMBAT_ATTRIBUTES(ped, 46, true)
        PED.SET_PED_INTO_VEHICLE(ped, last_veh, -1)
        VEHICLE.SET_VEHICLE_ENGINE_ON(last_veh, true, true, false)
        TASK.TASK_VEHICLE_DRIVE_TO_COORD(ped, last_veh, math.random(1000), math.random(1000), math.random(100), 100, 1, ENTITY.GET_ENTITY_MODEL(last_veh), 786996, 5, 0)
        util.stop_thread()
    end)
end

function Vmod(vmod, plate)
    VEHICLE.SET_VEHICLE_FIXED(vmod)
    for M=0, 49 do
        local modn = VEHICLE.GET_NUM_VEHICLE_MODS(vmod, M)
        VEHICLE.SET_VEHICLE_MOD(vmod, M, modn -1, false)
        VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vmod, plate)
        VEHICLE.GET_VEHICLE_MOD_KIT(vmod, 0)
        VEHICLE.SET_VEHICLE_MOD_KIT(vmod, 0)
        VEHICLE.SET_VEHICLE_MOD(vmod, 14, 0)
        VEHICLE.TOGGLE_VEHICLE_MOD(vmod, 22, true)
        VEHICLE.TOGGLE_VEHICLE_MOD(vmod, 18, true)
        VEHICLE.TOGGLE_VEHICLE_MOD(vmod, 20, true)
        VEHICLE.SET_VEHICLE_TYRE_SMOKE_COLOR(vmod, 0, 0, 0)
        VEHICLE.SET_VEHICLE_MAX_SPEED(vmod, 100)
        VEHICLE.MODIFY_VEHICLE_TOP_SPEED(vmod, 40)
        VEHICLE.SET_VEHICLE_BURNOUT(vmod, false)
    end
end

local function tp_player_car_to_coords(pid, coord)
    local name = players.get_name(pid)
    local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
    if car ~= 0 then
        request_control_of_entity(car)
        if NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(car) then
            for i=1, 3 do
                ENTITY.SET_ENTITY_COORDS_NO_OFFSET(car, coord['x'], coord['y'], coord['z'], false, false, false)
            end
        end
    end
end

function GetControl(vic, spec, pid)
    if pid == playerid then
        return
    end    
    if not players.exists(pid) then
        util.stop_thread()
    end
    local tick = 0
    NETWORK.NETWORK_REQUEST_CONTROL_OF_ENTITY(vic)
    while not NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(vic) do
        local nid = NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(vic)
        NETWORK.SET_NETWORK_ID_CAN_MIGRATE(nid, true)
        NETWORK.NETWORK_REQUEST_CONTROL_OF_ENTITY(vic)
        util.yield()
        tick =  tick + 1
        if tick > 10 then
            if not NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(vic) then
                util.toast(sprefix .. ' Konnte keine Kontrolle erlangen')
                util.log(sprefix .. ' Konnte keine Kontrolle erlangen')
                if not spec then
                    Specoff(pid)
                end
                util.stop_thread()
            end
        
        end
    end


end

local function get_ground_z(coords)
    local start_time = os.time()
    while true do
        if os.time() - start_time >= 5 then
            util.log("Failed to get ground Z in 5 seconds.")
            return nil
        end
        local success, est = util.get_ground_z(coords['x'], coords['y'], coords['z']+2000)
        if success then
            return est
        end
        util.yield()
    end
end

local function get_waypoint_coords()
    local coords = HUD.GET_BLIP_COORDS(HUD.GET_FIRST_BLIP_INFO_ID(8))
    if coords['x'] == 0 and coords['y'] == 0 and coords['z'] == 0 then
        return nil
    else
        local estimate = get_ground_z(coords)
        if estimate then
            coords['z'] = estimate
        end
        return coords
    end
end

function Disbet(pid)
    local targets = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
    local tar1 = ENTITY.GET_ENTITY_COORDS(targets, true)
    local play = ENTITY.GET_ENTITY_COORDS(playerped, true)
    local disbet = SYSTEM.VDIST2(play.x, play.y, play.z, tar1.x, tar1.y, tar1.z)
    return disbet
end

function GetPlayVeh(pid, opt)

    local pedm = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
    if not players.exists(pid) then
        util.stop_thread()
    end
    local spec = menu.get_value(menu.ref_by_rel_path(menu.player_root(pid), "Spectate>Ninja Method"))
    util.toast(sprefix .. ' Versuche Kontrolle über das Fahrzeug zu erhalten')
    util.log(sprefix .. ' Versuche Kontrolle über das Fahrzeug zu erhalten')
    if Disbet(pid) > 750000  then
        Specon(pid)
    if PED.IS_PED_IN_ANY_VEHICLE(pedm, true) then
        opt()
        if not spec then
            Specoff(pid)
        end
        return
    else
        util.toast(sprefix .. ' Spieler ist nicht im Fahrzeug')
        util.log(sprefix .. ' Spieler ist nicht im Fahrzeug')
        Specoff(pid)
    end
    elseif Disbet(pid) < 750000 then
        if PED.IS_PED_IN_ANY_VEHICLE(pedm, true) then
            opt()
            if not spec then
                Specoff(pid)
            end
        return
        end
    else
        util.toast(sprefix .. ' Spieler ist nicht im Fahrzeug')
        util.log(sprefix .. ' Spieler ist nicht im Fahrzeug')
    end
end

function Specon(pid)
    menu.trigger_commands("spectate".. players.get_name(pid).. ' on')
    util.yield(3000)
end

function Specoff(pid)
    menu.trigger_commands("spectate".. players.get_name(pid).. ' off')
end

function Maxoutcar(pid)
    local pedm = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
    local spec = menu.get_value(menu.ref_by_rel_path(menu.player_root(pid), "Spectate>Ninja Method"))
    local vmod = PED.GET_VEHICLE_PED_IS_IN(pedm, false)
    GetControl(vmod, spec, pid)
     Vmod(vmod, "Enjoy")
     VEHICLE.SET_VEHICLE_WHEEL_TYPE(vmod, math.random(0, 7))
     VEHICLE.SET_VEHICLE_MOD(vmod, 23, math.random(-1, 50))
     ENTITY.SET_ENTITY_INVINCIBLE(vmod, true)
     util.toast(sprefix .. ' Fahrzeug vollständig geupgradet')
     util.log(sprefix .. ' Fahrzeug vollständig geupgradet')
end

function Platechange(cusplate, pid)
    local pedm = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
    local spec = menu.get_value(menu.ref_by_rel_path(menu.player_root(pid), "Spectate>Ninja Method"))
    local vmod = PED.GET_VEHICLE_PED_IS_IN(pedm, false)
    GetControl(vmod, spec, pid)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vmod, cusplate)
    util.toast(sprefix .. ' Nummernschild geändert')
    util.log(sprefix .. ' Nummernschild geändert')
end

function Fixveh(pid)
    local pedm = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
    local spec = menu.get_value(menu.ref_by_rel_path(menu.player_root(pid), "Spectate>Ninja Method"))
    local vmod = PED.GET_VEHICLE_PED_IS_IN(pedm, false)
    GetControl(vmod, spec, pid)
    VEHICLE.SET_VEHICLE_FIXED(vmod)
    util.toast(sprefix .. ' Fahrzeug repariert')
    util.log(sprefix .. ' Fahrzeug repariert')
end

function Accelveh( speed, pid)
    local pedm = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
    local spec = menu.get_value(menu.ref_by_rel_path(menu.player_root(pid), "Spectate>Ninja Method"))
    local vmod = PED.GET_VEHICLE_PED_IS_IN(pedm, false)
    GetControl(vmod, spec, pid)
    VEHICLE.SET_VEHICLE_FORWARD_SPEED(vmod, speed)
    util.toast(sprefix .. ' Fahrzeug beschleunigt')
    util.log(sprefix .. ' Fahrzeug beschleunigt')
end

function Stopveh(pid)
    local pedm = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
    local spec = menu.get_value(menu.ref_by_rel_path(menu.player_root(pid), "Spectate>Ninja Method"))
    local vmod = PED.GET_VEHICLE_PED_IS_IN(pedm, false)
    GetControl(vmod, spec, pid)
    VEHICLE.SET_VEHICLE_FORWARD_SPEED(vmod, -1000)
    ENTITY.SET_ENTITY_VELOCITY(vmod, 0, 0, 0)
    VEHICLE.SET_VEHICLE_ENGINE_ON(vmod, false, false, false)
    util.toast(sprefix .. ' Fahrzeug abbremsen')
    util.log(sprefix .. ' Fahrzeug abbremsen')
end

---------------------
---------------------
-- functions zum claimen von zerstörten Autos bei Mors Mutual Insurance
---------------------
---------------------

local function clearBit(addr, bitIndex)
    memory.write_int(addr, memory.read_int(addr) & ~(1<<bitIndex))
end

local function bitTest(addr, offset)
    return (memory.read_int(addr) & (1 << offset)) ~= 0
end

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
    "virtue",
    "powersurge",
    "broadway",
    "panthere",
    "issi8",
    "everon2",
    "eudora",
    "boor"
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
-- Script neuladen
---------------------
---------------------

menu.action(menu.my_root(), 'Script neuladen', {}, 'Startet das Skript neu, um nach Updates zu suchen', function ()
    util.restart_script()
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
local fahrzeuge <const> = menu.list(menu.my_root(), "Fahrzeuge", {}, "")
    menu.divider(fahrzeuge, "Athego's Script - Fahrzeuge")
local loadout <const> = menu.list(menu.my_root(), "Loadout", {}, "")
    menu.divider(loadout, "Athego's Script - Loadout")
local sonstiges <const> = menu.list(menu.my_root(), "Sonstiges", {}, "")
    menu.divider(sonstiges, "Athego's Script - Sonstiges")

---------------------
---------------------
-- Selbst
---------------------
---------------------

---------------------
---------------------
-- Selbst
---------------------
---------------------

---------------------
---------------------
-- Selbst/Unlocks
---------------------
---------------------

local unlocks = menu.list(self, "Freischalten")

menu.toggle_loop(unlocks, "50 Auto-Garage", {}, "", function()
    if memory.read_byte(memory.script_global(262145 + 32688)) ~= 0 then-- thx aero for this global <3
        memory.write_byte(memory.script_global(262145 + 32688), 0) 
    end

    if memory.read_byte(memory.script_global(262145 + 32702)) ~= 1 then
        memory.write_byte(memory.script_global(262145 + 32702), 1)  
    end
end)

menu.action(unlocks, "Drug Wars Inhalt", {}, "", function()
    for i = 33974, 34112, 1 do
        memory.write_byte(memory.script_global(262145 + i), 1)  
    end
end)

menu.action(unlocks, "Weihnachts- und Neujahrsgeschenke", {}, "Wechseln Sie die Sitzungen für die zu vergebenden Geschenke.", function()
    memory.write_byte(memory.script_global(262145 + 33915), 1)  
    memory.write_byte(memory.script_global(262145 + 33916), 1)  
end)

---------------------
---------------------
-- Selbst/Anti-Orbital
---------------------
---------------------

local orb = menu.list(self, "Anti-Orbital Kanone")

ghost_tgl = menu.toggle_loop(orb, "Geist", {""}, "Die Spieler, die die Orbitalkanone benutzen, werden automatisch ausgeblendet.", function()
    for _, pid in ipairs(players.list(false, true, true)) do
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        if IsPlayerUsingOrbitalCannon(pid) and TASK.GET_IS_TASK_ACTIVE(ped, 135) 
        and v3.distance(ENTITY.GET_ENTITY_COORDS(players.user_ped(), false), cam_pos) > 300 
        and v3.distance(ENTITY.GET_ENTITY_COORDS(players.user_ped(), false), cam_pos) < 400 then
            util.toast(players.get_name(pid) .. " zielt mit der Orbitalkanone auf dich.")
        end
       if IsPlayerUsingOrbitalCannon(pid) then
            NETWORK.SET_REMOTE_PLAYER_AS_GHOST(pid, true)
        else
            NETWORK.SET_REMOTE_PLAYER_AS_GHOST(pid, false)
        end
    end
end, function()
    for _, pid in ipairs(players.list(false, true, true)) do
        NETWORK.SET_REMOTE_PLAYER_AS_GHOST(pid, false)
    end
end)

local annoy = menu.list(orb, "Verärgern", {}, "Zeigt und entfernt Ihren Namen schnell aus der Liste der angreifbaren Spieler.")
local orb_delay = 1000
menu.list_select(annoy, "Verzögerung", {}, "Die Geschwindigkeit, mit der Ihr Name bei Nutzern von Orbitalkanonen flackert.", {"Langsam", "Mittel", "Schnell"}, 1, function(index, value)
switch value do
    case "Langsam":
        orb_delay = 1000
        break
    case "Mittel":
        orb_delay = 500
        break
    case "Schnell":
        orb_delay = 100
        break
    end
end)

local annoy_tgl
annoy_tgl = menu.toggle_loop(annoy, "Aktivieren", {}, "", function()
    if menu.get_value(ghost_tgl) then
        menu.set_value(annoy_tgl, false)
        util.toast("Bitte aktiviere nicht gleichzeitig Verärgern und Geist")
    return end
    
    for _, pid in ipairs(players.list(false, true, true)) do
       if IsPlayerUsingOrbitalCannon(pid) then
            NETWORK.SET_REMOTE_PLAYER_AS_GHOST(pid, true)
            util.yield(orb_delay)
            NETWORK.SET_REMOTE_PLAYER_AS_GHOST(pid, false)
            util.yield(orb_delay)
        else
            NETWORK.SET_REMOTE_PLAYER_AS_GHOST(pid, false)
        end
    end
end, function()
    for _, pid in ipairs(players.list(false, true, true)) do
        NETWORK.SET_REMOTE_PLAYER_AS_GHOST(pid, false)
    end
end)

---------------------
---------------------
-- Selbst
---------------------
---------------------

menu.toggle_loop(self, "Beitretende Spiele Automatisch annehmen", {}, "Automatische Annahme der Beitrittsbildschirme", function()
    local message_hash = HUD.GET_WARNING_SCREEN_MESSAGE_HASH()
    if message_hash == 15890625 or message_hash == -398982408 or message_hash == -587688989 then
        PAD.SET_CONTROL_VALUE_NEXT_FRAME(2, 201, 1.0)
        util.yield(50)
    end
end)

menu.toggle(self, "Leiser Schritt", {}, "Entfernt die Geräusche die du beim gehen machst", function (toggle)
    AUDIO.SET_PED_FOOTSTEPS_EVENTS_ENABLED(players.user_ped(), not toggle)
end)

local roll_speed = nil
menu.list_select(self, "Roll-Geschwindigkeit", {}, "", {"Standard", "1.25x", "1.5x", "1.75x", "2x"}, 1, function(index, value)
roll_speed = index
util.create_tick_handler(function()
    switch value do
        case "1.25x":
            STATS.STAT_SET_INT(util.joaat("MP"..util.get_char_slot().."_SHOOTING_ABILITY"), 115, true)
            break
        case "1.5x":
            STATS.STAT_SET_INT(util.joaat("MP"..util.get_char_slot().."_SHOOTING_ABILITY"), 125, true)
            break
        case "1.75x":
            STATS.STAT_SET_INT(util.joaat("MP"..util.get_char_slot().."_SHOOTING_ABILITY"), 135, true)
            break
        case "2x":
            STATS.STAT_SET_INT(util.joaat("MP"..util.get_char_slot().."_SHOOTING_ABILITY"), 150, true)
            break
        end
        return roll_speed == index
    end)
end)

local climb_speed = nil
menu.list_select(self, "Kletter-Geschwindigkeit", {}, "", {"Standard", "1.25x", "1.5x", "2x",}, 1, function(index, value)
climb_speed = index
util.create_tick_handler(function()
    if TASK.GET_IS_TASK_ACTIVE(players.user_ped(), 1) then
        switch value do
            case "1.25x":
                PED.FORCE_PED_AI_AND_ANIMATION_UPDATE(players.user_ped())
                util.yield(150)
                break
            case "1.5x":
                PED.FORCE_PED_AI_AND_ANIMATION_UPDATE(players.user_ped())
                util.yield(75)
                break
            case "2x":
                PED.FORCE_PED_AI_AND_ANIMATION_UPDATE(players.user_ped())
                util.yield(50)
                break
            end
        end
        return climb_speed == index
    end)
end)

menu.action(self, "Explodiere selbst", {}, "", function()
	local pos = ENTITY.GET_ENTITY_COORDS(players.user_ped(), false)
	pos.z = pos.z - 1.0
	FIRE.ADD_OWNED_EXPLOSION(players.user_ped(), pos.x, pos.y, pos.z, 0, 1.0, true, false, 1.0)
end)

---------------------
---------------------
-- Farhzeug
---------------------
---------------------

local seat_id = -1
local moved_seat = menu.click_slider(fahrzeuge, "Sitz wechseln", {}, "", 1, 1, 1, 1, function(seat_id)
    TASK.TASK_WARP_PED_INTO_VEHICLE(players.user_ped(), entities.get_user_vehicle_as_handle(), seat_id - 2)
end)

menu.on_tick_in_viewport(moved_seat, function()
    if not PED.IS_PED_IN_ANY_VEHICLE(players.user_ped(), false) then
        moved_seat.max_value = 0
    return end

    if not PED.IS_PED_IN_ANY_VEHICLE(players.user_ped(), false) then
        moved_seat.max_value = 0
    return end
    
    moved_seat.max_value = VEHICLE.GET_VEHICLE_MODEL_NUMBER_OF_SEATS(ENTITY.GET_ENTITY_MODEL(entities.get_user_vehicle_as_handle()))
end)

menu.toggle_loop(fahrzeuge, "Schnelles Hotwire", {""}, "", function()
    if not VEHICLE.GET_IS_VEHICLE_ENGINE_RUNNING(entities.get_user_vehicle_as_handle()) and TASK.GET_IS_TASK_ACTIVE(players.user_ped(), 150) then
        PED.FORCE_PED_AI_AND_ANIMATION_UPDATE(players.user_ped())
    end
end)

menu.toggle_loop(fahrzeuge, "Schneller einsteigen", {""}, "Fahrzeuge schneller betreten.", function()
    if (TASK.GET_IS_TASK_ACTIVE(players.user_ped(), 160) or TASK.GET_IS_TASK_ACTIVE(players.user_ped(), 167) or TASK.GET_IS_TASK_ACTIVE(players.user_ped(), 165)) and not TASK.GET_IS_TASK_ACTIVE(players.user_ped(), 195) then
        PED.FORCE_PED_AI_AND_ANIMATION_UPDATE(players.user_ped())
    end
end)

menu.toggle_loop(fahrzeuge, "Godmode beim Verlassen deaktivieren", {""}, "", function()
    if not ENTITY.GET_ENTITY_CAN_BE_DAMAGED(entities.get_user_vehicle_as_handle()) then
        if not PED.IS_PED_IN_ANY_VEHICLE(players.user_ped(), false) then
            ENTITY.SET_ENTITY_CAN_BE_DAMAGED(PED.GET_VEHICLE_PED_IS_IN(players.user_ped(), true), true)
        end
    end
end)

menu.toggle_loop(fahrzeuge, "Wheelie-Start", {}, "Drücke Strg und W zum Wheelie.", function(toggled)
    local veh = entities.get_user_vehicle_as_handle()
    if veh == 0 then return end
    local CAutomobile = entities.handle_to_pointer(veh)
    local CHandlingData = memory.read_long(CAutomobile + 0x0918)
    if util.is_key_down(0x57) and util.is_key_down(0x11) then 
       memory.write_float(CHandlingData + 0x00EC, -0.25)
    else
       memory.write_float(CHandlingData + 0x00EC, 0.5)
    end
end)

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

    menu.toggle_loop(detections, "Godmode", {}, "Detects if someone is using godmode.", function()
        for _, pid in ipairs(players.list(false, true, true)) do
            local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
            local pos = ENTITY.GET_ENTITY_COORDS(ped, false)
            for i, interior in ipairs(interior_stuff) do
                if players.is_godmode(pid) and not NETWORK.NETWORK_IS_PLAYER_FADING(pid) and ENTITY.IS_ENTITY_VISIBLE(ped) and get_spawn_state(pid) == 99 and get_interior_player_is_in(pid) == interior then
                util.toast(sprefix .. " " .. players.get_name(pid) .. " benutzt Godmode")
                util.log(sprefix .. " " .. players.get_name(pid) .. " benutzt Godmode")
                break
            end
        end
    end
end)

menu.toggle_loop(detections, "Fahrzeug Godmode", {}, "Erkennt ob jemand Fahrzeug Godmode benutzt", function()
    for _, pid in ipairs(players.list(false, true, true)) do
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local pos = ENTITY.GET_ENTITY_COORDS(ped, false)
        local player_veh = PED.GET_VEHICLE_PED_IS_USING(ped)
        if PED.IS_PED_IN_ANY_VEHICLE(ped, false) then
            for i, interior in ipairs(interior_stuff) do
                if not ENTITY.GET_ENTITY_CAN_BE_DAMAGED(player_veh) and (not NETWORK.NETWORK_IS_PLAYER_FADING(pid) and ENTITY.IS_ENTITY_VISIBLE(ped)) and get_transition_state(pid) == 99 and get_interior_player_is_in(pid) == interior then
                    util.draw_debug_text(sprefix .. " " .. players.get_name(pid) .. " benutzt Vehicle Godmode")
                    util.toast(sprefix .. " " .. players.get_name(pid) .. " benutzt Vehicle Godmode")
                    util.log(sprefix .. " " .. players.get_name(pid) .. " benutzt Vehicle Godmode")
                    break
                end
            end
        end
    end
end)

menu.toggle_loop(detections, "Nicht veröffentliches Fahrzeug", {}, "Erkennt ob jemand ein Fahrzeug benutzt welches noch nicht veröffentlicht wurde", function()
    for _, pid in ipairs(players.list(false, true, true)) do
        local modelHash = players.get_vehicle_model(pid)
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local vehicle = PED.GET_VEHICLE_PED_IS_USING(ped)
        local PedID = NETWORK.NETWORK_GET_PLAYER_INDEX_FROM_PED(VEHICLE.GET_PED_IN_VEHICLE_SEAT(vehicle, -1))
        for i, name in ipairs(unreleased_vehicles) do
            if modelHash == util.joaat(name) and PED.IS_PED_IN_ANY_VEHICLE(ped, false) then
                util.toast(sprefix .. " " .. players.get_name(pid) .. " fährt ein unveröffentliches Fahrzeug " .. "(" .. name .. ")")
                util.log(sprefix .. " " .. players.get_name(pid) .. " fährt ein unveröffentliches Fahrzeug " .. "(" .. name .. ")")
            end
        end
    end
end)

menu.toggle_loop(detections, "Gemoddete Waffe", {}, "Erkennt ob jemand eine Waffe benutzt die man Online nicht haben kann.", function()
    for _, pid in ipairs(players.list(false, true, true)) do
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        for i, hash in ipairs(modded_weapons) do
            local weapon_hash = util.joaat(hash)
            if WEAPON.HAS_PED_GOT_WEAPON(ped, weapon_hash, false) and (WEAPON.IS_PED_ARMED(ped, 7) or TASK.GET_IS_TASK_ACTIVE(ped, 8) or TASK.GET_IS_TASK_ACTIVE(ped, 9)) then
                util.toast(sprefix .. " " .. players.get_name(pid) .. " benutzt eine Gemoddete Waffe " .. "(" .. hash .. ")")
                util.log(sprefix .. " " .. players.get_name(pid) .. " benutzt eine Gemoddete Waffe " .. "(" .. hash .. ")")
                break
            end
        end
    end
end)

menu.toggle_loop(detections, "Gemoddetes Fahrzeug", {}, "Erkennt ob jemand ein Gemoddetes Fahrzeug benutzt", function()
    for _, pid in ipairs(players.list(false, true, true)) do
        local modelHash = players.get_vehicle_model(pid)
        for i, name in ipairs(modded_vehicles) do
            if modelHash == util.joaat(name) then
                util.toast(sprefix .. " " .. players.get_name(pid) .. " fährt ein gemoddetes Fahrzeug " .. "(" .. name .. ")")
                util.log(sprefix .. " " .. players.get_name(pid) .. " fährt ein gemoddetes Fahrzeug " .. "(" .. name .. ")")
                break
            end
        end
    end
end)

menu.toggle_loop(detections, "Noclip", {}, "Erkennt ob jemand Noclipe benutzt", function()
    for _, pid in ipairs(players.list(false, true, true)) do
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local ped_ptr = entities.handle_to_pointer(ped)
        local vehicle = PED.GET_VEHICLE_PED_IS_USING(ped)
        local oldpos = players.get_position(pid)
        util.yield()
        local currentpos = players.get_position(pid)
        local vel = ENTITY.GET_ENTITY_VELOCITY(ped)
        if not util.is_session_transition_active() and players.exists(pid)
        and get_interior_player_is_in(pid) == 0 and get_spawn_state(pid) ~= 0
        and not PED.IS_PED_IN_ANY_VEHICLE(ped, false) -- too many false positives occured when players where driving. so fuck them. lol.
        and not NETWORK.NETWORK_IS_PLAYER_FADING(pid) and ENTITY.IS_ENTITY_VISIBLE(ped) and not PED.IS_PED_DEAD_OR_DYING(ped)
        and not PED.IS_PED_CLIMBING(ped) and not PED.IS_PED_VAULTING(ped) and not PED.IS_PED_USING_SCENARIO(ped)
        and not TASK.GET_IS_TASK_ACTIVE(ped, 160) and not TASK.GET_IS_TASK_ACTIVE(ped, 2)
        and v3.distance(ENTITY.GET_ENTITY_COORDS(players.user_ped(), false), players.get_position(pid)) <= 395.0 -- 400 was causing false positives
        and ENTITY.GET_ENTITY_HEIGHT_ABOVE_GROUND(ped) > 5.0 and not ENTITY.IS_ENTITY_IN_AIR(ped) and entities.player_info_get_game_state(ped_ptr) == 0
        and oldpos.x ~= currentpos.x and oldpos.y ~= currentpos.y and oldpos.z ~= currentpos.z 
        and vel.x == 0.0 and vel.y == 0.0 and vel.z == 0.0 then
            util.toast(sprefix .. " " .. players.get_name(pid) .. " benutzt Noclip")
            util.log(sprefix .. " " .. players.get_name(pid) .. " benutzt Noclip")
            break
        end
    end
end)

menu.toggle_loop(detections, "Super Drive", {}, "Erkennt ob jemand Super Drive benutzt.", function()
    for _, pid in ipairs(players.list(false, true, true)) do
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local vehicle = PED.GET_VEHICLE_PED_IS_USING(ped)
        local veh_speed = (ENTITY.GET_ENTITY_SPEED(vehicle)* 2.236936)
        local class = VEHICLE.GET_VEHICLE_CLASS(vehicle)
        if class ~= 15 and class ~= 16 and veh_speed >= 200 and VEHICLE.GET_PED_IN_VEHICLE_SEAT(vehicle, -1) and (players.get_vehicle_model(pid) ~= util.joaat("oppressor") or players.get_vehicle_model(pid) ~= util.joaat("oppressor2")) then
            util.toast(sprefix .. " " .. players.get_name(pid) .. " benutzt Super Drive")
            util.log(sprefix .. " " .. players.get_name(pid) .. " benutzt Super Drive")
            break
        end
    end
end)

menu.toggle_loop(detections, "Zuschauen", {}, "Erkennt ob dir jemand zuguckt.", function()
    for _, pid in ipairs(players.list(false, true, true)) do
        for i, interior in ipairs(interior_stuff) do
            local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
            if not util.is_session_transition_active() and get_spawn_state(pid) ~= 0 and get_interior_player_is_in(pid) == interior
            and not NETWORK.NETWORK_IS_PLAYER_FADING(pid) and ENTITY.IS_ENTITY_VISIBLE(ped) and not PED.IS_PED_DEAD_OR_DYING(ped) then
                if v3.distance(ENTITY.GET_ENTITY_COORDS(players.user_ped(), false), players.get_cam_pos(pid)) < 15.0 and v3.distance(ENTITY.GET_ENTITY_COORDS(players.user_ped(), false), players.get_position(pid)) > 20.0 then
                    util.toast(sprefix .. " " .. players.get_name(pid) .. " schaut dir zu")
                    util.log(sprefix .. " " .. players.get_name(pid) .. " schaut dir zu")
                    break
                end
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

menu.toggle_loop(protections, "Anti-Beast", {}, "Verhindert, dass du in die Bestie verwandelt wirst, hält aber auch das Ereignis für andere auf.", function()
    if SCRIPT.GET_NUMBER_OF_THREADS_RUNNING_THE_SCRIPT_WITH_THIS_HASH(util.joaat("am_hunt_the_beast")) > 0 then
        local host
        repeat
            host = NETWORK.NETWORK_GET_HOST_OF_SCRIPT("am_hunt_the_beast", -1, 0)
            util.yield()
        until host ~= -1
        util.toast(sprefix .. " " .. players.get_name(host) .. " hat Hunt The Beast gestartet. Beende es...")
        util.log(sprefix .. " " .. players.get_name(host) .. " hat Hunt The Beast gestartet. Beende es...")
        menu.trigger_command(menu.ref_by_path("Online>Session>Session Scripts>Hunt the Beast>Stop Script"))
    end
end)

---------------------
---------------------
-- Online
---------------------
---------------------

menu.action(online, 'Schneeballschlacht', {}, 'Gibt allen in der Lobby Schneebälle und benachrichtigt sie per SMS', function ()
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

menu.action(online, 'Silvester', {}, 'Gibt allen in der Lobby Feuerwerkskörper und benachrichtigt sie per SMS', function ()
    local plist = players.list()
    local fireworks = util.joaat('weapon_firework')
    for i = 1, #plist do
        local plyr = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(plist[i])
        WEAPON.GIVE_DELAYED_WEAPON_TO_PED(plyr, fireworks, 10, true)
        WEAPON.SET_PED_AMMO(plyr, fireworks, 20)
        players.send_sms(plist[i], playerid, 'Murica f*** ya! You now have Fireworks')
        util.yield()
    end
end)

menu.toggle_loop(online, 'Erhöhung der Kosatka Raketen Reichweite', {}, 'Du kannst sie jetzt überall auf der Karte verwenden', function ()
    if util.is_session_started() then
    memory.write_float(memory.script_global(262145 + 30176), 200000.0)
    end
end)

menu.toggle_loop(online, "Kopfgeld automatisch entfernen", {}, "", function()
    if util.is_session_started() then
        if memory.read_int(memory.script_global(1835502 + 4 + 1 + (players.user() * 3))) == 1 then
            memory.write_int(memory.script_global(2815059 + 1856 + 17), -1)
            memory.write_int(memory.script_global(2359296 + 1 + 5149 + 13), 2880000)
            util.toast(sprefix .. " Removed bounty of: $" ..memory.read_int(memory.script_global(1835502 + 4 + 1 + (players.user() * 3) + 1)).. " ")
            util.log(sprefix .. " Removed bounty of: $" ..memory.read_int(memory.script_global(1835502 + 4 + 1 + (players.user() * 3) + 1)).. " ")
        end
    end
    util.yield(5000)
end)

---------------------
---------------------
-- Fahrzeuge
---------------------
---------------------



---------------------
---------------------
-- Fahrzeuge/Lazer Space Docker
---------------------
---------------------



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

protect_weapons = menu.toggle(loadout, "Meine Waffen schützen", {}, "Andere Modder daran hindern, deine Waffen zu entfernen oder dir neue zu geben\n(Sollte ausbleiben wenn du vor hast Missionen zu spielen)",
    function(on, click_type)
        local single_path = menu.ref_by_path("Online>Protections>Events>Raw Network Events>Remove Weapon Event>Block")
        local all_path = menu.ref_by_path("Online>Protections>Events>Raw Network Events>Remove All Weapons Event>Block")
        local add_path = menu.ref_by_path("Online>Protections>Events>Raw Network Events>Give Weapon Event>Block")
        if on then
            if single_path.value > 0 and all_path.value > 0 and add_path.value > 0 then
                util.toast("Die Protections sind bereits an. Du solltest sicher sein")
            else
                single_path.value = 1
                all_path.value = 1
                add_path.value = 1
            end
        else
            if click_type == 4 then return end
            single_path.value = 0
            all_path.value = 0
            add_path.value = 0
        end
    end
)

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
    -- Spieler Liste/Spieler Entfernen
    ---------------------
    ---------------------

    local spieler_entfernen = menu.list(menu.player_root(pid), "Athego's Script: Spieler Entfernen", {}, "")
        menu.divider(spieler_entfernen, "Anti-Modder")

    menu.action(spieler_entfernen, "Griefer Jesus", {}, "Nicht wirklich zuverlässig, funktioniert aber bei den meisten Menüs", function()
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
		local pos = players.get_position(pid)
		local mdl = util.joaat("u_m_m_jesus_01")
		local veh_mdl = util.joaat("oppressor")
		util.request_model(veh_mdl)
        util.request_model(mdl)
			for i = 1, 10 do
				if not players.exists(pid) then
					return
				end
				local veh = entities.create_vehicle(veh_mdl, pos, 0)
				local jesus = entities.create_ped(2, mdl, pos, 0)
				PED.SET_PED_INTO_VEHICLE(jesus, veh, -1)
				util.yield(100)
				TASK.TASK_VEHICLE_HELI_PROTECT(jesus, veh, ped, 10.0, 0, 10, 0, 0)
				util.yield(1000)
				entities.delete_by_handle(jesus)
				entities.delete_by_handle(veh)
			end
		STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(mdl)
		STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(veh_mdl)
    end)

    menu.action(spieler_entfernen, "Fragment Crash", {""}, "", function()
        BlockSyncs(pid, function()
            local object = entities.create_object(util.joaat("prop_fragtest_cnst_04"), ENTITY.GET_ENTITY_COORDS(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)))
            OBJECT.BREAK_OBJECT_FRAGMENT_CHILD(object, 1, false)
            util.yield(1000)
            entities.delete_by_handle(object)
        end)
    end)

    ---------------------
    ---------------------
    -- Spieler Liste/Freundlich
    ---------------------
    ---------------------

    local friendly = menu.list(menu.player_root(pid), "Athego's Script: Freundlich", {}, "")
        menu.divider(friendly, "Freundlich")

    local firw = {speed = 1000}
    menu.toggle_loop(friendly, 'Feuerwerkshow', {'feuerw'}, 'Zünde ein Feuerwerk am Standort des Spielers', function ()
        local targets = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local tar1 = ENTITY.GET_ENTITY_COORDS(targets, true)
        local weap = util.joaat('weapon_firework')
        WEAPON.REQUEST_WEAPON_ASSET(weap)
        FIRE.ADD_EXPLOSION(tar1.x, tar1.y, tar1.z + math.random(50, 75), 38, 1, false, false, 0, false)
        FIRE.ADD_EXPLOSION(tar1.x + math.random(-50, 50), tar1.y, tar1.z + math.random(50, 75), 38, 1, false, false, 0, false)
        FIRE.ADD_EXPLOSION(tar1.x, tar1.y + math.random(-50, 50), tar1.z + math.random(50, 75), 38, 1, false, false, 0, false)
        FIRE.ADD_EXPLOSION(tar1.x + math.random(-50, 50), tar1.y + math.random(-50, 50), tar1.z + math.random(50, 75), 38, 1, false, false, 0, false)
        FIRE.ADD_EXPLOSION(tar1.x - math.random(-50, 50), tar1.y, tar1.z + math.random(50, 75), 38, 1, false, false, 0, false)
        FIRE.ADD_EXPLOSION(tar1.x, tar1.y - math.random(-50, 50), tar1.z + math.random(50, 75), 38, 1, false, false, 0, false)
        FIRE.ADD_EXPLOSION(tar1.x - math.random(-50, 50), tar1.y - math.random(-50, 50), tar1.z + math.random(50, 75), 38, 1, false, false, 0, false)
        FIRE.ADD_EXPLOSION(tar1.x - math.random(-50, 50), tar1.y + math.random(-50, 50), tar1.z + math.random(50, 75), 38, 1, false, false, 0, false)
        FIRE.ADD_EXPLOSION(tar1.x + math.random(-50, 50), tar1.y - math.random(-50, 50), tar1.z + math.random(50, 75), 38, 1, false, false, 0, false)
        MISC.SHOOT_SINGLE_BULLET_BETWEEN_COORDS(tar1.x, tar1.y, tar1.z + 4.0, tar1.x, tar1.y, tar1.z + math.random(10, 15), 200, 0, weap, 0, false, true, firw.speed)
        MISC.SHOOT_SINGLE_BULLET_BETWEEN_COORDS(tar1.x, tar1.y, tar1.z + 4.0, tar1.x + math.random(-50, 50), tar1.y, tar1.z + math.random(10, 15), 200, 0, weap, 0, false, false, firw.speed)
        MISC.SHOOT_SINGLE_BULLET_BETWEEN_COORDS(tar1.x, tar1.y, tar1.z + 4.0, tar1.x , tar1.y + math.random(-50, 50), tar1.z + math.random(10, 15), 200, 0, weap, 0, false, false, firw.speed)
        MISC.SHOOT_SINGLE_BULLET_BETWEEN_COORDS(tar1.x, tar1.y, tar1.z + 4.0, tar1.x + math.random(-50, 50), tar1.y, tar1.z + math.random(10, 15), 200, 0, weap, 0, false, false, firw.speed)
        MISC.SHOOT_SINGLE_BULLET_BETWEEN_COORDS(tar1.x, tar1.y, tar1.z + 4.0, tar1.x + math.random(-50, 50), tar1.y + math.random(-50, 50), tar1.z + math.random(10, 15), 200, 0, weap, 0, false, false, firw.speed)
        MISC.SHOOT_SINGLE_BULLET_BETWEEN_COORDS(tar1.x, tar1.y, tar1.z + 4.0, tar1.x - math.random(-50, 50), tar1.y, tar1.z + math.random(10, 15), 200, 0, weap, 0, false, false, firw.speed)
        MISC.SHOOT_SINGLE_BULLET_BETWEEN_COORDS(tar1.x, tar1.y, tar1.z + 4.0, tar1.x , tar1.y - math.random(-50, 50), tar1.z + math.random(10, 15), 200, 0, weap, 0, false, false, firw.speed)
        MISC.SHOOT_SINGLE_BULLET_BETWEEN_COORDS(tar1.x, tar1.y, tar1.z + 4.0, tar1.x - math.random(-50, 50), tar1.y - math.random(-50, 50), tar1.z + math.random(10, 15), 200, 0, weap, 0, false, false, firw.speed)
        if not players.exists(pid) then
            util.stop_thread()
        end
    end)

    ---------------------
    ---------------------
    -- Spieler Liste/Freundlich/Fahrzeug
    ---------------------
    ---------------------

    local friendlyvehicle = menu.list(friendly, "Fahrzeug", {}, "")
        menu.divider(friendlyvehicle, "Fahrzeug")

    menu.action(friendlyvehicle, 'Fahrzeug komplett upgraden', {}, 'Upgradet sein Fahrzeug und erhöht die Geschwindigkeit (setzt jedes Mal zufällige Räder auf das Fahrzeug)', function()
        GetPlayVeh(pid,  function ()
            Maxoutcar(pid)
        end)
    end, nil, nil, COMMANDPERM_FRIENDLY)

    menu.action(friendlyvehicle, "Fahrzeug Godmode", {}, "Gibt dem Fahrzeug Godmode", function(click_type)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            ENTITY.SET_ENTITY_INVINCIBLE(car, true)
            VEHICLE.SET_VEHICLE_CAN_BE_VISIBLY_DAMAGED(car, false)
        end
    end)

    menu.text_input(friendlyvehicle, 'Nummernschild ändern', {"nschild"}, 'Ändert das Nummernschild mit einem individuellen Text', function(cusplate)
        GetPlayVeh(pid,  function ()
            Platechange(cusplate, pid)
        end)
    end)

    menu.action(friendlyvehicle, 'Fahrzeug repaieren', {}, 'Repariert sein Fahrzeug', function()
        GetPlayVeh(pid,  function ()
            Fixveh(pid)
        end)
    end, nil, nil, COMMANDPERM_FRIENDLY)

    menu.action(friendlyvehicle, "Entferne Haftbomben vom Fahrzeug", {}, "", function(click_type)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        NETWORK.REMOVE_ALL_STICKY_BOMBS_FROM_ENTITY(car)
    end)

    menu.click_slider(friendlyvehicle, 'Fahrzeug beschleunigen', {}, 'Beschleunige das Fahrzeug vorwärts um den eingestellten Wert (die tatsächliche Geschwindigkeit ist etwa doppelt so hoch wie die Zahl in km/h)', 10, 150, 40, 10, function (s)
        local  speed = s
         GetPlayVeh(pid, function ()
            Accelveh( speed, pid)
            util.yield(1000)
         end)
    end)

    menu.click_slider(friendlyvehicle, "Höchstgeschwindigkeit", {}, "", -10000, 10000, 200, 100, function(s)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            VEHICLE.MODIFY_VEHICLE_TOP_SPEED(car, s)
            ENTITY.SET_ENTITY_MAX_SPEED(car, s)
        end
    end)

    ---------------------
    ---------------------
    -- Spieler Liste/Trolling
    ---------------------
    ---------------------

    local playertroll = menu.list(menu.player_root(pid), "Athego's Script: Trolling", {}, "")
        menu.divider(playertroll, "Trolling")


    ---------------------
    ---------------------
    -- Spieler Liste/Trolling/Explosionen
    ---------------------
    ---------------------

    local playertrollexplo = menu.list(playertroll, "Explosionen", {}, "")
        menu.divider(playertrollexplo, "Explosionen")

    local explo_types = {13, 12, 70}
    local e_type = 13
    local explo_options = {"Wasser", "Feuer", "Launch"}
    local explo_type_slider = menu.list_action(playertrollexplo, "Explosion's Typ", {}, "", explo_options, function(index, value, click_type)
        local target_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local coords = ENTITY.GET_ENTITY_COORDS(target_ped, false)
        e_type = explo_types[index]
        FIRE.ADD_EXPLOSION(coords['x'], coords['y'], coords['z'], e_type, 100.0, true, false, 0.0)
    end)

    menu.toggle_loop(playertrollexplo, "Unendliche Explosionen", {}, "Lässt den Spieler dauerhaft explodieren", function(on)
        local target_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local coords = ENTITY.GET_ENTITY_COORDS(target_ped)
        FIRE.ADD_EXPLOSION(coords['x'], coords['y'], coords['z'], e_type, 1.0, true, false, 0.0)
    end)

    menu.toggle_loop(playertrollexplo, "Zufällige Explosionen", {}, "", function(on)
        local target_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local coords = ENTITY.GET_ENTITY_COORDS(target_ped)
        FIRE.ADD_EXPLOSION(coords['x'], coords['y'], coords['z'], math.random(0, 82), 1.0, true, false, 0.0)
    end)

    ---------------------
    ---------------------
    -- Spieler Liste/Trolling/Fahrezug
    ---------------------
    ---------------------

    local playertrollfahrzeug = menu.list(playertroll, "Fahrzeug", {}, "")
        menu.divider(playertrollfahrzeug, "Fahrzeug")

    local tp_options = {"Zu mir", "Wegpunkt", "Maze Bank", "Unterwasser", "Hoch oben", "LSC", "SCP-173", "Große Zelle", "Luxus-Autos Austellung", "Unterwasser, und schließ die Türen ab"}
    menu.list_action(playertrollfahrzeug, "Teleportieren", {}, "", tp_options, function(index, value, click_type)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            local c = {}
            pluto_switch index do
                case 1:
                    c = players.get_position(players.user())
                    break
                case 2: 
                    c = get_waypoint_coords()
                    break
                case 3:
                    c.x = -75.261375
                    c.y = -818.674
                    c.z = 326.17517
                    break
                case 4: 
                    c.x = 4497.2207
                    c.y = 8028.3086
                    c.z = -32.635174
                    break
                case 5: 
                    c.x = 0.0
                    c.y = 0.0
                    c.z = 2000
                    break
                case 6: 
                    c.x = -353.84512
                    c.y = -135.59108
                    c.z = 39.009624
                    break
                case 7: 
                    c.x = 1642.8401
                    c.y = 2570.7695
                    c.z = 45.564854
                    break
                case 8:
                    c.x = 1737.1896
                    c.y = 2634.897
                    c.z = 45.56497
                    break
                case 9: 
                    c.x = -787.4092
                    c.y = -239.00093
                    c.z = 37.734055
                    break
                case 10: 
                    menu.set_value(childlock, true)
                    c.x = 4497.2207
                    c.y = 8028.3086
                    c.z = -32.635174
                    break
            end
            request_control_of_entity(car)
            tp_player_car_to_coords(pid, c)
        end
    end)

    menu.toggle(playertrollfahrzeug, 'Dauerhafter Burnout', {}, 'Sein Auto macht dauerhaft Burnouts', function(toggle)
        local pedm = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        if PED.IS_PED_IN_ANY_VEHICLE(pedm, true) then
            local playerVehicle = PED.GET_VEHICLE_PED_IS_IN(pedm, false)
            NETWORK.NETWORK_REQUEST_CONTROL_OF_ENTITY(playerVehicle)
            VEHICLE.SET_VEHICLE_BURNOUT(playerVehicle, toggle)
        end
    end)

    local fahrzeughealth_optionen = {"Zerstören", "Reparieren"}
    menu.list_action(playertrollfahrzeug, "Zustand", {},  "Es kann passieren das die Zerstörung unumkehrbar ist. So funktioniert das Spiel nun mal", fahrzeughealth_optionen, function(index, value, click_type)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            VEHICLE.SET_VEHICLE_ENGINE_HEALTH(car, if index == 1 then -4000.0 else 10000.0)
            VEHICLE.SET_VEHICLE_BODY_HEALTH(car, if index == 1 then -4000.0 else 10000.0)
            if index == 2 then
                VEHICLE.SET_VEHICLE_FIXED(car)
            end
        end
    end)

    menu.action(playertrollfahrzeug, "YEET", {}, "", function(click_type)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            ENTITY.SET_ENTITY_MAX_SPEED(car, 10000000.0)
            ENTITY.APPLY_FORCE_TO_ENTITY(car, 1,  0.0, 0.0, 10000000, 0, 0, 0, 0, true, false, true, false, true)
        end
    end)

    kindersicherung = menu.toggle_loop(playertrollfahrzeug, "Kindersicherung", {}, "", function()
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            VEHICLE.SET_VEHICLE_DOORS_LOCKED(car, 4)
        end
    end, function()
        if car ~= 0 then
            VEHICLE.SET_VEHICLE_DOORS_LOCKED(car, 1)
        end
    end)

    local door_options = {"Offen", "Geschlossen", "Kaputt"}
    menu.list_action(playertrollfahrzeug, "Tür Kontrolle", {}, "", door_options, function(index, value, click_type)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            local d = VEHICLE.GET_NUMBER_OF_VEHICLE_DOORS(car)
            for i=0, d do
                pluto_switch index do
                    case 1: 
                        VEHICLE.SET_VEHICLE_DOOR_OPEN(car, i, false, true)
                        break
                    case 2:
                        VEHICLE.SET_VEHICLE_DOOR_SHUT(car, i, true)
                        break
                    case 3:
                        VEHICLE.SET_VEHICLE_DOOR_BROKEN(car, i, false)
                        break
                end
            end
        end
    end)

    menu.toggle(playertrollfahrzeug, "Handbremse", {}, "Stellt die Handbremse des Auto's fest", function(on)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            VEHICLE.SET_VEHICLE_HANDBRAKE(car, on)
        end
    end)

    menu.toggle_loop(playertrollfahrzeug, "Zufälliges Bremsen", {}, "Anscheinend sind die Bremsen kaputt oder warum Bremst das Auto zufällig?", function(on)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            VEHICLE.SET_VEHICLE_HANDBRAKE(car, true)
            util.yield(1000)
            request_control_of_entity(car)
            VEHICLE.SET_VEHICLE_HANDBRAKE(car, false)
            util.yield(math.random(3000, 15000))
        end
    end)

    menu.toggle_loop(playertrollfahrzeug, "Beyblade", {}, "You spin me right round, baby right round like a record, baby Right round, round round", function(on)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity_once(car)
            ENTITY.APPLY_FORCE_TO_ENTITY_CENTER_OF_MASS(car, 4, 0.0, 0.0, 300.0, 0, true, true, false, true, true, true)
        end
    end)

    menu.action(playertrollfahrzeug, "Einmal wenden bitte", {}, "Lässt das Fahrzeug in die andere Richtung Fahren", function(on)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            local rot = ENTITY.GET_ENTITY_ROTATION(car, 0)
            local vel = ENTITY.GET_ENTITY_VELOCITY(car)
            ENTITY.SET_ENTITY_ROTATION(car, rot['x'], rot['y'], rot['z']+180, 0, true)
            ENTITY.SET_ENTITY_VELOCITY(car, -vel['x'], -vel['y'], vel['z'])
        end
    end)

    menu.action(playertrollfahrzeug, "Fahrzeug umdrehen", {}, "Dreht das Fahrzeug auf den Kopf", function(on)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            local rot = ENTITY.GET_ENTITY_ROTATION(car, 0)
            local vel = ENTITY.GET_ENTITY_VELOCITY(car)
            ENTITY.SET_ENTITY_ROTATION(car, rot['x'], rot['y']+180, rot['z'], 0, true)
            ENTITY.SET_ENTITY_VELOCITY(car, -vel['x'], -vel['y'], vel['z'])
        end
    end)

    menu.action(playertrollfahrzeug, "Motor ausschalten", {}, "", function(on)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            request_control_of_entity(car)
            VEHICLE.SET_VEHICLE_ENGINE_ON(car, false, true, false)
        end
    end)

    menu.action(playertrollfahrzeug, "EMP", {}, "Schaltet durch eine EMP Bombe die Elektronik in dem Fahrzeug aus", function(on)
        local car = PED.GET_VEHICLE_PED_IS_IN(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), true)
        if car ~= 0 then
            local c = ENTITY.GET_ENTITY_COORDS(car)
            FIRE.ADD_EXPLOSION(c.x, c.y, c.z, 83, 100.0, false, true, 0.0)
        end
    end)

    ---------------------
    ---------------------
    -- Spieler Liste/Trolling/NPC's
    ---------------------
    ---------------------

    local playertrollnpc = menu.list(playertroll, "NPC Trolling", {}, "")
        menu.divider(playertrollnpc, "NPC Trolling")

    menu.action(playertrollnpc, "Letztes Auto klauen", {}, "Schickt einen NPC der das Fahrzeug klaut", function(click_type)
        npc_jack(pid, false)
    end)

    local kidnap_types = {"LKW", "Helikopter"}
    menu.list_action(playertrollnpc, "Entführen", {}, "Spawnt ein Fahrzeug in dem der Spieler feststeckt und fährt mit ihm rum", kidnap_types, function(index, value)
        local p_hash = util.joaat("s_m_y_factory_01")
        local v_hash = 0
        pluto_switch index do 
            case 1:
                v_hash = util.joaat("boxville3")
                break 
            case 2:
                v_hash = util.joaat("cargobob")
                break
        end
        local user_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        request_model_load(v_hash)
        request_model_load(p_hash)
        local c = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(user_ped, 0.0, 2.0, 0.0)
        local truck = entities.create_vehicle(v_hash, c, ENTITY.GET_ENTITY_HEADING(user_ped))
        local driver = entities.create_ped(5, p_hash, c, 0)
        PED.SET_PED_INTO_VEHICLE(driver, truck, -1)
        PED.SET_PED_FLEE_ATTRIBUTES(driver, 0, false)
        ENTITY.SET_ENTITY_INVINCIBLE(driver, true)
        ENTITY.SET_ENTITY_INVINCIBLE(truck, true)
        request_model_load(prop_hash)
        PED.SET_PED_CAN_BE_DRAGGED_OUT(driver, false)
        PED.SET_BLOCKING_OF_NON_TEMPORARY_EVENTS(driver, true)
        util.yield(2000)
        if index == 1 then
            TASK.TASK_VEHICLE_DRIVE_TO_COORD(driver, truck, math.random(1000), math.random(1000), math.random(100), 100, 1, ENTITY.GET_ENTITY_MODEL(truck), 786996, 5, 0)
        elseif index == 2 then 
            TASK.TASK_HELI_MISSION(driver, truck, 0, 0, math.random(1000), math.random(1000), 1500, 4, 200.0, 0.0, 0, 100, 1000, 0.0, 16)
        end
    end)

    ---------------------
    ---------------------
    -- Spieler Liste/Trolling/Chat troll
    ---------------------
    ---------------------

    local playertrollchat = menu.list(playertroll, "Chat Trolling", {}, "")
        menu.divider(playertrollchat, "Chat Trolling")

    menu.action(playertrollchat, "Schizo-Nachricht senden", {"schizo"}, "Sendet ihnen eine Chat-Nachricht, die normal aussieht, aber nur sie selbst sehen können. Lässt sie schizophren aussehen, wenn sie antworten", function(click_type)
        util.show_corner_help(sprefix .. " Bitte gib die Nachricht ein")
        menu.show_command_box("schizo" .. players.get_name(pid) .. " ")
        end, function(on_command)
            if #on_command > 140 then
                util.toast(sprefix .. " Die Nachricht ist zu lang")
            else
                chat.send_targeted_message(pid, players.user(), on_command, false)
                util.toast(sprefix .. " Nachricht gesendet!")
            end
    end)

    menu.action(playertrollchat, "Falsche RAC Erkennung", {"fakerac"}, "Der Benutzer hat eine Erkennung ausgelöst: Rockstar Anti Cheat", function(click_type)
        local types = {'I3', 'C1'}
        local det_type = types[math.random(1, #types)]
        chat.send_message('> ' .. players.get_name(pid) .. " triggered a detection: Rockstar Anti Cheat (" .. det_type .. ")", false, true, true)
    end)

    menu.action(playertrollchat, "Falsche Knockoff Breakup Erkennung", {}, "", function(click_type)
        chat.send_message("> Knockoff Breakup Kick from " .. players.get_name(pid) .. " against " .. players.get_name(players.user()), false, true, true)
    end)

    ---------------------
    ---------------------
    -- Spieler Liste/Trolling/SMS troll
    ---------------------
    ---------------------

    local playertrollsms = menu.list(playertroll, "SMS Trolling", {}, "")
        menu.divider(playertrollsms, "SMS Trolling")

    ---------------------
    ---------------------
    -- Spieler Liste/Trolling/Ram
    ---------------------
    ---------------------

    local playertrollram = menu.list(playertroll, "Spieler Rammen", {}, "")
        menu.divider(playertrollram, "Spieler Rammen")

    local ram_car = "brickade"
    menu.text_input(playertrollram, "Eigenes Fahrzeug", {"brickade"}, "Eingabe eines benutzerdefinierten Modells, mit dem der Spieler gerammt werden soll", function(on_input)
        ram_car = on_input
    end, "brickade")

    local ram_hashes = {-1007528109, -2103821244, 368211810, -1649536104}
    local ram_options = {"Howard", "Rally Truck", "Transportflugzeug", "Phantom Wedge", "Benutzerdefiniert"}
    menu.list_action(playertrollram, "Rammen mit", {}, "", ram_options, function(index, value, click_type)
        if value ~= "Benutzerdefiniert" then
            ram_ped_with(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), ram_hashes[index], math.random(5, 15))
        else
            ram_ped_with(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), util.joaat(ram_car), math.random(5, 15))
        end
    end)

    ---------------------
    ---------------------
    -- Spieler Liste/Trolling
    ---------------------
    ---------------------

    menu.action(playertroll, "Ragdoll", {}, "", function(on)
        local coords = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), 0.0, 0.0, 2.8)
        FIRE.ADD_EXPLOSION(coords['x'], coords['y'], coords['z'], 70, 100.0, false, true, 0.0)
    end)

    menu.action(playertroll, "Herzinfarkt", {}, "Führt dazu, dass der Spieler einen Herzinfarkt erleidet und stirbt.", function(on)
        local coords = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), 0.0, 0.5, 1.0)
        local v = PED.GET_VEHICLE_PED_IS_USING(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid))
        if v ~= 0 then 
            request_control_of_entity(v)
            ENTITY.SET_ENTITY_INVINCIBLE(v, true)
        end
        FIRE.ADD_EXPLOSION(coords['x'], coords['y'], coords['z'], 47, 100.0, false, true, 0.0)
        if v ~= 0 then 
            request_control_of_entity(v)
            ENTITY.SET_ENTITY_INVINCIBLE(v, false)
        end
    end)

    menu.action(playertroll,  "Spieler aus dem Innenraum zwingen", {}, "Für die meisten Innenräume geeignet.", function() -- very innovative!
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local pos = ENTITY.GET_ENTITY_COORDS(ped, false)
        local glitch_hash = util.joaat("p_spinning_anus_s")
        local poopy_butt = util.joaat("brickade2")
        request_model(glitch_hash)
        request_model(poopy_butt)
        for i, interior in ipairs(interior_stuff) do
            if get_interior_player_is_in(pid) == interior then
                util.toast("Der Spieler befindet sich nicht in einem Innenraum :/")
            return end
        end
        for i = 1, 5 do
            local stupid_object = entities.create_object(glitch_hash, pos)
            local glitch_vehicle = entities.create_vehicle(poopy_butt, pos, 0)
            ENTITY.SET_ENTITY_VISIBLE(stupid_object, false)
            ENTITY.SET_ENTITY_VISIBLE(glitch_vehicle, false)
            ENTITY.SET_ENTITY_INVINCIBLE(stupid_object, true)
            ENTITY.SET_ENTITY_COLLISION(stupid_object, true, true)
            ENTITY.APPLY_FORCE_TO_ENTITY(glitch_vehicle, 1, 0.0, 10, 10, 0.0, 0.0, 0.0, 0, 1, 1, 1, 0, 1)
            util.yield(500)
            entities.delete_by_handle(stupid_object)
            entities.delete_by_handle(glitch_vehicle)
            util.yield(500)     
        end
    end)

    menu.action(playertroll, "An Schwarze Leere senden", {""}, "Die Ergebnisse können variieren, je nachdem, ob sie ein aktives MOC haben.", function()
        util.trigger_script_event(1 << pid, {1268038438, pid, 81, 0, 0, 1, 1130429716, -1001012850, 1106067788, 0, 0, 1, 2123789977, 1, -1})
    end)

    menu.action(playertroll, "Aufschneiden", {}, "Macht aus dem Spieler Fleisch Salat mit Hubschrauberblättern. Funktioniert am besten, wenn der Spieler in der Nähe ist", function(click_type)
        local target_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local coords = ENTITY.GET_ENTITY_COORDS(target_ped, false)
        coords.z = coords['z']+2.5
        local hash = util.joaat("buzzard")
        request_model_load(hash)
        local heli = entities.create_vehicle(hash, coords, ENTITY.GET_ENTITY_HEADING(target_ped))
        VEHICLE.SET_VEHICLE_ENGINE_ON(heli, true, true, false)
        VEHICLE.SET_HELI_BLADES_FULL_SPEED(heli)
        ENTITY.SET_ENTITY_INVINCIBLE(heli, true)
        ENTITY.FREEZE_ENTITY_POSITION(heli, true)
        ENTITY.SET_ENTITY_COMPLETELY_DISABLE_COLLISION(heli, true, true)
        ENTITY.SET_ENTITY_ROTATION(heli, 180, 0.0, ENTITY.GET_ENTITY_HEADING(target_ped), 0)
        ENTITY.SET_ENTITY_COORDS_NO_OFFSET(heli, coords.x, coords.y, coords.z, true, false, false)
        VEHICLE.SET_VEHICLE_ENGINE_ON(heli, true, true, true)
    end)

    -- menu.toggle(playertroll, "Schwarzes Loch", {"sloch"}, "Eine wirklich Nervige Funktion", function(on)
    --     if on then
    --         if not blackhole then
    --             blackhole = true
    --             menu.trigger_commands(translations.blackhole .. " on")
    --         end
    --         bh_target = pid
    --     else
    --         bh_target = -1
    --         if blackhole then
    --             blackhole = false
    --             menu.trigger_commands(translations.blackhole .. " off")
    --         end
    --     end
    -- end)

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
        util.yield(1700)
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