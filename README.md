# jinjing365
automatically issue enter permits (outside the sixth ring) of Beijing 365 days
# usage
sh jinjing.sh 2>verbose.log
# prepare
see config.ini
```
userid=150121198603226428
vehicle=津ADY1951
authorization=f36abdfa-8878-46bf-91d9-5666f808e9a4
source=8724a2428c3f47358741f978fd082810
drivername=云海
driverid=150121198603226428
localip=172.21.222.55
```
modify following fields:
* userid to car owner cardid
* vehicle to car number you want issue permit
* authorization to user token
* source to device code
* drivername to car driver name
* driverid to car driver cardid
* localip to you local ip
## authorization & source
obtain by network package capture APP (e.g. VNET) under android platform
![vnet overview](https://files-cdn.cnblogs.com/files/goodcitizen/vnet_view.bmp?t=1675062652)
![vnet capture](https://files-cdn.cnblogs.com/files/goodcitizen/vnet_capture.bmp?t=1675062645)
## localip
can obtain by following command:
```
> ifconfig | grep '\binet\b'
	inet 127.0.0.1 netmask 0xff000000 
	inet 172.21.222.55 netmask 0xfffffe00 broadcast 172.21.223.255
```
select one that not loopback (127.0.0.1)
# note
support more than one car under same cardid, need indicate the car number (vehicle) in config.ini, this field is required

only issue new permit in following situation:
* no permits under other car belongs to this user and
* no permits under this car or
* has permits outside the sixth ring and
* this permit has expire day less or equal 1

which is:

(condition1 && (condition2 || (condition3 && condtion4)))
# supplement
if you have a permit outside the sixth ring, you can issue new permit inside the sixth ring, but NOT vice versa

if you have a permit on car A and you can not issue new permit on car B/C/D... that belong to this cardid too
# effect
```
> sh jinjing.sh 2>verbose.log
check jq ok
check curl ok
check head ok
check cat ok
check awk ok
check grep ok
check date ok
query permits status ok: 用户办证信息查询成功!
try 津ADY1951 
find match vehicle <津ADY1951> at index: 0
云海 [150121198603226428] issue permits on <津ADY1951> with type '进京证（六环外）' status: 审核通过(生效中)
expire day: 7, from 2023-01-30 to 2023-02-05
still in effect, try 7 days later ..
```
# schedule every day
add oneline in your linux crontab:
```
> crontab -e
0 12 * * * cd /home/users/yunhai01/code/jinjing365; date >> jinjing.log; sh jinjing.sh >> jinjing.log 2>>verbose.log 
```
change directory to where you place jinjing.sh, logs will be 'jinjing.log', detail logs will be 'verbose.log'

other platform like windows can do the same thing with 'schedule tasks' & 'git bash' & 'jq for windows', command with be:
```
cd /path/to/jinjing365
bash.exe jinjing.sh >> jinjing.log 2>>verbose.log
```
# see detail
[https://www.cnblogs.com/goodcitizen/p/issue_enter_permits_of_beijing_outside_sixth_ring_by_shell_scripts.html](https://www.cnblogs.com/goodcitizen/p/issue_enter_permits_of_beijing_outside_sixth_ring_by_shell_scripts.html)
# sponsorship
buy me a cup of tea, I may motivated to develop a new version to get rid of package capture by VNET, using username & password to login instead..

<img src="https://files-cdn.cnblogs.com/files/goodcitizen/wepay.bmp?t=1675132801" width = "400" alt="wechatpay" align=center />
