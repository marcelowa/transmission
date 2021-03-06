#!/usr/bin/env bash
#===============================================================================
#          FILE: transmission.sh
#
#         USAGE: ./transmission.sh
#
#   DESCRIPTION: Entrypoint for transmission docker container
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: David Personette (dperson@gmail.com),
#  ORGANIZATION:
#       CREATED: 09/28/2014 12:11
#      REVISION: 1.0
#===============================================================================

set -o nounset                              # Treat unset variables as an error

dir="/var/lib/transmission-daemon"

### timezone: Set the timezone for the container
# Arguments:
#   timezone) for example EST5EDT
# Return: the correct zoneinfo file will be symlinked into place
timezone() { local timezone="${1:-EST5EDT}"
    [[ -e /usr/share/zoneinfo/$timezone ]] || {
        echo "ERROR: invalid timezone specified: $timezone" >&2
        return
    }

    if [[ -w /etc/timezone && $(cat /etc/timezone) != $timezone ]]; then
        echo "$timezone" >/etc/timezone
        ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
        dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1
    fi
}

### usage: Help
# Arguments:
#   none)
# Return: Help text
usage() { local RC=${1:-0}
    echo "Usage: ${0##*/} [-opt] [command]
Options (fields in '[]' are optional, '<>' are required):
    -h          This help
    -n          No auth config; don't configure authentication at runtime
    -t \"\"       Configure timezone
                possible arg: \"[timezone]\" - zoneinfo timezone for container

The 'command' (if provided and valid) will be run instead of transmission
" >&2
    exit $RC
}

while getopts ":hnt:" opt; do
    case "$opt" in
        h) usage ;;
        n) export NOAUTH=true ;;
        t) timezone "$OPTARG" ;;
        "?") echo "Unknown option: -$OPTARG"; usage 1 ;;
        ":") echo "No argument value for option: -$OPTARG"; usage 2 ;;
    esac
done
shift $(( OPTIND - 1 ))

[[ "${TZ:-""}" ]] && timezone "$TZ"
[[ "${USER_ID:-""}" =~ ^[0-9]+$ ]] && usermod -u $USER_ID -o debian-transmission
[[ "${GROUP_ID:-""}" =~ ^[0-9]+$ ]]&& groupmod -g $GROUP_ID -o debian-transmission
for env in $(printenv | grep '^TR_'); do
    name=$(cut -c4- <<< ${env%%=*} | tr '_A-Z' '-a-z')
    val="\"${env##*=}\""
    [[ "$val" =~ ^\"([0-9]+|false|true)\"$ ]] && val=$(sed 's/"//g' <<<$val)
    if grep -q $name $TRANSMISSION_DIR/info/settings.json; then
        sed -i "/\"$name\"/s/:.*/: $val,/" $TRANSMISSION_DIR/info/settings.json
    else
        sed -i 's/\([0-9"]\)$/\1,/' $TRANSMISSION_DIR/info/settings.json
        sed -i "/^}/i\    \"$name\": $val" $TRANSMISSION_DIR/info/settings.json
    fi
done

[[ -d $TRANSMISSION_DIR/downloads ]] || mkdir -p $TRANSMISSION_DIR/downloads
[[ -d $TRANSMISSION_DIR/incomplete ]] || mkdir -p $TRANSMISSION_DIR/incomplete
[[ -d $TRANSMISSION_DIR/info/blocklists ]] || mkdir -p $TRANSMISSION_DIR/info/blocklists

chown -Rh debian-transmission. $TRANSMISSION_DIR 2>&1 | grep -iv 'Read-only' || :

if [[ $# -ge 1 && -x $(which $1 2>&-) ]]; then
    exec "$@"
elif [[ $# -ge 1 ]]; then
    echo "ERROR: command not found: $1"
    exit 13
elif ps -ef | egrep -v 'grep|transmission.sh' | grep -q transmission; then
    echo "Service already running, please restart container to apply changes"
else
    # Initialize blocklist
    url='http://list.iblocklist.com'
    curl -Ls "$url"'/?list=bt_level1&fileformat=p2p&archiveformat=gz' |
                gzip -cd >$TRANSMISSION_DIR/info/blocklists/bt_level1
    chown debian-transmission. $TRANSMISSION_DIR/info/blocklists/bt_level1
    exec su -l debian-transmission -s /bin/bash -c "exec transmission-daemon \
                --config-dir $TRANSMISSION_DIR/info --blocklist --encryption-preferred \
                --dht --foreground --log-error -e /dev/stdout --no-portmap \
                --download-dir $TRANSMISSION_DIR/downloads --incomplete-dir $TRANSMISSION_DIR/incomplete \
                $([[ -z ${NOAUTH:-""} ]] && echo '--auth --username \
                '"${TRUSER:-admin}"' --password '"${TRPASSWD:-admin}") \
                --allowed \\* 2>&1"
fi
