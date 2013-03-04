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
  @models = []
  models = OpenTox::Model.all $model[:uri]
  models.each do |model|
    model.get
    @models << model
  end
  haml :predict
end

post '/predict/?' do
  @identifier = params[:identifier]
  @compound = OpenTox::Compound.from_smiles $compound[:uri], @identifier.to_s
  @models = []
  @predictions = []
  lazar = OpenTox::Algorithm.new File.join($algorithm[:uri],"lazar")

  params[:selection].each do |model|
    @mselected = model[0]
    @mall = OpenTox::Model.all $model[:uri]
    @mall.each do |m|
      m.get
      @models << m if m.title.match("#{@mselected}")
    end
  end
  @models.each do |m| 
    @prediction_uri = m.run :compound_uri => "#{@compound.uri}"
    prediction = OpenTox::Dataset.new @prediction_uri
    @predictions << prediction
  end

  @prediction_results = []
  @predictions.each{|p| @prediction_results << p.get}

  
  haml :prediction
end

get '/stylesheets/:name.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass(:"stylesheets/#{params[:name]}", Compass.sass_engine_options )
end


