#!/bin/bash
#R CMD Rserve
#sudo mongod
#unicorn -p 8088 -E production

RETVAL=0

stop() {
  grep_mongo=`ps aux | grep -v grep | grep mongod`
  if [ ${#grep_mongo} -gt 0 ]
  then
    echo "Stop MongoDB."
    PID=`ps ax | grep -v grep | grep mongod | awk '{ print $1 }'`
    for i in "${PID}"
    do 
      `sudo kill -2 $i`
    done
    RETVAL=$?
  else
    echo "MongoDB is not running."
  fi
}

exit $RETVAL
