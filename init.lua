--io initialize:,5 quantity,6 work,7 key,8 config ttl
quantityPin = 5
gpio.mode(quantityPin, gpio.INT)
gpio.write(quantityPin, gpio.LOW)

workPin = 6
gpio.write(workPin, gpio.LOW)
gpio.mode(workPin, gpio.INPUT)

keyPin = 7
gpio.write(keyPin, gpio.LOW)
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
actionType = "053"
function get(warningType)
    if actionType == "053" then
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
                            1000 * 5,
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
    --8h last get again
    lastWarningType = warningType
    if get8AgainTmr then
        get8AgainTmr:unregister()
        get8AgainTmr = nil
    end
    againCount = 0
    get8AgainTmr = tmr.create()
    get8AgainTmr:alarm(
        1000 * 60,
        tmr.ALARM_AUTO,
        function(timer)
            againCount = againCount + 1
            if againCount >= 480 then
                if lastWarningType then
                    get(lastWarningType)
                end
                againCount = 0
            end
        end
    )
end

--wifi init
--config_running_flag: wifi config is running ,disconnected register don't blink
wifi.setmode(wifi.STATION)
wifi.sta.sleeptype(wifi.LIGHT_SLEEP)

wifi.eventmon.register(
    wifi.eventmon.STA_GOT_IP,
    function(T)
        get("0")
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
    config_running_flag = true
    gpio.write(configPin, gpio.HIGH)
    --save last config
    last_ssid, last_pwd = wifi.sta.getconfig()
    --60s last reload ssid and pwd
    configTmr = tmr.create()
    configTmr:alarm(
        60 * 1000,
        tmr.ALARM_SINGLE,
        function()
            print("after 60s....")
            if configRunningFlag then
                configRunningFlag = nil
                enduser_setup.stop()
                if last_ssid ~= nil then
                    wifi.sta.config({ssid = last_ssid, pwd = last_pwd})
                end
            end
        end
    )
    --startconfig
    wifi.sta.clearconfig()
    wifi.sta.autoconnect(1)
    enduser_setup.start(
        function()
            print("wifi config success")
            config_running_flag = nil
            gpio.write(configPin, gpio.LOW)
            --wifi config end,send a GET
            print("remove 60s tmr")
            configTmr:unregister()
            configTmr = nil
        end
    )
end

--work
function warning()
    print("warning...")
    actionType = "052"
    get("0")
end

function endWarning()
    print("warning end")
    actionType = "053"
    get("0")
end

gpio.trig(
    workPin,
    "both",
    function(level)
        if level == gpio.HIGH then
            warning()
        else
            endWarning()
        end
    end
)

--key press
function keyLongPress()
    print("key long press")
    get("1")
end

gpio.trig(
    keyPin,
    "up",
    function()
        if not keyCheckFlag then
            keyCheckFlag = true
            local key_long_press_count = 0
            tmr:create():alarm(
                20,
                tmr.ALARM_AUTO,
                function(timer)
                    if key_long_press_count == 150 then
                        keyLongPress()
                    end
                    if gpio.read(keyPin) == gpio.HIGH then
                        key_long_press_count = key_long_press_count + 1
                    else
                        timer:unregister()
                        keyCheckFlag = nil
                    end
                end
            )
        end
    end
)
--Boot configuration
do
    local ssid = wifi.sta.getconfig()
    if ssid ~= nil and ssid ~= "" then
        local boot_count = 0
        tmr.create():alarm(
            1000 * 2,
            tmr.ALARM_AUTO,
            function(timer)
                if boot_count >= 5 then
                    boot_count = nil
                    timer:unregister()
                    return
                end
                if wifi.sta.status() == wifi.STA_GOTIP then
                    timer:unregister()
                    http.get(
                        "http://www.zhihuiyanglao.com/gateMagnetController.do?gateDeviceRecord&deviceCode=1",
                        nil,
                        function(code)
                            if code < 0 then
                                startConfig()
                            end
                        end
                    )
                else
                    boot_count = boot_count + 1
                end
            end
        )
    else
        startConfig()
    end
end
