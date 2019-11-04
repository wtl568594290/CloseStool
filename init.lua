-- io init
-- 1:run with not wifi,then never wake device
-- 5:work signal,receive
-- 6:wake pin ,high level wake
-- 7:one key warning,receive
-- 8:Network signal,send
pinNeverWake_G = 1
gpio.write(pinNeverWake_G, gpio.LOW)
gpio.mode(pinNeverWake_G, gpio.INT)
gpio.mode(pinNeverWake_G, gpio.INPUT)

pinWork_G = 5
gpio.write(pinWork_G, gpio.LOW)
gpio.mode(pinWork_G, gpio.INT)
gpio.mode(pinWork_G, gpio.INPUT)

pinWake_G = 6
gpio.write(pinWake_G, gpio.LOW)
gpio.mode(pinWake_G, gpio.INT)
gpio.mode(pinWake_G, gpio.INPUT)

pinKey_G = 7
gpio.write(pinKey_G, gpio.LOW)
gpio.mode(pinKey_G, gpio.INT)
gpio.mode(pinKey_G, gpio.INPUT)

pinNet_G = 8
gpio.mode(pinNet_G, gpio.INT)
gpio.write(pinNet_G, gpio.LOW)

--electronic quantities detection
if adc.force_init_mode(adc.INIT_ADC) then
    node.restart()
    return -- don't bother continuing, the restart is scheduled
end
--return electronic quantity
function getQuantity()
    local q = adc.read(0)
    local gQ = 0
    if q >= 960 then
        gQ = 100
    elseif q < 960 and q >= 768 then
        gQ = math.floor((q - 768) / 1.92)
    else
        gQ = 0
    end
    return gQ
end
quantity_G = getQuantity()

function setNetHigh()
    gpio.write(pinNet_G, gpio.HIGH)
end
function setNetLow()
    gpio.write(pinNet_G, gpio.LOW)
end

--wifi init
wifi.setmode(wifi.STATION)
wifi.sta.autoconnect(1)
wifi.sta.sleeptype(wifi.LIGHT_SLEEP)
--insert url
deviceCode_G = string.upper(string.gsub(wifi.sta.getmac(), ":", ""))
action_G, actionStart_G, actionStop_G, warningStart_G, warningStop_G = "053", "052", "053", "1", "0"
function insertURL(warning)
    if not isConfigRun_G and bootCount_G == 0 then
        setNetHigh()
        local url =
            string.format(
            "http://www.zhihuiyanglao.com/gateMagnetController.do?gateDeviceRecord&deviceCode=%s&actionType=%s&warningType=%s&quantity=%s",
            deviceCode_G,
            action_G,
            warning,
            quantity_G
        )
        table.insert(urlList_G, url)
    end
end
--config net
function configNet()
    isConfigRun_G = true
    print("start config net")
    wifi.startsmart(
        0,
        function()
            isConfigRun_G = nil
            insertURL(warningStop_G)
        end
    )
    tmr.create():alarm(
        1000 * 60,
        tmr.ALARM_SINGLE,
        function()
            if isConfigRun_G then
                -- isConfigRun_G = nil
                wifi.stopsmart()
                --never use wifi
                setNetLow()
                sleepCfg.wake_pin = pinNeverWake_G
                node.sleep(sleepCfg)
            end
        end
    )
end

--boot
bootCount_G = 0
function boot()
    setNetHigh()
    local ssid = wifi.sta.getconfig()
    if ssid == nil or ssid == "" then
        configNet()
    else
        tmr.create():alarm(
            100,
            tmr.ALARM_AUTO,
            function(timer)
                if wifi.sta.status() ~= wifi.STA_GOTIP then
                    bootCount_G = bootCount_G + 1
                    if bootCount_G > 100 then
                        timer:unregister()
                        bootCount_G = 0
                        configNet()
                    end
                else
                    timer:unregister()
                    bootCount_G = 0
                end
            end
        )
    end
end
boot()
--check work
function checkWork(level)
    if level == gpio.HIGH then
        action_G = actionStart_G
    else
        action_G = actionStop_G
    end
    insertURL(warningStop_G)
    gpio.trig(pinWork_G, level == gpio.HIGH and "down" or "high")
end
gpio.trig(pinWork_G, "high", checkWork)

--check key
keyCount_G = 0
function checkKey(level)
    gpio.trig(pinKey_G)
    keyCount_G = 0
    tmr.create():alarm(
        100,
        tmr.ALARM_AUTO,
        function(timer)
            if gpio.read(pinKey_G) == gpio.HIGH then
                keyCount_G = keyCount_G + 1
                if keyCount_G == 29 then
                    insertURL(warningStart_G)
                end
            else
                timer:unregister()
                keyCount_G = 0
                gpio.trig(pinKey_G, "high", checkKey)
            end
        end
    )
end
gpio.trig(pinKey_G, "high", checkKey)
-----------------
-- get request
urlList_G = {}
ready_G = true
tryCount_G = 0
getTmr = tmr.create()
getTmr:register(
    1000,
    tmr.ALARM_AUTO,
    function(timer)
        if #urlList_G > 0 then
            if ready_G then
                tryCount_G = tryCount_G + 1
                tryMax_G = 5
                if string.find(urlList_G[1], "warningType=1") then
                    tryMax_G = 10
                end
                print(tryMax_G)
                if tryCount_G <= tryMax_G then
                    if wifi.sta.status() == wifi.STA_GOTIP then
                        ready_G = false
                        http.get(
                            urlList_G[1],
                            nil,
                            function(code)
                                print(code)
                                if code > 0 then
                                    table.remove(urlList_G, 1)
                                    tryCount_G = 0
                                end
                                ready_G = true
                            end
                        )
                    end
                else
                    urlList_G = {}
                    tryCount_G = 0
                end
            end
        else
            if not isConfigRun_G and bootCount_G == 0 then
                setNetLow()
                if gpio.read(pinWake_G) == gpio.LOW and gpio.read(pinKey_G) == gpio.LOW then
                    print("i m go to sleep")
                    gpio.trig(pinWork_G)
                    timer:stop()
                    node.sleep(sleepCfg)
                end
            end
        end
    end
)
--node light sleep
sleepCfg = {}
sleepCfg.wake_pin = pinWake_G
sleepCfg.int_type = node.INT_HIGH
sleepCfg.resume_cb = function()
    print("i m wake up")
    quantity_G = getQuantity()
    urlList_G = {}
    ready_G = true
    tryCount_G = 0
    gpio.trig(pinWork_G, "high", checkWork)
    getTmr:start()
end
getTmr:start()
--welcome
VERSION = 1.04
print("matong version = " .. VERSION)
