require "sinatra"
require "sinatra/reloader"
require 'sinatra/cross_origin'

configure do
  $logger = Logger.new(STDOUT)
  enable :reloader #if development?
  enable :cross_origin
  disable :show_exceptions
  disable :raise_errors
end

#set :protection, :except => :frame_options

# Environment setup from unicorn -E param
ENV["LAZAR_ENV"] = ENV["RACK_ENV"]
require "../lazar/lib/lazar.rb"
require "../qsar-report/lib/qsar-report.rb"
=begin
if ENV["LAZAR_ENV"] == "development"
  require "../lazar/lib/lazar.rb"
  require "../qsar-report/lib/qsar-report.rb"
else
  require "lazar"
  require "qsar-report"
end
=end

include OpenTox

before do
  @accept = request.env['HTTP_ACCEPT']
  response['Content-Type'] = @accept
end

not_found do
  400
  "Path '#{request.env["REQUEST_PATH"]}' not found.\n"
end

error do
  response['Content-Type'] = "text/plain"
  error = request.env['sinatra.error']
  body = error.message+"\n"
  error.respond_to?(:http_code) ? code = error.http_code : code = 500
  halt code, body
end

# https://github.com/britg/sinatra-cross_origin#responding-to-options
options "*" do
  response.headers["Allow"] = "HEAD,GET,PUT,POST,DELETE,OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept"
  200
end

[
  "aa.rb",
  "api.rb",
  "compound.rb",
  "dataset.rb",
  "feature.rb",
  "model.rb",
  "nanoparticle.rb",
  "report.rb",
  "substance.rb",
  "swagger.rb",
  "validation.rb"
].each{ |f| require_relative f }

