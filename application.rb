require 'rubygems'
require 'compass' #must be loaded before sinatra
require 'sinatra'
require 'haml' #must be loaded after sinatra
require 'opentox-client'
require 'opentox-server'
require_relative 'helper.rb'
require File.join(ENV["HOME"],".opentox","config","lazar-gui.rb") # until added to ot-tools

helpers do
end

get '/?' do
  redirect to('/predict') 
end

get '/predict/?' do
  @models = OpenTox::Model.all $model[:uri]
  $logger.debug "Models:\n#{@models.inspect}"
  haml :predict
end

get '/jme_help/?' do
  File.read(File.join('views','jme_help.html'))
end

# best way to get individual compound uri for details
get '/prediction/:neighbour/details/?' do
  @compound_uri = OpenTox::Compound.new params[:neighbour]
  @smiles = @compound_uri.smiles
  task = OpenTox::Task.run("look for names.") do
    names = @compound_uri.names
  end
  task.wait
  $logger.debug "names task uri: #{task.uri}"
  case task[RDF::OT.hasStatus]
  when "Error"
    @names = "There are no names for this compound available."
  when "Completed"
    @names = @compound_uri.names.join(",")
  end
  @inchi = @compound_uri.inchi.gsub("InChI=", "")
  haml :details, :layout => false
end

post '/predict/?' do
  # validate identifier input
  task = OpenTox::Task.run("Validate SMILES string.") do
    # transfered input
    @identifier = params[:identifier]
    # get compound from SMILES
    @compound = OpenTox::Compound.from_smiles @identifier.to_s
    # validate SMILES by converting to INCHI
    inchi = @compound.inchi
  end
  # necessary to wait for task
  task.wait
  # case task fails return message smiles invalid  
  # case task completed go ahead
  case task[RDF::OT.hasStatus]
  when "Error"
    @error_report = "Attention, #{@identifier} is not a valid SMILES string."
    haml :error
  when "Completed"
    @identifier = params[:identifier]
    @compound = OpenTox::Compound.from_smiles @identifier.to_s
    # init
    @@prediction_models = []
    @@predictions = []
    # init lazar algorithm
    lazar = OpenTox::Algorithm.new File.join($algorithm[:uri],"lazar")
    # gather models from service and compare if selected
    #TODO compare selected by uri
    params[:selection].each do |model|
      $logger.debug "Model inspect in POST:\n#{model.inspect}"
      @mselected = model[0]
      @mall = OpenTox::Model.all $model[:uri]
      @mall.each do |m|
        @@prediction_models << m if m.title =~ /#{@mselected}/
      end
      $logger.debug "@prediction_models: #{@@prediction_models.inspect}"
    end

    # predict with selected models
    # results in prediction variable
    # store prediction in array for better handling
    @@prediction_models.each do |m| 
      @prediction_uri = m.run :compound_uri => "#{@compound.uri}"
      prediction = OpenTox::Dataset.new @prediction_uri
      pa = []
      pa << prediction
      @@predictions << pa
    end
    
    haml :prediction
  end
  
  
end

get '/predict/stylesheets/:name.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass(:"stylesheets/#{params[:name]}", Compass.sass_engine_options )
end


