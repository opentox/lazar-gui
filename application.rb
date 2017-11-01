include OpenTox

configure :production do
  $logger = Logger.new(STDOUT)
  enable :reloader
end

configure :development do
  $logger = Logger.new(STDOUT)
  enable :reloader
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

helpers do
  def embedded_svg image, options={}
    doc = Nokogiri::HTML::DocumentFragment.parse image
    svg = doc.at_css 'svg'
    title = doc.at_css 'title'
    if options[:class].present?
      svg['class'] = options[:class]
    end
    if options[:title].present?
      title.children.remove
      text_node = Nokogiri::XML::Text.new(options[:title], doc)
      title.add_child(text_node)
    end
    doc.to_html.html_safe
  end

  def to_csv(m,predictions,compounds)
    model = (m != "Cramer" ? Model::Validation.find(m.to_s) : "Cramer")
    csv = ""
    if model == "Cramer"
      compounds = compounds.collect{|c| c.smiles}
      
      prediction = [Toxtree.predict(compounds, "Cramer rules"), Toxtree.predict(compounds, "Cramer rules with extensions")]
      output = {}
      output["model_name"] = "Oral toxicity (Cramer rules)"
      output["model_type"] = false
      output["model_unit"] = false
      ["measurements", "converted_measurements", "prediction_value", "converted_value", "interval", "converted_interval", "probability", "db_hit", "warnings", "info", "toxtree", "sa_prediction", "sa_matches", "confidence"].each do |key|
        output["#{key}"] = false
      end
      output["toxtree"] = true
      output["cramer_rules"] = prediction.collect{|array| array.collect{|hash| hash["Cramer rules"]}}.flatten.compact
      output["cramer_rules_extensions"] = prediction.collect{|array| array.collect{|hash| hash["Cramer rules, with extensions"]}}.flatten.compact

      # header
      csv = "ID,Endpoint,Unique SMILES,Cramer rules,Cramer rules with extensions\n"
      
      compounds.each_with_index do |smiles, idx|
        csv << "#{idx+1},#{output["model_name"]},#{smiles},"\
          "#{output["cramer_rules"][idx] != "nil" ? output["cramer_rules"][idx] : "none" },"\
          "#{output["cramer_rules_extensions"][idx] != "nil" ? output["cramer_rules_extensions"][idx] : "none"}\n"
      end

    else
      output = {}
      predictions.each_with_index do |prediction,idx|
        compound = compounds[idx]
        line = ""
        output["model_name"] = "#{model.endpoint.gsub('_', ' ')} (#{model.species})"
        output["model_type"] = model.model.class.to_s.match("Classification") ? type = "Classification" : type = "Regression"
        output["model_unit"] = (type == "Regression") ? "(#{model.unit})" : ""
        output["converted_model_unit"] = (type == "Regression") ? "#{model.unit =~ /\b(mmol\/L)\b/ ? "(mg/L)" : "(mg/kg_bw/day)"}" : ""
        ["measurements", "converted_measurements", "prediction_value", "converted_value", "interval", "converted_interval", "probability", "db_hit", "warnings", "info", "toxtree", "sa_prediction", "sa_matches", "confidence"].each do |key|
          output["#{key}"] = false
        end

        if prediction[:value]
          inApp = (prediction[:warnings].join(" ") =~ /Cannot/ ? "no" : (prediction[:warnings].join(" ") =~ /may|Insufficient/ ? "maybe" : "yes"))
          if prediction[:info] =~ /\b(identical)\b/i
            prediction[:info] = "This compound was part of the training dataset. All information "\
              "from this compound was removed from the training data before the "\
              "prediction, to obtain unbiased results."
          end
          note = "\"#{prediction[:warnings].uniq.join(" ")}\""

          output["prediction_value"] = (type == "Regression") ? "#{prediction[:value].delog10.signif(3)}" : "#{prediction[:value]}"
          output["converted_value"] = "#{compound.mmol_to_mg(prediction[:value].delog10).signif(3)}" if type == "Regression"

          output["db_hit"] = prediction[:info] if prediction[:info]
          
          if prediction[:measurements].is_a?(Array)
            output["measurements"] = (type == "Regression") ? prediction[:measurements].collect{|value| "#{value.delog10.signif(3)} (#{model.unit})"} : prediction[:measurements].collect{|value| "#{value}"}
            output["converted_measurements"] = (type == "Regression") ? prediction[:measurements].collect{|value| "#{compound.mmol_to_mg(value.delog10).signif(3)} #{model.unit =~ /mmol\/L/ ? "(mg/L)" : "(mg/kg_bw/day)"}"} : false
          else
            output["measurements"] = (type == "Regression") ? "#{prediction[:measurements].delog10.signif(3)} (#{model.unit})}" : "#{prediction[:measurements]}"
            output["converted_measurements"] = (type == "Regression") ? "#{compound.mmol_to_mg(prediction[:measurements].delog10).signif(3)} #{(model.unit =~ /\b(mmol\/L)\b/) ? "(mg/L)" : "(mg/kg_bw/day)"}" : false

          end #db_hit

          if type == "Regression"

            if !prediction[:prediction_interval].nil?
              interval = prediction[:prediction_interval]
              output['interval'] = "#{interval[1].delog10.signif(3)} - #{interval[0].delog10.signif(3)}"
              output['converted_interval'] = "#{compound.mmol_to_mg(interval[1].delog10).signif(3)} - #{compound.mmol_to_mg(interval[0].delog10).signif(3)}"
            end #prediction interval

            line += "#{idx+1},#{output['model_name']},#{compound.smiles},"\
              "\"#{prediction[:info] ? prediction[:info] : "no"}\",\"#{prediction[:measurements].join("; ") if prediction[:info]}\","\
              "#{output['prediction_value'] != false ? output['prediction_value'] : ""},"\
              "#{output['converted_value'] != false ? output['converted_value'] : ""},"\
              "#{output['interval'].split(" - ").first.strip unless output['interval'] == false},"\
              "#{output['interval'].split(" - ").last.strip unless output['interval'] == false},"\
              "#{output['converted_interval'].split(" - ").first.strip unless output['converted_interval'] == false},"\
              "#{output['converted_interval'].split(" - ").last.strip unless output['converted_interval'] == false},"\
              "#{inApp},#{note.nil? ? "" : note.chomp}\n"
          else # Classification

            # consensus mutagenicity
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
            output['sa_prediction'] = sa_prediction
            output['sa_matches'] = sa_prediction[:matches].collect{|a| a.first}.join("; ") unless sa_prediction[:matches].blank?
            output['confidence'] = confidence.signif(3)
            output['model_name'] = "Lazar #{model.endpoint.gsub('_', ' ').downcase} (#{model.species}):"
            output['probability'] = prediction[:probabilities] ? prediction[:probabilities].collect{|k,v| "#{k}: #{v.signif(3)}"} : false

            line += "#{idx+1},Consensus mutagenicity,#{compound.smiles},"\
              "\"#{prediction[:info] ? prediction[:info] : "no"}\",\"#{prediction[:measurements].join("; ") if prediction[:info]}\","\
              "#{sa_prediction[:prediction] == false ? "non-mutagenic" : "mutagenic"},"\
              "#{output['confidence']},#{output['sa_matches'] != false ? "\"#{output['sa_matches']}\"" : "none"},"\
              "#{output['prediction_value']},"\
              "#{output['probability'][0] != false ? output['probability'][0].split(":").last : ""},"\
              "#{output['probability'][1] != false ? output['probability'][1].split(":").last : ""},"\
              "#{inApp},#{note.nil? ? "" : note}\n"

          end
          
          output["warnings"] = prediction[:warnings] if prediction[:warnings]

        else #no prediction value
          inApp = "no"
          if prediction[:info] =~ /\b(identical)\b/i
            prediction[:info] = "This compound was part of the training dataset. All information "\
              "from this compound was removed from the training data before the "\
              "prediction, to obtain unbiased results."
          end
          note = "\"#{prediction[:warnings].join(" ")}\""

          output["warnings"] = prediction[:warnings]
          output["info"] = prediction[:info] if prediction[:info]

          if type == "Regression"
            line += "#{idx+1},#{output['model_name']},#{compound.smiles},#{prediction[:info] ? prediction[:info] : "no"},"\
              "#{prediction[:measurements] if prediction[:info]},,,,,,,"+ [inApp,note].join(",")+"\n"
          else
            line += "#{idx+1},Consensus mutagenicity,#{compound.smiles},#{prediction[:info] ? prediction[:info] : "no"},"\
              "#{prediction[:measurements] if prediction[:info]},,,,,,,"+ [inApp,note].join(",")+"\n"
          end

        end
        csv += line
      end
      csv
    end
  end

