local ESX = exports['es_extended']:getSharedObject()

-- Anti-Spam: letzter Service-Zeitpunkt pro Spieler
local lastPay = {}

ESX.RegisterServerCallback('mtj_prostitution:pay', function(source, cb, index)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(false, 'Spieler nicht gefunden') end

    local svc = Config.Services[tonumber(index)]
    if not svc then return cb(false, 'Ungültiger Service') end

    -- Cooldown serverseitig erzwingen
    local now = os.time()
    if lastPay[source] and (now - lastPay[source]) < Config.Cooldown then
        return cb(false, 'Du musst noch warten')
    end

    if Config.Direction == 'pay' then
        -- Spieler zahlt
        local balance
        if Config.Account == 'bank' then
            balance = xPlayer.getAccount('bank').money
        else
            balance = xPlayer.getMoney()
        end

        if balance < svc.price then
            return cb(false, 'Nicht genug Geld')
        end

        if Config.Account == 'bank' then
            xPlayer.removeAccountMoney('bank', svc.price)
        else
            xPlayer.removeMoney(svc.price)
        end
    else
        -- Spieler bekommt Geld
        if Config.Account == 'bank' then
            xPlayer.addAccountMoney('bank', svc.price)
        else
            xPlayer.addMoney(svc.price)
        end
    end

    lastPay[source] = now
    cb(true)
end)

-- Polizei-Alarm (optional)
RegisterNetEvent('mtj_prostitution:policeAlert', function(coords)
    local src = source
    for _, playerId in ipairs(GetPlayers()) do
        local xTarget = ESX.GetPlayerFromId(tonumber(playerId))
        if xTarget and xTarget.job and xTarget.job.name == Config.PoliceAlertJob then
            TriggerClientEvent('esx:showNotification', xTarget.source, '~r~Verdächtige Aktivität gemeldet.')
            TriggerClientEvent('mtj_prostitution:policeBlip', xTarget.source, coords)
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastPay[source] = nil
end)
