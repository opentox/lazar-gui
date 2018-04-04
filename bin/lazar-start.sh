#!/bin/sh
sudo mongod &
R CMD Rserve --vanilla &
LAZARPATH=$(gem path lazar-gui)
cd $LAZARPATH
unicorn -c unicorn.rb -E production -D

exit 0
