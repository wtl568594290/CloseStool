-- io init
-- 5:work signal,receive
-- 7:one key warning,receive
-- 8:Network signal,send
pinWork_G = 5
gpio.write(pinWork_G, gpio.LOW)
gpio.mode(pinWork_G, gpio.INT)
gpio.mode(pinWork_G, gpio.INPUT)

gpio.mode(6, gpio.INPUT)

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
    if gpio.read(pinNet_G) == gpio.LOW then
        print("set net high")
        gpio.write(pinNet_G, gpio.HIGH)
    end
end
function setNetLow()
    if gpio.read(pinNet_G) == gpio.HIGH then
        print("set net low")
        gpio.write(pinNet_G, gpio.LOW)
    end
end
--http get
urlList_G = {}
ready_G = true
tryCount_G = 0
tmr.create():alarm(
    1000,
    tmr.ALARM_AUTO,
    function()
        if #urlList_G > 0 then
            if ready_G then
                tryCount_G = tryCount_G + 1
                if tryCount_G <= 5 then
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
            end
        end
    end
)
--insert url
deviceCode_G = string.upper(string.gsub(wifi.sta.getmac(), ":", ""))
action_G, actionStart_G, actionStop_G, warningStart_G, warningStop_G = "053", "052", "053", "1", "0"
function insertURL(warning)
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

--wifi init
wifi.setmode(wifi.STATION)
wifi.sta.autoconnect(1)
wifi.sta.sleeptype(wifi.LIGHT_SLEEP)

--config net
function configNet()
    print("start config net")
    isConfigRun_G = true
    wifi.startsmart(
        0,
        function()
            insertURL(warningStop_G)
            isConfigRun_G = nil
        end
    )
    tmr.create():alarm(
        1000 * 60,
        tmr.ALARM_SINGLE,
        function()
            if isConfigRun_G then
                isConfigRun_G = nil
                wifi.stopsmart()
            end
        end
    )
end

--check wifi
bootCount_G = 0
function boot()
    setNetHigh()
    print("boot")
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

--check pluse
pulseCount_G = 0
function checkPulse(level)
    pulseCount_G = pulseCount_G + 1
    gpio.trig(pinWork_G, level == gpio.HIGH and "down" or "high")
end
gpio.trig(pinWork_G, "high", checkPulse)

--check work
function checkWork(level)
    if level == gpio.HIGH then
        action_G = actionStart_G
        insertURL(warningStop_G)
    else
        action_G = actionStop_G
        insertURL(warningStop_G)
    end
    gpio.trig(pinWork_G, level == gpio.HIGH and "down" or "high")
end
tmr.create():alarm(
    600,
    tmr.ALARM_SINGLE,
    function()
        if pulseCount_G > 3 then
            boot()
            tmr.create():alarm(
                1000 * 12,
                tmr.ALARM_SINGLE,
                function()
                    pulseCount_G = 0
                    gpio.trig(pinWork_G, "high", checkWork)
                end
            )
        else
            gpio.trig(pinWork_G, "high", checkWork)
        end
    end
)
--check key
function checkKey(level)
    gpio.trig(pinKey_G)
    keyCount_G = 0
    tmr.create():alarm(
        100,
        tmr.ALARM_AUTO,
        function(timer)
            if gpio.read(pinKey_G) == gpio.HIGH then
                keyCount_G = keyCount_G + 1
                if keyCount_G == 25 then
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
--welcome
print('welcome...matong by power')
--------------