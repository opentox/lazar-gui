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

get '/predict/:tmppath/:filename/?' do
  response['Content-Type'] = "text/csv"
  path = "/tmp/#{params[:tmppath]}"
  send_file path, :filename => "lazar_batch_prediction_#{params[:filename]}", :type => "text/csv", :disposition => "attachment"
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
      if input.class == OpenTox::Dataset
        dataset = Dataset.find input
      else
        bad_request_error "Could not serialize file '#{@filename}'."
      end
    rescue
      bad_request_error "Could not serialize file '#{@filename}'."
    end
    @compounds = dataset.compounds
    if @compounds.size == 0
      message = dataset[:warnings]
      dataset.delete
      bad_request_error message
    end

    # for csv export
    @batch = {}
    # for haml table
    @view = {}

    @compounds.each{|c| @view[c] = []}
    params[:selection].keys.each do |model_id|
      model = Model::Validation.find model_id
      @batch[model] = []
      @compounds.each_with_index do |compound,idx|
        prediction = model.predict(compound)
        @batch[model] << [compound, prediction]
        @view[compound] << [model,prediction]
      end
    end

    @csvhash = {}
    @warnings = dataset[:warnings]
    dupEntries = {}
    delEntries = ""
    
    # split duplicates and deleted entries
    @warnings.each do |w|
      substring = w.match(/line .* of/)
      unless substring.nil?
        delEntries += "\"#{w.sub(/\b(tmp\/)\b/,"")}\"\n"
      end
      substring = w.match(/rows .* Entries/)
      unless substring.nil?
        lines = []
        substring[0].split(",").each{|s| lines << s[/\d+/]}
        lines.shift
        lines.each{|l| dupEntries[l.to_i] = w.split(".").first}
      end
    end

    @batch.each_with_index do |hash, idx|
      @csvhash[idx] = ""
      model = hash[0]
      # create header
      if model.regression?
        predAunit = "(#{model.unit})"
        predBunit = "(#{model.unit =~ /mmol\/L/ ? "(mol/L)" : "(mg/kg_bw/day)"})"
        @csvhash[idx] = "\"ID\",\"Endpoint\",\"Type\",\"Unique SMILES\",\"Prediction #{predAunit}\",\"Prediction #{predBunit}\",\"95% Prediction interval (low) #{predAunit}\",\"95% Prediction interval (high) #{predAunit}\",\"95% Prediction interval (low) #{predBunit}\",\"95% Prediction interval (high) #{predBunit}\",\"inApplicabilityDomain\",\"inTrainningSet\",\"Note\"\n"
      else #classification
        av = model.prediction_feature.accept_values
        probFirst = av[0].capitalize
        probLast = av[1].capitalize
        @csvhash[idx] = "\"ID\",\"Endpoint\",\"Type\",\"Unique SMILES\",\"Prediction\",\"predProbability#{probFirst}\",\"predProbability#{probLast}\",\"inApplicabilityDomain\",\"inTrainningSet\",\"Note\"\n"
      end
      values = hash[1]
      dupEntries.keys.each{|k| values.insert(k-1, dupEntries[k])}.compact!
      
      values.each_with_index do |array, id|
        type = (model.regression? ? "Regression" : "Classification")
        endpoint = "#{model.endpoint.gsub('_', ' ')} (#{model.species})"
      
        if id == 0
          @csvhash[idx] += delEntries unless delEntries.blank?
        end
        unless array.kind_of? String
          compound = array[0]
          prediction = array[1]
          smiles = compound.smiles
          
          if prediction[:neighbors]
            if prediction[:value]
              pred = prediction[:value].numeric? ? "#{prediction[:value].delog10.signif(3)}" : prediction[:value]
              predA = prediction[:value].numeric? ? "#{prediction[:value].delog10.signif(3)}" : prediction[:value]
              predAunit = prediction[:value].numeric? ? "(#{model.unit})" : ""
              predB = prediction[:value].numeric? ? "#{compound.mmol_to_mg(prediction[:value].delog10).signif(3)}" : prediction[:value]
              predBunit = prediction[:value].numeric? ? "#{model.unit =~ /\b(mmol\/L)\b/ ? "(mg/L)" : "(mg/kg_bw/day)"}" : ""
              int = (prediction[:prediction_interval].nil? ? nil : prediction[:prediction_interval])
              intervalLow = (int.nil? ? "" : "#{int[1].delog10.signif(3)}")
              intervalHigh = (int.nil? ? "" : "#{int[0].delog10.signif(3)}")
              intervalLowMg = (int.nil? ? "" : "#{compound.mmol_to_mg(int[1].delog10).signif(3)}")
              intervalHighMg = (int.nil? ? "" : "#{compound.mmol_to_mg(int[0].delog10).signif(3)}")
              inApp = "yes"
              inT = prediction[:info] =~ /\b(identical)\b/i ? "yes" : "no"
              note = prediction[:warnings].join("\n") + ( prediction[:info] ? prediction[:info].sub(/\'.*\'/,"") : "\n" )
              
              unless prediction[:probabilities].nil?
                av = model.prediction_feature.accept_values
                propA = "#{prediction[:probabilities][av[0]].to_f.signif(3)}"
                propB = "#{prediction[:probabilities][av[1]].to_f.signif(3)}"
              end
            else
              # no prediction value only one neighbor
              inApp = "no"
              inT = prediction[:info] =~ /\b(identical)\b/i ? "yes" : "no"
              note = prediction[:warnings].join("\n") + ( prediction[:info] ? prediction[:info].sub(/\'.*\'/,"") : "\n" )
            end
          else
            # no prediction value
            inApp = "no"
            inT = prediction[:info] =~ /\b(identical)\b/i ? "yes" : "no"
            note = prediction[:warnings].join("\n") + ( prediction[:info] ? prediction[:info].sub(/\'.*\'/,"") : "\n" )
          end
          if @warnings
            @warnings.each do |w|
              note += (w.split(".").first + ".") if /\b(#{Regexp.escape(smiles)})\b/ === w
            end
          end
        else
          # string note for duplicates
          endpoint = type = smiles = pred = predA = predB = propA = propB = intervalLow = intervalHigh = intervalLowMg = intervalHighMg = inApp = inT = ""
          note = array
        end
        if model.regression?
          @csvhash[idx] += "\"#{id+1}\",\"#{endpoint}\",\"#{type}\",\"#{smiles}\",\"#{predA}\",\"#{predB}\",\"#{intervalLow}\",\"#{intervalHigh}\",\"#{intervalLowMg}\",\"#{intervalHighMg}\",\"#{inApp}\",\"#{inT}\",\"#{note.chomp}\"\n"
        else
          @csvhash[idx] += "\"#{id+1}\",\"#{endpoint}\",\"#{type}\",\"#{smiles}\",\"#{pred}\",\"#{propA}\",\"#{propB}\",\"#{inApp}\",\"#{inT}\",\"#{note.chomp}\"\n"
        end
      end
    end
    t = Tempfile.new
    @csvhash.each do |model, csv|
      t.write(csv)
      t.write("\n")
    end
    t.rewind
    @tmppath = t.path.split("/").last

    dataset.delete
    File.delete File.join("tmp", params[:fileselect][:filename])
    return haml :batch
  end

  # validate identifier input
  if !params[:identifier].blank?
    @identifier = params[:identifier]
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

