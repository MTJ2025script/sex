local ESX = exports['es_extended']:getSharedObject()

-- ════════════════════════════════════════════════════════════════
--  ZUSTAND
-- ════════════════════════════════════════════════════════════════
local spawnedPeds   = {}
local pedBlips      = {}
local activePed     = nil
local state         = 'IDLE'
local lastService   = 0
local lastApproachCall = 0
local targetSpot    = nil
local spotBlip      = nil
local externalPeds  = {}

local DEFAULT_RECRUIT_DISTANCE        = 9.0
local SERVICE_ANIM_DICT               = 'mini@prostitutes@sexnorm_veh'
local SERVICE_ANIM_DICT_AF            = 'mini@prostitutes@sexnorm_veh_af'
local SERVICE_ANIM_DICTS              = { SERVICE_ANIM_DICT, SERVICE_ANIM_DICT_AF }
local HOOKER_03_MODEL                 = `s_f_y_hooker_03`
local MENU_FAILSAFE_MS                = 45000
local RECRUIT_FAILSAFE_MS             = 20000
local FOLLOW_FAILSAFE_BUFFER_MS       = 15000
local SERVICE_FAILSAFE_BUFFER_MS      = 30000
local DEFAULT_POST_SERVICE_WATCHDOG_MS = 8000
local ENTRY_STABILIZE_MS              = 1200

local stateChangedAt           = GetGameTimer()
local serviceFailSafeUntil     = 0
local serviceAbortRequested    = false
local activeCam                = nil
local serviceRocking           = false
local postServiceWatchdogToken = 0
local postServiceRecoveryUntil = 0

local SERVICE_PLAYER_ANIMS = {
    'proposition_to_BJ_p1_male',  'proposition_to_BJ_p2_male',
    'BJ_loop_male',
    'BJ_to_proposition_p1_male',  'BJ_to_proposition_p2_male',
    'proposition_to_sex_p1_male', 'proposition_to_sex_p2_male',
    'sex_loop_male',
    'sex_to_proposition_p1_male', 'sex_to_proposition_p2_male',
}

local hookerModelHashes = {}
for _, model in ipairs(Config.PedModels) do
    local hash = (type(model) == 'number') and model or GetHashKey(model)
    hookerModelHashes[hash] = true
end

-- ════════════════════════════════════════════════════════════════
--  EXTERNE PED-REGISTRIERUNG
-- ════════════════════════════════════════════════════════════════
exports('RegisterHooker', function(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) then externalPeds[ped] = true end
end)

exports('UnregisterHooker', function(ped)
    if ped then externalPeds[ped] = nil end
end)

AddEventHandler('mtj_prostitution:registerExternalPed', function(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) then externalPeds[ped] = true end
end)

AddEventHandler('mtj_prostitution:unregisterExternalPed', function(ped)
    if ped then externalPeds[ped] = nil end
end)

-- ════════════════════════════════════════════════════════════════
--  DIALOG-SYSTEM
-- ════════════════════════════════════════════════════════════════
local SPEECH = {
    approach     = { 'HOOKER_OFFER', 'CHAT_STATE', 'GENERIC_HI' },
    approachFoot = { 'HOOKER_OFFER', 'CHAT_STATE', 'GENERIC_HI' },
    enter        = { 'HOOKER_ACCEPT', 'GENERIC_HI', 'CHAT_STATE' },
    ride         = { 'CHAT_STATE', 'CHAT_STATE', 'CHAT_STATE' },
    pleased      = { 'HOOKER_PLEASED', 'GENERIC_BYE', 'CHAT_STATE' },
}

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

local subtitleEndTime = 0
local subtitleText    = ''

local function showSubtitle(text, durationMs)
    subtitleText    = text
    subtitleEndTime = GetGameTimer() + (durationMs or 3500)
end

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

