require 'rdiscount'
require_relative 'qmrf_report.rb'
require_relative 'task.rb'
require_relative 'prediction.rb'
require_relative 'batch.rb'
require_relative 'helper.rb'
include OpenTox

[
  "aa.rb",
  "api.rb",
  "compound.rb",
  "dataset.rb",
  "endpoint.rb",
  "feature.rb",
  "model.rb",
  "report.rb",
  "substance.rb",
  "swagger.rb",
  "validation.rb"
].each{ |f| require_relative "./lib/#{f}" }


configure :production, :development do
  STDOUT.sync = true  
  $logger = Logger.new(STDOUT)
  $logger.level = Logger::DEBUG
  enable :reloader
  also_reload './helper.rb'
  also_reload './prediction.rb'
  also_reload './batch.rb'
  [
    "aa.rb",
    "api.rb",
    "compound.rb",
    "dataset.rb",
    "endpoint.rb",
    "feature.rb",
    "model.rb",
    "report.rb",
    "substance.rb",
    "swagger.rb",
    "validation.rb"
  ].each{ |f| also_reload "./lib/#{f}" }
end

before do
  $paths = [
  "/",
  "api",
  "authenticate",
  "compound",
  "dataset",
  "endpoint",
  "feature",
  "model",
  "report",
  "substance",
  "swagger",
  "validation"]
  if request.path == "/" || $paths.include?(request.path.split("/")[1])
    @accept = request.env['HTTP_ACCEPT']
    response['Content-Type'] = @accept
    auths = ["compound","dataset","endpoint","feature","model","report","substance","validation"]
    if auths.include?(request.path.split("/")[1])
      valid = Authorization.is_token_valid(request.env['HTTP_SUBJECTID'])
      bad_request_error "Not authorized." unless valid
    end
  else
    @version = File.read("VERSION").chomp
  end
end

not_found do
  redirect to('/predict')
end

error do
  if request.path == "/" || $paths.include?(request.path.split("/")[1])
    @accept = request.env['HTTP_ACCEPT']
    response['Content-Type'] = @accept
    @accept == "text/plain" ? request.env['sinatra.error'] : request.env['sinatra.error'].to_json
  else
    @error = request.env['sinatra.error']
    haml :error
  end
end

# https://github.com/britg/sinatra-cross_origin#responding-to-options
options "*" do
  response.headers["Allow"] = "HEAD,GET,PUT,POST,DELETE,OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept"
  200
end

get '/predict/?' do
  @models = OpenTox::Model::Validation.all
  @models = @models.delete_if{|m| m.model.name =~ /\b(Net cell association)\b/}
  @endpoints = @models.collect{|m| m.endpoint}.sort.uniq
  if @models.count > 0
    rodent_index = 0
    @models.each_with_index{|model,idx| rodent_index = idx if model.species =~ /Rodent/}
    @models.insert(rodent_index-1,@models.delete_at(rodent_index))
  end
  @models.count > 0 ? (haml :predict) : (haml :info)
end

get '/predict/modeldetails/:model' do
  model = OpenTox::Model::Validation.find params[:model]
  crossvalidations = OpenTox::Validation::RepeatedCrossValidation.find(model.repeated_crossvalidation_id).crossvalidations

  return haml :model_details, :layout=> false, :locals => {:model => model, :crossvalidations => crossvalidations}
end

get "/predict/report/:id/?" do
  prediction_model = Model::Validation.find params[:id]
  bad_request_error "model with id: '#{params[:id]}' not found." unless prediction_model
  report = qmrf_report params[:id]
  # output
  t = Tempfile.new
  t << report.to_xml
  name = prediction_model.species.sub(/\s/,"-")+"-"+prediction_model.endpoint.downcase.sub(/\s/,"-")
  send_file t.path, :filename => "QMRF_report_#{name.gsub!(/[^0-9A-Za-z]/, '_')}.xml", :type => "application/xml", :disposition => "attachment"
end

get '/predict/jme_help/?' do
  File.read(File.join('views','jme_help.html'))
end

get '/predict/dataset/:name' do
  response['Content-Type'] = "text/csv"
  dataset = Dataset.find_by(:name=>params[:name])
  csv = dataset.to_csv
  t = Tempfile.new
  t << csv
  name = params[:name] + ".csv"
  send_file t.path, :filename => name, :type => "text/csv", :disposition => "attachment"
end

get '/predict/:tmppath/:filename/?' do
  response['Content-Type'] = "text/csv"
  path = "/tmp/#{params[:tmppath]}"
  send_file path, :filename => "lazar_batch_prediction_#{params[:filename]}", :type => "text/csv", :disposition => "attachment"
end

