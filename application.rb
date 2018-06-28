require_relative 'task.rb'
require_relative 'prediction.rb'
require_relative 'batch.rb'
require_relative 'helper.rb'
include OpenTox

configure :production, :development do
  $logger = Logger.new(STDOUT)
  enable :reloader
  also_reload './helper.rb'
  also_reload './prediction.rb'
  also_reload './batch.rb'
end

before do
  @version = File.read("VERSION").chomp
end

not_found do
  redirect to('/predict')
end

error do
  @error = request.env['sinatra.error']
  haml :error
end

get '/?' do
  redirect to('/predict') 
end

get '/predict/?' do
  begin
    Process.kill(9,params[:tpid].to_i) if !params[:tpid].blank? #if (Process.getpgid(pid) rescue nil).present?
  rescue
    nil
  end
  @existing_datasets = dataset_storage
  @models = Model::Validation.all
  @models = @models.delete_if{|m| m.model.name =~ /\b(Net cell association)\b/}
  @endpoints = @models.collect{|m| m.endpoint}.sort.uniq
  @endpoints << "Oral toxicity (Cramer rules)"
  @models.count <= 0 ? (haml :info) : (haml :predict)
end

get '/task/?' do
  if params[:turi]
    task = Task.find(params[:turi].to_s)
    return JSON.pretty_generate(:percent => task.percent)
  elsif params[:predictions]
    task = Task.find(params[:predictions])
    pageSize = params[:pageSize].to_i - 1
    pageNumber= params[:pageNumber].to_i - 1
    if params[:model] == "Cramer"
      prediction = task.predictions[params[:model]]
      compound = Compound.find prediction["compounds"][pageNumber]
      image = compound.svg
      smiles = compound.smiles
      html = "<table class=\"table table-bordered single-batch\"><tr>"
      html += "<td>#{image}</br>#{smiles}</br></td>"
      string = "<td><table class=\"table\">"
      string += "<tr class=\"hide-top\"><td>Cramer rules:</td><td>#{prediction["Cramer rules"][pageNumber.to_i]}</td>"
      string += "<tr><td>Cramer rules, with extensions:</td><td>#{prediction["Cramer rules, with extensions"][pageNumber.to_i]}</td>"
      string += "</table></td>"
      html += "#{string}</tr></table>"
    else
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
        sorter << {"Consensus prediction" => prediction["Consensus prediction"]}
        sorter << {"Consensus confidence" => prediction["Consensus confidence"]}
        sorter << {"Structural alerts for mutagenicity" => prediction["Structural alerts for mutagenicity"]}
        sorter << {"Lazar mutagenicity (Salmonella typhimurium)" => ""}
        sorter << {"Prediction" => prediction[:value]}
        sorter << {"Probability" => prediction[:probabilities].collect{|k,v| "#{k}: #{v.signif(3)}"}.join("</br>")}
      elsif !prediction[:value] && type == "Classification"
        sorter << {"Consensus prediction" => prediction["Consensus prediction"]}
        sorter << {"Consensus confidence" => prediction["Consensus confidence"]}
        sorter << {"Structural alerts for mutagenicity" => prediction["Structural alerts for mutagenicity"]}
        sorter << {"Lazar mutagenicity (Salmonella typhimurium)" => ""}
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
    end
    return JSON.pretty_generate(:prediction => [html])
  end
end

get '/predict/modeldetails/:model' do
  model = Model::Validation.find params[:model]
  crossvalidations = Validation::RepeatedCrossValidation.find(model.repeated_crossvalidation_id).crossvalidations

  return haml :model_details, :layout=> false, :locals => {:model => model, :crossvalidations => crossvalidations}
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

get '/download/dataset/:id' do
  response['Content-Type'] = "text/csv"
  dataset = Batch.find params[:id]
  tempfile = Tempfile.new
  tempfile.write(File.read("tmp/"+dataset.name+".csv"))
  tempfile.rewind
  send_file tempfile, :filename => dataset.name+".csv", :type => "text/csv", :disposition => "attachment"
end

get '/delete/dataset/:id' do
  dataset = Batch.find params[:id]
  dataset.delete
  File.delete File.join("tmp/"+dataset.name+".csv")
  redirect to("/")
end

