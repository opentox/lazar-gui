SERVICE = "lazar-gui"
require 'bundler'
Bundler.require
require './application.rb'
run Sinatra::Application
