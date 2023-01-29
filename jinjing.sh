#! /bin/sh

function main()
{
    # constant
    local stateurl="https://jjz.jtgl.beijing.gov.cn/pro//applyRecordController/stateList"
    local agent="okhttp-okgo/jeasonlzy"
    local host="jjz.jtgl.beijing.gov.cn"
    local content="application/json;charset=utf-8"
    local lang="zh-CN,zh;q=0.8"
    
    # read config
    local idcard=$(grep '^idcard=' config.ini | head -1 | awk -F'=' '{print $2}')
    local auth=$(grep '^authorization=' config.ini | head -1 | awk -F'=' '{print $2}')
    local source=$(grep '^source=' config.ini | head -1 | awk -F'=' '{print $2}')
    local localip=$(grep '^localip=' config.ini | head -1 | awk -F'=' '{print $2}')

    # query current status
    # note: s-source should be quoted to prevent jq complain:
    # jq: error: syntax error, unexpected '-', expecting '}' (Unix shell quoting issues?) at <top-level>, line 1:
    local statereq=$(cat statereq.json | jq --arg sfzshm "${idcard}" --arg timestamp $(date "+%s") -c '{ v, sfzshm: $sfzshm, "s-source", timestamp: $timestamp }')
    echo "state req: ${statereq}" 1>&2
    local stateheader=()
    stateheader[0]="ip:${localip}"
    stateheader[1]="Accept-Language:${lang}"
    stateheader[2]="User-Agent:${agent}"
    stateheader[3]="source:${source}"
    stateheader[4]="authorization:${auth}"
    stateheader[5]="Content-Type:${content}"
    stateheader[6]="Content-Length:${#statereq}"
    stateheader[7]="Host:${host}"
    stateheader[8]="Connection:Keep-Alive"
    stateheader[9]="Accept-Encoding:gzip"
    # prevent whole time be truncated to only date
    # add time alone here..
    # stateheader[10]="time:$(date '+%Y-%m-%d %H:%M:%S')"
    local time="time:$(date '+%Y-%m-%d %H:%M:%S')"
    # size, what does it mean? seem to be optional..
    # stateheader[11]="size:459"
    local headers=""
    for var in "${stateheader[@]}"; 
    do
        headers="${headers} -H ${var}"
    done
    echo "state headers: ${headers} -H ${time}" 1>&2
    local resp=$(curl -s ${headers} -H "${time}" -d "${statereq}" "${stateurl}")
    echo "${resp}" | jq  '.'  1>&2
    local ret=$(echo "${resp}" | jq -r '.code')
    local msg=$(echo "${resp}" | jq -r '.msg')
    if [ -z ${ret} -o "${ret}" = "null" -o ${ret} -ne 200 ]; then 
        echo "query permits status failed, code: ${ret}, msg: ${msg}"
        exit 1
    fi

    echo "query permits status ok: ${msg}"

    # check if in effect

    # issue new permits request
}

main "$@"
