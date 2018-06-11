
# Get a list of all prediction models
# @param [Header] Accept one of text/uri-list,
# @return [text/uri-list] list of all prediction models
get "/model/?" do
  models = Model::Validation.all
  case @accept
  when "text/uri-list"
    uri_list = models.collect{|model| uri("/model/#{model.id}")}
    return uri_list.join("\n") + "\n"
  when "application/json"
    models = JSON.parse models.to_json
    list = []
    models.each{|m| list << uri("/model/#{m["_id"]["$oid"]}")}
    return list.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

get "/model/:id/?" do
  model = Model::Validation.find params[:id]
  not_found_error "Model with id: #{params[:id]} not found." unless model
  return model.to_json
end


post "/model/:id/?" do
  identifier = params[:identifier].split(",")
  compounds = identifier.collect{ |i| Compound.from_smiles i.strip }
  model = Model::Validation.find params[:id]
  batch = {}
  compounds.each do |compound|
    prediction = model.predict(compound)
    batch[compound] = {:id => compound.id, :inchi => compound.inchi, :smiles => compound.smiles, :model => model, :prediction => prediction}
  end
  return batch.to_json
end
