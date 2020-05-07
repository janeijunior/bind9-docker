FROM ubuntu:bionic

RUN apt-get update \
  && apt-get install -y \
  bind9 \
  bind9utils \
  bind9-doc \
  dnsutils \
  wget \
  nano \
  sudo \
  iputils-ping \
  -o Dpkg::Options::="--force-confold" 

# Enable IPv4
RUN sed -i 's/OPTIONS=.*/OPTIONS="-4 -u bind"/' /etc/default/bind9

# RUN mkdir /var/log/named/ && chown bind. /var/log/named/ 

RUN mkdir -m 0770 -p /etc/bind && chown -R root:bind /etc/bind ; \
    mkdir -m 0770 -p /var/cache/bind && chown -R bind:bind /var/cache/bind ; \
    wget -q -O /etc/bind/bind.keys https://ftp.isc.org/isc/bind9/keys/9.11/bind.keys.v9_11 ; \
    rndc-confgen -a

COPY configs/. /etc/bind/

RUN mkdir /var/run/named

VOLUME ["/etc/bind"]
VOLUME ["/var/cache/bind"]

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]

# Run eternal loop
CMD ["/bin/bash", "-c", "while :; do sleep 10; done"]
