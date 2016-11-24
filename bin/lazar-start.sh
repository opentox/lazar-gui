#!/bin/bash
sudo mongod &
R CMD Rserve
LAZARPATH=$(gem path lazar-gui)
cd $LAZARPATH
unicorn -c unicorn.rb -E production -D

exit 0
