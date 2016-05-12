#!/bin/bash
lazar-stop
sudo mongod &
R CMD Rserve
unicorn -c unicorn.rb -E production -D

exit 0
