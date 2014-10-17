require_relative 'helper.rb'
require File.join(ENV["HOME"],".opentox","config","lazar-gui.rb") # until added to ot-tools

# DG: workaround for https://github.com/sinatra/sinatra/issues/808
# Date: 18/11/2013
set :protection, :except => :path_traversal

helpers do
  # models must be edited with RDF.type => (RDF::OT.PredictionModel, EchaEndpoint)
  @@models = []
  models = `curl -k GET -H accept:text/uri-list #{$model[:uri]}`.split("\n")
  .collect{|m| model = OpenTox::Model::Lazar.find m; @@models << model if model.type.flatten.to_s =~ /PredictionModel/}
  @@cv = []
  `curl -k GET -H accept:text/uri-list #{$validation[:uri]}/crossvalidation`.split("\n").each{|cv| x = OpenTox::Validation.find cv; @@cv << x}
end

get '/?' do
  redirect to('/predict') 
end

get '/predict/?' do
  # sort models by endpoint alphabetically
  $size = 0
  @models = @@models.sort!{|a, b| a.type.select{|e| e =~ /endpoint/i} <=> b.type.select{|e| e =~ /endpoint/i}}
  @cv = @@cv.collect{|cv| cv.metadata.select{|x| x =~ /predictionFeature/}}
  haml :predict
end

get '/jme_help/?' do
  File.read(File.join('views','jme_help.html'))
end

# get individual compound details
get '/prediction/:neighbor/details/?' do
  @compound = OpenTox::Compound.new params[:neighbor]
  @smiles = @compound.smiles
  task = OpenTox::Task.run("Get names for '#{@smiles}'.") do
    names = @compound.names
  end
  task.wait
  
  case task[RDF::OT.hasStatus]
  when "Error"
    @names = "No names for this compound available."
  when "Completed"
    @names = @compound.names
  else
    @names = "No names for this compound available."
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
  @significant_fragments = []
  if @type =~ /classification/i
    # collect all feature values with fingerprint
    fingerprints = OpenTox::Algorithm::Descriptor.send("smarts_match", [@compound], feature_dataset.features.collect{ |f| f[RDF::DC.title]})[@compound.uri]
    #$logger.debug "fingerprints:\t#{fingerprints}\n"

    # collect fingerprints with value 1
    @fingerprint_values = fingerprints.collect{|smarts, value| [smarts, value] if value > 0}
    
    # collect all features from feature_dataset
    @features = feature_dataset.features.collect{|f| f }
    
    # search for each fingerprint in all features and collect feature values( effect, smarts, pValue )
    @fingerprint_values.each{ |fi, v| @features.each{ |f| @significant_fragments << [f[RDF::OT.effect].to_i, f[RDF::OT.smarts], f[RDF::OT.pValue]] if fi == f[RDF::OT.smarts] } }
    
    # pass value_map, important to interprete effect value
    prediction_feature_uri = ""
    model.parameters.each {|p|
      if p[RDF::DC.title].to_s == "prediction_feature_uri"
        prediction_feature_uri = p[RDF::OT.paramValue].object
      end
    }
    prediction_feature = OpenTox::Feature.find prediction_feature_uri
    @value_map = prediction_feature.value_map

  else #regression
    feature_calc_algo = ""
    model.parameters.each {|p|
      if p[RDF::DC.title].to_s == "feature_calculation_algorithm"
        feature_calc_algo = p[RDF::OT.paramValue].object
      end
    }

    @desc = []
    fingerprints = OpenTox::Algorithm::Descriptor.send( feature_calc_algo, [ @compound ], feature_dataset.features.collect{ |f| f[RDF::DC.title] } )
    fingerprints.each{|x, h| h.each{|descriptor, value| @desc << [descriptor, [value]]}}
    
    pc_descriptor_titles_descriptions = {}
    feature_dataset.features.collect{ |f|
      pc_descriptor_titles_descriptions[f[RDF::DC.title]]= f[RDF::DC.description]
    }

    @desc.each{|d, v| @significant_fragments << [pc_descriptor_titles_descriptions[d], v] }
  end

  haml :significant_fragments, :layout => false
end

get '/prediction/:model_uri/:type/:neighbor/significant_fragments/?' do
  @type = params[:type]
  @compound = OpenTox::Compound.new params[:neighbor]
  model = OpenTox::Model::Lazar.find params[:model_uri]
  #$logger.debug "model for significant fragments:\t#{model.uri}"
  
  feature_dataset = OpenTox::Dataset.find model[RDF::OT.featureDataset]
  $logger.debug "feature_dataset_uri:\t#{feature_dataset.uri}\n"
  
  # load all compounds
  feature_dataset.compounds
  
  # load all features
  @features = feature_dataset.features.collect{|f| f}
  
  # find all features and values for a neighbor compound
  @significant_fragments = []
  # check type first
  if @type =~ /classification/i
    # get compound index in feature dataset
    c_idx = feature_dataset.compound_indices @compound.uri

    # collect feature uris with value
    @feat = @features.collect{|f| [feature_dataset.data_entry_value(c_idx[0], f.uri), f.uri]}
    #$logger.debug "@feat:\t#{@feat}\n"

    # pass feature uris if value > 0
    @feat.each do |f|
      # search relevant features
      if f[0] > 0
        f = OpenTox::Feature.find f[1]
        # pass relevant features with [ effect, smarts, pValue ] 
        @significant_fragments << [f[RDF::OT.effect].to_i, f[RDF::OT.smarts], f[RDF::OT.pValue].to_f.round(3)]
      end
    end
    # pass value_map, important to interprete effect value
    prediction_feature_uri = ""
    model.parameters.each {|p|
      if p[RDF::DC.title].to_s == "prediction_feature_uri"
        prediction_feature_uri = p[RDF::OT.paramValue].object
      end
    }
    prediction_feature = OpenTox::Feature.find prediction_feature_uri
    @value_map = prediction_feature.value_map

  else # regression
    # find a value in feature dataset by compound and feature
    @values = @features.collect{|f| feature_dataset.values(@compound, f)}
    #$logger.debug "values in fd:\t#{@values}"
    
    @features.each_with_index{|f, i| @significant_fragments << [f.description, @values[i]]}
  end  
  #$logger.debug "significant fragments:\t#{@significant_fragments}\n"
  
  haml :significant_fragments, :layout => false
end

get '/predict/:dataset/?' do
  t = Tempfile.new("tempfile.rdf")
  t << `curl -k -H accept:application/rdf+xml #{params[:dataset]}`
  send_file t.path,
    :filename => params[:dataset].split("_").last+".rdf"
  t.close
  t.unlink
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
  end#smiles
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
    @model_type = []
    # get selected models
    #TODO compare if model is selected by uri not title
    params[:selection].each do |model|
      # selected model = model[0]
      # compare selected with all models
      @@models.each do |m|
        @prediction_models << m if m.uri == model[0]
      end
    end
    # predict with selected models
    # one prediction in 'pa' array = OpenTox::Dataset
    # all collected predictions in '@predictions' array
    @prediction_models.each_with_index do |m, idx|
      # define type (classification|regression)
      m.type.join =~ /classification/i ? (@model_type << "classification") : (@model_type << "regression")
      
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

get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

