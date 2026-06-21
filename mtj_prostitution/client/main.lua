local ESX = exports['es_extended']:getSharedObject()

-- ════════════════════════════════════════════════════════════════
--  STATE
-- ════════════════════════════════════════════════════════════════
local spawnedPeds   = {}      -- [index] = pedHandle
local pedBlips      = {}      -- [index] = blipHandle
local activePed     = nil     -- aktuell angeworbene Hure
local state         = 'IDLE'  -- IDLE | RECRUITED | RECRUITED_FOOT | FOLLOWING | RIDING | MENU | SERVICE | DONE
local lastService   = 0       -- Cooldown-Timer
local lastApproachCall = 0    -- Throttle für Approach-Speech
local targetSpot    = nil     -- vector3 der gewählten ruhigen Ecke
local spotBlip      = nil

local DEFAULT_RECRUIT_DISTANCE = 9.0
local SERVICE_ANIM_DICT = 'mini@prostitutes@sexnorm_veh'
local MENU_FAILSAFE_MS = 45000
local RECRUIT_FAILSAFE_MS = 20000
local FOLLOW_FAILSAFE_BUFFER_MS = 15000
local SERVICE_FAILSAFE_BUFFER_MS = 30000
local DEFAULT_POST_SERVICE_WATCHDOG_MS = 8000
local stateChangedAt = GetGameTimer()
local serviceFailSafeUntil = 0
local serviceAbortRequested = false
local activeCam = nil          -- Cinematic-Kamera während Service (Modul-Level für Cleanup)
local serviceRocking = false   -- Fahrzeug-Rütteln-Flag (Modul-Level für Cleanup)
local postServiceWatchdogToken = 0
local postServiceRecoveryUntil = 0
local SERVICE_PLAYER_ANIMS = {
    'proposition_to_BJ_p1_male',
    'proposition_to_BJ_p2_male',
    'BJ_loop_male',
    'BJ_to_proposition_p1_male',
    'BJ_to_proposition_p2_male',
    'proposition_to_sex_p1_male',
    'proposition_to_sex_p2_male',
    'sex_loop_male',
    'sex_to_proposition_p1_male',
    'sex_to_proposition_p2_male',
}

-- Von externen Resourcen (z.B. npc_dashboard) registrierte Huren.
-- Diese Peds werden NICHT von diesem Script gespawnt/gelöscht – nur angeworben.
local externalPeds  = {}      -- [pedHandle] = true

-- Hash-Set der konfigurierten Ped-Modelle für den Spiel-Pool-Scan.
-- Synchron beim Script-Load befüllt, damit der Pool-Scan vom ersten Frame an korrekt arbeitet.
local hookerModelHashes = {}
for _, model in ipairs(Config.PedModels) do
    local hash = (type(model) == 'number') and model or GetHashKey(model)
    hookerModelHashes[hash] = true
end