get '/predict/csv/:task/:model/:filename/?' do
  response['Content-Type'] = "text/csv"
  filename = params[:filename] =~ /\.csv$/ ? params[:filename].gsub(/\.csv$/,"") : params[:filename]
  task = Task.find params[:task].to_s
  m = Model::Validation.find params[:model].to_s unless params[:model] == "Cramer"
  dataset = Batch.find_by(:name => filename)
  warnings = dataset.warnings.blank? ? nil : dataset.warnings.join("\n")
  unless warnings.nil?
    keys_array = []
    warnings.split("\n").each do |warning|
      text = warning.split("ID").first
      numbers = warning.split("ID").last.split("and")
      keys_array << numbers.collect{|n| n.strip.to_i}
    end
    @dups = {}
    keys_array.each do |keys|
      keys.each do |key|
        @dups[key] = "Duplicate compound at ID #{keys.join(" and ")}\n"
      end
    end
  end
  endpoint = (params[:model] == "Cramer") ? "Oral_toxicity_(Cramer_rules)" : (m.endpoint =~ /Mutagenicity/i ? "Consensus_mutagenicity" : "#{m.endpoint}_(#{m.species})")
  tempfile = Tempfile.new
  if params[:model] == "Cramer"
    # add duplicate warning at the end of a line if ID matches
    if @dups
      lines = task.csv.split("\n")
      header = lines.shift
      out = ""
      lines.each_with_index do |line,idx|
        if @dups[idx+1]
          out << "#{line.tr("\n","")},#{@dups[idx+1]}"
        else
          out << line+"\n"
        end
      end
      tempfile.write(header+"\n"+out)
    else
      tempfile.write(task.csv)
    end
  else
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
        else
          if @ids.blank?
            lines << "#{idx+1},#{identifier},#{p},#{@dups[idx+1]}"
          else
            lines << "#{idx+1},#{@ids[idx]},#{identifier},#{p},#{@dups[idx+1]}"
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
    csv = header + lines.join("")
    tempfile.write(csv)
  end
  tempfile.rewind
  send_file tempfile, :filename => "#{Time.now.strftime("%Y-%m-%d")}_lazar_batch_prediction_#{endpoint}_#{filename}.csv", :type => "text/csv", :disposition => "attachment"
end

