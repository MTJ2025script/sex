Config = {}

-- ════════════════════════════════════════════════════════════════
--  ALLGEMEIN
-- ════════════════════════════════════════════════════════════════

Config.Locale = 'de'

-- Nur nachts spawnen (wie in GTA Online). false = immer aktiv.
Config.NightOnly      = true
Config.NightStartHour = 20   -- ab dieser Stunde spawnen Huren
Config.NightEndHour   = 6    -- bis zu dieser Stunde

-- ════════════════════════════════════════════════════════════════
--  ZEITFENSTER: WANN ERLAUBT DAS SCRIPT SEX/SERVICE?
--  Gilt für ALLE Huren (auch die vom npc_dashboard). Außerhalb des
--  Fensters kann nicht angeworben / kein Service gestartet werden.
-- ════════════════════════════════════════════════════════════════
Config.ServiceHours = {
    enabled   = true,   -- false = jederzeit erlaubt (kein Zeitfenster)
    startHour = 20,     -- ab dieser Stunde (0-23)
    endHour   = 6,      -- bis zu dieser Stunde (0-23) - darf über Mitternacht gehen
}

-- Reichweite, in der eine Hure per Hupe angeworben werden kann
-- (2D-Distanz vom AUTO, Höhe wird ignoriert -> Straße zu Gehweg funktioniert)
Config.RecruitDistance = 9.0

-- Reichweite, in der eine Hure zu Fuß angesprochen werden kann (2D-Distanz, wie beim Auto)
Config.RecruitDistanceOnFoot = 9.0

-- Folgephase zu Fuß: so weit darf die Begleitung maximal zurückfallen,
-- bevor der Vorgang abbricht.
Config.FollowRecruitMaxDistance = 75.0

-- Folgephase zu Fuß: so lange wartet die Begleitung darauf, dass du als
-- Fahrer in ein Fahrzeug einsteigst.
Config.FollowRecruitTimeoutMs = 60000

-- Karten-Blips für die Huren anzeigen (damit du die ECHTEN findest)
Config.ShowBlips = true

-- Debug-Ausgaben in der F8-Konsole (Spawn-Anzahl etc.)
Config.Debug = true

-- Privatsphäre: KEINE feste Ecke mehr. Der Spieler muss selbst eine Stelle
-- ohne NPCs finden (wie in GTA Online). So nah dürfen KEINE Leute sein:
Config.PrivacyRadius        = 25.0   -- Meter - im Umkreis dürfen keine NPCs stehen
Config.PrivacyIncludePlayers = false -- true = auch andere SPIELER müssen weg sein
Config.MaxStartSpeed        = 2.0    -- m/s (~7 km/h) - quasi Stillstand zum Starten

-- Cooldown pro Spieler nach einem Service (in Sekunden)
Config.Cooldown = 60

-- Chance auf Polizei-Alarm beim Service (0.0 = nie, 1.0 = immer)
Config.PoliceAlertChance = 0.4
Config.PoliceAlertJob    = 'police'

-- Wanted-Level: Nutte steigt nicht ein, solange du gesucht wirst (GTA-Style)
Config.NoRecruitWhenWanted = true

-- ════════════════════════════════════════════════════════════════
--  BEZAHLUNG
--  Standard wie GTA: DER SPIELER ZAHLT die Hure.
--  Auf 'earn' stellen, wenn der Spieler stattdessen Geld bekommen soll
--  (z.B. wenn er selbst die Rolle spielt).
-- ════════════════════════════════════════════════════════════════

Config.Direction = 'pay'   -- 'pay' = Spieler zahlt | 'earn' = Spieler bekommt
Config.Account   = 'money' -- 'money' = Bargeld | 'bank'

-- Service-Stufen. scene = 'blowjob' oder 'sex' (echte GTA-Animationen).
-- loops = wie oft die Loop-Animation wiederholt wird (= Länge).
-- image = Foto im Ordner html/img/  (einfach austauschen, Name gleich lassen)
Config.Services = {
    { label = 'Blowjob',       price = 100, scene = 'blowjob', loops = 12, health = 25,  image = 'service1.png' },
    { label = 'Normal',        price = 250, scene = 'sex',     loops = 20, health = 50,  image = 'service2.png' },
}