get '/predict/csv/:task/:model/:filename/?' do
  response['Content-Type'] = "text/csv"
  filename = params[:filename] =~ /\.csv$/ ? params[:filename].gsub(/\.csv$/,"") : params[:filename]
  task = Task.find params[:task].to_s
  m = Model::Validation.find params[:model].to_s
  dataset = Batch.find_by(:name => filename)
  @ids = dataset.ids
  warnings = dataset.warnings.blank? ? nil : dataset.warnings.join("\n")
  unless warnings.nil?
    @parse = []
    warnings.split("\n").each do |warning|
      if warning =~ /^Cannot/
        smi = warning.split("SMILES compound").last.split("at").first
        line = warning.split("SMILES compound").last.split("at line").last.split("of").first.strip.to_i
        @parse << "Cannot parse SMILES compound#{smi}at line #{line} of #{dataset.source.split("/").last}\n"
      end
    end
    keys_array = []
    warnings.split("\n").each do |warning|
      if warning =~ /^Duplicate/
        text = warning.split("ID").first
        numbers = warning.split("ID").last.split("and")
        keys_array << numbers.collect{|n| n.strip.to_i}
      end
    end
    @dups = {}
    keys_array.each do |keys|
      keys.each do |key|
        @dups[key] = "Duplicate compound at ID #{keys.join(" and ")}\n"
      end
    end
  end
  endpoint = "#{m.endpoint}_(#{m.species})"
  tempfile = Tempfile.new
  header = task.csv
  lines = []
  task.predictions[params[:model]].each_with_index do |hash,idx|
    identifier = hash.keys[0]
    prediction_id = hash.values[0]
    # add duplicate warning at the end of a line if ID matches
    if @dups && @dups[idx+1]
      if prediction_id.is_a? BSON::ObjectId
        if @ids.blank?
          lines << "#{idx+1},#{identifier},#{Prediction.find(prediction_id).csv.tr("\n","")},#{@dups[idx+1]}"
        else
          lines << "#{idx+1},#{@ids[idx]},#{identifier},#{Prediction.find(prediction_id).csv.tr("\n","")},#{@dups[idx+1]}"
        end
      end
    else
      if prediction_id.is_a? BSON::ObjectId
        if @ids.blank?
          lines << "#{idx+1},#{identifier},#{Prediction.find(prediction_id).csv}"
        else
          lines << "#{idx+1},#{@ids[idx]},#{identifier},#{Prediction.find(prediction_id).csv}"
        end
      else
        if @ids.blank?
          lines << "#{idx+1},#{identifier},#{p}\n"
        else
          lines << "#{idx+1},#{@ids[idx]}#{identifier},#{p}\n"
        end
      end
    end
  end
  (@parse && !@parse.blank?) ? tempfile.write(header+lines.join("")+"\n"+@parse.join("\n")) : tempfile.write(header+lines.join(""))
  #tempfile.write(header+lines.join(""))
  tempfile.rewind
  send_file tempfile, :filename => "#{Time.now.strftime("%Y-%m-%d")}_lazar_batch_prediction_#{endpoint}_#{filename}.csv", :type => "text/csv", :disposition => "attachment"
end

