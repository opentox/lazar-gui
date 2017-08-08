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
  report.value "QSAR_title", "Lazar model for #{prediction_model.species} #{prediction_model.endpoint.downcase}"

  # Software coding the model 1.3
  report.change_catalog :software_catalog, :firstsoftware, {:name => "lazar", :description => "lazar Lazy Structure- Activity Relationships. See #{lazar_commit}", :number => "1", :url => "https://lazar.in-silico.ch", :contact => "info@in-silico.ch"}
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
  report.change_catalog :publications_catalog, :publications_catalog_1, {:title => "Maunz A., Guetlein M., Rautenberg M., Vorgrimmler D., Gebele D. and Helma C. (2013), lazar: a modular predictive toxicology framework  ", :number => "1", :url => "http://dx.doi.org/10.3389/fphar.2013.00038"}
  report.ref_catalog :references, :publications_catalog, :publications_catalog_1

  report.change_catalog :publications_catalog, :publications_catalog_2, {:title => "Helma C, Gebele D, Rautenberg M (2017) lazar, software available at https://lazar.in-silico.ch,source code available at #{lazar_commit}", :number => "2", :url => "https://doi.org/10.5281/zenodo.215483"}
  report.ref_catalog :references, :publications_catalog, :publications_catalog_2

  # Availability of information about the model 2.8
  report.value "info_availability", "Prediction interface and validation results available at https://lazar.in-silico.ch"

  # Species 3.1
  report.value "model_species", prediction_model.species 

  # Endpoint 3.2
  report.change_catalog :endpoints_catalog, :endpoints_catalog_1, {:name => prediction_model.qmrf["name"], :group => "#{prediction_model.qmrf["group"]}"}
  report.ref_catalog :model_endpoint, :endpoints_catalog, :endpoints_catalog_1

  # Endpoint Units 3.4
  report.value "endpoint_units", "#{prediction_model.unit}"

  # Dependent variable 3.5
  report.value "endpoint_variable", "#{prediction_model.endpoint} #{prediction_model.regression? ? "regression" : "classification"}"

  # Type of model 4.1
  model_type = model.class.to_s.gsub('OpenTox::Model::Lazar','')
  report.value "algorithm_type", "#{model_type}"

  # Explicit algorithm 4.2
  report.ref_catalog :algorithm_explicit, :algorithms_catalog, :algorithms_catalog_1
  report.change_catalog :algorithms_catalog, :algorithms_catalog_1, {:definition => "", :description => "modified k-nearest neighbor #{model_type.downcase} (#{model_type =~ /regression/i ? "local random forest" : "weighted majority vote"}), see #{lazar_commit}"  }

  # Descriptors in the model 4.3
  if model.algorithms["descriptors"][:type]
    report.change_catalog :descriptors_catalog, :descriptors_catalog_1, {:description => "Molprint 2D (Bender et al. 2004)", :name => "#{model.algorithms["descriptors"][:type]} fingerprints", :publication_ref => "", :units => ""}
    report.ref_catalog :algorithms_descriptors, :descriptors_catalog, :descriptors_catalog_1
  end

  # Descriptor selection 4.4
  report.value "descriptors_selection", (model.class == OpenTox::Model::LazarRegression ? "Correlation with dependent variable (Pearson p <= 0.05)" : "none")
  
  # Algorithm and descriptor generation 4.5
  report.value "descriptors_generation", "lazar"
  
  # Software name and version for descriptor generation 4.6
  report.change_catalog :software_catalog, :software_catalog_2, {:name => "lazar, submitted version: #{lazar_commit}", :description => "", :number => "2", :url => "", :contact => ""}
  report.ref_catalog :descriptors_generation_software, :software_catalog, :software_catalog_2

  # Chemicals/Descriptors ratio 4.7
  report.value "descriptors_chemicals_ratio", (model.class == OpenTox::Model::LazarRegression ? "variable (local regression models)" : "not applicable (classification based on activities of neighbors, descriptors are used for similarity calculation)")

  # Description of the applicability domain of the model 5.1
  report.value "app_domain_description", "<html><head></head><body>
      <p>
        No predictions are made for query compounds without similar structures
        in the training data. Similarity is determined as the Tanimoto coefficient of
        Molprint 2D fingerprints with a threshold of 0.1.
      </p>
      <p>
        Predictions based on a low number and/or very dissimilar neighbors or
        on neighbors with conflicting experimental measurements
        should be treated with caution.
      </p>
    </body>
  </html>"

  # Method used to assess the applicability domain 5.2
  report.value "app_domain_method", "Number and similarity of training set compounds (part of the main lazar algorithm)"
  
  # Software name and version for applicability domain assessment 5.3  
  report.change_catalog :software_catalog, :software_catalog_3, {:name => "lazar, submitted version: #{lazar_commit}", :description => "", :number => "3", :url => "", :contact => ""}
  report.ref_catalog :app_domain_software, :software_catalog, :software_catalog_3

  # Limits of applicability 5.4
  report.value "applicability_limits", "Compounds without similar substances in the training dataset"

  # Availability of the training set 6.1
  report.change_attributes "training_set_availability", {:answer => "Yes"}

  # Available information for the training set 6.2
  report.change_attributes "training_set_data", {:cas => "Yes", :chemname => "Yes", :formula => "Yes", :inchi => "Yes", :mol => "Yes", :smiles => "Yes"}

  # Data for each descriptor variable for the training set 6.3
  report.change_attributes "training_set_descriptors", {:answer => "on demand"}

  # Data for the dependent variable for the training set 6.4
  report.change_attributes "dependent_var_availability", {:answer => "Yes"}

  # Other information about the training set 6.5
  report.value "other_info", "Original data from: #{prediction_model.source}"

  # Pre-processing of data before modelling 6.6
  report.value "preprocessing", (model.class == OpenTox::Model::LazarRegression ? "-log10 transformation" : "none")

  # Robustness - Statistics obtained by leave-many-out cross-validation 6.9
  if prediction_model.repeated_crossvalidation
    crossvalidations = prediction_model.crossvalidations
    block = ""
    crossvalidations.each do |cv|
      block += "<p>
                  <p>Num folds: #{cv.folds}</p>
                  <p>Num instances: #{cv.nr_instances}</p>
                  <p>Num unpredicted: #{cv.nr_unpredicted}</p>"
      if model_type =~ /classification/i
				block += "<p>Accuracy: #{cv.accuracy.signif(3)}</p>
									<p>Weighted accuracy: #{cv.weighted_accuracy.signif(3)}</p>
              		<p>True positive rate: #{cv.true_rate[cv.accept_values[0]].signif(3)}</p>
              		<p>True negative rate: #{cv.true_rate[cv.accept_values[1]].signif(3)}</p>
              		<p>Positive predictive value: #{cv.predictivity[cv.accept_values[0]].signif(3)}</p>
              		<p>Negative predictive value: #{cv.predictivity[cv.accept_values[1]].signif(3)}</p>"
			end
			if model_type =~ /regression/i
      	block += "<p>RMSE: #{cv.rmse.signif(3)}</p>
        					<p>MAE: #{cv.mae.signif(3)}</p>
        					<p>R<sup>2</sup>: #{cv.r_squared.signif(3)}</p>"
      end
			block += "</p>"
		end 
    report.value "lmo", "<html><head></head><body><b>3 independent 10-fold crossvalidations:</b>"+block+"</body></html>"
  end

  # Availability of the external validation set 7.1
  report.change_attributes "validation_set_availability", {:answer => "No"}

  # Available information for the external validation set 7.2
  report.change_attributes "validation_set_data", {:cas => "", :chemname => "", :formula => "", :inchi => "", :mol => "", :smiles => ""}

  # Data for each descriptor variable for the external validation set 7.3
  report.change_attributes "validation_set_descriptors", {:answer => "Unknown"}

  # Data for the dependent variable for the external validation set 7.4
  report.change_attributes "validation_dependent_var_availability", {:answer => "Unknown"}

  # Mechanistic basis of the model 8.1
  report.value "mechanistic_basis","<html><head></head><body>
    <p>
      Compounds with similar structures (neighbors) are assumed to have
      similar activities as the query compound.
    </p>
  </body>
