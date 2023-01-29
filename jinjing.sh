#! /bin/sh

function main()
{
    # constant
    local stateurl="https://jjz.jtgl.beijing.gov.cn/pro//applyRecordController/stateList"
    local agent="User-Agent: okhttp-okgo/jeasonlzy"
    local host="jjz.jtgl.beijing.gov.cn"
    local content="application/json;charset=utf-8"
    local lang="zh-CN,zh;q=0.8"
    # read config
    local idcard=$(grep '^idcard=' config.ini | head -1 | awk -F'=' '{print $2}')
    local auth=$(grep '^authorization=' config.ini | head -1 | awk -F'=' '{print $2}')
    local source=$(grep '^source=' config.ini | head -1 | awk -F'=' '{print $2}')
    local localip=$(grep '^localip=' config.ini | head -1 | awk -F'=' '{print $2}')
    # query current status
    local statereq=$(cat statereq.json | jq --arg sfzshm "${idcard}" --arg timestamp $(date "+%s") -c '{ v, sfzshm: $sfzshm, s-source, timestamp: $timestamp }')
    echo "state req: ${statereq}"
    local stateheader=()
    stateheader[0]="ip:${localip}"
    stateheader[1]="time:$(date '+%Y-%m-%d %H:%M:%S')"
    stateheader[2]="Accept-Language:${lang}"
    stateheader[3]="User-Agent:${agent}"
    stateheader[4]="source:${source}"
    stateheader[5]="authorization:${auth}"
    stateheader[6]="Content-Type:${content}"
    stateheader[7]="Content-Length:${#statereq}"
    stateheader[8]="Host:${host}"
    stateheader[9]="Connection:Keep-Alive"
    stateheader[10]="Accept-Encoding:gzip"
    # stateheader[11]="size:459"
    local headers=""
    for var in ${stateheader[@]}; 
    do
        headers="${headers} -H ${var}"
    done
    echo "state headers: ${headers}"
    local resp=$(curl -s -H ${headers} -d "${statereq}" "${stateurl}")
    echo "${resp}"
    echo "${resp}" | jq  '.'
    # issue new permits request
}

main "$@"
