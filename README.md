"# CloseStool" 
io口定义:
5:配网指示,平时低电平，配网全程高电平，发送消息时2秒高电平
6:工作指示,上升沿发送启动，下降沿发送停止
7:一键呼叫，高电平有效，3秒长按
8:电量指示，>2.6V时低电平，<2.5V时高电平，2.5v-2.6v之间不作为


AD:
798->2.5V,832>2.6V

配网:
开机检测wifi.getconfig(),如果ssid为空触发配网程序，如果不为空，发送一条GET请求，无返回值也会触发配网程序

GET请求:
get失败后延时1秒再触发，最多重发5次

电量:
798->10%,977->100%,电量低于10%发送电量低