IST Software&Services GUI
=========================

Installation:
-------------
    bundle install

Service start:
------
    sudo mongod &
    R CMD Rserve --vanilla &
    unicorn -p 8088 -c unicorn.rb -E production

Visit:
------
    http://localhost:8088
