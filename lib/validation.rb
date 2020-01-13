# All available validation types
VALIDATION_TYPES = ["repeatedcrossvalidation", "leaveoneout", "crossvalidation", "regressioncrossvalidation"]

# Get a list of ayll possible validation types
# @param [Header] Accept one of text/uri-list, application/json
# @return [text/uri-list] URI list of all validation types
get "/api/validation/?" do
  uri_list = VALIDATION_TYPES.collect{|validationtype| uri("/validation/#{validationtype}")}
  case @accept
  when "text/uri-list"
    return uri_list.join("\n") + "\n"
  when "application/json"
    return uri_list.to_json
  else
    halt 400, "Mime type #{@accept} is not supported."
  end
end

# Get a list of all validations 
# @param [Header] Accept one of text/uri-list, application/json
# @param [Path] Validationtype One of "repeatedcrossvalidation", "leaveoneout", "crossvalidation", "regressioncrossvalidation"
# @return [text/uri-list] list of all validations of a validation type
get "/api/validation/:validationtype/?" do
  halt 400, "There is no such validation type as: #{params[:validationtype]}" unless VALIDATION_TYPES.include? params[:validationtype]
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
    uri_list = validations.collect{|validation| uri("/api/validation/#{params[:validationtype]}/#{validation.id}")}
    return uri_list.join("\n") + "\n"
  when "application/json"
    validations = JSON.parse validations.to_json
    validations.each_index do |idx|
      validations[idx][:URI] = uri("/api/validation/#{params[:validationtype]}/#{validations[idx]["_id"]["$oid"]}")
    end
    return validations.to_json
  else
    halt 400, "Mime type #{@accept} is not supported."
  end
end

# Get validation representation
get "/api/validation/:validationtype/:id/?" do
  halt 400, "There is no such validation type as: #{params[:validationtype]}" unless VALIDATION_TYPES.include? params[:validationtype]
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

  halt 404, "#{params[:validationtype]} with id: #{params[:id]} not found." unless validation
  return validation.to_json
end
