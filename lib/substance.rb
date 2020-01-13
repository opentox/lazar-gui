# Get all substances
get "/api/substance/?" do
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
    halt 400, "Mime type #{@accept} is not supported."
  end
end

# Get a substance by ID
get "/api/substance/:id/?" do
  case @accept
  when "application/json"
    substance = Substance.find params[:id]
    if substance
      out = {"compound": {"id": substance.id, 
                          "inchi": substance.inchi, 
                          "smiles": substance.smiles 
      }}
      return JSON.pretty_generate JSON.parse(out.to_json)
    else
      halt 400, "Substance with ID #{params[:id]} not found."
    end
  else
    halt 400, "Mime type #{@accept} is not supported."
  end
end
