--io initialize:5 work,6 quantity,7 key,8 config ttl
workPin = 5
gpio.write(workPin, gpio.LOW)
gpio.mode(workPin, gpio.INT)
gpio.mode(workPin, gpio.INPUT)

quantityPin = 6
gpio.mode(quantityPin, gpio.INT)
gpio.write(quantityPin, gpio.LOW)

keyPin = 7
gpio.write(keyPin, gpio.LOW)
gpio.mode(keyPin, gpio.INT)
gpio.mode(keyPin, gpio.INPUT)

configPin = 8
gpio.mode(configPin, gpio.INT)
gpio.write(configPin, gpio.LOW)

--quantity check,3min check once
--0-1024:0-3.3V
if adc.force_init_mode(adc.INIT_ADC) then
    node.restart()
    return -- don't bother continuing, the restart is scheduled
end
function getQuantity(q)
    -- local q = adc.read(0)
    local gQ = 0
    if q >= 977 then
        gQ = 100
    elseif q < 977 and q >= 798 then
        gQ = math.floor((q - 798) / (977 - 798) * 90 + 10)
    elseif q < 798 then
        gQ = math.floor(q / 798 * 10)
    end
    if gQ >= 27 then
        gpio.write(quantityPin, gpio.LOW)
    elseif gQ <= 10 then
        gpio.write(quantityPin, gpio.HIGH)
    end
    return gQ
end

--json decode
function decode(str)
    local function local_decode(local_str)
        local json = sjson.decode(local_str)
        return json
    end
    local status, result = pcall(local_decode, str)
    if status then
        return result
    else
        return nil
    end
end

--http get,sending led blink
deviceCode = string.upper(string.gsub(wifi.sta.getmac(), ":", ""))
actionStart, actionStop, actionType, warningStart, warningStop = "052", "053", "053", "1", "0"
function get(warningType)
    local localQuantity = 0
    if actionType == actionStart then
        localQuantity = getQuantity(adc.read(0) + 70)
    else
        localQuantity = getQuantity(adc.read(0))
    end
    local url =
        string.format(
        "http://www.zhihuiyanglao.com/gateMagnetController.do?gateDeviceRecord&deviceCode=%s&actionType=%s&warningType=%s&quantity=%s",
        deviceCode,
        actionType,
        warningType,
        localQuantity
    )
    local tryAgain = 0
    local function localGet(url)
        --2s high
        gpio.serout(configPin, gpio.HIGH, {1000 * 1000 * 2, 0}, 1, 1)
        http.get(
            url,
            nil,
            function(code, data)
                if code == 200 then
                    local json = decode(data)
                    if json then
                        if json.isSuc == "1" then
                            print("operate success")
                        else
                            print("operate failed")
                        end
                    else
                        print("no json")
                    end
                else
                    if tryAgain < 5 then
                        tmr:create():alarm(
                            1000 * 1,
                            tmr.ALARM_SINGLE,
                            function()
                                localGet(url)
                            end
                        )
                    end
                    tryAgain = tryAgain + 1
                    print("get error")
                end
            end
        )
    end
    localGet(url)
end

--wifi init
wifi.setmode(wifi.STATION)
-- wifi.sta.sleeptype(wifi.LIGHT_SLEEP)

wifi.eventmon.register(
    wifi.eventmon.STA_GOT_IP,
    function(T)
        print("wifi is connected,ip is " .. T.IP)
    end
)

wifi.eventmon.register(
    wifi.eventmon.STA_DISCONNECTED,
    function(T)
        print("\n\tSTA - DISCONNECTED" .. "\n\t\reason: " .. T.reason)
    end
)