local function hookerSay(ped, phase)
    if not ped or not DoesEntityExist(ped) then return end
    local speeches = SPEECH[phase]
    if speeches then
        local s = speeches[math.random(#speeches)]
        pcall(function()
            PlayPedAmbientSpeechNative(ped, s, 'SPEECH_PARAMS_FORCE_SHOUTED_CLEAR')
        end)
    end
    local lines = DIALOGUE[phase]
    if lines then showSubtitle(lines[math.random(#lines)], 3500) end
end

local rideTalkActive = false

local function startRideTalk()
    if rideTalkActive then return end
    rideTalkActive = true
    CreateThread(function()
        Wait(4000)
        while rideTalkActive and activePed and DoesEntityExist(activePed) and state == 'RIDING' do
            hookerSay(activePed, 'ride')
            Wait(math.random(8000, 14000))
        end
        rideTalkActive = false
    end)
end

local function stopRideTalk()
    rideTalkActive = false
end

-- ════════════════════════════════════════════════════════════════
--  HILFSFUNKTIONEN
-- ════════════════════════════════════════════════════════════════
local function dbg(...)
    if Config.Debug then print('[mtj_prostitution]', ...) end
end

local function setState(newState)
    if state ~= newState then
        state          = newState
        stateChangedAt = GetGameTimer()
    end
end

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

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
    for _, dict in ipairs(SERVICE_ANIM_DICTS) do
        for _, anim in ipairs(SERVICE_PLAYER_ANIMS) do
            if IsEntityPlayingAnim(player, dict, anim, 3) then return true end
        end
    end
    return false
end

local function stopPlayerServiceAnimations(player)
    if not player or player == 0 or not DoesEntityExist(player) then return end
    for _, dict in ipairs(SERVICE_ANIM_DICTS) do
        for _, anim in ipairs(SERVICE_PLAYER_ANIMS) do
            StopAnimTask(player, dict, anim, 4.0)
        end
    end
    ClearPedSecondaryTask(player)
end

local function getServiceAnimDictForPed(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) and GetEntityModel(ped) == HOOKER_03_MODEL then
        return SERVICE_ANIM_DICT_AF
    end
    return SERVICE_ANIM_DICT
end

local function releasePlayerLocks(forceClearTasks)
    local player = PlayerPedId()
    serviceRocking = false
    RenderScriptCams(false, false, 0, true, true)
    if activeCam then
        DestroyCam(activeCam, true)
        activeCam = nil
    end
    if IsScreenFadedOut() then DoScreenFadeIn(0) end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
    EnableAllControlActions(0)
    SetPlayerControl(PlayerId(), true, 0)
    FreezeEntityPosition(player, false)
    if forceClearTasks or isPlayerInServiceAnimation(player) then
        stopPlayerServiceAnimations(player)
        if IsPedInAnyVehicle(player, false) then
            ClearPedTasks(player)
        else
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
    postServiceWatchdogToken  = postServiceWatchdogToken + 1
    postServiceRecoveryUntil  = 0
end

local function startPostServiceWatchdog(veh, ped, reason)
    stopPostServiceWatchdog()
    local token      = postServiceWatchdogToken
    local trackedVeh = (veh and veh ~= 0 and DoesEntityExist(veh)) and veh or 0
    local trackedPed = (ped and ped ~= 0 and DoesEntityExist(ped)) and ped or 0

    CreateThread(function()
        local deadline        = GetGameTimer() + getPostServiceWatchdogMs()
        postServiceRecoveryUntil = deadline

        while postServiceWatchdogToken == token and GetGameTimer() < deadline do
            local player     = PlayerPedId()
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

            local pedReleased = trackedPed == 0
                or trackedVeh == 0
                or (DoesEntityExist(trackedPed) and not IsPedInVehicle(trackedPed, trackedVeh, false))

            if not playerBusy and pedReleased then break end

            Wait(250)
        end

        if postServiceWatchdogToken == token then
            releasePlayerLocks(true)
            if trackedVeh ~= 0 and DoesEntityExist(trackedVeh) then
                SetVehicleLights(trackedVeh, 0)
            end
            postServiceRecoveryUntil = 0
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

local function nearbyPeopleCount(center, radius)
    local count = 0
    local me    = PlayerPedId()
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and ped ~= activePed and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local isPlayer = IsPedAPlayer(ped)
            if (not isPlayer) or Config.PrivacyIncludePlayers then
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
    while not HasModelLoaded(model) and t < 100 do Wait(50); t = t + 1 end
    return HasModelLoaded(model)
end

local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) and t < 100 do Wait(50); t = t + 1 end
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
    if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    return veh
end

-- ════════════════════════════════════════════════════════════════
--  PED FÜR REKRUTIERUNG VORBEREITEN
--  Setzt alle KI-Sperren und löscht laufende Tasks, bevor ein
--  neuer Task (TaskEnterVehicle o. ä.) zugewiesen wird.
-- ════════════════════════════════════════════════════════════════
local function preparePedForRecruitment(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedKeepTask(ped, false)
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
end

-- ════════════════════════════════════════════════════════════════
--  PED NACH SERVICE / ABBRUCH FREIGEBEN
--  Entsperrt KI, lässt den Ped aussteigen, lässt ihn wandern
--  und löscht ihn nach 15 s.
-- ════════════════════════════════════════════════════════════════
local function releasePedAfterService(ped, veh)
    if not ped or not DoesEntityExist(ped) then return end
    if IsPedDeadOrDying(ped, true) then DeleteEntity(ped); return end

    SetPedConfigFlag(ped, 26, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedKeepTask(ped, false)

    local pedVeh = GetVehiclePedIsIn(ped, false)
    if pedVeh == 0 and veh and DoesEntityExist(veh) then pedVeh = veh end

    if pedVeh ~= 0 then TaskLeaveVehicle(ped, pedVeh, 0) end

    SetEntityAsNoLongerNeeded(ped)

    local toDelete = ped
    CreateThread(function()
        local t0 = GetGameTimer()
        while DoesEntityExist(toDelete)
            and not IsPedDeadOrDying(toDelete, true)
            and pedVeh ~= 0
            and IsPedInVehicle(toDelete, pedVeh, false)
            and GetGameTimer() - t0 < 6000
        do
            Wait(200)
        end

        if not DoesEntityExist(toDelete) then return end
        if IsPedDeadOrDying(toDelete, true) then DeleteEntity(toDelete); return end

        TaskWanderStandard(toDelete, 10.0, 10)
        SetTimeout(15000, function()
            if DoesEntityExist(toDelete) then DeleteEntity(toDelete) end
        end)
    end)
end

-- ════════════════════════════════════════════════════════════════
--  PED SPAWNEN
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
                    SetBlipSprite(blip, 121)
                    SetBlipColour(blip, 27)
                    SetBlipScale(blip, 0.8)
                    SetBlipAsShortRange(blip, true)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString('Nutte')
                    EndTextCommandSetBlipName(blip)
                    pedBlips[i] = blip
                end
                count = count + 1
            else
                dbg('Modell konnte nicht geladen werden:', i)
            end
        end
    end
    if count > 0 then dbg('Neue Peds gespawnt:', count) end
end

CreateThread(function()
    while true do
        if isNight() then
            spawnPeds()
        else
            if next(spawnedPeds) and not activePed then clearPeds() end
        end
        Wait(5000)
    end
end)

-- ════════════════════════════════════════════════════════════════
--  SPIEL-POOL-SCAN
-- ════════════════════════════════════════════════════════════════
CreateThread(function()
    while true do
        if isServiceTime() then
            local me         = PlayerPedId()
            local myPos      = GetEntityCoords(me)
            local scanRadius = math.max(getRecruitDistance(), getRecruitDistanceOnFoot()) + 5.0
            for _, ped in ipairs(GetGamePool('CPed')) do
                if ped ~= me
                    and ped ~= activePed
                    and DoesEntityExist(ped)
                    and not IsPedDeadOrDying(ped, true)
                    and isRecognizedHookerPed(ped)
                    and not externalPeds[ped]
                then
                    local pedPos = GetEntityCoords(ped)
                    if #(vector2(pedPos.x, pedPos.y) - vector2(myPos.x, myPos.y)) < scanRadius then
                        local inSpawned = false
                        for _, sp in pairs(spawnedPeds) do
                            if sp == ped then inSpawned = true; break end
                        end
                        if not inSpawned then externalPeds[ped] = true end
                    end
                end
            end
        end
        Wait(2000)
    end
end)

-- ════════════════════════════════════════════════════════════════
--  ANWERBEN
-- ════════════════════════════════════════════════════════════════
CreateThread(function()
    while true do
        local sleep = 750
        if state == 'IDLE' and isServiceTime() and (GetGameTimer() - lastService) > (Config.Cooldown * 1000) then
            local veh = getDriverVehicle()
            if veh then
                -- Per Fahrzeug anwerben
                local vp              = GetEntityCoords(veh)
                local nearest, nearIdx, nearDist = nil, nil, 9999.0
                local nearIsExternal  = false

                for i, ped in pairs(spawnedPeds) do
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        local pc = GetEntityCoords(ped)
                        local d  = #(vector2(vp.x, vp.y) - vector2(pc.x, pc.y))
                        if d < nearDist then nearDist, nearest, nearIdx, nearIsExternal = d, ped, i, false end
                    end
                end
                for ped in pairs(externalPeds) do
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        local pc = GetEntityCoords(ped)
                        local d  = #(vector2(vp.x, vp.y) - vector2(pc.x, pc.y))
                        if d < nearDist then nearDist, nearest, nearIdx, nearIsExternal = d, ped, nil, true end
                    else
                        externalPeds[ped] = nil
                    end
                end

                if nearest and nearDist < getRecruitDistance() then
                    sleep = 0
                    local pc = GetEntityCoords(nearest)
                    if not lastApproachCall or GetGameTimer() - lastApproachCall > 8000 then
                        lastApproachCall = GetGameTimer()
                        hookerSay(nearest, 'approach')
                    end
                    if Config.NoRecruitWhenWanted and GetPlayerWantedLevel(PlayerId()) > 0 then
                        helpText('Sie steigt nicht ein, solange die ~r~Cops~s~ hinter dir her sind.', false)
                    else
                        helpText('Drücke ~INPUT_VEH_HORN~ oder ~INPUT_PICKUP~ um die Begleitung anzuwerben', false)
                        DrawText3D(pc.x, pc.y, pc.z + 1.0, '~y~Begleitung~w~')
                        if IsControlJustPressed(0, Config.HornControl)
                            or IsControlJustPressed(0, 86)
                            or IsControlJustPressed(0, 38)
                        then
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
                -- Zu Fuß anwerben
                local player          = PlayerPedId()
                local pp              = GetEntityCoords(player)
                local nearest, nearIdx, nearDist = nil, nil, 9999.0
                local nearIsExternal  = false

                for i, ped in pairs(spawnedPeds) do
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        local pc = GetEntityCoords(ped)
                        local d  = #(vector2(pp.x, pp.y) - vector2(pc.x, pc.y))
                        if d < nearDist then nearDist, nearest, nearIdx, nearIsExternal = d, ped, i, false end
                    end
                end
                for ped in pairs(externalPeds) do
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        local pc = GetEntityCoords(ped)
                        local d  = #(vector2(pp.x, pp.y) - vector2(pc.x, pc.y))
                        if d < nearDist then nearDist, nearest, nearIdx, nearIsExternal = d, ped, nil, true end
                    else
                        externalPeds[ped] = nil
                    end
                end

                local recruitRange = getRecruitDistanceOnFoot()
                if not nearest or nearDist >= recruitRange then
                    for _, ped in ipairs(GetGamePool('CPed')) do
                        if ped ~= player and ped ~= activePed
                            and DoesEntityExist(ped)
                            and not IsPedDeadOrDying(ped, true)
                            and isRecognizedHookerPed(ped)
                        then
                            local pc = GetEntityCoords(ped)
                            local d  = #(vector2(pp.x, pp.y) - vector2(pc.x, pc.y))
                            if d < nearDist then
                                nearDist, nearest, nearIdx, nearIsExternal = d, ped, nil, true
                                if d < recruitRange then externalPeds[ped] = true end
                            end
                        end
                    end
                end

                if nearest and nearDist < recruitRange then
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
                        if IsControlJustPressed(0, 38) then
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
--  EINSTEIGEN (Fahrzeug-Rekrutierung)
-- ════════════════════════════════════════════════════════════════
local function startRecruit()
    local veh = getDriverVehicle()
    if not veh then setState('IDLE'); activePed = nil; return end
    if not activePed or not DoesEntityExist(activePed) then setState('IDLE'); activePed = nil; return end

    preparePedForRecruitment(activePed)

    notify('~y~Sie kommt...~s~')
    TaskEnterVehicle(activePed, veh, 15000, 0, 2.0, 1, 0)

    local t0 = GetGameTimer()
    while not IsPedInVehicle(activePed, veh, false) do
        Wait(300)
        if not DoesEntityExist(activePed) or not DoesEntityExist(veh) then
            setState('IDLE'); activePed = nil; return
        end
        if GetGameTimer() - t0 > 15000 then
            SetPedIntoVehicle(activePed, veh, 0)
            Wait(500)
            break
        end
    end

    -- Stabilisierungspause: GTA braucht einen Moment um den Sitz zu bestätigen
    Wait(ENTRY_STABILIZE_MS)

    if not DoesEntityExist(activePed) or not IsPedInVehicle(activePed, veh, false) then
        cleanupEscort('~r~Sie hat das Fahrzeug sofort wieder verlassen.')
        return
    end

    notify('~g~Sie ist drin.~s~ Fahr zu einer ~y~abgelegenen Stelle~s~.')
    hookerSay(activePed, 'enter')
    startRideTalk()
    setState('RIDING')
end

-- ════════════════════════════════════════════════════════════════
--  FOLGEMODUS (Fuß-Rekrutierung → gemeinsam zum Fahrzeug)
-- ════════════════════════════════════════════════════════════════
local function startFollowRecruit()
    if not activePed or not DoesEntityExist(activePed) then setState('IDLE'); activePed = nil; return end

    preparePedForRecruitment(activePed)

    notify('~y~Sie folgt dir.~s~ Geh zu deinem ~y~Fahrzeug~s~.')
    setState('FOLLOWING')

    CreateThread(function()
        local t0       = GetGameTimer()
        local TIMEOUT  = Config.FollowRecruitTimeoutMs or 60000
        local MAX_DIST = Config.FollowRecruitMaxDistance or 75.0

        while state == 'FOLLOWING' do
            local player = PlayerPedId()

            if not activePed or not DoesEntityExist(activePed) or IsPedDeadOrDying(activePed, true) then
                cleanupEscort('~r~Sie ist weg.')
                return
            end

            local pp   = GetEntityCoords(player)
            local pc   = GetEntityCoords(activePed)
            local dist = #(vector2(pp.x, pp.y) - vector2(pc.x, pc.y))

            if dist > MAX_DIST then
                cleanupEscort('~r~Sie hat dich verloren.')
                return
            end

            if GetGameTimer() - t0 > TIMEOUT then
                cleanupEscort('~r~Sie ist gegangen. Du hast zu lange gewartet.')
                return
            end

            TaskFollowToOffsetOfEntity(activePed, player, 0.0, -1.0, 0.0, 1.5, -1, 0.5, true)

            local remaining = math.ceil((TIMEOUT - (GetGameTimer() - t0)) / 1000)
            helpText('Geh zu deinem ~y~Fahrzeug~s~. Sie folgt dir. (~r~' .. remaining .. 's~s~)', false)

            local veh = getDriverVehicle()
            if veh then
                preparePedForRecruitment(activePed)
                TaskEnterVehicle(activePed, veh, 15000, 0, 2.0, 1, 0)
                notify('~y~Sie steigt ein...~s~')

                local t1 = GetGameTimer()
                while not IsPedInVehicle(activePed, veh, false) do
                    Wait(300)
                    if not DoesEntityExist(activePed) or not DoesEntityExist(veh) then
                        setState('IDLE'); activePed = nil; return
                    end
                    if GetPedInVehicleSeat(veh, -1) ~= player then
                        cleanupEscort('~r~Vorgang abgebrochen.')
                        return
                    end
                    if GetGameTimer() - t1 > 15000 then
                        SetPedIntoVehicle(activePed, veh, 0)
                        Wait(500)
                        break
                    end
                end

                Wait(ENTRY_STABILIZE_MS)

                if not DoesEntityExist(activePed) or not IsPedInVehicle(activePed, veh, false) then
                    cleanupEscort('~r~Sie hat das Fahrzeug sofort wieder verlassen.')
                    return
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
--  FAHRT: RUHIGE STELLE SUCHEN
-- ════════════════════════════════════════════════════════════════
local lastPrivacyCheck = 0
local cachedNearby     = 0

local function watchRiding()
    local veh = getDriverVehicle()

    if not veh or not activePed or not DoesEntityExist(activePed) then
        cleanupEscort('~r~Vorgang abgebrochen.')
        return
    end

    if not IsPedInVehicle(activePed, veh, false) then
        cleanupEscort('~r~Sie hat das Fahrzeug verlassen.')
        return
    end

    if not isServiceTime() then
        helpText('Zu dieser Uhrzeit läuft nichts. Komm im Zeitfenster wieder.', false)
        return
    end

    local pos   = GetEntityCoords(PlayerPedId())
    local speed = GetEntitySpeed(veh)
    local now   = GetGameTimer()

    if now - lastPrivacyCheck > 400 then
        lastPrivacyCheck = now
        cachedNearby     = nearbyPeopleCount(pos, Config.PrivacyRadius)
    end

    if cachedNearby > 0 then
        helpText('Hier sind zu viele Leute. Fahr weiter zu einer ~y~abgelegenen Stelle~s~.', false)
    elseif speed > Config.MaxStartSpeed then
        helpText('Abgelegene Stelle gefunden. ~g~Halte an~s~, um zu starten.', false)
    else
        helpText('Drücke ~INPUT_CONTEXT~, um die Begleitung zu fragen', false)
        if IsControlJustPressed(0, 38) then
            openServiceMenu()
        end
    end
end

-- ════════════════════════════════════════════════════════════════
--  SERVICE-MENÜ
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
--  SERVICE
-- ════════════════════════════════════════════════════════════════
function runService(svc)
    stopPostServiceWatchdog()
    setState('SERVICE')
    serviceAbortRequested = false
    if spotBlip then RemoveBlip(spotBlip); spotBlip = nil end

    if Config.PoliceAlertChance > 0.0 and math.random() < Config.PoliceAlertChance then
        TriggerServerEvent('mtj_prostitution:policeAlert', GetEntityCoords(PlayerPedId()))
    end

    local player       = PlayerPedId()
    local veh          = GetVehiclePedIsIn(player, false)
    local scene        = svc.scene or 'sex'
    local DICT         = getServiceAnimDictForPed(activePed)
    local playerFemale = (GetEntityModel(player) == GetHashKey('mp_f_freemode_01'))
    local realDuration = (svc.loops or 6) * 2.5

    serviceFailSafeUntil = GetGameTimer() + math.max(math.floor(realDuration * 1000) + SERVICE_FAILSAFE_BUFFER_MS, 45000)

    if veh == 0 or not DoesEntityExist(veh) or not activePed or not DoesEntityExist(activePed) then
        return cleanupEscort('~r~Vorgang abgebrochen.')
    end

    local A
    if scene == 'blowjob' then
        A = {
            e1h = 'proposition_to_BJ_p1_prostitute', e2h = 'proposition_to_BJ_p2_prostitute',
            lh  = 'BJ_loop_prostitute',
            x1h = 'BJ_to_proposition_p1_prostitute', x2h = 'BJ_to_proposition_p2_prostitute',
            e1p = 'proposition_to_BJ_p1_male',       e2p = 'proposition_to_BJ_p2_male',
            lp  = 'BJ_loop_male',
            x1p = 'BJ_to_proposition_p1_male',       x2p = 'BJ_to_proposition_p2_male',
            speech = playerFemale and 'SEX_ORAL_FEM' or 'SEX_ORAL',
        }
    else
        A = {
            e1h = 'proposition_to_sex_p1_prostitute', e2h = 'proposition_to_sex_p2_prostitute',
            lh  = 'sex_loop_prostitute',
            x1h = 'sex_to_proposition_p1_prostitute', x2h = 'sex_to_proposition_p2_prostitute',
            e1p = 'proposition_to_sex_p1_male',       e2p = 'proposition_to_sex_p2_male',
            lp  = 'sex_loop_male',
            x1p = 'sex_to_proposition_p1_male',       x2p = 'sex_to_proposition_p2_male',
            speech = playerFemale and 'SEX_GENERIC_FEM' or 'SEX_GENERIC',
        }
    end

    loadAnimDict(DICT)

    -- Ped vollständig sperren: KI darf während des gesamten Services
    -- keine neuen Tasks (z.B. Fahrzeug verlassen) zuweisen.
    SetBlockingOfNonTemporaryEvents(activePed, true)
    SetPedKeepTask(activePed, true)
    SetPedIntoVehicle(activePed, veh, 0)

    local function stabilize()
        if DoesEntityExist(veh) and activePed and DoesEntityExist(activePed)
            and not IsPedInVehicle(activePed, veh, false)
        then
            SetPedIntoVehicle(activePed, veh, 0)
        end
    end

    SendNUIMessage({ action = 'progress', duration = realDuration, label = svc.label })
    stopRideTalk()
    hookerSay(activePed, 'serviceStart')

    if Config.VisibleService then
        stabilize()
        SetVehicleLights(veh, 1)

        local camCfg = (Config.Cam and Config.Cam[scene]) or {
            pos = { x = -0.12, y = 0.10, z = 0.56 }, lookAt = { x = 0.32, y = 0.10, z = 0.42 }, fov = 46.0
        }

        local function placeCam()
            if not activeCam then return end
            local p, l   = camCfg.pos, camCfg.lookAt
            local camPos = GetOffsetFromEntityInWorldCoords(veh, p.x, p.y, p.z)
            local lookAt = GetOffsetFromEntityInWorldCoords(veh, l.x, l.y, l.z)
            SetCamCoord(activeCam, camPos.x, camPos.y, camPos.z)
            PointCamAtCoord(activeCam, lookAt.x, lookAt.y, lookAt.z)
        end

        local function playOnce(hookerAnim, playerAnim)
            if shouldAbortService() then return false end
            local t = math.max(math.floor(GetAnimDuration(DICT, hookerAnim) * 1000), 1500)
            stabilize()
            if activePed and DoesEntityExist(activePed) then
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
            ShakeCam(activeCam, 'HAND_SHAKE', 0.12)
        end

        if not playOnce(A.e1h, A.e1p) then releasePlayerLocks(true); return end
        if not playOnce(A.e2h, A.e2p) then releasePlayerLocks(true); return end

        if activePed and DoesEntityExist(activePed) then
            TaskPlayAnim(activePed, DICT, A.lh, 2.0, 2.0, -1, 49, 0.0, false, false, false)
        end
        TaskPlayAnim(player, DICT, A.lp, 2.0, 2.0, -1, 49, 0.0, false, false, false)

        serviceRocking = (scene == 'sex')
        if serviceRocking and Config.RockVehicle then
            CreateThread(function()
                while serviceRocking do
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, -0.5, 0.0, 0.0, 0.0, 0, true, true, true, true, false)
                    Wait(780)
                end
            end)
        end

        local SEG = 2500
        for i = 1, (svc.loops or 6) do
            if shouldAbortService() then releasePlayerLocks(true); return end
            if not activePed or not DoesEntityExist(activePed) then break end

            if not HasAnimDictLoaded(DICT) then loadAnimDict(DICT) end

            stabilize()
            TaskPlayAnim(activePed, DICT, A.lh, 2.0, 2.0, -1, 49, 0.0, false, false, false)
            TaskPlayAnim(player,    DICT, A.lp, 2.0, 2.0, -1, 49, 0.0, false, false, false)

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

        SetPedKeepTask(player, false)
        if activePed and DoesEntityExist(activePed) then SetPedKeepTask(activePed, false) end

        if not playOnce(A.x1h, A.x1p) then releasePlayerLocks(true); return end
        if not playOnce(A.x2h, A.x2p) then releasePlayerLocks(true); return end

        SetVehicleLights(veh, 0)
        stabilize()

        stopPlayerServiceAnimations(player)
        if activePed and DoesEntityExist(activePed) then
            StopAnimTask(activePed, DICT, A.x2h, 4.0)
            ClearPedSecondaryTask(activePed)
        end

        if activeCam then
            RenderScriptCams(false, true, 600, true, true)
            Wait(350)
            DestroyCam(activeCam, true)
            activeCam = nil
        end

        EnableAllControlActions(0)
    else
        DoScreenFadeOut(800)
        Wait(900)
        local secs    = (svc.loops or 6) * 3
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

    serviceFailSafeUntil  = 0
    serviceAbortRequested = false
    releasePlayerLocks(true)
    if Config.RestoreHealth then SetEntityHealth(player, GetEntityMaxHealth(player)) end
    if Config.RestoreArmor  then SetPedArmour(player, 100) end
    startPostServiceWatchdog(veh, activePed, 'service-end')

    local finishedPed = activePed
    releasePedAfterService(finishedPed, veh)

    hookerSay(finishedPed, 'pleased')
    notify('~g~Service erledigt.~w~')
    lastService = GetGameTimer()
    activePed   = nil
    targetSpot  = nil
    setState('IDLE')
end

-- ════════════════════════════════════════════════════════════════
--  AUFRÄUMEN (Abbruch / Fehler)
-- ════════════════════════════════════════════════════════════════
function cleanupEscort(msg)
    local wasService = (state == 'SERVICE')
    local cleanupPed = activePed
    local cleanupVeh = (cleanupPed and DoesEntityExist(cleanupPed))
                        and GetVehiclePedIsIn(cleanupPed, false) or 0

    serviceAbortRequested = true
    serviceFailSafeUntil  = 0
    stopRideTalk()
    if msg then notify(msg) end
    if spotBlip then RemoveBlip(spotBlip); spotBlip = nil end

    if cleanupPed then
        releasePedAfterService(cleanupPed, cleanupVeh ~= 0 and cleanupVeh or nil)
    end

    releasePlayerLocks(wasService)

    if wasService or isPlayerInServiceAnimation(PlayerPedId()) then
        startPostServiceWatchdog(cleanupVeh, cleanupPed, 'cleanup')
    else
        stopPostServiceWatchdog()
    end

    activePed  = nil
    targetSpot = nil
    setState('IDLE')
end

-- ════════════════════════════════════════════════════════════════
--  SICHERHEITS-FALLBACK (Watchdog für verklemmte Zustände)
-- ════════════════════════════════════════════════════════════════
local function triggerEmergencyRecovery(msg)
    releasePlayerLocks(true)
    cleanupEscort(msg or '~r~Sicherheits-Fallback ausgelöst.')
end

CreateThread(function()
    while true do
        local now        = GetGameTimer()
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

-- ════════════════════════════════════════════════════════════════
--  NETZWERK-EVENTS
-- ════════════════════════════════════════════════════════════════
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

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopPostServiceWatchdog()
    serviceAbortRequested = true
    serviceFailSafeUntil  = 0
    clearPeds()
    if activePed and DoesEntityExist(activePed) then DeleteEntity(activePed) end
    if spotBlip then RemoveBlip(spotBlip) end
    releasePlayerLocks(true)
end)
