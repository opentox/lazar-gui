require_relative 'helper.rb'
include OpenTox
#require File.join(ENV["HOME"],".opentox","config","lazar-gui.rb") # until added to ot-tools

# DG: workaround for https://github.com/sinatra/sinatra/issues/808
# Date: 18/11/2013
#set :protection, :except => :path_traversal

configure :development do
  $logger = Logger.new(STDOUT)
end

helpers do
  class Numeric
    def percent_of(n)
      self.to_f / n.to_f * 100.0
    end
  end

end

get '/?' do
  redirect to('/predict') 
end

get '/predict/?' do
  @models = OpenTox::Model::Prediction.all
  @endpoints = @models.collect{|m| m.endpoint}.sort.uniq
  @models.count <= 0 ? (haml :info) : (haml :predict)
end

get '/predict/modeldetails/:model' do
  model = OpenTox::Model::Prediction.find params[:model]
  crossvalidations = model.crossvalidations
  confidence_plots = crossvalidations.collect{|cv| [cv.id, cv.confidence_plot]}
  confidence_plots.each do |confp|
    File.open(File.join('public', "confp#{confp[0]}.png"), 'w'){|file| file.write(confp[1])} unless File.exists? File.join('public', "confp#{confp[0]}.png")
  end
  if model.regression?
    correlation_plots = crossvalidations.collect{|cv| [cv.id, cv.correlation_plot]}
    correlation_plots.each do |corrp|
      File.open(File.join('public', "corrp#{corrp[0]}.png"), 'w'){|file| file.write(corrp[1])} unless File.exists? File.join('public', "corrp#{corrp[0]}.png")
    end
  end

  return haml :model_details, :layout=> false, :locals => {:model => model}
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
=begin
# sdf representation for datasets
#TODO fix 502 errors from compound service
get '/predict/:dataset_uri/sdf/?' do
  uri = CGI.unescape(params[:dataset_uri])
  $logger.debug uri
  bad_request_error "Not a dataset uri." unless URI.dataset? uri
  dataset = OpenTox::Dataset.find uri
  @compounds = dataset.compounds
  @data_entries = dataset.data_entries
  sum=""
  @compounds.each_with_index{ |c, idx|
    sum << c.inchi
    sum << c.sdf.sub(/\n\$\$\$\$/,'')
    @data_entries[idx].each{ |f,v|
      sum << "> <\"#{f}\">\n"
      sum << v.join(", ")
      sum << "\n\n"
    }
    sum << "$$$$\n"
  }
  send_file sum, :filename => "#{dataset.title}.sdf"
end
=end
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

get '/predict/?:csv?' do
  response['Content-Type'] = "text/csv"
  @csv = "\"Compound\",\"Endpoint\",\"Type\",\"Prediction\",\"Confidence\"\n"
  @@batch.each do |key, values|
    values.each do |array|
      model = array[0]
      prediction = array[1]
      compound = key.smiles
      mw = key.molecular_weight
      endpoint = "#{model.endpoint.gsub('_', ' ')} (#{model.species})"
      if prediction[:confidence] == "measured"
        if prediction[:value].is_a?(Array)
          prediction[:value].each do |value|
            type = ""
            weight = Compound.from_smiles(compound).mmol_to_mg(value, mw)
            pred = value.numeric? ? "#{'%.2e' % value} (#{model.unit}) | #{'%.2e' % weight} (mg/kg_bw/day)" : value
            confidence = "measured activity"
            @csv += "\"#{compound}\",\"#{endpoint}\",\"#{type}\",\"#{pred}\",\"#{confidence}\"\n"
          end
        else
          type = ""
          weight = Compound.from_smiles(compound).mmol_to_mg(prediction[:value], mw)
          pred = prediction[:value].numeric? ? "#{'%.2e' % prediction[:value]} (#{model.unit}) | #{'%.2e' % weight} (mg/kg_bw/day)" : prediction[:value]
          confidence = "measured activity"
        end
      elsif prediction[:neighbors].size > 0
        weight = Compound.from_smiles(compound).mmol_to_mg(prediction[:value], mw)
        type = model.model.class.to_s.match("Classification") ? "Classification" : "Regression"
        pred = prediction[:value].numeric? ? "#{'%.2e' % prediction[:value]} (#{model.unit}) | #{'%.2e' % weight} (mg/kg_bw/day)" : prediction[:value]
        confidence = prediction[:confidence]
      else
        type = ""
        pred = "Not enough similar compounds in training dataset."
        confidence = ""
      end
      @csv += "\"#{compound}\",\"#{endpoint}\",\"#{type}\",\"#{pred}\",\"#{confidence}\"\n" unless prediction[:value].is_a?(Array)
    end
  end
  @csv
end

post '/predict/?' do

  # process batch prediction
  if !params[:fileselect].blank?
    if params[:fileselect][:filename] !~ /\.csv$/
      @error_report = "Please submit a csv file."
      return haml :error
    end
    File.open('tmp/' + params[:fileselect][:filename], "w") do |f|
      f.write(params[:fileselect][:tempfile].read)
    end
    @filename = params[:fileselect][:filename]
    input = OpenTox::Dataset.from_csv_file File.join "tmp", params[:fileselect][:filename]
    dataset = OpenTox::Dataset.find input.id 
    @compounds = dataset.compounds
    if @compounds.size == 0
      @error_report = "No valid SMILES submitted."
      dataset.delete
      return haml :error
    end
    @batch = {}
    @compounds.each do |compound|
      @batch[compound] = []
      params[:selection].keys.each do |model_id|
        model = Model::Prediction.find model_id
        prediction = model.predict(compound)
        @batch[compound] << [model, prediction]
      end
    end
    @@batch = @batch
    dataset.delete
    return haml :batch
  end

  # validate identifier input
  # transfered input
  if !params[:identifier].blank?
    @identifier = params[:identifier]
    $logger.debug "input:#{@identifier}"
    # get compound from SMILES
    @compound = Compound.from_smiles @identifier
    if @compound.blank?
      @error_report = "Attention, '#{@identifier}' is not a valid SMILES string."
      return haml :error
    end

    @models = []
    @predictions = []
    params[:selection].keys.each do |model_id|
      model = Model::Prediction.find model_id
      @models << model
      @predictions << model.predict(@compound)
    end
    haml :prediction
  end
end

get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