end
              
get '/?' do
  redirect to('/predict') 
end

get '/predict/?' do
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
    pageSize = params[:pageSize].to_i - 1
    pageNumber= params[:pageNumber].to_i - 1
    compound = Compound.find @@compounds_ids[pageNumber]
    image = compound.svg
    smiles = compound.smiles
    task = Task.find(params[:predictions].to_s)
    unless task.predictions[params[:model]].nil?
      if params[:model] == "Cramer"
        prediction = task.predictions[params[:model]]
        html = "<table class=\"table table-bordered single-batch\"><tr>"
        html += "<td>#{image}</br>#{smiles}</br></td>"
        string = "<td><table class=\"table\">"
        string += "<tr class=\"hide-top\"><td>Cramer rules:</td><td>#{prediction["Cramer rules"][pageNumber.to_i]}</td>"
        string += "<tr><td>Cramer rules, with extensions:</td><td>#{prediction["Cramer rules, with extensions"][pageNumber.to_i]}</td>"
        string += "</table></td>"
        html += "#{string}</tr></table>"
      else
        html = "<table class=\"table table-bordered single-batch\"><tr>"
        html += "<td>#{image}</br>#{smiles}</br></td>"
        string = "<td><table class=\"table\">"
        prediction = task.predictions[params[:model]][pageNumber.to_i]
        sorter = []
        $logger.debug prediction
        if prediction[:info]
          sorter << {"Info" => prediction[:info]}
          if prediction[:measurements_string].kind_of?(Array)
            sorter << {"Measured activity" => "#{prediction[:measurements_string].join(";")}</br>#{prediction[:converted_measurements].join(";")}"}
          else
            sorter << {"Measured activity" => "#{prediction[:measurements_string]}</br>#{prediction[:converted_measurements]}"}
          end
        end

        # regression
        if prediction[:prediction_interval]
          sorter << {"Prediction" => "#{prediction[:prediction_value]}</br>#{prediction[:converted_prediction_value]}"}
          sorter << {"95% Prediction interval" => "#{prediction[:interval]}</br>#{prediction[:converted_interval]}"}
          sorter << {"Warnings" => prediction[:warnings].join("</br>")}
        # classification
        elsif prediction[:probabilities]
          sorter << {"Consensus prediction" => prediction["Consensus prediction"]}
          sorter << {"Consensus confidence" => prediction["Consensus confidence"]}
          sorter << {"Structural alerts for mutagenicity" => prediction["Structural alerts for mutagenicity"]}
          sorter << {"Lazar mutagenicity (Salmonella typhimurium)" => ""}
          sorter << {"Prediction" => prediction[:value]}
          sorter << {"Probability" => prediction[:probabilities].collect{|k,v| "#{k}: #{v.signif(3)}"}.join("</br>")}
        else
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
    end
    return JSON.pretty_generate(:predictions => [html])
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