do
    --wifi configuration
    local function startConfig()
        if not configRunningFlag then
            gpio.write(configPin, gpio.HIGH)
            lastSsid, lastPwd = wifi.sta.getconfig()
            configRunningFlag = true
            local removeCount = 0
            tmr.create():alarm(
                1000 * 1,
                tmr.ALARM_AUTO,
                function(timer)
                    if configSuccessFlag then
                        print("config success")
                        configSuccessFlag = nil
                        configRunningFlag = nil
                        gpio.write(configPin, gpio.LOW)
                        timer:unregister()
                    else
                        removeCount = removeCount + 1
                        if removeCount >= 20 then
                            print("after 60s ...")
                            configRunningFlag = nil
                            gpio.write(configPin, gpio.LOW)
                            wifi.stopsmart()
                            if lastSsid ~= nil and lastSsid ~= "" then
                                wifi.sta.config({ssid = lastSsid, pwd = lastPwd})
                            end
                            timer:unregister()
                        end
                    end
                end
            )
            --startconfig
            wifi.startsmart(
                0,
                function(ssid, pwd)
                    print("config success,info:" .. ssid .. pwd)
                    configSuccessFlag = true
                end
            )
        end
    end

    --boot config wifi
    local function bootConfig()
        local ssid = wifi.sta.getconfig()
        if ssid ~= nil and ssid ~= "" then
            local boot_count = 0
            tmr.create():alarm(
                100,
                tmr.ALARM_AUTO,
                function(timer)
                    if wifi.sta.status() == wifi.STA_GOTIP then
                        timer:unregister()
                        http.get(
                            "http://www.zhihuiyanglao.com/gateMagnetController.do?gateDeviceRecord&deviceCode=1&actionType=0&warningType=0&quantity=0",
                            nil,
                            function(code)
                                if code < 0 then
                                    startConfig()
                                end
                            end
                        )
                    else
                        boot_count = boot_count + 1
                        if boot_count >= 50 then
                            boot_count = nil
                            timer:unregister()
                            startConfig()
                        end
                    end
                end
            )
        else
            startConfig()
        end
    end
    --work
    local function workStart()
        print("work...")
        actionType = "052"
        get(warningStop)
    end

    local function workStop()
        print("work end")
        actionType = "053"
        get(warningStop)
    end

    --boot 600ms flag
    local isFirst600msFlag = true
    tmr:create():alarm(
        600,
        tmr.ALARM_SINGLE,
        function()
            isFirst600msFlag = false
        end
    )
    local function workChangecb(level)
        gpio.trig(workPin)
        local checkCount = 0
        local workLevelChangeCount = 0
        local workLevelNoChangeCount = 0
        local workLevel = level
        local workFlag = false
        tmr:create():alarm(
            100,
            tmr.ALARM_AUTO,
            function(timer)
                checkCount = checkCount + 1
                local checkLevel = gpio.read(workPin)
                if workLevel ~= checkLevel then
                    workLevel = checkLevel
                    workLevelChangeCount = workLevelChangeCount + 1
                    workLevelNoChangeCount = 0
                else
                    workLevelNoChangeCount = workLevelNoChangeCount + 1
                end
                if isFirst600msFlag and checkCount < 7 and workLevelChangeCount == 3 then
                    bootConfig()
                end
                if workLevelNoChangeCount > 3 then
                    if checkLevel == gpio.HIGH then
                        if not workFlag then
                            workFlag = true
                            workStart()
                        end
                    else
                        if workFlag then
                            workStop()
                        end
                        timer:unregister()
                        gpio.trig(workPin, "high", workChangecb)
                    end
                end
            end
        )
    end
    gpio.trig(workPin, "high", workChangecb)
end
--key press
do
    local function keyLongPress()
        print("key long press")
        get(warningStart)
    end
    local function keyChangecb(level)
        gpio.trig(keyPin, level == gpio.HIGH and "down" or "high")
        if level == gpio.HIGH then
            local keyPressCount = 0
            tmr:create():alarm(
                20,
                tmr.ALARM_AUTO,
                function(timer)
                    if gpio.read(keyPin) == gpio.HIGH then
                        keyPressCount = keyPressCount + 1
                        if keyPressCount == 125 then
                            keyLongPress()
                        end
                    else
                        timer:unregister()
                    end
                end
            )
        end
    end
    gpio.trig(keyPin, "high", keyChangecb)
end
