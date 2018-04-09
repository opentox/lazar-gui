#!/bin/bash
sudo mongod &
R CMD Rserve --vanilla &
LAZARPATH=$(gem path lazar-gui)
cd $LAZARPATH
unicorn -c unicorn.rb -E production

exit 0