get '/predict/csv/:task/:model/:filename/?' do
  response['Content-Type'] = "text/csv"
  task = Task.find params[:task].to_s
  tempfile = Tempfile.new
  tempfile.write(task.csv)
  tempfile.rewind
  send_file tempfile, :filename => "#{Time.now.strftime("%Y-%m-%d")}_lazar_batch_prediction_#{params[:model]}_#{params[:filename]}", :type => "text/csv", :disposition => "attachment"
end

post '/predict/?' do

  # process batch prediction
  if !params[:fileselect].blank?
    if params[:fileselect][:filename] !~ /\.csv$/
      bad_request_error "Please submit a csv file."
    end
    File.open('tmp/' + params[:fileselect][:filename], "w") do |f|
      f.write(params[:fileselect][:tempfile].read)
    end
    @filename = params[:fileselect][:filename]
    begin
      input = Dataset.from_csv_file File.join("tmp", params[:fileselect][:filename]), true
      $logger.debug "save dataset #{params[:fileselect][:filename]}"
      if input.class == OpenTox::Dataset
        @dataset = Dataset.find input
        @compounds = @dataset.compounds
      else
        bad_request_error "Could not serialize file '#{@filename}'."
      end
    rescue
      bad_request_error "Could not serialize file '#{@filename}'."
    end

    if @compounds.size == 0
      message = dataset[:warnings]
      @dataset.delete
      bad_request_error message
    end
    
    @models = params[:selection].keys
    # for single predictions in batch
    @@compounds_ids = @compounds.collect{|c| c.id.to_s}
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
            header = "ID,Endpoint,Unique SMILES,inTrainingSet,Measurements,Prediction #{unit},Prediction #{converted_unit},"\
              "Prediction Interval Low #{unit},Prediction Interval High #{unit},"\
              "Prediction Interval Low #{converted_unit},Prediction Interval High #{converted_unit},"\
              "inApplicabilityDomain,Note\n"
          end
          # add header for classification
          if type == "Classification"
            av = m.prediction_feature.accept_values
            header = "ID,Endpoint,Unique SMILES,inTrainingSet,Measurements,Consensus Prediction,Consensus Confidence,"\
              "Structural alerts for mutagenicity,Lazar Prediction,"\
              "Lazar predProbability #{av[0]},Lazar predProbability #{av[1]},inApplicabilityDomain,Note\n"
          end
          # predict compounds
          p = 100.0/@compounds.size
          counter = 1
          predictions = []
          @compounds.each do |compound|
            prediction = m.predict(compound)
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
              prediction["Structural alerts for mutagenicity"] = sa_prediction[:matches].blank? ? "none" : sa_prediction[:matches].collect{|a| a.first}.join("; ")
            end
            # regression
            unless prediction[:value].blank?
              if type == "Regression"
                prediction[:prediction_value] = "#{prediction[:value].delog10.signif(3)} #{unit}"
                prediction["converted_prediction_value"] = "#{compound.mmol_to_mg(prediction[:value].delog10).signif(3)} #{converted_unit}"
              end
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
            predictions << prediction.delete_if{|k,v| k =~ /neighbors|prediction_feature_id|r_squared|rmse/i}
            t.update_percent((counter*p).ceil)
            counter += 1
          end
          # write csv
          t[:csv] = header + to_csv(model,predictions,@compounds)
          # write predictions
          @predictions["#{model}"] = predictions
        else # Cramer model
          #t[:csv] = to_csv(model,nil,@compounds)
          compounds = @compounds.collect{|c| c.smiles}
          prediction = [Toxtree.predict(compounds, "Cramer rules"), Toxtree.predict(compounds, "Cramer rules with extensions")]
          output = {}
          output["model_name"] = "Oral toxicity (Cramer rules)"
          output["cramer_rules"] = prediction.collect{|array| array.collect{|hash| hash["Cramer rules"]}}.flatten.compact
          output["cramer_rules_extensions"] = prediction.collect{|array| array.collect{|hash| hash["Cramer rules, with extensions"]}}.flatten.compact
          # header
          csv = "ID,Endpoint,Unique SMILES,Cramer rules,Cramer rules with extensions\n"
          # content
          compounds.each_with_index do |smiles, idx|
            csv << "#{idx+1},#{output["model_name"]},#{smiles},"\
              "#{output["cramer_rules"][idx] != "nil" ? output["cramer_rules"][idx] : "none" },"\
              "#{output["cramer_rules_extensions"][idx] != "nil" ? output["cramer_rules_extensions"][idx] : "none"}\n"
          end
          #predictions = []
          #predictions << {"Cramer rules" => output["cramer_rules"]}
          #predictions << {"Cramer rules, with extensions" => output["cramer_rules_extensions"]}
          predictions = {}
          predictions["Cramer rules"] = output["cramer_rules"].collect{|rule| rule != "nil" ? rule : "none"}
          predictions["Cramer rules, with extensions"] = output["cramer_rules_extensions"].collect{|rule| rule != "nil" ? rule : "none"}

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

    File.delete File.join("tmp", params[:fileselect][:filename])
    return haml :task
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
        if model.model.name =~ /kazius/
          sa_prediction = KaziusAlerts.predict(@compound.smiles)
          lazar_mutagenicity = model.predict(@compound)
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
          @predictions << [lazar_mutagenicity, {:prediction => sa_prediction, :confidence => confidence}]
        else
          @predictions << model.predict(@compound)
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
