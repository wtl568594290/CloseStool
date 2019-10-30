"# CloseStool" 
io口定义:
1:配网失败，不再唤醒。设置唤醒口为1
5:工作指示,高电平启动，低电平发停止
6:高电平唤醒口，高电平时不睡眠
7:一键呼叫，高电平有效，2.5秒检测
8:配网指示,平时低电平，配网全程高电平，发送消息时高电平

变量:
    _G后缀表示全局变量

发送消息：
    定时器循环检测url消息池，如果池中有url，就发送一次get请求，成功从消息池中去除这个url，失败则重试4次，4次发送不成功，清除消息池。发送过程中设置标志位，防止并发。

电量:
    每次启动或者唤醒时检测一次电量
    960->3v->100
    768->2.4V->0

配网:
    上电配网，即：
        检测wifi.getconfig(),如果ssid为空触发配网程序。
        如果不为空，用10秒时间连接wifi,若是10秒之内未连接上wifi,也会触发配网程序
        1分钟之内未配网,或者配网失败，不再唤醒wifi模组

睡眠：
    消息池为空，并且不处于:启动连网、配网、唤醒口为高、按键按下这几种状态时，自动进入睡眠。睡眠时关闭work口中断。
    唤醒时，重启work口中断，清空并启动消息池。