-- Export: andere Resourcen melden ihre Huren-Peds hier an, damit sie
-- per Hupe/E angeworben werden können (wie die Script-eigenen Huren).
exports('RegisterHooker', function(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        externalPeds[ped] = true
    end
end)

exports('UnregisterHooker', function(ped)
    if ped then externalPeds[ped] = nil end
end)

-- LocalEvent-Alternative: npc-system (oder andere Scripts) können Peds auch per TriggerEvent melden.
-- Aufruf: TriggerEvent('mtj_prostitution:registerExternalPed', pedHandle)
--         TriggerEvent('mtj_prostitution:unregisterExternalPed', pedHandle)
AddEventHandler('mtj_prostitution:registerExternalPed', function(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        externalPeds[ped] = true
        dbg('Ped per LocalEvent registriert:', ped)
    end
end)
AddEventHandler('mtj_prostitution:unregisterExternalPed', function(ped)
    if ped then externalPeds[ped] = nil end
end)

-- ════════════════════════════════════════════════════════════════
--  DIALOG-SYSTEM (GTA-Online-Style Sprache + Untertitel)
-- ════════════════════════════════════════════════════════════════

-- GTA-Ped-Speech pro Phase (native Stimmen, funktionieren auf Hooker-Models)
local SPEECH = {
    approach  = { 'HOOKER_OFFER', 'CHAT_STATE', 'GENERIC_HI' },
    approachFoot = { 'HOOKER_OFFER', 'CHAT_STATE', 'GENERIC_HI' },
    enter     = { 'HOOKER_ACCEPT', 'GENERIC_HI', 'CHAT_STATE' },
    ride      = { 'CHAT_STATE', 'CHAT_STATE', 'CHAT_STATE' },
    pleased   = { 'HOOKER_PLEASED', 'GENERIC_BYE', 'CHAT_STATE' },
}

-- Untertitel-Texte pro Phase (zufällig gewählt, GTA-Stil)
local DIALOGUE = {
    approach = {
        'Hey Süßer, suchst du Gesellschaft?',
        'Na, wohin fährst du so alleine?',
        'Willst du eine gute Zeit haben?',
        'Hey... du siehst einsam aus.',
        'Lust auf was Besonderes heute Nacht?',
        'Hübsches Auto... willst du Gesellschaft?',
    },
    approachFoot = {
        'Hey Süßer, suchst du Gesellschaft?',
        'Na, gehst du hier alleine spazieren?',
        'Willst du eine gute Zeit haben?',
        'Hey... du siehst einsam aus.',
        'Lust auf was Besonderes heute Nacht?',
        'Na, hast du kurz Zeit für mich?',
    },
    enter = {
        'Na dann lass uns fahren...',
        'Gute Wahl, Süßer.',
        'Das wird dir gefallen...',
        'Fahr irgendwohin, wo uns keiner sieht.',
    },
    ride = {
        'Fahr nicht so schnell, ich will heil ankommen.',
        'Hast du schon eine Stelle im Kopf?',
        'Ich mag dein Auto...',
        'Du bist nicht von der Polizei, oder?',
        'Hier sind zu viele Leute... fahr weiter.',
        'Keine Sorge, ich beiße nicht... meistens.',
        'Bist du nervös? Das ist süß.',
        'Such dir eine ruhige Ecke...',
        'Wohin bringst du mich?',
    },
    serviceStart = {
        'Mmh, endlich allein...',
        'Na dann... fangen wir an.',
        'Komm her...',
    },
    pleased = {
        'Das war schön, Süßer.',
        'Ruf mich wieder an...',
        'War mir ein Vergnügen.',
        'Bis zum nächsten Mal...',
    },
}

-- Untertitel anzeigen (GTA-Style: unten mittig, halbtransparent)
local subtitleEndTime = 0
local subtitleText = ''

local function showSubtitle(text, durationMs)
    subtitleText = text
    subtitleEndTime = GetGameTimer() + (durationMs or 3500)
end

-- Subtitle-Renderer (läuft dauerhaft, zeichnet nur wenn aktiv)
CreateThread(function()
    while true do
        if GetGameTimer() < subtitleEndTime and subtitleText ~= '' then
            SetTextScale(0.38, 0.38)
            SetTextFont(4)
            SetTextProportional(true)
            SetTextColour(255, 255, 255, 230)
            SetTextDropshadow(2, 0, 0, 0, 200)
            SetTextEdge(1, 0, 0, 0, 180)
            SetTextEntry('STRING')
            SetTextCentre(true)
            AddTextComponentString(subtitleText)
            DrawText(0.5, 0.88)
            Wait(0)
        else
            Wait(200)
        end
    end
end)

-- Sprache + Untertitel zusammen abspielen
local function hookerSay(ped, phase)
    if not ped or not DoesEntityExist(ped) then return end
    -- GTA-Ped-Speech (native Stimme, kann fehlschlagen -> pcall)
    local speeches = SPEECH[phase]
    if speeches then
        local s = speeches[math.random(#speeches)]
        pcall(function()
            PlayPedAmbientSpeechNative(ped, s, 'SPEECH_PARAMS_FORCE_SHOUTED_CLEAR')
        end)
    end
    -- Untertitel
    local lines = DIALOGUE[phase]
    if lines then
        showSubtitle(lines[math.random(#lines)], 3500)
    end
end

-- Ride-Talk: während der Fahrt gelegentlich reden
local rideTalkActive = false
local function startRideTalk()
    if rideTalkActive then return end
    rideTalkActive = true
    CreateThread(function()
        Wait(4000) -- erste Pause nach dem Einsteigen
        while rideTalkActive and activePed and DoesEntityExist(activePed) and state == 'RIDING' do
            hookerSay(activePed, 'ride')
            Wait(math.random(8000, 14000)) -- alle 8-14 Sekunden
        end
        rideTalkActive = false
    end)
end

local function stopRideTalk()
    rideTalkActive = false
end

-- ════════════════════════════════════════════════════════════════
--  HELFER
-- ════════════════════════════════════════════════════════════════
local function dbg(...)
    if Config.Debug then print('[mtj_prostitution]', ...) end
end

local function setState(newState)
    if state ~= newState then
        state = newState
        stateChangedAt = GetGameTimer()
    end
end

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

-- GTA-Style Hilfetext oben links (mit Button-Glyphen wie ~INPUT_VEH_HORN~)
local function helpText(msg, beep)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, beep == true, -1)
end

local function DrawText3D(x, y, z, text)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(0.0, 0.0)
    local factor = (#text) / 370
    DrawRect(0.0, 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 150)
    ClearDrawOrigin()
end

local function isPlayerInServiceAnimation(player)
    if not player or player == 0 then return false end
    for _, anim in ipairs(SERVICE_PLAYER_ANIMS) do
        if IsEntityPlayingAnim(player, SERVICE_ANIM_DICT, anim, 3) then
            return true
        end
    end
    return false
end

local function stopPlayerServiceAnimations(player)
    if not player or player == 0 or not DoesEntityExist(player) then return end
    for _, anim in ipairs(SERVICE_PLAYER_ANIMS) do
        StopAnimTask(player, SERVICE_ANIM_DICT, anim, 4.0)
    end
    ClearPedSecondaryTask(player)
end

local function releasePlayerLocks(forceClearTasks)
    local player = PlayerPedId()
    -- Fahrzeugrütteln sofort stoppen
    serviceRocking = false
    -- Cinematic-Kamera zerstören, falls noch aktiv; sonst nur Rendering deaktivieren
    RenderScriptCams(false, false, 0, true, true)
    if activeCam then
        DestroyCam(activeCam, true)
        activeCam = nil
    end
    -- Schwarzblende aufheben, falls der Bildschirm noch ausgeblendet ist
    if IsScreenFadedOut() then
        DoScreenFadeIn(0)
    end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
    EnableAllControlActions(0)
    SetPlayerControl(PlayerId(), true, 0)
    FreezeEntityPosition(player, false)
    if forceClearTasks or isPlayerInServiceAnimation(player) then
        stopPlayerServiceAnimations(player)
        -- ClearPedTasksImmediately würde den Spieler aus dem Fahrzeug werfen;
        -- nur aufrufen wenn er NICHT im Auto sitzt
        if not IsPedInAnyVehicle(player, false) then
            ClearPedTasksImmediately(player)
        end
    end
end

local function shouldAbortService()
    return serviceAbortRequested or state ~= 'SERVICE'
end

local function getPostServiceWatchdogMs()
    return math.max(tonumber(Config.PostServiceWatchdogMs) or DEFAULT_POST_SERVICE_WATCHDOG_MS, 1000)
end

local function isPlayerBusyWithService(player)
    return isPlayerInServiceAnimation(player) or activeCam ~= nil or IsScreenFadedOut()
end

local function stopPostServiceWatchdog()
    postServiceWatchdogToken = postServiceWatchdogToken + 1
    postServiceRecoveryUntil = 0
end

local function startPostServiceWatchdog(veh, ped, reason)
    stopPostServiceWatchdog()

    local token = postServiceWatchdogToken
    local trackedVeh = (veh and veh ~= 0 and DoesEntityExist(veh)) and veh or 0
    local trackedPed = (ped and ped ~= 0 and DoesEntityExist(ped)) and ped or 0

    CreateThread(function()
        dbg('[WATCHDOG] Start post-service watchdog:', reason or 'n/a', 'veh=', trackedVeh, 'ped=', trackedPed)

        local deadline = GetGameTimer() + getPostServiceWatchdogMs()
        postServiceRecoveryUntil = deadline
        while postServiceWatchdogToken == token and GetGameTimer() < deadline do
            local player = PlayerPedId()
            local playerBusy = isPlayerBusyWithService(player)

            releasePlayerLocks(playerBusy)

            if trackedVeh ~= 0 then
                if DoesEntityExist(trackedVeh) then
                    SetVehicleLights(trackedVeh, 0)
                else
                    trackedVeh = 0
                end
            end

            if trackedPed ~= 0 then
                if DoesEntityExist(trackedPed) and not IsPedDeadOrDying(trackedPed, true) then
                    SetPedConfigFlag(trackedPed, 26, false)
                    SetBlockingOfNonTemporaryEvents(trackedPed, false)
                    if trackedVeh ~= 0 and IsPedInVehicle(trackedPed, trackedVeh, false) then
                        TaskLeaveVehicle(trackedPed, trackedVeh, 0)
                    end
                else
                    trackedPed = 0
                end
            end

            local pedGone = trackedPed == 0
            local vehicleGone = trackedVeh == 0
            local pedLeftVehicle = trackedPed ~= 0
                and trackedVeh ~= 0
                and DoesEntityExist(trackedPed)
                and not IsPedInVehicle(trackedPed, trackedVeh, false)
            local pedReleased = pedGone or vehicleGone or pedLeftVehicle

            if not playerBusy and pedReleased then
                break
            end

            Wait(250)
        end

        if postServiceWatchdogToken == token then
            releasePlayerLocks(true)
            if trackedVeh ~= 0 and DoesEntityExist(trackedVeh) then
                SetVehicleLights(trackedVeh, 0)
            end
            postServiceRecoveryUntil = 0
            dbg('[WATCHDOG] Stop post-service watchdog:', reason or 'n/a')
        end
    end)
end

local function isNight()
    if not Config.NightOnly then return true end
    local h = GetClockHours()
    if Config.NightStartHour > Config.NightEndHour then
        return h >= Config.NightStartHour or h < Config.NightEndHour
    else
        return h >= Config.NightStartHour and h < Config.NightEndHour
    end
end

-- Zeitfenster: darf gerade angeworben / Service gestartet werden?
local function isServiceTime()
    local sh = Config.ServiceHours
    if not sh or not sh.enabled then return true end
    local h = GetClockHours()
    if sh.startHour > sh.endHour then
        return h >= sh.startHour or h < sh.endHour
    else
        return h >= sh.startHour and h < sh.endHour
    end
end

-- Zählt NPCs (und optional Spieler) im Umkreis - für die Privatsphäre-Prüfung
local function nearbyPeopleCount(center, radius)
    local count = 0
    local me = PlayerPedId()
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and ped ~= activePed and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local isPlayerPed = IsPedAPlayer(ped)
            if (not isPlayerPed) or Config.PrivacyIncludePlayers then
                if #(GetEntityCoords(ped) - center) < radius then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function loadModel(model)
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) and t < 100 do
        Wait(50); t = t + 1
    end
    return HasModelLoaded(model)
end

local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) and t < 100 do
        Wait(50); t = t + 1
    end
    return HasAnimDictLoaded(dict)
end

local function getRecruitDistance()
    return Config.RecruitDistance or DEFAULT_RECRUIT_DISTANCE
end

local function getRecruitDistanceOnFoot()
    return Config.RecruitDistanceOnFoot or getRecruitDistance()
end

local function isRecognizedHookerPed(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsPedAPlayer(ped) or IsPedDeadOrDying(ped, true) then return false end
    if hookerModelHashes[GetEntityModel(ped)] then return true end

    if Config.EnableStandardPedRecognition then
        return IsPedHuman(ped) and not IsPedMale(ped)
    end

    return false
end

local function getDriverVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end  -- nur Fahrer
    return veh
end

-- ════════════════════════════════════════════════════════════════
--  PED-SPAWNING (Threads, läuft dauerhaft, prüft Tageszeit)
-- ════════════════════════════════════════════════════════════════
local function clearPeds()
    for i, ped in pairs(spawnedPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
        spawnedPeds[i] = nil
    end
    for i, blip in pairs(pedBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        pedBlips[i] = nil
    end
end

local function spawnPeds()
    local count = 0
    for i, point in ipairs(Config.SpawnPoints) do
        if not spawnedPeds[i] or not DoesEntityExist(spawnedPeds[i]) then
            local model = Config.PedModels[math.random(#Config.PedModels)]
            if loadModel(model) then
                local ped = CreatePed(4, model, point.x, point.y, point.z - 1.0, point.w, false, true)
                SetEntityAsMissionEntity(ped, true, true)
                SetPedFleeAttributes(ped, 0, false)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedCanRagdoll(ped, false)
                SetPedKeepTask(ped, true)
                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_PROSTITUTE_HIGH_CLASS', 0, true)
                SetModelAsNoLongerNeeded(model)
                spawnedPeds[i] = ped

                if Config.ShowBlips then
                    local blip = AddBlipForCoord(point.x, point.y, point.z)
                    SetBlipSprite(blip, 121)        -- Hure-Icon
                    SetBlipColour(blip, 27)         -- pink
                    SetBlipScale(blip, 0.8)
                    SetBlipAsShortRange(blip, true)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString('Nutte')
                    EndTextCommandSetBlipName(blip)
                    pedBlips[i] = blip
                end
                count = count + 1
            else
                dbg('Modell konnte nicht geladen werden fuer Spawn', i)
            end
        end
    end
    if count > 0 then dbg('Neue Nutten gespawnt:', count) end
end

CreateThread(function()
    while true do
        local sleep = 5000
        if isNight() then
            spawnPeds()
        else
            if next(spawnedPeds) and not activePed then clearPeds() end
        end
        Wait(sleep)
    end
end)

-- ════════════════════════════════════════════════════════════════
--  SPIEL-POOL-SCAN: unbekannte Huren-Peds in externalPeds aufnehmen
--  Läuft im Hintergrund und registriert alle Peds mit einem der konfigurierten
--  Modelle automatisch, egal ob von GTA ambient oder einem anderen Script.
-- ════════════════════════════════════════════════════════════════
CreateThread(function()
    while true do
        if isServiceTime() then
            local me = PlayerPedId()
            local myPos = GetEntityCoords(me)
            for _, ped in ipairs(GetGamePool('CPed')) do
                if ped ~= me
                    and ped ~= activePed
                    and DoesEntityExist(ped)
                    and not IsPedDeadOrDying(ped, true)
                    and isRecognizedHookerPed(ped)
                    and not externalPeds[ped]
                then
                    -- Nur Peds in der Nähe registrieren (Scan-Radius = max Erkennungsweite)
                    local scanRadius = math.max(getRecruitDistance(), getRecruitDistanceOnFoot()) + 5.0
                    local pedPos = GetEntityCoords(ped)
                    if #(vector2(pedPos.x, pedPos.y) - vector2(myPos.x, myPos.y)) < scanRadius then
                        -- Nicht erneut eintragen wenn bereits in spawnedPeds
                        local inSpawned = false
                        for _, sp in pairs(spawnedPeds) do
                            if sp == ped then inSpawned = true; break end
                        end
                        if not inSpawned then
                            externalPeds[ped] = true
                            dbg('Ped aus Spiel-Pool registriert:', ped)
                        end
                    end
                end
            end
        end
        Wait(2000)
    end
end)

-- ════════════════════════════════════════════════════════════════
--  ANWERBEN PER HUPE
-- ════════════════════════════════════════════════════════════════
CreateThread(function()
    while true do
        local sleep = 750
        if state == 'IDLE' and isServiceTime() and (GetGameTimer() - lastService) > (Config.Cooldown * 1000) then
            local veh = getDriverVehicle()
            if veh then
                local vp = GetEntityCoords(veh)
                -- nächste Nutte finden (2D-Distanz, Höhe egal)
                local nearest, nearIdx, nearDist = nil, nil, 9999.0
                local nearIsExternal = false
                for i, ped in pairs(spawnedPeds) do
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        local pc = GetEntityCoords(ped)
                        local d = #(vector2(vp.x, vp.y) - vector2(pc.x, pc.y))
                        if d < nearDist then
                            nearDist, nearest, nearIdx, nearIsExternal = d, ped, i, false
                        end
                    end
                end
                -- auch extern registrierte Huren (z.B. vom npc_dashboard) prüfen
                for ped in pairs(externalPeds) do
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        local pc = GetEntityCoords(ped)
                        local d = #(vector2(vp.x, vp.y) - vector2(pc.x, pc.y))
                        if d < nearDist then
                            nearDist, nearest, nearIdx, nearIsExternal = d, ped, nil, true
                        end
                    else
                        externalPeds[ped] = nil  -- ungültige Handles aufräumen
                    end
                end

                if nearest and nearDist < getRecruitDistance() then
                    sleep = 0
                    local pc = GetEntityCoords(nearest)
                    -- Approach-Speech: sie ruft dem Spieler zu (alle 8s, nicht spammen)
                    if not lastApproachCall or GetGameTimer() - lastApproachCall > 8000 then
                        lastApproachCall = GetGameTimer()
                        hookerSay(nearest, 'approach')
                    end
                    if Config.NoRecruitWhenWanted and GetPlayerWantedLevel(PlayerId()) > 0 then
                        -- Sie steigt nicht ein solange du gesucht wirst (GTA-Style)
                        helpText('Sie steigt nicht ein, solange die ~r~Cops~s~ hinter dir her sind.', false)
                    else
                        helpText('Drücke ~INPUT_VEH_HORN~ oder ~INPUT_PICKUP~ um die Begleitung anzuwerben', false)
                        DrawText3D(pc.x, pc.y, pc.z + 1.0, '~y~Begleitung~w~')
                        -- Hupe (86) ODER E (38) ODER konfigurierte Taste
                        if IsControlJustPressed(0, Config.HornControl)
                            or IsControlJustPressed(0, 86)
                            or IsControlJustPressed(0, 38) then
                            dbg('Nutte angeworben, Distanz:', math.floor(nearDist))
                            activePed = nearest
                            if nearIsExternal then
                                externalPeds[nearest] = nil
                            else
                                spawnedPeds[nearIdx] = nil
                                if pedBlips[nearIdx] then
                                    if DoesBlipExist(pedBlips[nearIdx]) then RemoveBlip(pedBlips[nearIdx]) end
                                    pedBlips[nearIdx] = nil
                                end
                            end
                            setState('RECRUITED')
                        end
                    end
                end
            else
                -- ── Anwerben zu Fuß (kein Fahrzeug) ──────────────────────────
                local player = PlayerPedId()
                local pp = GetEntityCoords(player)
                local nearest, nearIdx, nearDist = nil, nil, 9999.0
                local nearIsExternal = false
                for i, ped in pairs(spawnedPeds) do
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        local pc = GetEntityCoords(ped)
                        local d = #(vector2(pp.x, pp.y) - vector2(pc.x, pc.y))
                        if d < nearDist then
                            nearDist, nearest, nearIdx, nearIsExternal = d, ped, i, false
                        end
                    end
                end
                for ped in pairs(externalPeds) do
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        local pc = GetEntityCoords(ped)
                        local d = #(vector2(pp.x, pp.y) - vector2(pc.x, pc.y))
                        if d < nearDist then
                            nearDist, nearest, nearIdx, nearIsExternal = d, ped, nil, true
                        end
                    else
                        externalPeds[ped] = nil
                    end
                end

                -- Spiel-Pool direkt scannen wenn kein Ped in Reichweite – läuft jedes Mal, nicht nur
                -- wenn nearest == nil, damit weit entfernte Peds aus spawnedPeds nicht blockieren.
                -- Erkennt Peds von externen Scripten (z.B. npc-system) auch ohne vorherige Registrierung.
                local recruitRange = getRecruitDistanceOnFoot()
                if not nearest or nearDist >= recruitRange then
                    for _, ped in ipairs(GetGamePool('CPed')) do
                        if ped ~= player
                            and ped ~= activePed
                            and DoesEntityExist(ped)
                            and not IsPedDeadOrDying(ped, true)
                            and isRecognizedHookerPed(ped)
                        then
                            local pedPos = GetEntityCoords(ped)
                            local d = #(vector2(pp.x, pp.y) - vector2(pedPos.x, pedPos.y))
                            if d < nearDist then
                                nearDist, nearest, nearIdx, nearIsExternal = d, ped, nil, true
                                if d < recruitRange then
                                    externalPeds[ped] = true  -- fuer naechste Runde vormerken
                                end
                            end
                        end
                    end
                end

                if nearest and nearDist < getRecruitDistanceOnFoot() then
                    sleep = 0
                    local pc = GetEntityCoords(nearest)
                    if not lastApproachCall or GetGameTimer() - lastApproachCall > 8000 then
                        lastApproachCall = GetGameTimer()
                        hookerSay(nearest, 'approachFoot')
                    end
                    if Config.NoRecruitWhenWanted and GetPlayerWantedLevel(PlayerId()) > 0 then
                        helpText('Sie kommt nicht mit, solange die ~r~Cops~s~ hinter dir her sind.', false)
                    else
                        helpText('Drücke ~INPUT_PICKUP~ um die Begleitung anzusprechen', false)
                        DrawText3D(pc.x, pc.y, pc.z + 1.0, '~y~Begleitung~w~')
                        if IsControlJustPressed(0, 38) then  -- E
                            dbg('Nutte zu Fuß angeworben, Distanz:', math.floor(nearDist))
                            activePed = nearest
                            if nearIsExternal then
                                externalPeds[nearest] = nil
                            else
                                spawnedPeds[nearIdx] = nil
                                if pedBlips[nearIdx] then
                                    if DoesBlipExist(pedBlips[nearIdx]) then RemoveBlip(pedBlips[nearIdx]) end
                                    pedBlips[nearIdx] = nil
                                end
                            end
                            setState('RECRUITED_FOOT')
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ════════════════════════════════════════════════════════════════
--  EINSTEIGEN
-- ════════════════════════════════════════════════════════════════
local function startRecruit()
    local veh = getDriverVehicle()
    if not veh then setState('IDLE'); activePed = nil; return end
    if not DoesEntityExist(activePed) then setState('IDLE'); activePed = nil; return end

    -- Dashboard-Szenario/KeepTask lösen
    SetPedKeepTask(activePed, false)
    ClearPedTasksImmediately(activePed)
    FreezeEntityPosition(activePed, false)

    -- Normal zum Auto laufen und einsteigen (wie in GTA)
    TaskEnterVehicle(activePed, veh, 10000, 0, 2.0, 1, 0)

    notify('~y~Sie kommt...~s~')

    -- Watchdog: wenn sie nach 10 s nicht drin ist, Fallback-Teleport
    local t0 = GetGameTimer()
    while not IsPedInVehicle(activePed, veh, false) do
        Wait(300)
        if not DoesEntityExist(activePed) or not DoesEntityExist(veh) then
            setState('IDLE'); activePed = nil; return
        end
        if GetGameTimer() - t0 > 10000 then
            SetPedIntoVehicle(activePed, veh, 0)
            break
        end
    end

    notify('~g~Sie ist drin.~s~ Fahr zu einer ~y~abgelegenen Stelle~s~.')
    hookerSay(activePed, 'enter')
    startRideTalk()
    setState('RIDING')
end

-- ════════════════════════════════════════════════════════════════
--  FOLGE-MODUS (Fuß-Rekrutierung → gemeinsam zum Auto)
-- ════════════════════════════════════════════════════════════════
local function startFollowRecruit()
    if not DoesEntityExist(activePed) then setState('IDLE'); activePed = nil; return end

    -- Szenario/KeepTask des Peds lösen
    SetPedKeepTask(activePed, false)
    ClearPedTasksImmediately(activePed)
    FreezeEntityPosition(activePed, false)
    SetBlockingOfNonTemporaryEvents(activePed, true)

    notify('~y~Sie folgt dir.~s~ Geh zu deinem ~y~Fahrzeug~s~.')
    setState('FOLLOWING')

    CreateThread(function()
        local t0       = GetGameTimer()
        local TIMEOUT  = Config.FollowRecruitTimeoutMs or 60000
        local MAX_DIST = Config.FollowRecruitMaxDistance or 75.0

        while state == 'FOLLOWING' do
            local player = PlayerPedId()  -- jedes Mal neu holen (nach Respawn kann sich die ID ändern)

            if not DoesEntityExist(activePed) or IsPedDeadOrDying(activePed, true) then
                cleanupEscort('~r~Sie ist weg.')
                return
            end

            local playerPos = GetEntityCoords(player)
            local pedPos    = GetEntityCoords(activePed)
            local dist      = #(vector2(playerPos.x, playerPos.y) - vector2(pedPos.x, pedPos.y))

            -- Ped zu weit? -> Abbruch
            if dist > MAX_DIST then
                cleanupEscort('~r~Sie hat dich verloren.')
                return
            end

            -- Timeout abgelaufen? -> Abbruch
            if GetGameTimer() - t0 > TIMEOUT then
                cleanupEscort('~r~Sie ist gegangen. Du hast zu lange gewartet.')
                return
            end

            -- Follow-Task kontinuierlich erneuern (1 m hinter dem Spieler)
            TaskFollowToOffsetOfEntity(activePed, player, 0.0, -1.0, 0.0, 1.5, -1, 0.5, true)

            -- Hinweistext
            helpText('Geh zu deinem ~y~Fahrzeug~s~. Sie folgt dir. (~r~' .. math.ceil((TIMEOUT - (GetGameTimer() - t0)) / 1000) .. 's~s~)', false)

            -- Hat der Spieler ein Fahrzeug betreten (als Fahrer)?
            local veh = getDriverVehicle()
            if veh then
                -- Ped zum Einsteigen auffordern
                SetPedKeepTask(activePed, false)
                ClearPedTasks(activePed)
                TaskEnterVehicle(activePed, veh, 12000, 0, 2.0, 1, 0)
                notify('~y~Sie steigt ein...~s~')

                -- Warten bis sie drin ist (Watchdog 12 s)
                local t1 = GetGameTimer()
                while not IsPedInVehicle(activePed, veh, false) do
                    Wait(300)
                    if not DoesEntityExist(activePed) or not DoesEntityExist(veh) then
                        setState('IDLE'); activePed = nil; return
                    end
                    -- Spieler nicht mehr Fahrer dieses Fahrzeugs? -> Abbruch
                    if GetPedInVehicleSeat(veh, -1) ~= player then
                        cleanupEscort('~r~Vorgang abgebrochen.')
                        return
                    end
                    if GetGameTimer() - t1 > 12000 then
                        SetPedIntoVehicle(activePed, veh, 0)
                        break
                    end
                end

                notify('~g~Sie ist drin.~s~ Fahr zu einer ~y~abgelegenen Stelle~s~.')
                hookerSay(activePed, 'ride')
                startRideTalk()
                setState('RIDING')
                return
            end

            Wait(300)
        end
    end)
end

-- ════════════════════════════════════════════════════════════════
--  RUHIGE STELLE SUCHEN (keine feste Ecke - frei wie in GTA Online)
-- ════════════════════════════════════════════════════════════════
local lastPrivacyCheck = 0
local cachedNearby = 0
local function watchRiding()
    local ped = PlayerPedId()
    local veh = getDriverVehicle()

    -- Abbruch wenn man aussteigt oder die Hure weg ist
    if not veh or not DoesEntityExist(activePed) then
        return cleanupEscort('~r~Vorgang abgebrochen.')
    end
    -- Abbruch wenn sie nicht (mehr) im Auto ist
    if not IsPedInVehicle(activePed, veh, false) then return end

    -- Zeitfenster abgelaufen? -> Hinweis, kein Start möglich
    if not isServiceTime() then
        helpText('Zu dieser Uhrzeit läuft nichts. Komm im Zeitfenster wieder.', false)
        return
    end

    local pos = GetEntityCoords(ped)
    local speed = GetEntitySpeed(veh)

    -- NPC-Umkreis nur alle 400ms neu prüfen (Performance)
    local now = GetGameTimer()
    if now - lastPrivacyCheck > 400 then
        lastPrivacyCheck = now
        cachedNearby = nearbyPeopleCount(pos, Config.PrivacyRadius)
    end

    if cachedNearby > 0 then
        -- zu viele Leute -> weiterfahren
        helpText('Hier sind zu viele Leute. Fahr weiter zu einer ~y~abgelegenen Stelle~s~.', false)
    elseif speed > Config.MaxStartSpeed then
        -- privat, aber noch in Bewegung -> anhalten
        helpText('Abgelegene Stelle gefunden. ~g~Halte an~s~, um zu starten.', false)
    else
        -- privat + steht -> Service möglich
        helpText('Drücke ~INPUT_CONTEXT~, um die Begleitung zu fragen', false)
        if IsControlJustPressed(0, 38) then  -- E
            openServiceMenu()
        end
    end
end

-- ════════════════════════════════════════════════════════════════
--  SERVICE-MENÜ (NUI)
-- ════════════════════════════════════════════════════════════════
function openServiceMenu()
    setState('MENU')
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openMenu', services = Config.Services })
end

RegisterNUICallback('selectService', function(data, cb)
    cb('ok')
    SetNuiFocus(false, false)
    local idx = tonumber(data.index)
    local svc = Config.Services[idx]
    if not svc then return cleanupEscort('~r~Ungültige Auswahl.') end
    -- Server validiert Geld und führt Transaktion aus
    ESX.TriggerServerCallback('mtj_prostitution:pay', function(success, reason)
        if success then
            runService(svc)
        else
            cleanupEscort('~r~' .. (reason or 'Transaktion fehlgeschlagen.'))
        end
    end, idx)
end)

RegisterNUICallback('cancelMenu', function(_, cb)
    cb('ok')
    SetNuiFocus(false, false)
    cleanupEscort('~r~Abgebrochen.')
end)

-- ════════════════════════════════════════════════════════════════
--  SERVICE (Fade + Fortschritt, dezent / Fade-to-Black)
-- ════════════════════════════════════════════════════════════════
function runService(svc)
    stopPostServiceWatchdog()
    setState('SERVICE')
    serviceAbortRequested = false
    if spotBlip then RemoveBlip(spotBlip); spotBlip = nil end

    if Config.PoliceAlertChance > 0.0 and math.random() < Config.PoliceAlertChance then
        TriggerServerEvent('mtj_prostitution:policeAlert', GetEntityCoords(PlayerPedId()))
    end

    local player = PlayerPedId()
    local veh = GetVehiclePedIsIn(player, false)
    local scene = svc.scene or 'sex'
    local DICT = SERVICE_ANIM_DICT
    local playerFemale = (GetEntityModel(player) == GetHashKey('mp_f_freemode_01'))
    local realDuration = (svc.loops or 6) * 2.5
    serviceFailSafeUntil = GetGameTimer() + math.max(math.floor(realDuration * 1000) + SERVICE_FAILSAFE_BUFFER_MS, 45000)

    if veh == 0 or not DoesEntityExist(veh) or not DoesEntityExist(activePed) then
        return cleanupEscort('~r~Vorgang abgebrochen.')
    end

    -- Echte GTA-Animationen je nach Service (Enter -> Loop -> Exit)
    local A
    if scene == 'blowjob' then
        A = {
            e1h='proposition_to_BJ_p1_prostitute', e2h='proposition_to_BJ_p2_prostitute', lh='BJ_loop_prostitute',
            x1h='BJ_to_proposition_p1_prostitute', x2h='BJ_to_proposition_p2_prostitute',
            e1p='proposition_to_BJ_p1_male',       e2p='proposition_to_BJ_p2_male',       lp='BJ_loop_male',
            x1p='BJ_to_proposition_p1_male',       x2p='BJ_to_proposition_p2_male',
            speech = playerFemale and 'SEX_ORAL_FEM' or 'SEX_ORAL'
        }
    else
        A = {
            e1h='proposition_to_sex_p1_prostitute', e2h='proposition_to_sex_p2_prostitute', lh='sex_loop_prostitute',
            x1h='sex_to_proposition_p1_prostitute', x2h='sex_to_proposition_p2_prostitute',
            e1p='proposition_to_sex_p1_male',       e2p='proposition_to_sex_p2_male',       lp='sex_loop_male',
            x1p='sex_to_proposition_p1_male',       x2p='sex_to_proposition_p2_male',
            speech = playerFemale and 'SEX_GENERIC_FEM' or 'SEX_GENERIC'
        }
    end

    loadAnimDict(DICT)

    -- Paar-Animation synchron auf Hure + Spieler
    local function pair(hookerAnim, playerAnim, flag, doWait)
        local t = GetAnimDuration(DICT, hookerAnim) * 1000
        if t <= 0 then t = 1500 end
        t = math.floor(t)
        local dur = (flag == 1) and -1 or t   -- Loop = unendlich, Enter/Exit = feste Länge
        if DoesEntityExist(activePed) then
            TaskPlayAnim(activePed, DICT, hookerAnim, 2.0, 2.0, dur, flag, 0.0, false, false, false)
        end
        TaskPlayAnim(player, DICT, playerAnim, 2.0, 2.0, dur, flag, 0.0, false, false, false)
        if doWait then Wait(t) end
    end

    SendNUIMessage({ action = 'progress', duration = realDuration, label = svc.label })
    stopRideTalk()
    hookerSay(activePed, 'serviceStart')

    if Config.VisibleService then
        if DoesEntityExist(activePed) and not IsPedInVehicle(activePed, veh, false) then
            SetPedIntoVehicle(activePed, veh, 0)
        end
        SetVehicleLights(veh, 1)

        -- ── GTA-Style Kamera: schräg von hinten/oben über den Ped ──
        activeCam = nil
        local camCfg = (Config.Cam and Config.Cam[scene]) or {
            pos = { x = -0.12, y = 0.10, z = 0.56 }, lookAt = { x = 0.32, y = 0.10, z = 0.42 }, fov = 46.0
        }
        local function placeCam()
            if not activeCam then return end
            local p, l = camCfg.pos, camCfg.lookAt
            local camPos = GetOffsetFromEntityInWorldCoords(veh, p.x, p.y, p.z)
            local lookAt = GetOffsetFromEntityInWorldCoords(veh, l.x, l.y, l.z)
            SetCamCoord(activeCam, camPos.x, camPos.y, camPos.z)
            PointCamAtCoord(activeCam, lookAt.x, lookAt.y, lookAt.z)
        end

        -- Spielt eine einmalige Übergangs-Animation (Enter/Exit) mit Steuerungs-
        -- sperre und Kamera-Update pro Frame, damit kein abrupter Schnitt entsteht.
        local function playOnce(hookerAnim, playerAnim)
            local t = math.max(math.floor(GetAnimDuration(DICT, hookerAnim) * 1000), 1500)
            if shouldAbortService() then return false end
            if DoesEntityExist(activePed) then
                TaskPlayAnim(activePed, DICT, hookerAnim, 2.0, 2.0, t, 0, 0.0, false, false, false)
            end
            TaskPlayAnim(player, DICT, playerAnim, 2.0, 2.0, t, 0, 0.0, false, false, false)
            local endTime = GetGameTimer() + t
            while GetGameTimer() < endTime do
                if shouldAbortService() then return false end
                if Config.LockControls then
                    DisableControlAction(0, 71, true)
                    DisableControlAction(0, 72, true)
                    DisableControlAction(0, 59, true)
                    DisableControlAction(0, 75, true)
                end
                if activeCam then placeCam() end
                Wait(0)
            end
            return true
        end
        if Config.UseCinematicCam ~= false then
            activeCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
            placeCam()
            SetCamFov(activeCam, camCfg.fov or 46.0)
            SetCamActive(activeCam, true)
            RenderScriptCams(true, true, 600, true, true)
            ShakeCam(activeCam, 'HAND_SHAKE', 0.12) -- dezentes Wackeln
        end

        -- ── Enter-Animationen (GTA-Stil: Übergang in die Service-Position) ──
        if not playOnce(A.e1h, A.e1p) then releasePlayerLocks(true); return end
        if not playOnce(A.e2h, A.e2p) then releasePlayerLocks(true); return end

        -- ── Loop-Animation ──
        pair(A.lh, A.lp, 1, false)

        -- ── Auto wackeln (nur Sex) ──
        serviceRocking = (scene == 'sex')
        if serviceRocking and Config.RockVehicle then
            CreateThread(function()
                while serviceRocking do
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, -0.5, 0.0, 0.0, 0.0, 0, true, true, true, true, false)
                    Wait(780)
                end
            end)
        end

        -- ── Dauer + Sound + Steuerung sperren + Kamera nachführen ──
        local SEG = 2500   -- ms pro Segment
        for i = 1, (svc.loops or 6) do
            if shouldAbortService() then releasePlayerLocks(true); return end
            if not DoesEntityExist(activePed) then break end

            -- Anim-Dict geladen halten (Engine kann es streamen)
            if not HasAnimDictLoaded(DICT) then loadAnimDict(DICT) end

            -- Animation JEDES Segment neu antriggern, damit die Engine sie
            -- nicht nach ein paar Sekunden stoppt (das war der Abbruch-Bug)
            TaskPlayAnim(activePed, DICT, A.lh, 2.0, 2.0, -1, 49, 0.0, false, false, false)
            TaskPlayAnim(player,    DICT, A.lp, 2.0, 2.0, -1, 49, 0.0, false, false, false)

            -- Falls sie draußen steht: still zurücksetzen (kein TaskClear!)
            if not IsPedInVehicle(activePed, veh, false) then
                SetPedIntoVehicle(activePed, veh, 0)
            end

            -- Sound: GTA Ped-Speech (Stöhnen)
            if not IsAnySpeechPlaying(activePed) then
                PlayPedAmbientSpeechNative(activePed, A.speech, 'SPEECH_PARAMS_FORCE_SHOUTED_CLEAR')
            end
            local segEnd = GetGameTimer() + SEG
            while GetGameTimer() < segEnd do
                if shouldAbortService() then releasePlayerLocks(true); return end
                if Config.LockControls then
                    DisableControlAction(0, 71, true)
                    DisableControlAction(0, 72, true)
                    DisableControlAction(0, 59, true)
                    DisableControlAction(0, 75, true)
                end
                if activeCam then placeCam() end
                Wait(0)
            end
        end
        serviceRocking = false

        -- KeepTask lösen, damit die Exit-Animationen korrekt abspielen können
        SetPedKeepTask(player, false)
        if DoesEntityExist(activePed) then SetPedKeepTask(activePed, false) end

        -- ── Exit-Animationen (GTA-Stil: sauber zurück in Sitzposition) ──
        if not playOnce(A.x1h, A.x1p) then releasePlayerLocks(true); return end
        if not playOnce(A.x2h, A.x2p) then releasePlayerLocks(true); return end

        SetVehicleLights(veh, 0)

        -- Animationen sauber abschließen (Sicherheits-Stop nach den Exit-Anims)
        stopPlayerServiceAnimations(player)   -- nur Anim-Task; ClearPedTasks würde den Vehicle-Task stören und das Auto einfrieren
        if DoesEntityExist(activePed) then
            StopAnimTask(activePed, DICT, A.x2h, 4.0)
            ClearPedSecondaryTask(activePed)
        end

        -- Kamera freigeben -> zurück zur normalen Gameplay-Kamera
        if activeCam then
            RenderScriptCams(false, true, 600, true, true)
            Wait(350)
            DestroyCam(activeCam, true)
            activeCam = nil
        end

        -- Steuerung wieder komplett freigeben
        EnableAllControlActions(0)
    else
        -- Fade-to-Black-Variante
        DoScreenFadeOut(800)
        Wait(900)
        local secs = (svc.loops or 6) * 3
        local elapsed = 0
        while elapsed < secs do
            if shouldAbortService() then releasePlayerLocks(false); return end
            Wait(1000)
            elapsed = elapsed + 1
        end
        DoScreenFadeIn(800)
        Wait(400)
    end

    if shouldAbortService() then releasePlayerLocks(false); return end

    serviceFailSafeUntil = 0
    serviceAbortRequested = false
    releasePlayerLocks(false)   -- Anims bereits über StopAnimTask+ClearPedSecondaryTask beendet; kein Force-Clear nötig
    if Config.RestoreHealth then SetEntityHealth(player, GetEntityMaxHealth(player)) end
    if Config.RestoreArmor then SetPedArmour(player, 100) end
    startPostServiceWatchdog(veh, activePed, 'service-end')

    -- Hure steigt aus und geht
    if DoesEntityExist(activePed) then
        SetPedConfigFlag(activePed, 26, false)
        SetBlockingOfNonTemporaryEvents(activePed, false)
        local v = GetVehiclePedIsIn(activePed, false)
        -- Nach dem Exit-Anim-Cleanup verliert der Ped kurz seinen Vehicle-Handle,
        -- obwohl er optisch noch im Service-Fahrzeug sitzt. Dann das bekannte
        -- Service-Fahrzeug wiederverwenden, damit TaskLeaveVehicle zuverlässig greift.
        if v == 0 and DoesEntityExist(veh) then
            v = veh
            dbg('[EXIT] Fallback auf Service-Fahrzeug:', v)
        end
        local pedDead = IsPedDeadOrDying(activePed, true)
        dbg('[EXIT] Service-Ende: ped=', activePed, 'veh=', v, 'dead=', pedDead)
        if v ~= 0 and not pedDead then TaskLeaveVehicle(activePed, v, 0) end
        SetEntityAsNoLongerNeeded(activePed)
        local toDelete = activePed
        -- Warten bis die Ausstieg-Animation fertig ist, erst dann wandern
        CreateThread(function()
            dbg('[EXIT] Warte auf Fahrzeug-Ausstieg: ped=', toDelete, 'veh=', v)
            local t0 = GetGameTimer()
            while v ~= 0 and DoesEntityExist(toDelete) and not IsPedDeadOrDying(toDelete, true) and IsPedInVehicle(toDelete, v, false) and GetGameTimer() - t0 < 6000 do
                Wait(200)
            end
            if DoesEntityExist(toDelete) then
                if IsPedDeadOrDying(toDelete, true) then
                    dbg('[EXIT] Ped ist tot – überspringe Wandern, lösche sofort.')
                    DeleteEntity(toDelete)
                    return
                end
                dbg('[EXIT] Ped draußen – starte Wandern.')
                TaskWanderStandard(toDelete, 10.0, 10)
            else
                dbg('[EXIT] Ped existiert nicht mehr.')
            end
            SetTimeout(15000, function()
                if DoesEntityExist(toDelete) then
                    dbg('[EXIT] Timeout – lösche Ped.')
                    DeleteEntity(toDelete)
                end
            end)
        end)
    end

    hookerSay(activePed, 'pleased')
    notify('~g~Service erledigt.~w~')
    lastService = GetGameTimer()
    activePed = nil
    targetSpot = nil
    setState('IDLE')
end
-- ════════════════════════════════════════════════════════════════
--  AUFRÄUMEN
-- ════════════════════════════════════════════════════════════════
function cleanupEscort(msg)
    local wasService = (state == 'SERVICE')
    local cleanupPed = activePed
    serviceAbortRequested = true
    serviceFailSafeUntil = 0
    stopRideTalk()
    if msg then notify(msg) end
    if spotBlip then RemoveBlip(spotBlip); spotBlip = nil end
    local cleanupVeh = 0
    if activePed and DoesEntityExist(activePed) then
        SetBlockingOfNonTemporaryEvents(activePed, false)
        cleanupVeh = GetVehiclePedIsIn(activePed, false)
        local pedDead = IsPedDeadOrDying(activePed, true)
        dbg('[CLEANUP] cleanupEscort: ped=', activePed, 'veh=', cleanupVeh, 'dead=', pedDead, 'msg=', msg)
        if cleanupVeh ~= 0 and not pedDead then TaskLeaveVehicle(activePed, cleanupVeh, 0) end
        SetEntityAsNoLongerNeeded(activePed)
        local toDelete = activePed
        local leaveVeh = cleanupVeh
        -- Warten bis die Ausstieg-Animation fertig ist, erst dann wandern
        CreateThread(function()
            dbg('[CLEANUP] Warte auf Fahrzeug-Ausstieg: ped=', toDelete, 'veh=', leaveVeh)
            local t0 = GetGameTimer()
            while DoesEntityExist(toDelete) and not IsPedDeadOrDying(toDelete, true) and leaveVeh ~= 0 and IsPedInVehicle(toDelete, leaveVeh, false) and GetGameTimer() - t0 < 6000 do
                Wait(200)
            end
            if DoesEntityExist(toDelete) then
                if IsPedDeadOrDying(toDelete, true) then
                    dbg('[CLEANUP] Ped ist tot – überspringe Wandern, lösche sofort.')
                    DeleteEntity(toDelete)
                    return
                end
                dbg('[CLEANUP] Ped draußen – starte Wandern.')
                TaskWanderStandard(toDelete, 10.0, 10)
            else
                dbg('[CLEANUP] Ped existiert nicht mehr.')
            end
            SetTimeout(15000, function()
                if DoesEntityExist(toDelete) then
                    dbg('[CLEANUP] Timeout – lösche Ped.')
                    DeleteEntity(toDelete)
                end
            end)
        end)
    end
    releasePlayerLocks(state == 'SERVICE')
    if wasService or isPlayerInServiceAnimation(PlayerPedId()) then
        startPostServiceWatchdog(cleanupVeh, cleanupPed, 'cleanup')
    else
        stopPostServiceWatchdog()
    end
    activePed = nil
    targetSpot = nil
    setState('IDLE')
end

local function triggerEmergencyRecovery(msg)
    dbg('Emergency recovery triggered:', msg or 'no message')
    releasePlayerLocks(true)
    cleanupEscort(msg or '~r~Sicherheits-Fallback ausgelöst.')
end

CreateThread(function()
    while true do
        local now = GetGameTimer()
        local recoverMsg = nil

        if state == 'MENU' and now - stateChangedAt > MENU_FAILSAFE_MS then
            recoverMsg = '~r~Fallback: Menü wurde sicher beendet.'
        elseif (state == 'RECRUITED' or state == 'RECRUITED_FOOT') and now - stateChangedAt > RECRUIT_FAILSAFE_MS then
            recoverMsg = '~r~Fallback: Vorgang wurde sicher zurückgesetzt.'
        elseif state == 'FOLLOWING' and now - stateChangedAt > ((Config.FollowRecruitTimeoutMs or 60000) + FOLLOW_FAILSAFE_BUFFER_MS) then
            recoverMsg = '~r~Fallback: Folgen wurde sicher abgebrochen.'
        elseif state == 'SERVICE' and serviceFailSafeUntil > 0 and now > serviceFailSafeUntil then
            recoverMsg = '~r~Fallback: Service wurde sicher beendet.'
        elseif state == 'IDLE' and postServiceRecoveryUntil > now and isPlayerInServiceAnimation(PlayerPedId()) then
            recoverMsg = '~r~Fallback: Spielerstatus wurde freigegeben.'
        end

        if recoverMsg then
            triggerEmergencyRecovery(recoverMsg)
            Wait(1000)
        else
            Wait(500)
        end
    end
end)

RegisterCommand('sexreset', function()
    triggerEmergencyRecovery('~g~Fallback ausgeführt. Du bist wieder frei.')
end, false)

-- ════════════════════════════════════════════════════════════════
--  HAUPT-LOOP (State Machine)
-- ════════════════════════════════════════════════════════════════
CreateThread(function()
    while true do
        local sleep = 500
        if state == 'RECRUITED' then
            startRecruit()
        elseif state == 'RECRUITED_FOOT' then
            startFollowRecruit()
        elseif state == 'RIDING' then
            sleep = 0
            watchRiding()
        end
        Wait(sleep)
    end
end)

-- Polizei-Blip (optional)
RegisterNetEvent('mtj_prostitution:policeBlip', function(coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Verdächtige Aktivität')
    EndTextCommandSetBlipName(blip)
    SetTimeout(45000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

-- Sicheres Aufräumen beim Resource-Stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopPostServiceWatchdog()
    serviceAbortRequested = true
    serviceFailSafeUntil = 0
    clearPeds()
    if activePed and DoesEntityExist(activePed) then DeleteEntity(activePed) end
    if spotBlip then RemoveBlip(spotBlip) end
    releasePlayerLocks(true)
end)
