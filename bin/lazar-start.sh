#!/bin/bash
#R CMD Rserve
#sudo mongod
#unicorn -p 8088 -E production

RETVAL=0

start() {
  grep_mongo=`ps aux | grep -v grep | grep mongod`
  if [ ${#grep_mongo} -gt 0 ]
  then
    echo "MongoDB is already running."
  else
    echo "Start MongoDB."
    `sudo mongod`
    RETVAL=$?
  fi
}

exit $RETVAL
