--io initialize:4 led,5 config ttl,6 work,7 key,8 quantity
ledPin = 4
gpio.write(ledPin, gpio.LOW)
gpio.mode(ledPin, gpio.OUTPUT)

configPin = 5
gpio.write(configPin, gpio.LOW)

workPin = 6
gpio.write(workPin, gpio.LOW)
gpio.mode(workPin, gpio.INPUT)

keyPin = 7
gpio.write(keyPin, gpio.LOW)
gpio.mode(keyPin, gpio.INPUT)

quantityPin = 8
gpio.write(quantityPin, gpio.LOW)

--quantity check
--0-1024:0-3.3V
if adc.force_init_mode(adc.INIT_ADC) then
    node.restart()
    return -- don't bother continuing, the restart is scheduled
end
tmr.create():alarm(
    1000 * 60 * 60,
    tmr.ALARM_AUTO,
    function()
        local q = adc.read(0)
        if q > 900 then
            gpio.write(quantityPin, gpio.LOW)
        elseif q < 837 then
            gpio.write(quantityPin, gpio.high)
        end
    end
)

--led blink
--high:light,low:black
--type:1-short blink,2-long blink,3-blink 3,4-long light
function ledBlink(type)
    type = type == nil and 1 or type
    local array = {200 * 1000, 200 * 1000}
    if type == 2 then
        array = {1000 * 1000, 500 * 1000}
    end
    local cycle = 100
    if type == 3 then
        cycle = 3
    elseif type == 4 then
        cycle = 1
    end
    gpio.serout(
        ledPin,
        gpio.HIGH,
        array,
        cycle,
        function()
            if type == 1 then
                ledBlink(1)
            elseif type == 2 then
                ledBlink(2)
            end
        end
    )
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
function get(actionType, warningType, quantity)
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
        -- --blink 3 times,2s high
        gpio.serout(configPin, gpio.HIGH, {1000 * 1000 * 2}, 1, 1)
        ledBlink(3)
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
                            1000,
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
--config_running_flag: wifi config is running ,disconnected register don't blink
wifi.setmode(wifi.STATION)
wifi.sta.sleeptype(wifi.MODEM_SLEEP)

wifi.eventmon.register(
    wifi.eventmon.STA_GOT_IP,
    function(T)
        ledBlink(4)
        --save last config
        last_ssid, last_pwd = wifi.sta.getconfig()
        print("wifi is connected,ip is " .. T.IP)
    end
)

wifi.eventmon.register(
    wifi.eventmon.STA_DISCONNECTED,
    function(T)
        print("\n\tSTA - DISCONNECTED" .. "\n\t\reason: " .. T.reason)
        --Set disconnected_flag to prevent repeated calls
        if not config_running_flag then
            ledBlink(2)
        end
    end
)

--wifi configuration
config_tmr = tmr.create()
config_tmr:register(
    60 * 1000,
    tmr.ALARM_SINGLE,
    function()
        print("after 60s....")
        if config_running_flag then
            ledBlink(4)
            config_running_flag = nil
            gpio.write(configPin, gpio.LOW)
            enduser_setup.stop()
            if last_ssid ~= nil then
                wifi.sta.config({ssid = last_ssid, pwd = last_pwd})
            end
        end
    end
)
function startConfig()
    config_running_flag = true
    gpio.write(configPin, gpio.HIGH)
    wifi.sta.clearconfig()
    wifi.sta.autoconnect(1)
    enduser_setup.start(
        function()
            print("wifi config success")
            config_running_flag = nil
            gpio.write(configPin, gpio.LOW)
            --wifi config end,send a GET
            get("053", "0", "50")
            if config_tmr then
                local running = config_tmr:state()
                if running then
                    print("remove 60s tmr")
                    config_tmr:stop()
                end
            end
        end
    )
    ledBlink()
    config_tmr:start()
end

--work
function warning()
    print("warning...")
    get("052", "0", "100")
end

function endWarning()
    print("warning end")
    get("053", "0", "100")
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
    get("053", "0", "0")
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
