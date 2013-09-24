require 'rubygems'
require 'compass' #must be loaded before sinatra
require 'sinatra'
require 'haml' #must be loaded after sinatra
require 'opentox-client'
require 'opentox-server'
require_relative 'helper.rb'
require File.join(ENV["HOME"],".opentox","config","lazar-gui.rb") # until added to ot-tools

helpers do
  # get prediction models from text file, ignore validation models
  # model uris must be manually added
  @@models = []
  CSV.foreach("./prediction_models.csv"){|uri| m = OpenTox::Model::Lazar.find uri[0]; @@models << m}
  #$logger.debug "model uris from csv file:\t#{@@models}\n"
end

get '/?' do
  redirect to('/predict') 
end

get '/predict/?' do
  @models = @@models
  haml :predict
end

get '/jme_help/?' do
  File.read(File.join('views','jme_help.html'))
end

# get individual compound details
get '/prediction/:neighbor/details/?' do
  @compound = OpenTox::Compound.new params[:neighbor]
  @smiles = @compound.smiles

  task = OpenTox::Task.run("look for names.") do
    names = @compound.names
  end
  task.wait

  case task[RDF::OT.hasStatus]
  when "Error"
    @names = "No names for this compound available."
  when "Completed"
    @names = @compound.names
  end
  @inchi = @compound.inchi.gsub("InChI=", "")

  haml :details, :layout => false
end

# fingerprints for compound in predictions
get '/prediction/:model_uri/:type/:compound_uri/fingerprints/?' do
  @type = params[:type]
  model = OpenTox::Model::Lazar.find params[:model_uri]
  feature_dataset = OpenTox::Dataset.find model[RDF::OT.featureDataset]
  @compound = OpenTox::Compound.new params[:compound_uri]

  if @type =~ /classification/i
    # collect all feature values with fingerprint
    fingerprints = OpenTox::Algorithm::Descriptor.send("smarts_match", [@compound], feature_dataset.features.collect{ |f| f[RDF::DC.title]})[@compound.uri]
    #$logger.debug "fingerprints:\t#{fingerprints}\n"

    # collect fingerprints with value 1
    @fingerprint_values = []
    fingerprints.each{|smarts, value| @fingerprint_values << [smarts, value] if value > 0}
    
    # collect all features from feature_dataset
    @features = feature_dataset.features.collect{|f| f }
    
    # search for each fingerprint in all features and collect feature values(smarts, pValue, effect)
    @significant_fragments = []
    @fingerprint_values.each{ |fi, v| @features.each{ |f| @significant_fragments << [f[RDF::OT.effect].to_i, f[RDF::OT.smarts], f[RDF::OT.pValue]] if fi == f[RDF::OT.smarts] } }
  else #regression
    @significant_fragments = []
  end

  haml :significant_fragments, :layout => false
end

get '/prediction/:model_uri/:type/:neighbor/significant_fragments/?' do
  @type = params[:type]
  #$logger.debug "sf type:\t#{@type}"
  @compound = OpenTox::Compound.new params[:neighbor]
  #$logger.debug "neighbor compound uri:\t#{@compound.uri}\n"
  
  model = OpenTox::Model::Lazar.find params[:model_uri]
  #$logger.debug "model for significant fragments:\t#{model.uri}"
  
  feature_dataset = OpenTox::Dataset.find model[RDF::OT.featureDataset]
  $logger.debug "fd :\t#{feature_dataset.uri}"
  
  # load all compounds
  feature_dataset.compounds
  
  # load all features
  @features = []
  feature_dataset.features.each{|f| @features << f}
  #$logger.debug "all features in fd:\t#{@features}\n"
  
  # find all features and values for a neighbor compound
  @significant_fragments = []
  # check type first
  if @type =~ /classification/i
    @feat = []
    # get compound index in feature dataset
    c_idx = feature_dataset.compound_indices @compound.uri
    #$logger.debug "compound idx:\t#{c_idx}\n"

    # collect feature uris with value
    @features.each{|f| @feat << [feature_dataset.data_entry_value(c_idx[0], f.uri), f.uri]}
    #$logger.debug "collected features:\t#{@feat}\n"

    # pass feature uris if value > 0
    @feat.each do |f|
      if f[0] > 0
        f = OpenTox::Feature.find f[1]
        @significant_fragments << [f[RDF::OT.effect].to_i, f[RDF::OT.smarts], f[RDF::OT.pValue].to_f.round(3)]
      end
    end
  else # regression
    # find a value in feature dataset by compound and feature
    @values = []
    @features.each{|f| @values << feature_dataset.values(@compound, f)}
    #$logger.debug "values in fd:\t#{@values}"
    
    count = 0
    @features.each{|f| @significant_fragments << [f.description, @values[count]]; count +=1}
  end  
  #$logger.debug "significant fragments:\t#{@significant_fragments}\n"
  
  haml :significant_fragments, :layout => false
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
    @error_report = "Attention, '#{params[:identifier]}' is not a valid SMILES string."
    haml :error
  when "Completed"
    @identifier = params[:identifier]
    @compound = OpenTox::Compound.from_smiles @identifier.to_s
    # init arrays
    @prediction_models = []
    @predictions = []
    # init lazar algorithm
    lazar = OpenTox::Algorithm::Fminer.new File.join($algorithm[:uri],"lazar")
    
    # get selected models
    #TODO compare if model is selected by uri not title
    params[:selection].each do |model|
      # selected model = model[0]
      # compare selected with all models
      @@models.each do |m|
        @prediction_models << m if m.title =~ /#{model[0]}/
      end
    end

    # predict with selected models
    # one prediction in 'pa' array = OpenTox::Dataset
    # all collected predictions in '@predictions' array
    # init model_type array
    @model_type = []
    @prediction_models.each do |m|
      # define type (classification|regression)
      m.type.join =~ /classification/i ? (@model_type << "classification") : (@model_type << "regression")
      
      #TODO each prediction get a task; load predictions page if first task finished and load results individually

      # predict against compound
      @prediction_uri = m.run :compound_uri => "#{@compound.uri}"
      $logger.debug "prediction dataset:\t#{@prediction_uri}\n"
      
      prediction = OpenTox::Dataset.new @prediction_uri
      pa = []
      pa << prediction
      @predictions << pa
    end
    
    haml :prediction
  end
  
  
end

get '/predict/stylesheets/:name.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass(:"stylesheets/#{params[:name]}", Compass.sass_engine_options )
end


