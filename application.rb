require 'rubygems'
require 'compass' #must be loaded before sinatra
require 'sinatra'
require 'haml' #must be loaded after sinatra
require 'opentox-client'
require 'opentox-server'
require File.join(File.dirname(__FILE__),'helper.rb')
require File.join(ENV["HOME"],".opentox","config","lazar-gui.rb")


get '/?' do
  redirect to('/predict') 
end

get '/predict/?' do
  @models = OpenTox::Model.all $model[:uri]

  haml :predict
end

post '/predict/?' do
  # check for content
  unless params[:selection] and params[:identifier] != ''
    redirect to('/predict')
  end
  # transferred input
  @identifier = params[:identifier]
  # get compound from SMILES
  @compound = OpenTox::Compound.from_smiles $compound[:uri], @identifier.to_s
  # init
  @@prediction_models = []
  @@predictions = []
  # init lazar algorithm
  lazar = OpenTox::Algorithm.new File.join($algorithm[:uri],"lazar")
  # gather models from service and compare if selected
  params[:selection].each do |model|
    @mselected = model[0]
    @mall = OpenTox::Model.all $model[:uri]
    @mall.each do |m|
      m.get
      @@prediction_models << m if m.title =~ /#{@mselected}/
    end
    #$logger.debug "@prediction_models: #{@@prediction_models.inspect}"
  end

  # predict with selected models
  # results in prediction variable
  # store prediction in array for better handling
  #$logger.debug "@models: #{@models.inspect}"
  @@prediction_models.each do |m| 
    @prediction_uri = m.run :compound_uri => "#{@compound.uri}"
    prediction = OpenTox::Dataset.new @prediction_uri
    pa = []
    pa << prediction
    @@predictions << pa
    #$logger.debug "prediction class: #{prediction.class}"
  end

  haml :prediction
end

get '/prediction/neighbours/:id?' do

  haml :neighbours, :layout => false
end

get '/prediction/:neighbour/details/?' do
  @compound = OpenTox::Compound.new params[:neighbour]
  haml :details, :layout => false
end

get '/stylesheets/:name.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass(:"stylesheets/#{params[:name]}", Compass.sass_engine_options )
end


