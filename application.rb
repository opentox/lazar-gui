#require_relative 'helper.rb'
require 'rdiscount'
include OpenTox

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

before do
  @version = File.read("VERSION").chomp
end

get '/?' do
  redirect to('/predict') 
end

get '/predict/?' do
  @models = OpenTox::Model::Validation.all
  @models = @models.delete_if{|m| m.model.name =~ /\b(Net cell association)\b/}
  @endpoints = @models.collect{|m| m.endpoint}.sort.uniq
  @models.count <= 0 ? (haml :info) : (haml :predict)
end

get '/predict/modeldetails/:model' do
  model = OpenTox::Model::Validation.find params[:model]
  crossvalidations = OpenTox::Validation::RepeatedCrossValidation.find(model.repeated_crossvalidation_id).crossvalidations

  return haml :model_details, :layout=> false, :locals => {:model => model, :crossvalidations => crossvalidations}
end

# get individual compound details
get '/prediction/:neighbor/details/?' do
  @compound = OpenTox::Compound.find params[:neighbor]
  @smiles = @compound.smiles
  begin
    @names = @compound.names.nil? ? "No names for this compound available." : @compound.names
  rescue
    @names = "No names for this compound available."
  end
  @inchi = @compound.inchi.gsub("InChI=", "")

  haml :details, :layout => false
end

get '/jme_help/?' do
  File.read(File.join('views','jme_help.html'))
end

get '/predict/dataset/:name' do
  response['Content-Type'] = "text/csv"
  dataset = Dataset.find_by(:name=>params[:name])
  csv = dataset.to_csv
  csv
end

get '/predict/?:csv?' do
  response['Content-Type'] = "text/csv"
  @csv = "\"Compound\",\"Endpoint\",\"Type\",\"Prediction\",\"95% Prediction interval\"\n"
  @@batch.each do |key, values|
    compound = key
    smiles = compound.smiles
    values.each do |array|
      model = array[0]
      type = model.model.class.to_s.match("Classification") ? "Classification" : "Regression"
      prediction = array[1]
      endpoint = "#{model.endpoint.gsub('_', ' ')} (#{model.species})"
      if prediction[:confidence] == "measured"
        if prediction[:value].is_a?(Array)
          prediction[:value].each do |value|
            pred = value.numeric? ? "#{value} (#{model.unit}), #{compound.mmol_to_mg(value.delog10)} #{(model.unit =~ /\b(mol\/L)\b/) ? "(mg/L)" : "(mg/kg_bw/day)"}" : value
            int = (prediction[:prediction_interval].nil? ? nil : prediction[:prediction_interval])
            interval = (int.nil? ? "--" : "#{int[1].delog10} - #{int[0].delog10} (#{model.unit})")
            @csv += "\"#{smiles}\",\"#{endpoint}\",\"#{type}\",\"#{pred}\",\"#{interval}\"\n"
          end
        else
          pred = prediction[:value].numeric? ? "#{prediction[:value]} (#{model.unit}), #{compound.mmol_to_mg(prediction[:value].delog10)} #{(model.unit =~ /\b(mol\/L)\b/) ? "(mg/L)" : "(mg/kg_bw/day)"}" : prediction[:value]
          confidence = "measured activity"
        end
      elsif prediction[:neighbors].size > 0
        type = model.model.class.to_s.match("Classification") ? "Classification" : "Regression"
        pred = prediction[:value].numeric? ? "#{prediction[:value].delog10} (#{model.unit}), #{compound.mmol_to_mg(prediction[:value].delog10)} #{(model.unit =~ /\b(mol\/L)\b/) ? "(mg/L)" : "(mg/kg_bw/day)"}" : prediction[:value]
        int = (prediction[:prediction_interval].nil? ? nil : prediction[:prediction_interval])
        interval = (int.nil? ? "--" : "#{int[1].delog10} - #{int[0].delog10} (#{model.unit})")
      else
        type = ""
        pred = "Not enough similar compounds in training dataset."
        interval = ""
      end
      @csv += "\"#{smiles}\",\"#{endpoint}\",\"#{type}\",\"#{pred}\",\"#{interval}\"\n" unless prediction[:value].is_a?(Array)
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
    begin
      input = OpenTox::Dataset.from_csv_file File.join("tmp", params[:fileselect][:filename]), true
      if input.class == OpenTox::Dataset
        dataset = OpenTox::Dataset.find input
      else
        @error_report = "Could not serialize file '#{@filename}' ."
        return haml :error
      end
    rescue
      @error_report = "Could not serialize file '#{@filename}' ."
      return haml :error
    end
    @compounds = dataset.compounds
    if @compounds.size == 0
      @error_report = dataset[:warnings]
      dataset.delete
      return haml :error
    end
    @batch = {}
    @compounds.each do |compound|
      @batch[compound] = []
      params[:selection].keys.each do |model_id|
        model = OpenTox::Model::Validation.find model_id
        prediction = model.predict(compound)
        @batch[compound] << [model, prediction]
      end
    end
    @@batch = @batch
    @warnings = dataset[:warnings]
    dataset.delete
    File.delete File.join("tmp", params[:fileselect][:filename])
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
      @error_report = "'#{@identifier}' is not a valid SMILES string."
      return haml :error
    end

    @models = []
    @predictions = []
    params[:selection].keys.each do |model_id|
      model = OpenTox::Model::Validation.find model_id
      @models << model
      @predictions << model.predict(@compound)
    end
    haml :prediction
  end
end

get '/license' do
  @license = RDiscount.new(File.read("LICENSE.md")).to_html
  haml :license, :layout => false
end

get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