-- Health/Armor wie in GTA wieder auffüllen?
Config.RestoreHealth = true
Config.RestoreArmor  = true

-- ════════════════════════════════════════════════════════════════
--  SICHTBARER SERVICE
-- ════════════════════════════════════════════════════════════════

Config.VisibleService = true   -- true = echte GTA-Animationen sichtbar | false = Fade-to-Black
Config.UseCinematicCam = true  -- GTA-Style Kamera: schräg von hinten/oben über den Ped
Config.RockVehicle    = true   -- Auto wackelt während des Sex
Config.LockControls   = true   -- Fahrsteuerung während Service sperren

-- Kamera pro Szene (Offsets relativ zum Fahrzeug, zum Feintunen).
--   x = rechts(+) / links(-)   y = vorne(+) / hinten(-)   z = oben(+) / unten(-)
--   fov: kleiner = näher rangezoomt
Config.Cam = {
    -- Blowjob: Kamera von der Rücksitzbank (rechts hinten) auf den Fahrerplatz
    blowjob = {
        pos    = { x = 0.35, y = -0.9, z = 0.65 },
        lookAt = { x = -0.35, y = 0.25, z = 0.45 },
        fov    = 55.0,
    },
    -- Sex: identisch - Rücksitzbank auf Fahrerplatz
    sex = {
        pos    = { x = 0.35, y = -0.9, z = 0.65 },
        lookAt = { x = -0.35, y = 0.25, z = 0.45 },
        fov    = 55.0,
    },
}

-- Die Sex-/Blowjob-Animationen sind die echten GTA-Online-Animationen aus
-- "mini@prostitutes@sexnorm_veh" (Enter -> Loop -> Exit) und werden je nach
-- gewähltem Service (blowjob/sex) automatisch abgespielt. Nichts einzustellen.

-- ════════════════════════════════════════════════════════════════
--  PEDS (Hurenmodelle)
-- ════════════════════════════════════════════════════════════════

-- NUR die echten GTA-Online-Hooker-Modelle eintragen!
-- Generische Ambient-Models (a_f_y_*) NICHT hier hinzufügen –
-- diese erscheinen überall in der Spielwelt und würden als Eskorte erkannt.
-- npc_dashboard-Peds werden automatisch über RegisterHooker/registerExternalPed eingetragen.
Config.PedModels = {
    `s_f_y_hooker_01`,
    `s_f_y_hooker_02`,
    `s_f_y_hooker_03`,
}

-- true = erkennt zusätzlich normale weibliche NPC-Peds (Standard-FiveM-Peds)
-- WICHTIG: auf false lassen! Nur Modelle aus Config.PedModels werden als Hure erkannt.
Config.EnableStandardPedRecognition = false

-- ════════════════════════════════════════════════════════════════
--  SPAWN-ORTE (wo die Huren an der Straße stehen)
--  heading = Blickrichtung
-- ════════════════════════════════════════════════════════════════

Config.SpawnPoints = {
    vector4(141.0,  -1306.0, 29.2, 300.0),  -- Strip Club / Strawberry
    vector4(316.0,  -1413.0, 31.4, 50.0),
    vector4(-1149.0, -1399.0, 5.0,  120.0), -- Vespucci Beach
    vector4(-1393.0, -591.0,  30.3, 30.0),
    vector4(906.0,  -1500.0, 30.7, 270.0),
    vector4(450.0,  -1290.0, 29.0, 180.0),
    vector4(-577.0,  -1063.0, 22.3, 90.0),
    vector4(1145.0, -1530.0, 34.5, 0.0),
}

-- ════════════════════════════════════════════════════════════════
--  (Keine festen ruhigen Ecken mehr - der Spieler sucht sich selbst
--   eine Stelle ohne NPCs, siehe Config.PrivacyRadius oben.)
-- ════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
--  TASTEN
-- ════════════════════════════════════════════════════════════════

Config.HornControl = 86  -- INPUT_VEH_HORN (Standard-Hupe)
