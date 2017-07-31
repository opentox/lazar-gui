#require_relative 'helper.rb'
require 'rdiscount'
include OpenTox


configure :production do
  $logger = Logger.new(STDOUT)
  enable :reloader
end

configure :development do
  $logger = Logger.new(STDOUT)
  enable :reloader
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

not_found do
  redirect to('/predict')
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

get '/predict/:tmppath/:filename/?' do
  response['Content-Type'] = "text/csv"
  path = "/tmp/#{params[:tmppath]}"
  send_file path, :filename => "lazar_batch_prediction_#{params[:filename]}", :type => "text/csv", :disposition => "attachment"
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

    # for csv export
    @batch = {}
    # for haml table
    @view = {}

    @compounds.each{|c| @view[c] = []}
    params[:selection].keys.each do |model_id|
      model = OpenTox::Model::Validation.find model_id
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
        delEntries += "\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"#{w.sub(/\b(tmp\/)\b/,"")}\"\n"
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
      values = hash[1]
      dupEntries.keys.each{|k| values.insert(k-1, dupEntries[k])}.compact!
      values.each_with_index do |array, id|
        unless array.kind_of? String
          compound = array[0]
          prediction = array[1]
          smiles = compound.smiles
          type = model.model.class.to_s.match("Classification") ? "Classification" : "Regression"
          endpoint = "#{model.endpoint.gsub('_', ' ')} (#{model.species})"
          pred = propA = propB = interval = inApp = inT = note = ""
          if prediction[:neighbors]
            if prediction[:value]
              pred = prediction[:value].numeric? ? "#{prediction[:value].delog10.signif(3)} (#{model.unit}), #{compound.mmol_to_mg(prediction[:value].delog10.signif(3))} #{(model.unit =~ /\b(mol\/L)\b/) ? "(mg/L)" : "(mg/kg_bw/day)"}" : prediction[:value]
              int = (prediction[:prediction_interval].nil? ? nil : prediction[:prediction_interval])
              interval = (int.nil? ? "" : "#{int[1].delog10.signif(3)} - #{int[0].delog10.signif(3)} (#{model.unit})")
              inApp = "yes"
              inT = prediction[:info] =~ /\b(identical)\b/i ? "yes" : "no"
              note = prediction[:warnings].join("\n") + ( prediction[:info] ? prediction[:info].sub(/\'.*\'/,"") : "\n" )
              unless prediction[:probabilities].nil?
                if id == 0
                  probFirst = probLast = ""
                  probFirst = prediction[:probabilities].keys.first.capitalize
                  prediction[:probabilities].keys.last.split("-").each{|s| probLast += s.capitalize}
                  @csvhash[idx] = "\"ID\",\"Endpoint\",\"Type\",\"Unique SMILES\",\"Prediction\",\"predProbability#{probFirst}\",\"predProbability#{probLast}\",\"95% Prediction interval\",\"inApplicabilityDomain\",\"inTrainningSet\",\"Note\"\n"
                  unless delEntries.blank? and id == 0
                    @csvhash[idx] += delEntries
                  end
                end
                propA = "#{prediction[:probabilities].values_at(prediction[:probabilities].keys.first)[0].to_f.signif(3)}"
                propB = "#{prediction[:probabilities].values_at(prediction[:probabilities].keys.last)[0].to_f.signif(3)}"
              else
                @csvhash[idx] = "\"ID\",\"Endpoint\",\"Type\",\"Unique SMILES\",\"Prediction\",\"predProbability\",\"predProbability\",\"95% Prediction interval\",\"inApplicabilityDomain\",\"inTrainningSet\",\"Note\"\n"
                unless delEntries.blank? and id == 0
                  @csvhash[idx] += delEntries
                end
              end
            # only one neighbor
            else
              inApp = "no"
              inT = prediction[:info] =~ /\b(identical)\b/i ? "yes" : "no"
              note = prediction[:warnings].join("\n") + ( prediction[:info] ? prediction[:info].sub(/\'.*\'/,"") : "\n" )
            end
          else # no prediction value
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
          endpoint = type = smiles = pred = propA = propB = interval = inApp = inT = ""
          note = array
        end
        @csvhash[idx] += "\"#{id+1}\",\"#{endpoint}\",\"#{type}\",\"#{smiles}\",\"#{pred}\",\"#{propA}\",\"#{propB}\",\"#{interval}\",\"#{inApp}\",\"#{inT}\",\"#{note.chomp}\"\n"
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

get "/report/:id/?" do
  lazarpath = `gem path lazar`
  lazarpath = File.dirname lazarpath
  lazarpath = File.dirname lazarpath
  qmrfpath = `gem path qsar-report`
  qmrfpath = File.dirname qmrfpath
  qmrfpath = File.dirname qmrfpath
  prediction_model = Model::Validation.find params[:id]
  model = prediction_model.model
  validation_template = "./views/model_details.haml"

  if File.directory?(lazarpath)
    lazar_commit = `cd #{lazarpath}; git rev-parse HEAD`.strip
    lazar_commit = "https://github.com/opentox/lazar/tree/#{lazar_commit}"
  else
    lazar_commit = "https://github.com/opentox/lazar/releases/tag/v#{Gem.loaded_specs["lazar"].version}"
  end

  report = OpenTox::QMRFReport.new

  # QSAR Identifier Title 1.1
  report.value "QSAR_title", "Lazar model for #{prediction_model.species} #{prediction_model.endpoint}"

  # Software coding the model 1.3
  report.change_catalog :software_catalog, :firstsoftware, {:name => "lazar", :description => "lazar Lazy Structure- Activity Relationships", :number => "1", :url => "https://lazar.in-silico.ch", :contact => "info@in-silico.ch"}
  report.ref_catalog :QSAR_software, :software_catalog, :firstsoftware

  # Date of QMRF 2.1
  report.value "qmrf_date", "#{Time.now.strftime('%d %B %Y')}"

  # QMRF author(s) and contact details 2.1
  report.change_catalog :authors_catalog, :firstauthor, {:name => "Christoph Helma", :affiliation => "in silico toxicology gmbh", :contact => "Rastatterstr. 41, CH-4057 Basel", :email => "info@in-silico.ch", :number => "1", :url => "www.in-silico.ch"}
  report.ref_catalog :qmrf_authors, :authors_catalog, :firstauthor

  # Model developer(s) and contact details 2.5
  report.change_catalog :authors_catalog, :modelauthor, {:name => "Christoph Helma", :affiliation => "in silico toxicology gmbh", :contact => "Rastatterstr. 41, CH-4057 Basel", :email => "info@in-silico.ch", :number => "1", :url => "www.in-silico.ch"}
  report.ref_catalog :model_authors, :authors_catalog, :modelauthor

  # Date of model development and/or publication 2.6
  report.value "model_date", "#{Time.parse(model.created_at.to_s).strftime('%Y')}"

  # Reference(s) to main scientific papers and/or software package 2.7
  report.change_catalog :publications_catalog, :publications_catalog_1, {:title => "Maunz, Guetlein, Rautenberg, Vorgrimmler, Gebele and Helma (2013), lazar: a modular predictive toxicology framework  ", :url => "http://dx.doi.org/10.3389/fphar.2013.00038"}
  report.ref_catalog :references, :publications_catalog, :publications_catalog_1

  # Reference(s) to main scientific papers and/or software package 2.7
  report.change_catalog :publications_catalog, :publications_catalog_2, {:title => "Maunz A and Helma C (2008) Prediction of chemical toxicity with local support vector regression and activity-specific kernels. SAR & QSAR in Environmental Research 19 (5-6), 413-431", :url => "http://dx.doi.org/10.1080/10629360802358430"}
  report.ref_catalog :references, :publications_catalog, :publications_catalog_2

  # Species 3.1
  report.value "model_species", prediction_model.species 

  # Endpoint 3.2 
  report.change_catalog :endpoints_catalog, :endpoints_catalog_1, {:name => prediction_model.endpoint, :group => ""}
  report.ref_catalog :model_endpoint, :endpoints_catalog, :endpoints_catalog_1

  # Endpoint Units 3.4
  report.value "endpoint_units", "#{prediction_model.unit}"

  model_type = model.class.to_s.gsub('OpenTox::Model::Lazar','')

  # Type of model 4.1
  report.value "algorithm_type", "#{model_type}"

  # Explicit algorithm 4.2
  report.change_catalog :algorithms_catalog, :algorithms_catalog_1, {:definition => "see Helma 2016 and lazar.in-silico.ch, submitted version: #{lazar_commit}", :description => "Neighbor algorithm: #{model.algorithms["similarity"]["method"].gsub('_',' ').titleize}#{(model.algorithms["similarity"][:min] ? ' with similarity > ' + model.algorithms["similarity"][:min].to_s : '')}"}
  report.ref_catalog :algorithm_explicit, :algorithms_catalog, :algorithms_catalog_1
  report.change_catalog :algorithms_catalog, :algorithms_catalog_3, {:definition => "see Helma 2016 and lazar.in-silico.ch, submitted version: #{lazar_commit}", :description => "modified k-nearest neighbor #{model_type}"}
  report.ref_catalog :algorithm_explicit, :algorithms_catalog, :algorithms_catalog_3
  if model.algorithms["prediction"]
    pred_algorithm_params = (model.algorithms["prediction"][:method] == "rf" ? "random forest" : model.algorithms["prediction"][:method])
  end
  report.change_catalog :algorithms_catalog, :algorithms_catalog_2, {:definition => "see Helma 2016 and lazar.in-silico.ch, submitted version: #{lazar_commit}", :description => "Prediction algorithm: #{model.algorithms["prediction"].to_s.gsub('OpenTox::Algorithm::','').gsub('_',' ').gsub('.', ' with ')} #{(pred_algorithm_params ? pred_algorithm_params : '')}"}
  report.ref_catalog :algorithm_explicit, :algorithms_catalog, :algorithms_catalog_2

  # Descriptors in the model 4.3
  if model.algorithms["descriptors"][:type]
    report.change_catalog :descriptors_catalog, :descriptors_catalog_1, {:description => "", :name => "#{model.algorithms["descriptors"][:type]}", :publication_ref => "", :units => ""}
    report.ref_catalog :algorithms_descriptors, :descriptors_catalog, :descriptors_catalog_1
  end

  # Descriptor selection 4.4
  report.value "descriptors_selection", "#{model.algorithms["feature_selection"].gsub('_',' ')} #{model.algorithms["feature_selection"].collect{|k,v| k.to_s + ': ' + v.to_s}.join(', ')}" if model.algorithms["feature_selection"]
  
  # Algorithm and descriptor generation 4.5
  report.value "descriptors_generation", "exhaustive breadth first search for paths in chemical graphs (simplified MolFea algorithm)"
  
  # Software name and version for descriptor generation 4.6
  report.change_catalog :software_catalog, :software_catalog_2, {:name => "lazar, submitted version: #{lazar_commit}", :description => "simplified MolFea algorithm", :number => "2", :url => "https://lazar.in-silico.ch", :contact => "info@in-silico.ch"}
  report.ref_catalog :descriptors_generation_software, :software_catalog, :software_catalog_2

  # Chemicals/Descriptors ratio 4.7
  report.value "descriptors_chemicals_ratio", "not applicable (classification based on activities of neighbors, descriptors are used for similarity calculation)"

  # Description of the applicability domain of the model 5.1
  report.value "app_domain_description", "<html><head></head><body>
      <p>
        The applicability domain (AD) of the training set is characterized by 
        the confidence index of a prediction (high confidence index: close to 
        the applicability domain of the training set/reliable prediction, low 
        confidence: far from the applicability domain of the 
        trainingset/unreliable prediction). The confidence index considers (i) 
        the similarity and number of neighbors and (ii) contradictory examples 
        within the neighbors. A formal definition can be found in Helma 2006.
      </p>
      <p>
        The reliability of predictions decreases gradually with increasing 
        distance from the applicability domain (i.e. decreasing confidence index)
      </p>
    </body>
  </html>"

  # Method used to assess the applicability domain 5.2
  report.value "app_domain_method", "see Helma 2006 and Maunz 2008"
  
  # Software name and version for applicability domain assessment 5.3  
  report.change_catalog :software_catalog, :software_catalog_3, {:name => "lazar, submitted version: #{lazar_commit}", :description => "integrated into main lazar algorithm", :number => "3", :url => "https://lazar.in-silico.ch", :contact => "info@in-silico.ch"}
  report.ref_catalog :app_domain_software, :software_catalog, :software_catalog_3

  # Limits of applicability 5.4
  report.value "applicability_limits", "Predictions with low confidence index, unknown substructures and neighbors that might act by different mechanisms"

  # Availability of the training set 6.1
  report.change_attributes "training_set_availability", {:answer => "Yes"}

  # Available information for the training set 6.2
  report.change_attributes "training_set_data", {:cas => "Yes", :chemname => "Yes", :formula => "Yes", :inchi => "Yes", :mol => "Yes", :smiles => "Yes"}

  # Data for each descriptor variable for the training set 6.3
  report.change_attributes "training_set_descriptors", {:answer => "No"}

  # Data for the dependent variable for the training set 6.4
  report.change_attributes "dependent_var_availability", {:answer => "All"}

  # Other information about the training set 6.5
  report.value "other_info", "#{prediction_model.source}"

  # Pre-processing of data before modelling 6.6
  report.value "preprocessing", (model.class == OpenTox::Model::LazarRegression ? "-log10 transformation" : "none")

  # Robustness - Statistics obtained by leave-many-out cross-validation 6.9
  if prediction_model.repeated_crossvalidation
    $logger.error "#####################{prediction_model}"
    crossvalidations = prediction_model.crossvalidations
    out = haml File.read(validation_template), :layout=> false, :locals => {:model => prediction_model, :crossvalidations => crossvalidations}
    report.value "lmo",  out
  end

  # Mechanistic basis of the model 8.1
  report.value "mechanistic_basis","<html><head></head><body>
    <p>
      Compounds with similar structures (neighbors) are assumed to have 
      similar activities as the query compound. For the determination of 
      activity specific similarities only statistically relevant subtructures 
      (paths) are used. For this reason there is a priori no bias towards 
      specific mechanistic hypothesis.
    </p>
  </body>
</html>"

  # A priori or a posteriori mechanistic interpretation 8.2
  report.value "mechanistic_basis_comments","a posteriori for individual predictions"

  # Other information about the mechanistic interpretation 8.3
  report.value "mechanistic_basis_info","<html><head></head><body><p>Hypothesis about biochemical mechanisms can be derived from individual 
      predictions by inspecting neighbors and relevant fragments.</p>
      <p>Neighbors are compounds that are similar in respect to a certain 
      endpoint and it is likely that compounds with high similarity act by 
      similar mechanisms as the query compound. Links at the webinterface 
      prove an easy access to additional experimental data and literature 
      citations for the neighbors and the query structure.</p>
      <p>Activating and deactivating parts of the query compound are highlighted 
      in red and green on the webinterface. Fragments that are unknown (or too 
      infrequent for statistical evaluation are marked in yellow and 
      additional statistical information about the individual fragments can be 
      retrieved. Please note that lazar predictions are based on neighbors and 
      not on fragments. Fragments and their statistical significance are used 
      for the calculation of activity specific similarities.</p>"

  # Bibliography 9.2
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_1
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_2
  report.change_catalog :publications_catalog, :publications_catalog_3, {:title => "Helma (2006), Lazy structure-activity relationships (lazar) for the prediction of rodent carcinogenicity and Salmonella mutagenicity.", :url => "http://dx.doi.org/10.1007/s11030-005-9001-5"}
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_3

  # output
  t = Tempfile.new
  t << report.to_xml
  send_file t.path, :filename => "QMRF_report_#{model.name}.xml", :type => "application/xml", :disposition => "attachment"
end

get '/license' do
  @license = RDiscount.new(File.read("LICENSE.md")).to_html
  haml :license, :layout => false
end

get '/faq' do
  @faq = RDiscount.new(File.read("FAQ.md")).to_html
  haml :faq, :layout => false
end

get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

