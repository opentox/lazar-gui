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

get '/predict/:tmppath/:model/:filename?' do
  response['Content-Type'] = "text/csv"
  path = File.join("tmp", params[:tmppath])
  `sort -gk1 #{path} -o #{path}`

  send_file path, :filename => "#{Time.now.strftime("%Y-%m-%d")}_lazar_batch_prediction_#{params[:model]}_#{params[:filename]}", :type => "text/csv", :disposition => "attachment"
end

get '/batch/:model/' do

  if params[:model] == "Cramer"
    dataset = Dataset.find params[:dataset]
    compounds = dataset.compounds.collect{|c| c.smiles}
    
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

    # td paths to insert results in GUI
    compound_ids = dataset.compounds.collect{|c| c.id}
    output["tds"] = compound_ids.each_with_index.map{|cid,idx| "prediction_#{cid}_Cramer_#{idx}"}
    
    # write to file
    # header
    csv = "ID,Endpoint,Unique SMILES,Cramer rules,Cramer rules with extensions\n"
    
    compounds.each_with_index do |smiles, idx|
      csv << "#{idx+1},#{output["model_name"]},#{smiles},"\
        "#{output["cramer_rules"][idx] != "nil" ? output["cramer_rules"][idx] : "none" },"\
        "#{output["cramer_rules_extensions"][idx] != "nil" ? output["cramer_rules_extensions"][idx] : "none"}\n"
    end
    File.open(File.join("tmp", params[:tmppath]),"a+"){|file| file.write(csv)}

    # cleanup
    dataset.delete

    # return output
    response['Content-Type'] = "application/json"
    return JSON.pretty_generate output

  else
    idx = params[:idx].to_i
    compound = Compound.find params[:compound]

    model = Model::Validation.find params[:model]
    prediction = model.predict(compound)
    output = {}
    output["model_name"] = "#{model.endpoint.gsub('_', ' ')} (#{model.species})"
    output["model_type"] = model.model.class.to_s.match("Classification") ? type = "Classification" : type = "Regression"
    output["model_unit"] = (type == "Regression") ? "(#{model.unit})" : ""
    output["converted_model_unit"] = (type == "Regression") ? "#{model.unit =~ /\b(mmol\/L)\b/ ? "(mg/L)" : "(mg/kg_bw/day)"}" : ""
    ["measurements", "converted_measurements", "prediction_value", "converted_value", "interval", "converted_interval", "probability", "db_hit", "warnings", "info", "toxtree", "sa_prediction", "sa_matches", "confidence"].each do |key|
      output["#{key}"] = false
    end

    if prediction[:value]
      inApp = prediction[:neighbors] ? "yes" : "no"
      inT = prediction[:info] =~ /\b(identical)\b/i ? "yes" : "no"
      if prediction[:info] =~ /\b(identical)\b/i
        prediction[:info] = "This compound was part of the training dataset. All information "\
          "from this compound was removed from the training data before the "\
          "prediction, to obtain unbiased results."
      end
      note = "\"#{prediction[:warnings].uniq.join(" ")}" + ( prediction[:info] ? "#{prediction[:info]}\"" : "\"" )

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

        csv = "#{idx+1},#{output['model_name']},#{output['model_type']},#{compound.smiles},"\
          "#{output['prediction_value'] != false ? output['prediction_value'] : "-"},"\
          "#{output['converted_value'] != false ? output['converted_value'] : "-"},"\
          "#{output['interval'].split(" - ").first.strip unless output['interval'] == false},"\
          "#{output['interval'].split(" - ").last.strip unless output['interval'] == false},"\
          "#{output['converted_interval'].split(" - ").first.strip unless output['converted_interval'] == false},"\
          "#{output['converted_interval'].split(" - ").last.strip unless output['converted_interval'] == false},"\
          "#{inApp},#{inT},#{note.nil? ? "" : note.chomp}\n"
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
        output["sa_prediction"] = sa_prediction
        output["sa_matches"] = sa_prediction[:matches].flatten.first unless sa_prediction[:matches].blank?
        output["confidence"] = confidence.signif(3)
        output["model_name"] = "Lazar #{model.endpoint.gsub('_', ' ').downcase} (#{model.species}):"
        output["probability"] = prediction[:probabilities] ? prediction[:probabilities].collect{|k,v| "#{k}: #{v.signif(3)}"} : false

        csv = "#{idx+1},Consensus mutagenicity,#{compound.smiles},"\
          "#{output['sa_prediction']['prediction'] == false ? "non-mutagenic" : "mutagenic"},"\
          "#{output['confidence']},#{output['sa_matches'] != false ? "\"#{output['sa_matches']}\"" : "none"}, ,"\
          "#{output['model_type']},#{output['prediction_value']},"\
          "#{output['probability'][0] != false ? output['probability'][0].split(":").last : ""},"\
          "#{output['probability'][1] != false ? output['probability'][1].split(":").last : ""},"\
          "#{inApp},#{inT},#{note.nil? ? "" : note}\n"

      end
      
      output["warnings"] = prediction[:warnings] if prediction[:warnings]

    else #no prediction value
      inApp = "no"
      inT = prediction[:info] =~ /\b(identical)\b/i ? "yes" : "no"
      if prediction[:info] =~ /\b(identical)\b/i
        prediction[:info] = "This compound was part of the training dataset. All information "\
          "from this compound was removed from the training data before the "\
          "prediction, to obtain unbiased results."
      end
      note = "\"#{prediction[:warnings].join(" ")}\"" + ( prediction[:info] ? "\"#{prediction[:info]}\"" : "" )

      output["warnings"] = prediction[:warnings]
      output["info"] = prediction[:info] if prediction[:info]

      if type == "Regression"
        csv = "#{idx+1},#{output['model_name']},#{output['model_type']},#{compound.smiles},,,,,,,"+ [inApp,inT,note].join(",")+"\n"
      else
        csv = "#{idx+1},Consensus mutagenicity,#{compound.smiles},,,,,#{output['model_type']},,,,"+ [inApp,inT,note].join(",")+"\n"
      end

    end #prediction value

    # write to file
    File.open(File.join("tmp", params[:tmppath]),"a"){|file| file.write(csv)}

    # return output
    response['Content-Type'] = "application/json"
    return JSON.pretty_generate output

  end# if Cramer
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
    @tmppaths = {}
    @models.each do |model|
      m = Model::Validation.find model
      type = (m.regression? ? "Regression" : "Classification") unless model == "Cramer"
      # add header for regression
      if type == "Regression"
        unit = (type == "Regression") ? "(#{m.unit})" : ""
        converted_unit = (type == "Regression") ? "#{m.unit =~ /\b(mmol\/L)\b/ ? "(mg/L)" : "(mg/kg_bw/day)"}" : ""
        header = "ID,Endpoint,Type,Unique SMILES,Prediction #{unit},Prediction #{converted_unit},"\
          "Interval Low #{unit},Interval High #{unit},Interval Low #{converted_unit},Interval High #{converted_unit},"\
          "inApplicabilityDomain,inTrainningSet,Note\n"
      end
      # add header for classification
      if type == "Classification"
        av = m.prediction_feature.accept_values
        header = "ID,Endpoint,Unique SMILES,Structural alerts prediction,Structural alerts confidence,"\
          "Structural alerts for mutagenicity,Lazar mutagenicity (Salmonella typhimurium),Type,Prediction,"\
          "predProbability #{av[0]},predProbability #{av[1]},inApplicabilityDomain,inTrainningSet,Note\n"
      end
      path = File.join("tmp", "#{Time.now.strftime("%Y-%m-%d")}_#{SecureRandom.urlsafe_base64(5)}")
      File.open(path, "w"){|f| f.write(header) if header}
      @tmppaths[model] = path.split("/").last
    end

    File.delete File.join("tmp", params[:fileselect][:filename])
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

