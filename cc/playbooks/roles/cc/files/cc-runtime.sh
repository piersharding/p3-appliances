#!/bin/sh

DTE=`date`
echo "Running container[${DTE}]:" >> /tmp/cc-runtime.log
echo "Parameters are[${DTE}]: $@" >> /tmp/cc-runtime.log

/home/piers/code/go/src/github.com/piersharding/singe/singe $@  >> /tmp/cc-runtime.log 2>&1
echo "singe return is [${DTE}]: $?" >> /tmp/cc-runtime.log

eval exec /usr/bin/cc-runtime --debug --log /tmp/cc.log $@

echo "END[${DTE}]: $@" >> /tmp/cc-runtime.log
echo "" >> /tmp/cc-runtime.log
