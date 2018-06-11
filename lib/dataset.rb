# Get all datasets
get "/dataset/?" do
  datasets = Dataset.all
  case @accept
  when "text/uri-list"
    uri_list = datasets.collect{|dataset| uri("/dataset/#{dataset.id}")}
    return uri_list.join("\n") + "\n"
  when "application/json"
    datasets = JSON.parse datasets.to_json
    list = []
    datasets.each{|d| list << uri("/dataset/#{d["_id"]["$oid"]}")}
    return list.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

# Get a dataset
get "/dataset/:id/?" do
  dataset = Dataset.find :id => params[:id]
  not_found_error "Dataset with id: #{params[:id]} not found." unless dataset
  case @accept
  when "application/json"
    dataset.data_entries.each do |k, v|
      dataset.data_entries[k][:URI] = uri("/substance/#{k}")
    end
    dataset[:URI] = uri("/dataset/#{dataset.id}")
    dataset[:substances] = uri("/dataset/#{dataset.id}/substances")
    dataset[:features] = uri("/dataset/#{dataset.id}/features")
    return dataset.to_json
  when "text/csv", "application/csv"
    return dataset.to_csv
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

# Get a dataset attribute. One of compounds, nanoparticles, substances, features 
get "/dataset/:id/:attribute/?" do
  dataset = Dataset.find :id => params[:id]
  not_found_error "Dataset with id: #{params[:id]} not found." unless dataset
  attribs = ["compounds", "nanoparticles", "substances", "features"]
  return "Attribute '#{params[:attribute]}' is not available. Choose one of #{attribs.join(', ')}." unless attribs.include? params[:attribute]
  out = dataset.send("#{params[:attribute]}")
  return out.to_json
end
