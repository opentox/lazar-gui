ENV["LAZAR_ENV"] = "development"
require 'bundler'
Bundler.require
require File.expand_path './application.rb'
require "sinatra/reloader" if development?
run Sinatra::Application