post '/predict/?' do
  # process batch prediction
  if !params[:fileselect].blank?
    next
    if params[:fileselect][:filename] !~ /\.csv$/
      bad_request_error "Wrong file extension for '#{params[:fileselect][:filename]}'. Please upload a CSV file."
    end
    @filename = params[:fileselect][:filename]
    begin
      File.open('tmp/' + params[:fileselect][:filename], "w") do |f|
        f.write(params[:fileselect][:tempfile].read)
      end
      input = Batch.from_csv_file File.join("tmp", params[:fileselect][:filename])
      $logger.debug "Processing '#{params[:fileselect][:filename]}'"
      if input.class == OpenTox::Batch
        @dataset = input
        @compounds = @dataset.compounds
        @identifiers = @dataset.identifiers
        @ids = @dataset.ids
      else
        File.delete File.join("tmp", params[:fileselect][:filename])
        bad_request_error "Could not serialize file '#{@filename}'."
      end
    rescue
      File.delete File.join("tmp", params[:fileselect][:filename])
      bad_request_error "Could not serialize file '#{@filename}'."
    end

    if @compounds.size == 0
      message = @dataset.warnings
      @dataset.delete
      bad_request_error message
    end
      
    @models = params[:selection].keys
    # for single predictions in batch
    @tasks = []
    @models.each{|m| t = Task.new; t.save; @tasks << t}
    @predictions = {}
    task = Task.run do
      @models.each_with_index do |model,idx|
        t = @tasks[idx]
        m = Model::Validation.find model
        type = (m.regression? ? "Regression" : "Classification")
        # add header for regression
        if type == "Regression"
          unit = (type == "Regression") ? "(#{m.unit})" : ""
          converted_unit = (type == "Regression") ? "#{m.unit =~ /\b(mmol\/L)\b/ ? "(mg/L)" : "(mg/kg_bw/day)"}" : ""
          if @ids.blank?
            header = "ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements #{unit},Prediction #{unit},Prediction #{converted_unit},"\
            "Prediction Interval Low #{unit},Prediction Interval High #{unit},"\
            "Prediction Interval Low #{converted_unit},Prediction Interval High #{converted_unit},"\
            "inApplicabilityDomain,Note\n"
          else
            header = "ID,Original ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements #{unit},Prediction #{unit},Prediction #{converted_unit},"\
            "Prediction Interval Low #{unit},Prediction Interval High #{unit},"\
            "Prediction Interval Low #{converted_unit},Prediction Interval High #{converted_unit},"\
            "inApplicabilityDomain,Note\n"
          end
        end
        # add header for classification
        if type == "Classification"
          av = m.prediction_feature.accept_values
          if @ids.blank?
            header = "ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements,Prediction,"\
            "predProbability #{av[0]},predProbability #{av[1]},inApplicabilityDomain,Note\n"
          else
            header = "ID,Original ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements,Prediction,"\
            "predProbability #{av[0]},predProbability #{av[1]},inApplicabilityDomain,Note\n"
          end
        end
        # predict compounds
        p = 100.0/@compounds.size
        counter = 1
        predictions = []
        @compounds.each_with_index do |cid,idx|
          compound = Compound.find cid
          if Prediction.where(compound: compound.id, model: m.id).exists?
            prediction_object = Prediction.find_by(compound: compound.id, model: m.id)
            prediction = prediction_object.prediction
            prediction_id = prediction_object.id
            # in case prediction object was created by single prediction
            if prediction_object.csv.blank?
              prediction_object[:csv] = prediction_to_csv(m,compound,prediction)
              prediction_object.save
            end
            # identifier
            identifier = @identifiers[idx]
          else
            prediction = m.predict(compound)
            # save prediction object
            prediction_object = Prediction.new
            prediction_id = prediction_object.id
            prediction_object[:compound] = compound.id
            prediction_object[:model] = m.id
            # add additionally fields for html representation
            unless prediction[:value].blank? || type == "Classification"
              prediction[:prediction_value] = "#{prediction[:value].delog10.signif(3)} #{unit}"
              prediction["converted_prediction_value"] = "#{compound.mmol_to_mg(prediction[:value].delog10).signif(3)} #{converted_unit}"
            end
            unless prediction[:prediction_interval].blank?
              interval = prediction[:prediction_interval]
              prediction[:interval] = "#{interval[1].delog10.signif(3)} - #{interval[0].delog10.signif(3)} #{unit}"
              prediction[:converted_interval] = "#{compound.mmol_to_mg(interval[1].delog10).signif(3)} - #{compound.mmol_to_mg(interval[0].delog10).signif(3)} #{converted_unit}"
            end
            prediction["unit"] = unit
            prediction["converted_unit"] = converted_unit
            if prediction[:measurements].is_a?(Array)
              prediction["measurements_string"] = (type == "Regression") ? prediction[:measurements].collect{|value| "#{value.delog10.signif(3)} #{unit}"} : prediction[:measurements].join("</br>")
              prediction["converted_measurements"] = prediction[:measurements].collect{|value| "#{compound.mmol_to_mg(value.delog10).signif(3)} #{unit =~ /mmol\/L/ ? "(mg/L)" : "(mg/kg_bw/day)"}"} if type == "Regression"
            else
              output["measurements_string"] = (type == "Regression") ? "#{prediction[:measurements].delog10.signif(3)} #{unit}}" : prediction[:measurements]
              output["converted_measurements"] = "#{compound.mmol_to_mg(prediction[:measurements].delog10).signif(3)} #{(unit =~ /\b(mmol\/L)\b/) ? "(mg/L)" : "(mg/kg_bw/day)"}" if type == "Regression"
            end

            # store in prediction_object
            prediction_object[:prediction] = prediction
            prediction_object[:csv] = prediction_to_csv(m,compound,prediction)
            prediction_object.save

            # identifier
            identifier = @identifiers[idx]
          end
          # collect prediction_object ids with identifier
          predictions << {identifier => prediction_id}
          t.update_percent((counter*p).ceil > 100 ? 100 : (counter*p).ceil)
          counter += 1
        end
        # write csv
        t[:csv] = header
        # write predictions
        @predictions["#{model}"] = predictions
        # save task 
        # append predictions as last action otherwise they won't save
        # mongoid works with shallow copy via #dup
        t[:predictions] = @predictions
        t.save
      end#models

    end#main task
    @pid = task.pid

    #@dataset.delete
    #File.delete File.join("tmp", params[:fileselect][:filename])
    return haml :batch
  else
    # single compound prediction
    # validate identifier input
    if !params[:identifier].blank?
      @identifier = params[:identifier].strip
      $logger.debug "input:#{@identifier}"
      # get compound from SMILES
      @compound = Compound.from_smiles @identifier
      bad_request_error "'#{@identifier}' is not a valid SMILES string." if @compound.blank?
      
      @models = []
      @predictions = []
      @toxtree = false
      params[:selection].keys.each do |model_id|
        model = Model::Validation.find model_id
        @models << model
        if Prediction.where(compound: @compound.id, model: model.id).exists?
          prediction_object = Prediction.find_by(compound: @compound.id, model: model.id)
          prediction = prediction_object.prediction
          @predictions << prediction
        else
          prediction_object = Prediction.new
          prediction = model.predict(@compound)
          prediction_object[:compound] = @compound.id
          prediction_object[:model] = model.id
          prediction_object[:prediction] = prediction
          prediction_object.save
          @predictions << prediction
        end
      end

      haml :prediction
    end
  end