</html>"

  # A priori or a posteriori mechanistic interpretation 8.2
  report.value "mechanistic_basis_comments","A posteriori for individual predictions"

  # Other information about the mechanistic interpretation 8.3
  report.value "mechanistic_basis_info","<html><head></head><body>
    <p>
      Hypothesis about biochemical mechanisms can be derived from individual 
      predictions by inspecting neighbors and relevant descriptors.
    </p>
    <p>
      Neighbors are compounds that are similar in respect to a certain 
      endpoint and it is likely that compounds with high similarity act by 
      similar mechanisms as the query compound. Links at the webinterface 
      prove an easy access to additional experimental data and literature 
      citations for the neighbors and the query structure.
    </p>
    <p>
      Please note that lazar predictions are based on neighbors.
			Descriptors are only used for the calculation of similarities.
    </p>
  </body>
</html>"

  # Comments 9.1
	report.value "comments", "<html><head></head><body>
    <p>
      Public model interface: https://lazar.in-silico.ch
    </p>
    <p>
      Source code: #{lazar_commit}
    </p>
    <p>
      Docker image: https://hub.docker.com/r/insilicotox/lazar/
    </p>
  </body>
</html>"

	# Bibliography 9.2
  report.change_catalog :publications_catalog, :publications_catalog_1, {:title => "Helma (2017), Nano-Lazar: Read across Predictions for Nanoparticle Toxicities with Calculated and Measured Properties", :url => "https://dx.doi.org/10.3389%2Ffphar.2017.00377"}
  report.change_catalog :publications_catalog, :publications_catalog_2, {:title => "Lo Piparo (2014), Automated and reproducible read-across like models for predicting carcinogenic potency", :url => "https://doi.org/10.1016/j.yrtph.2014.07.010"}
  report.change_catalog :publications_catalog, :publications_catalog_3, {:title => "Helma (2006), Lazy structure-activity relationships (lazar) for the prediction of rodent carcinogenicity and Salmonella mutagenicity.", :url => "http://dx.doi.org/10.1007/s11030-005-9001-5"}
  report.change_catalog :publications_catalog, :publications_catalog_4, {:title => "Bender et al. (2004), Molecular similarity searching using atom environments, information-based feature selection, and a nave bayesian classifier.", :url => "https://doi.org/10.1021/ci034207y"}

  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_1
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_2
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_3
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_4


  # output
  t = Tempfile.new
  t << report.to_xml
  name = prediction_model.species.sub(/\s/,"-")+"-"+prediction_model.endpoint.downcase.sub(/\s/,"-")
  send_file t.path, :filename => "QMRF_report_#{name.gsub!(/[^0-9A-Za-z]/, '_')}.xml", :type => "application/xml", :disposition => "attachment"
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

