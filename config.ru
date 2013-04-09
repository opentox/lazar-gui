SERVICE = "lazar-gui"
require 'bundler'
Bundler.require
require File.expand_path './application.rb', __FILE__
run Sinatra::Application