post '/predict/?' do
  # process batch prediction
  if !params[:fileselect].blank? || !params[:existing].blank?
    if !params[:existing].blank?
      @dataset = Batch.find params[:existing].keys[0]
      @compounds = @dataset.compounds
      @identifiers = @dataset.identifiers
      @ids = @dataset.ids
      @filename = @dataset.name
    end
    if !params[:fileselect].blank?
      if params[:fileselect][:filename] !~ /\.csv$/
        bad_request_error "Wrong file extension for '#{params[:fileselect][:filename]}'. Please upload a CSV file."
      end
      @filename = params[:fileselect][:filename]
      begin
        @dataset = Batch.find_by(:name => params[:fileselect][:filename].sub(/\.csv$/,""))
        if @dataset
          $logger.debug "Take file from database."
          @compounds = @dataset.compounds
          @identifiers = @dataset.identifiers
          @ids = @dataset.ids
        else
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
    end
      
    @models = params[:selection].keys
    # for single predictions in batch
    @tasks = []
    @models.each{|m| t = Task.new; t.save; @tasks << t}
    @predictions = {}
    task = Task.run do
      @models.each_with_index do |model,idx|
        t = @tasks[idx]
        unless model == "Cramer"
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
              header = "ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements,Consensus Prediction,Consensus Confidence,"\
              "Structural alerts for mutagenicity,Lazar Prediction,"\
              "Lazar predProbability #{av[0]},Lazar predProbability #{av[1]},inApplicabilityDomain,Note\n"
            else
              header = "ID,Original ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements,Consensus Prediction,Consensus Confidence,"\
              "Structural alerts for mutagenicity,Lazar Prediction,"\
              "Lazar predProbability #{av[0]},Lazar predProbability #{av[1]},inApplicabilityDomain,Note\n"
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
              if type == "Classification"# consensus mutagenicity
                sa_prediction = KaziusAlerts.predict(compound.smiles)
                lazar_mutagenicity = prediction
                confidence = 0
                lazar_mutagenicity_val = (lazar_mutagenicity[:value] == "non-mutagenic" ? false : true)
                if sa_prediction[:prediction] == false && lazar_mutagenicity_val == false
                  confidence = 0.85
                elsif sa_prediction[:prediction] == true && lazar_mutagenicity_val == true
                  confidence = 0.85 * ( 1 - sa_prediction[:error_product] )
                elsif sa_prediction[:prediction] == false && lazar_mutagenicity_val == true
                  confidence = 0.11
                elsif sa_prediction[:prediction] == true && lazar_mutagenicity_val == false
                  confidence = ( 1 - sa_prediction[:error_product] ) - 0.57
                end
                prediction["Consensus prediction"] = sa_prediction[:prediction] == false ? "non-mutagenic" : "mutagenic"
                prediction["Consensus confidence"] = confidence.signif(3)
                prediction["Structural alerts for mutagenicity"] = sa_prediction[:matches].blank? ? "none" : sa_prediction[:matches].collect{|a| a.first}.join("; ").gsub(/,/," ")
              end
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
        else # Cramer model
          compounds = @compounds.collect{|cid| c = Compound.find cid; c.smiles}
          prediction = [Toxtree.predict(compounds, "Cramer rules"), Toxtree.predict(compounds, "Cramer rules with extensions")]
          output = {}
          output["model_name"] = "Oral toxicity (Cramer rules)"
          output["cramer_rules"] = prediction.collect{|array| array.collect{|hash| hash["Cramer rules"]}}.flatten.compact
          output["cramer_rules_extensions"] = prediction.collect{|array| array.collect{|hash| hash["Cramer rules, with extensions"]}}.flatten.compact
          # header
          if @ids.blank?
            csv = "ID,Input,Endpoint,Unique SMILES,Cramer rules,Cramer rules with extensions\n"
          else
            csv = "ID,Original ID,Input,Endpoint,Unique SMILES,Cramer rules,Cramer rules with extensions\n"
          end
          # content
          compounds.each_with_index do |smiles, idx|
            if @ids.blank?
              csv << "#{idx+1},#{@identifiers[idx]},#{output["model_name"]},#{smiles},"\
              "#{output["cramer_rules"][idx] != "nil" ? output["cramer_rules"][idx] : "none" },"\
              "#{output["cramer_rules_extensions"][idx] != "nil" ? output["cramer_rules_extensions"][idx] : "none"}\n"
            else
              csv << "#{idx+1},#{@ids[idx]},#{@identifiers[idx]},#{output["model_name"]},#{smiles},"\
              "#{output["cramer_rules"][idx] != "nil" ? output["cramer_rules"][idx] : "none" },"\
              "#{output["cramer_rules_extensions"][idx] != "nil" ? output["cramer_rules_extensions"][idx] : "none"}\n"
            end
          end
          predictions = {}
          predictions["Cramer rules"] = output["cramer_rules"].collect{|rule| rule != "nil" ? rule : "none"}
          predictions["Cramer rules, with extensions"] = output["cramer_rules_extensions"].collect{|rule| rule != "nil" ? rule : "none"}
          predictions["compounds"] = @compounds
          # write csv
          t[:csv] = csv
          # write predictions
          @predictions["#{model}"] = predictions
          t.update_percent(100)
        end
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
  end

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
      if model_id == "Cramer"
        @toxtree = true
        @predictions << [Toxtree.predict(@compound.smiles, "Cramer rules"), Toxtree.predict(@compound.smiles, "Cramer rules with extensions")]
      else
        model = Model::Validation.find model_id
        @models << model
        if Prediction.where(compound: @compound.id, model: model.id).exists?
          prediction_object = Prediction.find_by(compound: @compound.id, model: model.id)
          prediction = prediction_object.prediction
          @predictions << prediction
        else
          prediction_object = Prediction.new

          if model.model.name =~ /kazius/
            sa_prediction = KaziusAlerts.predict(@compound.smiles)
            prediction = model.predict(@compound)
            lazar_mutagenicity = prediction
            confidence = 0
            lazar_mutagenicity_val = (lazar_mutagenicity[:value] == "non-mutagenic" ? false : true)
            if sa_prediction[:prediction] == false && lazar_mutagenicity_val == false
              confidence = 0.85
            elsif sa_prediction[:prediction] == true && lazar_mutagenicity_val == true
              confidence = 0.85 * ( 1 - sa_prediction[:error_product] )
            elsif sa_prediction[:prediction] == false && lazar_mutagenicity_val == true
              confidence = 0.11
            elsif sa_prediction[:prediction] == true && lazar_mutagenicity_val == false
              confidence = ( 1 - sa_prediction[:error_product] ) - 0.57
            end
            prediction["Consensus prediction"] = sa_prediction[:prediction] == false ? "non-mutagenic" : "mutagenic"
            prediction["Consensus confidence"] = confidence.signif(3)
            prediction["Structural alerts for mutagenicity"] = sa_prediction[:matches].blank? ? "none" : sa_prediction[:matches].collect{|a| a.first}.join("; ")
          else
            prediction = model.predict(@compound)
          end
          prediction_object[:compound] = @compound.id
          prediction_object[:model] = model.id
          prediction_object[:prediction] = prediction
          prediction_object.save
          @predictions << prediction
        end
      end
    end

    haml :prediction
  end
end

get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end
