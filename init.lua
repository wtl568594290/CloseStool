--io initialize:5 work,6 quantity,7 key,8 config ttl
workPin = 5
gpio.mode(workPin, gpio.INPUT)

quantityPin = 6
gpio.mode(quantityPin, gpio.INT)
gpio.write(quantityPin, gpio.LOW)

keyPin = 7
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
function getQuantity()
    local q = adc.read(0)
    local gQ = q
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
quantity = getQuantity()

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
actionStart, actionStop, warningStart, warningStop = "052", "053", "1", "0"
actionType = actionStop
warningType = warningStop
function get(warningType)
    if actionType == actionStart then
        quantity = getQuantity()
    end
    local url =
        string.format(
        "http://www.zhihuiyanglao.com/gateMagnetController.do?gateDeviceRecord&deviceCode=%s&actionType=%s&warningType=%s&quantity=%s",
        deviceCode,
        actionType,
        warningType,
        quantity
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
wifi.sta.sleeptype(wifi.LIGHT_SLEEP)

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

--wifi configuration
function startConfig()
    gpio.write(configPin, gpio.HIGH)
    --60s last reload ssid and pwd
    configTmr = tmr.create()
    configTmr:alarm(
        60 * 1000,
        tmr.ALARM_SINGLE,
        function()
            print("after 60s....")
            wifi.stopsmart()
        end
    )
    --startconfig
    wifi.stopsmart()
    wifi.startsmart(
        0,
        function(ssid, pwd)
            print("config success,info:" .. ssid .. pwd)
            gpio.write(configPin, gpio.LOW)
            print("remove 60s")
            configTmr:unregister()
            configTmr = nil
        end
    )
end

--work
function workStart()
    print("work...")
    actionType = "052"
    get(warningStop)
end

function workStop()
    print("work end")
    actionType = "053"
    get(warningStop)
end
do
    local function workChangecb(level)
        gpio.trig(workPin, level == gpio.HIGH and "down" or "high")
        if level == gpio.HIGH then
            workStart()
        else
            workStop()
        end
    end
    gpio.trig(workPin, "high", workChangecb)
end

--key press
function keyLongPress()
    print("key long press")
    get(warningStart)
end

do
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

--Boot configuration
do
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
