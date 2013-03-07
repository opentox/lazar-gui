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
  # transferred input
  @identifier = params[:identifier]
  # get input as compound
  @compound = OpenTox::Compound.from_smiles $compound[:uri], @identifier.to_s
  # init
  @prediction_models = []
  @predictions = []
  # init lazar algorithm
  lazar = OpenTox::Algorithm.new File.join($algorithm[:uri],"lazar")
  # gather models from service and compare if selected
  params[:selection].each do |model|
    $logger.debug "selection: #{model[0]}"
    @mselected = model[0]
    @mall = OpenTox::Model.all $model[:uri]
    @mall.each do |m|
      m.get
      $logger.debug "m.title: #{m.title}; m.uri: #{m.uri}\n"
      @prediction_models << m if m.title =~ /#{@mselected}/
    end
    $logger.debug "@prediction_models: #{@prediction_models.inspect}"
  end
  # predict with selected models
  # predictions in @predictions variable
  $logger.debug "@models: #{@models.inspect}"
  @prediction_models.each do |m| 
    @prediction_uri = m.run :compound_uri => "#{@compound.uri}"
    prediction = OpenTox::Dataset.new @prediction_uri
    @predictions << prediction
  end
  
  @prediction_values = []
  @prediction_compound = []
  @prediction_neighbours_values = []
  @prediction_neighbours_compounds = []
  
  @predictions.each do |p|
    # get object
    p.get
    # first data_entries are prediction values
    @prediction_values << p.data_entries[0]
    # get prediction compound as object
    $logger.debug "prediction.compound: #{p.compounds.inspect}"
    $logger.debug "prediction.compound: #{p.compounds[0].inspect}"
    @prediction_compound << p.compounds[0]
    # delete first data_entries from array
    p.data_entries.shift
    # delete first compound from array
    p.compounds.shift
    # following data_entries are neighbours
    @prediction_neighbours_values << p.data_entries
    # get neighbour compounds as object
    p.compounds.each{|c| @prediction_neighbours_compounds << c}
  end 
  haml :prediction
end

get '/stylesheets/:name.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass(:"stylesheets/#{params[:name]}", Compass.sass_engine_options )
end


