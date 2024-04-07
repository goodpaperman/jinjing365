#! /bin/sh

# @brief: is MacOS platform
#         mac date a little different with other 
# @retval: 0 - no
# @retval: 1 - yes
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


# @brief: check command existent before run our script
#         useful especially in msys2 on windows
# @param: cmd to check
# @retval: 0 - exist
# @retval: 1 - not exist
function check_cmd()
{
    local cmd=$1
    type "${cmd}" >/dev/null 2>&1
    if [ $? -ne 0 ]; then 
        echo "please install ${cmd} before run this script, fatal error!"
        exit -1
    else 
        echo "check ${cmd} ok"
    fi
}

# do environment check first
check_cmd "jq"
check_cmd "curl"
check_cmd "head"
check_cmd "cat"
check_cmd "awk"
check_cmd "grep"
check_cmd "date"

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
    local userid=$(grep '^userid=' config.ini | head -1 | awk -F'=' '{print $2}')
    local vehicle=$(grep '^vehicle=' config.ini | head -1 | awk -F'=' '{print $2}')
    local auth=$(grep '^authorization=' config.ini | head -1 | awk -F'=' '{print $2}')
    # local source=$(grep '^source=' config.ini | head -1 | awk -F'=' '{print $2}')
    local drivername=$(grep '^drivername=' config.ini | head -1 | awk -F'=' '{print $2}')
    local driverid=$(grep '^driverid=' config.ini | head -1 | awk -F'=' '{print $2}')

    # query current status
    # note: s-source should be quoted to prevent jq complain:
    # jq: error: syntax error, unexpected '-', expecting '}' (Unix shell quoting issues?) at <top-level>, line 1:
    local statereq=$(cat statereq.json | jq --arg sfzmhm "${userid}" --arg timestamp $(date "+%s000") -c '{ v, sfzmhm: $sfzmhm, "s-source", timestamp: $timestamp }')
    echo "state req: ${statereq}" 1>&2
    local stateheader #=() adb shell not support =() initialize an array..
    stateheader[0]="Accept-Language:${lang}"
    stateheader[1]="User-Agent:${agent}"
    # stateheader[2]="source:${source}"
    stateheader[2]="authorization:${auth}"
    stateheader[3]="Content-Type:${content}"
    stateheader[4]="Host:${host}"
    stateheader[5]="Connection:Keep-Alive"
    stateheader[6]="Accept-Encoding:gzip"
    # prevent whole time be truncated to only date
    # for reuse, add content-length alone here..
    local bytes=$(echo ${issuereq} | wc -c)
    bytes=$((bytes-1))   # remove heading spaces and tailing \n
    local length="Content-Length:${bytes}"
    # note: string length != data length, especially for utf-8 characters!!
    #local length="Content-Length:${#statereq}"
    local headers=""
    for var in "${stateheader[@]}"; 
    do
        headers="${headers} -H ${var}"
    done
    echo "state headers: ${headers} -H ${length}" 1>&2
    local resp=$(curl -s -k ${headers} -H ${length} -d "${statereq}" "${stateurl}")
    echo "${resp}" | jq  '.'  1>&2
    # for debug purpose
    # resp=$(cat demo.txt)
    local ret=$(echo "${resp}" | jq -r '.code')
    local msg=$(echo "${resp}" | jq -r '.msg')
    if [ -z "${ret}" -o "${ret}" = "null" -o ${ret} -ne 200 ]; then 
        echo "query permits status failed, code: ${ret}, msg: ${msg}"
        exit 1
    fi

    echo "query permits status ok: ${msg}"

    # check cardid 
    local id=$(echo "${resp}" | jq -r '.data.sfzmhm')
    if [ -z "${id}" -o "${id}" = "null" -o "${id}" != "${userid}" ]; then 
        echo "id [${id}] from user token does not match given [${userid}], fatal error!"
        exit 1
    fi

    local outside6ring="进京证（六环外）"
    # get permit type form response differs with above result: 进京证(六环外)
    # mainly different is the brackets..
    #
    # local outside6ring=$(echo "${resp}" | jq -r '.data.elzmc')
    # if [ -z "${outside6ring}" -o "${outside6ring}" = "null" -o "${outside6ring}" != "进京证(六环外)" ]; then 
    #     echo "permit type [${outside6ring}] incorrect, fatal error!"
    #     exit 1
    # fi

    # check if any permits there
    local vsize=$(echo "${resp}" | jq -r '.data.bzclxx|length')
    if [ -z "${vsize}" -o "${vsize}" = "null" -o ${vsize} -eq 0 ]; then 
        echo "no vehicle (${vsize}) under [${userid}], please add vehicle first!"
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
        echo "no vehicle named <${vehicle}> under [${userid}], fatal error!"
        exit 1
    fi

    echo "find match vehicle <${vehicle}> at index: ${index}"
    # vehicle info needed later in permit issue request..
    local vid=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].vId")
    local hpzl=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].hpzl")
    if [ -z "${vid}" -o "${vid}" = "null" -o \
         -z "${hpzl}" -o "${hpzl}" = "null" ]; then 
        echo "some vehicle fields in state response null, fatal error!"
        exit 1
    fi

    local hour_now=$(date '+%H')
    local issuedate=$(date '+%Y-%m-%d')
    if [ ${hour_now} -ge 12 ]; then 
        # can NOT issue new permit for today if afternoon
        if [ ${IS_MAC} -eq 1 ]; then 
            issuedate=$(date -v+1d '+%Y-%m-%d')
        else 
            issuedate=$(date '+%Y-%m-%d' -d "+1 days")
        fi
    fi

    local psize=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].bzxx|length")
    # echo "psize: ${psize}"
    if [ -n "${psize}" -a "${psize}" != "null" -a ${psize} -gt 0 ]; then 
        # if have more than one permit, one of them must be inside 6th ring
        # in that case, we can not issue new permit with type outside 6th ring..
        if [ ${psize} -gt 1 ]; then 
            echo "have more than 1 permits, can not issue new permit!"
            exit 1
        fi

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
             echo "some permit fields in state response null, fatal error!"
             exit 1
        fi

        # we can issue permit outside sixth ring when last day of permit inside sixth ring, so here just ignore..
        # if [ "${type}" != "${outside6ring}" ]; then 
        #     echo "have permits with type <${type}> != <${outside6ring}>, can not issue new permit!"
        #     exit 1
        # fi

        echo "${man} [${card}] issue permits on <${vehicle}> with type '${type}' status: ${status}"
        # status may 审核通过(生效中) or 审核通过(待生效) or 审核通过(已失效) or 审核通过(已作废) or 审核中 or 失败(审核不通过) or 取消办理中 or 已取消
        #if [ "${status:0:4}" = "审核通过" ]; then 
        case ${status} in
            审核通过*) 
                local daybeg=$(echo "${resp}" | jq -r  ".data.bzclxx[${index}].bzxx[0].yxqs")
                local dayend=$(echo "${resp}" | jq -r  ".data.bzclxx[${index}].bzxx[0].yxqz")
                if [ -z "${daybeg}" -o "${daybeg}" = "null" -o \
                     -z "${dayend}" -o "${dayend}" = "null" ]; then 
                    echo "some permit fields(valid/invalid) in state response null, fatal error!"
                    exit 1
                fi
    
                if [ "${status}" = "审核通过(已失效)" -o "${status}" = "审核通过(已作废)" ]; then 
                    # treate invalid permit as no permit
                    echo "invalid permit find under <${vehicle}>, try issue new.."
                else 
                    local expire=$(echo "${resp}" | jq -r  ".data.bzclxx[${index}].bzxx[0].sxsyts")
                    if [ -z "${expire}" -o "${expire}" = "null" ]; then 
                        echo "some permit fields(valid) in state response null, fatal error!"
                        exit 1
                    fi

                    echo "in effect from ${daybeg} to ${dayend}"
                    # can issue new permits in last day
                    if [ ${expire} -gt 1 ]; then 
                        echo "still in effect, try ${expire} days later .."
                        exit 0
                    fi

                    # mac date performs differs with other unix..
                    if [ ${IS_MAC} -eq 1 ]; then 
                        issuedate=$(date "-v+${expire}d" '+%Y-%m-%d')
                    else 
                        issuedate=$(date '+%Y-%m-%d' -d "+${expire} days")
                    fi
                fi
                ;;
            审核中)
                echo "still in verify, try later.."
                exit 0
                ;;
            取消办理中)
                echo "still in cancel progress, try later.."
                exit 0
                ;;
            "失败(审核不通过)")
                echo "previous issue rejected, try new permit"
                ;;
            已取消)
                echo "previous issue cancelled, try new permit"
                ;;
            *)
                echo "unknown status ${status}, fatal error!"
                exit 1
                ;;
        esac
    else 
        local bnbzyy=$(echo "${resp}" | jq -r ".data.bzclxx[${index}].bnbzyy")
        if [ "${bnbzyy}" = "每个用户同一时间只能为一辆机动车申请办理进京证。" ]; then 
            echo "no permit(${psize}) under <${vehicle}>, but some permits under other vehicles exist.."
            echo "can only issue new permit when no permits exists under [${userid}], do a check"
            exit 1
        fi

        echo "no permit(${psize}) under <${vehicle}>, and no permits under [${userid}], try issue new.."
    fi

    # issue new permit request
    echo "new permit will start from ${issuedate}"
    local issuereq=$(cat issuereq.json | jq --arg hphm "${vehicle}" --arg hpzl "${hpzl}" --arg vid "${vid}" --arg jjrq "${issuedate}" --arg jsrxm "${drivername}" --arg jszh "${driverid}" --arg sfzmhm "${userid}" --arg timestamp $(date "+%s000") -c '{ dabh, hphm: $hphm, hpzl: $hpzl, vId: $vid, jjdq, jjlk, jjlkmc, jjmd, jjmdmc, jjrq: $jjrq, jjzzl, jsrxm: $jsrxm, jszh: $jszh, sfzmhm: $sfzmhm, xxdz, sqdzbdjd, sqdzbdwd }')
    echo "issue req: ${issuereq}" 1>&2
    # time="time:$(date '+%Y-%m-%d %H:%M:%S')"
    bytes=$(echo ${issuereq} | wc -c)
    bytes=$((bytes-1))   # remove heading spaces and tailing \n
    length="Content-Length:${bytes}"
    echo "issue headers: ${headers} -H ${length}" 1>&2
    resp=$(curl -s -k ${headers} -H ${length} -d "${issuereq}" "${issueurl}")
    echo "${resp}" | jq  '.'  1>&2
    # resp=$(cat demo.txt)
    ret=$(echo "${resp}" | jq -r '.code')
    msg=$(echo "${resp}" | jq -r '.msg')
    if [ -z "${ret}" -o "${ret}" = "null" -o ${ret} -ne 200 ]; then 
        echo "issue new permit failed, code: ${ret}, msg: ${msg}"
        exit 1
    fi

    echo "issue new permit status ok: ${msg}"
    exit 0
}

main "$@"
