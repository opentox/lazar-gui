#!/bin/bash
sudo /usr/bin/mongod &
unicorn -p 8088 -E production &
