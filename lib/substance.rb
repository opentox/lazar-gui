# Get all substances
get "/substance/?" do
  substances = Substance.all
  case @accept
  when "text/uri-list"
    uri_list = substances.collect{|substance| uri("/substance/#{substance.id}")}
    return uri_list.join("\n") + "\n"
  when "application/json"
    list = substances.collect{|substance| uri("/substance/#{substance.id}")}
    substances = JSON.parse list.to_json
    return JSON.pretty_generate substances
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

# Get a substance by ID
get "/substance/:id/?" do
  case @accept
  when "application/json"
    mongoid = /^[a-f\d]{24}$/i
    halt 400, "Input #{params[:id]} is no valid ID.".to_json unless params[:id].match(mongoid)
    substance = Substance.find params[:id]
    if substance
      out = {"compound": {"id": substance.id, "inchi": substance.inchi, "smiles": substance.smiles, "warnings": substance.warnings}}
      response['Content-Type'] = @accept
      return JSON.pretty_generate JSON.parse(out.to_json)
    else
      halt 400, "Substance with ID #{input} not found."
    end
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end
