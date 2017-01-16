ENV["LAZAR_ENV"] = "development"#"production"
require 'bundler'
Bundler.require
require File.expand_path './application.rb'
require "sinatra/reloader" if development?
run Sinatra::Application
