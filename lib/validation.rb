# All available validation types
VALIDATION_TYPES = ["repeatedcrossvalidation", "leaveoneout", "crossvalidation", "regressioncrossvalidation"]

# Get a list of ayll possible validation types
# @param [Header] Accept one of text/uri-list, application/json
# @return [text/uri-list] URI list of all validation types
get "/validation/?" do
  uri_list = VALIDATION_TYPES.collect{|validationtype| uri("/validation/#{validationtype}")}
  case @accept
  when "text/uri-list"
    return uri_list.join("\n") + "\n"
  when "application/json"
    return uri_list.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

# Get a list of all validations 
# @param [Header] Accept one of text/uri-list, application/json
# @param [Path] Validationtype One of "repeatedcrossvalidation", "leaveoneout", "crossvalidation", "regressioncrossvalidation"
# @return [text/uri-list] list of all validations of a validation type
get "/validation/:validationtype/?" do
  bad_request_error "There is no such validation type as: #{params[:validationtype]}" unless VALIDATION_TYPES.include? params[:validationtype]
  case params[:validationtype]
  when "repeatedcrossvalidation"
    validations = Validation::RepeatedCrossValidation.all
  when "leaveoneout"
    validations = Validation::LeaveOneOut.all
  when "crossvalidation"
    validations = Validation::CrossValidation.all
  when "regressioncrossvalidation"
    validations = Validation::RegressionCrossValidation.all
  end

  case @accept
  when "text/uri-list"
    uri_list = validations.collect{|validation| uri("/validation/#{params[:validationtype]}/#{validation.id}")}
    return uri_list.join("\n") + "\n"
  when "application/json"
    validations = JSON.parse validations.to_json
    validations.each_index do |idx|
      validations[idx][:URI] = uri("/validation/#{params[:validationtype]}/#{validations[idx]["_id"]["$oid"]}")
    end
    return validations.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

# Get validation representation
get "/validation/:validationtype/:id/?" do
  bad_request_error "There is no such validation type as: #{params[:validationtype]}" unless VALIDATION_TYPES.include? params[:validationtype]
  case params[:validationtype]
  when "repeatedcrossvalidation"
    validation = Validation::RepeatedCrossValidation.find params[:id]
  when "leaveoneout"
    validation = Validation::LeaveOneOut.find params[:id]
  when "crossvalidation"
    validation = Validation::CrossValidation.find params[:id]
  when "regressioncrossvalidation"
    validation = Validation::RegressionCrossValidation.find params[:id]
  end

  not_found_error "#{params[:validationtype]} with id: #{params[:id]} not found." unless validation
  #model[:URI] = uri("/model/#{model.id}")
  #model[:neighbor_algorithm_parameters][:feature_dataset_uri] = uri("/dataset/#{model[:neighbor_algorithm_parameters][:feature_dataset_id]}") if model[:neighbor_algorithm_parameters][:feature_dataset_id]
  #model[:training_dataset_uri] = uri("/dataset/#{model.training_dataset_id}") if model.training_dataset_id
  #model[:prediction_feature_uri] = uri("/dataset/#{model.prediction_feature_id}") if model.prediction_feature_id
  return validation.to_json
end
