FROM debian:jessie
MAINTAINER David Personette <dperson@dperson.com>

ENV TRANSMISSION_DIR=${TRANSMISSION_DIR:-"/var/lib/transmission-daemon"}

# Install transmission
RUN export DEBIAN_FRONTEND='noninteractive' && \
    apt-get update -qq && \
    apt-get install -qqy --no-install-recommends transmission-daemon curl \
                $(apt-get -s dist-upgrade|awk '/^Inst.*ecurity/ {print $2}') &&\
    apt-get clean && \
    rm $TRANSMISSION_DIR/info && \
    mv $TRANSMISSION_DIR/.config/transmission-daemon $TRANSMISSION_DIR/info && \
    rmdir $TRANSMISSION_DIR/.config && \
    usermod -d $TRANSMISSION_DIR debian-transmission && \
    [ -d $TRANSMISSION_DIR/downloads ] || mkdir -p $TRANSMISSION_DIR/downloads && \
    [ -d $TRANSMISSION_DIR/incomplete ] || mkdir -p $TRANSMISSION_DIR/incomplete && \
    [ -d $TRANSMISSION_DIR/info/blocklists ] || mkdir -p $TRANSMISSION_DIR/info/blocklists && \
    file="$TRANSMISSION_DIR/info/settings.json" && \
    sed -i '/"peer-port"/a\    "peer-socket-tos": "lowcost",' $file && \
    sed -i '/"port-forwarding-enabled"/a\    "queue-stalled-enabled": true,' \
                $file && \
    sed -i '/"queue-stalled-enabled"/a\    "ratio-limit-enabled": true,' \
                $file && \
    sed -i '/"rpc-whitelist"/a\    "speed-limit-up": 10,' $file && \
    sed -i '/"speed-limit-up"/a\    "speed-limit-up-enabled": true,' $file && \
    chown -Rh debian-transmission. $TRANSMISSION_DIR && \
    rm -rf /var/lib/apt/lists/* /tmp/*
COPY transmission.sh /usr/bin/

VOLUME [$TRANSMISSION_DIR]

EXPOSE 9091 51413/tcp 51413/udp

ENTRYPOINT ["transmission.sh"]
