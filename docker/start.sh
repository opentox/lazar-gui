#!/bin/sh

# start basic services
mongod --bind_ip 127.0.0.1 --dbpath ~/data &
R CMD Rserve --vanilla &

# import data
ruby -e "require 'lazar'; include OpenTox; Import.public_data" 

# start lazar service
cd $HOME/lazar-gui
unicorn -p 8088 -E production
