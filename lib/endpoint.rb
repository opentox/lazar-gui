# Get a list of all endpoints
# @param [Header] Accept one of text/uri-list,
# @return [text/uri-list] list of all prediction models
get "/api/endpoint/?" do
  models = Model::Validation.all
  endpoints = models.collect{|m| m.endpoint}.uniq
  case @accept
  when "text/uri-list"
    return endpoints.join("\n") + "\n"
  when "application/json"
    return endpoints.to_json
  else
    halt 400, "Mime type #{@accept} is not supported."
  end
end

get "/api/endpoint/:endpoint/?" do
  models = Model::Validation.where(endpoint: params[:endpoint])
  list = []
  models.each{|m| list << {m.species => uri("/api/model/#{m.id}")} }
  halt 404, "Endpoint: #{params[:endpoint]} not found." if models.blank?
  return list.to_json
end
