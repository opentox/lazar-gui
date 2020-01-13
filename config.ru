ENV["BATCH_MODE"] = "true"
ENV["LAZAR_ENV"] = "production"
require "lazar"
require "qsar-report"
require "sinatra"
require "haml"
require "sass"
require "rdiscount"
require File.expand_path './application.rb'
require "sinatra/reloader" if production?
require "sinatra/reloader" if development?
run Sinatra::Application
