#! /bin/sh

function is_macos()
{
    local os="${OSTYPE/"darwin"//}"
    if [ "$os" != "$OSTYPE" ]; then 
        # darwin: macos
        return 1
    else 
        return 0
    fi
}

is_macos
IS_MAC=$?

function main()
{
    # constant
    local stateurl="https://jjz.jtgl.beijing.gov.cn/pro//applyRecordController/stateList"
    local issueurl="https://jjz.jtgl.beijing.gov.cn/pro//applyRecordController/insertApplyRecord"
    local agent="okhttp-okgo/jeasonlzy"
    local host="jjz.jtgl.beijing.gov.cn"
    local content="application/json;charset=utf-8"
    local lang="zh-CN,zh;q=0.8"
    
    # read config
    local user=$(grep '^user=' config.ini | head -1 | awk -F'=' '{print $2}')
    local idcard=$(grep '^idcard=' config.ini | head -1 | awk -F'=' '{print $2}')
    local vehicle=$(grep '^vehicle=' config.ini | head -1 | awk -F'=' '{print $2}')
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
    stateheader[6]="Host:${host}"
    stateheader[7]="Connection:Keep-Alive"
    stateheader[8]="Accept-Encoding:gzip"
    # prevent whole time be truncated to only date
    # add time alone here..
    # stateheader[10]="time:$(date '+%Y-%m-%d %H:%M:%S')"
    local time="time:$(date '+%Y-%m-%d %H:%M:%S')"
    # for reuse, add content-length alone here..
    local length="Content-Length:${#statereq}"
    # size, what does it mean? seem to be optional..
    # stateheader[11]="size:459"
    local headers=""
    for var in "${stateheader[@]}"; 
    do
        headers="${headers} -H ${var}"
    done
    echo "state headers: ${headers} -H ${time} -H ${length}" 1>&2
    local resp=$(curl -s ${headers} -H "${time}" -H ${length} -d "${statereq}" "${stateurl}")
    echo "${resp}" | jq  '.'  1>&2
    # for debug purpose
    # resp=$(cat demo.txt)
    local ret=$(echo "${resp}" | jq -r '.code')
    local msg=$(echo "${resp}" | jq -r '.msg')
    if [ -z ${ret} -o "${ret}" = "null" -o ${ret} -ne 200 ]; then 
        echo "query permits status failed, code: ${ret}, msg: ${msg}"
        exit 1
    fi

    echo "query permits status ok: ${msg}"

    # check if any permits there
    local vsize=$(echo "${resp}" | jq -r '.data.bzclxx|length')
    if [ -z "${vsize}" -o "${vsize}" = "null" -o ${vsize} -eq 0 ]; then 
        echo "no vehicle (${vsize}) under ${idcard}, please add vehicle first!"
        exit 0
    fi

    local vehicles=$(echo "${resp}" | jq -r '.data.bzclxx[].hphm')
    local find=0
    local index=0
    # echo "${#vehicles}"
    for var in ${vehicles}
    do
        echo "try ${var} "
        if [ "${var}" = "${vehicle}" ]; then 
            # match
            find=1
            break; 
        fi
        index=$((index+1))
    done

    if [ ${find} -eq 0 ]; then 
        # match reach end
        echo "no vehicle named ${vehicle} under ${idcard}, fatal error!"
        exit 1
    fi

    echo "find match vehicle <${vehicle}> at index: ${index}"
    # use by issue request later..
    local vid=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].vId")
    local hpzl=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].hpzl")
    if [ -z "${vid}" -o "${vid}" = "null" -o \
         -z "${hpzl}" -o "${hpzl}" = "null" ]; then 
        echo "some fields in state response null, fatal error!"
        exit 1
    fi

    local issuedate=$(date '+%Y-%m-%d')
    local psize=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].bzxx|length")
    # echo "psize: ${psize}"
    if [ -n "${psize}" -a "${psize}" != "null" -a ${psize} -gt 0 ]; then 
        # has permits, check if in effect
        local status=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].bzxx[0].blztmc")
        local man=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].bzxx[0].jsrxm")
        local card=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].bzxx[0].jszh")
        local type=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].bzxx[0].jjzzlmc")
        local v=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].bzxx[0].hphm")
        if [ -z "${status}" -o "${status}" = "null" -o \
             -z "${man}" -o "${man}" = "null" -o \
             -z "${card}" -o "${card}" = "null" -o \
             -z "${type}" -o "${type}" = "null" -o \
             -z "$v" -o "$v" = "null" -o "$v" != "${vehicle}" ]; then 
             echo "some fields in state response null, fatal error!"
             exit 1
        fi
    
        echo "${man} [${card}] issue permits on <${vehicle}> with type ${type} status: ${status}"
        # status may 审核通过(生效中) or 审核通过(待生效) or 审核中
        #if [ "${status:0:4}" = "审核通过" ]; then 
        case ${status} in
            审核通过*) 
                local expire=$(echo "${resp}" | jq -r  ".data.bzclxx[${index}].bzxx[0].sxsyts")
                local daybeg=$(echo "${resp}" | jq -r  ".data.bzclxx[${index}].bzxx[0].yxqs")
                local dayend=$(echo "${resp}" | jq -r  ".data.bzclxx[${index}].bzxx[0].yxqz")
                if [ -z "${expire}" -o "${expire}" = "null" -o \
                     -z "${daybeg}" -o "${daybeg}" = "null" -o \
                     -z "${dayend}" -o "${dayend}" = "null" ]; then 
                    echo "some fields in state response null, fatal error!"
                    exit 1
                fi
    
                echo "expire day: ${expire}, from ${daybeg} to ${dayend}"
                # can issue new permits in last day
                if [ ${expire} -gt 1 ]; then 
                    echo "still in effect, try ${expire} days later .."
                    exit 0
                fi

                # make new permit begin day 1 large than the previous end day..
                local to=$((expire+1))
                # mac date performs differs with other unix..
                if [ ${IS_MAC} -eq 1 ]; then 
                    issuedate=$(date "-v+${to}d" '+%Y-%m-%d')
                else 
                    issuedate=$(date '+%Y-%m-%d' -d "+${to} days")
                fi
                echo "issue new permit from ${issuedate}"
                ;;
            审核中)
                echo "still in verify, try later.."
                exit 0
                ;;
            *)
                echo "unknown status ${status}, fatal error!"
                exit 1
                ;;
        esac
    else 
        echo "no permit (${psize}) under ${idcard}, try issue new.."
    fi

    # issue new permit request
    local issuereq=$(cat issuereq.json | jq --arg hphm "${vehicle}" --arg hpzl "${hpzl}" --arg vid "${vid}" --arg jjrq "${issuedate}" --arg jsrxm "${user}" --arg sfzshm "${idcard}" --arg timestamp $(date "+%s") -c '{ hphm: $hphm, hpzl: $hpzl, vId: $vid, jjdq, jjlk, jjlkmc, jjmd, jjmdmc, jjrq: $jjrq, jjzzl, jsrxm: $jsrxm, jszh: $sfzshm, sfzshm: $sfzshm, xxdz, sqdzbdjd, sqdzbdwd }')
    echo "issue req: ${issuereq}" 1>&2
    time="time:$(date '+%Y-%m-%d %H:%M:%S')"
    length="Content-Length:${#issuereq}"
    echo "issue headers: ${headers} -H ${time} -H ${length}" 1>&2
    resp=$(curl -v ${headers} -H "${time}" -H ${length} -d "${issuereq}" "${issueurl}")
    echo "${resp}" | jq  '.'  1>&2
}

main "$@"