end

get '/prediction/task/?' do
  if params[:turi]
    task = Task.find(params[:turi].to_s)
    return JSON.pretty_generate(:percent => task.percent)
  elsif params[:predictions]
    task = Task.find(params[:predictions])
    pageSize = params[:pageSize].to_i - 1
    pageNumber= params[:pageNumber].to_i - 1
    predictions = task.predictions[params[:model]].collect{|hash| hash.values[0]}
    prediction_object = Prediction.find predictions[pageNumber]
    prediction = prediction_object.prediction
    compound = Compound.find prediction_object.compound
    model = Model::Validation.find prediction_object.model
    image = compound.svg
    smiles = compound.smiles
    type = (model.regression? ? "Regression" : "Classification")
    html = "<table class=\"table table-bordered single-batch\"><tr>"
    html += "<td>#{image}</br>#{smiles}</br></td>"
    string = "<td><table class=\"table\">"
    sorter = []
    if prediction[:info]
      prediction[:info] = "This compound was part of the training dataset. All information from this compound was "\
                          "removed from the training data before the prediction to obtain unbiased results."
      sorter << {"Info" => prediction[:info]}
      if prediction["measurements_string"].kind_of?(Array)
        sorter << {"Measured activity" => "#{prediction["measurements_string"].join(";")}</br>#{prediction["converted_measurements"].join(";")}"}
      else
        sorter << {"Measured activity" => "#{prediction["measurements_string"]}</br>#{prediction["converted_measurements"]}"}
      end
    end

    # regression
    if prediction[:value] && type == "Regression"
      sorter << {"Prediction" => "#{prediction["prediction_value"]}</br>#{prediction["converted_prediction_value"]}"}
      sorter << {"95% Prediction interval" => "#{prediction[:interval]}</br>#{prediction["converted_interval"]}"}
      sorter << {"Warnings" => prediction[:warnings].join("</br>")}
    elsif !prediction[:value] && type == "Regression"
      sorter << {"Prediction" => ""}
      sorter << {"95% Prediction interval" => ""}
      sorter << {"Warnings" => prediction[:warnings].join("</br>")}
    # classification
    elsif prediction[:value] && type == "Classification"
      sorter << {"Prediction" => prediction[:value]}
      sorter << {"Probability" => prediction[:probabilities].collect{|k,v| "#{k}: #{v.signif(3)}"}.join("</br>")}
    elsif !prediction[:value] && type == "Classification"
      sorter << {"Prediction" => ""}
      sorter << {"Probability" => ""}
    #else
      sorter << {"Warnings" => prediction[:warnings].join("</br>")}
    end
    sorter.each_with_index do |hash,idx|
      k = hash.keys[0]
      v = hash.values[0]
      string += (idx == 0 ? "<tr class=\"hide-top\">" : "<tr>")+(k =~ /lazar/i ? "<td colspan=\"2\">" : "<td>")
      # keyword
      string += "#{k}:"
      string += "</td><td>"
      # values
      string += "#{v}"
      string += "</td></tr>"
    end
    string += "</table></td>"
    html += "#{string}</tr></table>"
    return JSON.pretty_generate(:prediction => [html])
  end
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

get '/license' do
  @license = RDiscount.new(File.read("LICENSE.md")).to_html
  haml :license, :layout => false
end

get '/predict/faq' do
  @faq = RDiscount.new(File.read("FAQ.md")).to_html
  haml :faq#, :layout => false
end

get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

# for swagger representation
get '/swagger-ui.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

get '/IST_logo_s.png' do
  redirect to('/images/IST_logo_s.png')
end
