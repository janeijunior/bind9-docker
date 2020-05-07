#!/bin/sh

echo " 
nameserver 10.5.0.5
nameserver 10.5.0.6
 " > /etc/resolv.conf 


service bind9 restart

/bin/bash", "-c", "while :; do sleep 10000000000; done
