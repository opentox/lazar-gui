def qmrf_report id
  lazarpath = `gem path lazar`
  lazarpath = File.dirname lazarpath
  lazarpath = File.dirname lazarpath
  qmrfpath = `gem path qsar-report`
  qmrfpath = File.dirname qmrfpath
  qmrfpath = File.dirname qmrfpath
  prediction_model = Model::Validation.find id
	model = prediction_model.model

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

  # QMRF author(s) and contact details 2.2
  report.change_catalog :authors_catalog, :firstauthor, {:name => "Christoph Helma", :affiliation => "in silico toxicology gmbh", :contact => "Rastatterstr. 41, CH-4057 Basel", :email => "info@in-silico.ch", :number => "1", :url => "www.in-silico.ch"}
  report.ref_catalog :qmrf_authors, :authors_catalog, :firstauthor

  # Date of QMRF update(s) 2.3
  $logger.debug prediction_model
  if prediction_model.model.name =~ /TD50|multiple/
    report.value "qmrf_date_revision", "2014-12-05" 
  end
 
  # Date of QMRF update(s) 2.4
  if prediction_model.model.name =~ /TD50/
    report.value "qmrf_revision", "Q29-44-39-423" 
  elsif prediction_model.model.name =~ /multiple/
    report.value "qmrf_revision", "Q28-43-38-420" 
  end
 
  # Model developer(s) and contact details 2.5
  report.change_catalog :authors_catalog, :modelauthor, {:name => "Christoph Helma", :affiliation => "in silico toxicology gmbh", :contact => "Rastatterstr. 41, CH-4057 Basel", :email => "info@in-silico.ch", :number => "1", :url => "www.in-silico.ch"}
  report.ref_catalog :model_authors, :authors_catalog, :modelauthor

  # Date of model development and/or publication 2.6
  report.value "model_date", "#{Time.parse(model.created_at.to_s).strftime('%Y')}"

  # Reference(s) to main scientific papers and/or software package 2.7
  report.change_catalog :publications_catalog, :publications_catalog_4, {:title => "Maunz A., Guetlein M., Rautenberg M., Vorgrimmler D., Gebele D. and Helma C. (2013), lazar: a modular predictive toxicology framework  ", :url => "http://dx.doi.org/10.3389/fphar.2013.00038"}
  
  report.ref_catalog :references, :publications_catalog, :publications_catalog_4
  
  report.change_catalog :publications_catalog, :publications_catalog_1, {:title => "Helma C., Gebele D., Rautenberg M. (2017) lazar, software available at https://lazar.in-silico.ch,source code available at #{lazar_commit}", :url => "https://doi.org/10.5281/zenodo.215483"}
  
  report.ref_catalog :references, :publications_catalog, :publications_catalog_1

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
  report.value "endpoint_variable", "#{prediction_model.endpoint}"

  # Type of model 4.1
  model_type = model.class.to_s.gsub('OpenTox::Model::Lazar','')
  report.value "algorithm_type", "#{model_type}"

  # Explicit algorithm 4.2
  report.ref_catalog :algorithm_explicit, :algorithms_catalog, :algorithms_catalog_1
  report.change_catalog :algorithms_catalog, :algorithms_catalog_1, {:definition => "", :description => "modified k-nearest neighbor #{model_type.downcase} (#{model_type =~ /regression/i ? "local random forest" : "weighted majority vote"}), see #{lazar_commit}"  }

  # Descriptors in the model 4.3
  if model.algorithms["descriptors"][:type]
    report.change_catalog :descriptors_catalog, :descriptors_catalog_1, {:description => "(Bender et al. 2004)", :name => "#{model.algorithms["descriptors"][:type]} fingerprints", :publication_ref => "", :units => ""}
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
                  <p>Predictions number:</p>
                    <p>all:#{cv.nr_predictions["all"]}</p>
                    <p>confidence high: #{cv.nr_predictions["confidence_high"]}</p>
                    <p>confidence low: #{cv.nr_predictions["confidence_low"]}</p>
                  </p>"
      if model_type =~ /classification/i
				block += "<p>Accuracy:
                    <p>all:#{cv.accuracy["all"].signif(3)}</p>
                    <p>confidence high:#{cv.accuracy["confidence_high"].signif(3)}</p>
                    <p>confidence_low:#{cv.accuracy["confidence_low"].signif(3)}</p>
                  </p>
              		<p>True rate:
                    <p>all:
                      <p>#{cv.accept_values[0]}:#{cv.true_rate["all"][cv.accept_values[0]].signif(3)}</p>
              		    <p>#{cv.accept_values[1]}:#{cv.true_rate["all"][cv.accept_values[1]].signif(3)}</p>
                    </p>
                    <p>confidence high:
                      <p>#{cv.accept_values[0]}:#{cv.true_rate["confidence_high"][cv.accept_values[0]].signif(3)}</p>
              		    <p>#{cv.accept_values[1]}:#{cv.true_rate["confidence_high"][cv.accept_values[1]].signif(3)}</p>
                    </p>
                    <p>confidence low:
                      <p>#{cv.accept_values[0]}:#{cv.true_rate["confidence_low"][cv.accept_values[0]].signif(3)}</p>
              		    <p>#{cv.accept_values[1]}:#{cv.true_rate["confidence_low"][cv.accept_values[1]].signif(3)}</p>
                    </p>
                  </p>
              		<p>Predictivity:
                    <p>all:
                      <p>#{cv.accept_values[0]}:#{cv.predictivity["all"][cv.accept_values[0]].signif(3)}</p>
              		    <p>#{cv.accept_values[1]}:#{cv.predictivity["all"][cv.accept_values[1]].signif(3)}</p>
                    </p>
                    <p>confidence high:
                      <p>#{cv.accept_values[0]}:#{cv.predictivity["confidence_high"][cv.accept_values[0]].signif(3)}</p>
              		    <p>#{cv.accept_values[1]}:#{cv.predictivity["confidence_high"][cv.accept_values[1]].signif(3)}</p>
                    </p>
                    <p>confidence low:
                      <p>#{cv.accept_values[0]}:#{cv.predictivity["confidence_low"][cv.accept_values[0]].signif(3)}</p>
              		    <p>#{cv.accept_values[1]}:#{cv.predictivity["confidence_low"][cv.accept_values[1]].signif(3)}</p>
                    </p>
                  </p>"
			end
			if model_type =~ /regression/i
      	block += "<p>RMSE:
                    <p>all:#{cv.rmse["all"].signif(3)}</p>
                    <p>confidence high:#{cv.rmse["confidence_high"].signif(3)}</p>
                    <p>confidence low:#{cv.rmse["confidence_low"].signif(3)}</p>
                  </p>
        					<p>MAE:
                    <p>all:#{cv.mae["all"].signif(3)}</p>
                    <p>confidence high:#{cv.mae["confidence_high"].signif(3)}</p>
                    <p>confidence low:#{cv.mae["confidence_low"].signif(3)}</p>
                  </p>
        					<p>R<sup>2</sup>:
                    <p>all:#{cv.r_squared["all"].signif(3)}</p>
                    <p>confidence high:#{cv.r_squared["confidence_high"].signif(3)}</p>
                    <p>confidence low:#{cv.r_squared["confidence_low"].signif(3)}</p>
                  </p>
        					<p>Within prediction interval:
                    <p>all:#{cv.within_prediction_interval["all"]}</p>
                    <p>confidence high:#{cv.within_prediction_interval["confidence_high"]}</p>
                    <p>confidence low:#{cv.within_prediction_interval["confidence_low"]}</p>
                  </p>
        					<p>Out of prediction interval:
                    <p>all:#{cv.out_of_prediction_interval["all"]}</p>
                    <p>confidence high:#{cv.out_of_prediction_interval["confidence_high"]}</p>
                    <p>confidence low:#{cv.out_of_prediction_interval["confidence_low"]}</p>
                  </p>"
      end
			block += "</p>"
		end 
    report.value "lmo", "<html><head></head><body><b>5 independent 10-fold crossvalidations:</b>"+block+"</body></html>"
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
  
  report.change_catalog :publications_catalog, :publications_catalog_2, {:title => "Helma C., Rautenberg M. and Gebele D. (2017), Nano-Lazar: Read across Predictions for Nanoparticle Toxicities with Calculated and Measured Properties", :url => "https://dx.doi.org/10.3389%2Ffphar.2017.00377"}
  
  report.change_catalog :publications_catalog, :publications_catalog_3, {:title => "Lo Piparo et al. (2014), Automated and reproducible read-across like models for predicting carcinogenic potency", :url => "https://doi.org/10.1016/j.yrtph.2014.07.010"}
  
  report.change_catalog :publications_catalog, :publications_catalog_5, {:title => "Maunz A. and Helma C. (2008), Prediction of chemical toxicity with local support vector regression and activity-specific kernels", :url => "http://dx.doi.org/10.1080/10629360802358430"}
  
  report.change_catalog :publications_catalog, :publications_catalog_6, {:title => "Helma C. (2006), Lazy structure-activity relationships (lazar) for the prediction of rodent carcinogenicity and Salmonella mutagenicity.", :url => "http://dx.doi.org/10.1007/s11030-005-9001-5"}
  
  report.change_catalog :publications_catalog, :publications_catalog_7, {:title => "Bender et al. (2004), Molecular similarity searching using atom environments, information-based feature selection, and a nave bayesian classifier.", :url => "https://doi.org/10.1021/ci034207y"}

  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_2
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_3
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_5
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_6
  report.ref_catalog :bibliography, :publications_catalog, :publications_catalog_7
	
	report

end
