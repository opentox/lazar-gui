# Get a list of all endpoints
# @param [Header] Accept one of text/uri-list,
# @return [text/uri-list] list of all prediction models
get "/endpoint/?" do
  models = Model::Validation.all
  endpoints = models.collect{|m| m.endpoint}.uniq
  case @accept
  when "text/uri-list"
    return endpoints.join("\n") + "\n"
  when "application/json"
    return endpoints.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

get "/endpoint/:endpoint/?" do
  models = Model::Validation.where(endpoint: params[:endpoint])
  list = []
  models.each{|m| list << {m.species => uri("/model/#{m.id}")} }
  not_found_error "Endpoint: #{params[:endpoint]} not found." if models.blank?
  return list.to_json
end
