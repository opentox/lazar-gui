SERVICE = "lazar"
require 'bundler'
Bundler.require
require File.expand_path './application.rb'
run Sinatra::Application
