# Get all datasets
get "/api/dataset/?" do
  datasets = Dataset.all #.limit(100)
  case @accept
  when "application/json"
    list = datasets.collect{|dataset| uri("/api/dataset/#{dataset.id}")}.to_json
    return list
  else
    halt 400, "Mime type #{@accept} is not supported."
  end
end

# Get a dataset
get "/api/dataset/:id/?" do
  dataset = Dataset.find :id => params[:id]
  halt 400, "Dataset with id: #{params[:id]} not found." unless dataset
  case @accept
  when "text/csv", "application/csv"
    return File.read dataset.source
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

# Get a dataset attribute. One of compounds, nanoparticles, substances, features 
get "/api/dataset/:id/:attribute/?" do
  dataset = Dataset.find :id => params[:id]
  halt 400,  "Dataset with id: #{params[:id]} not found." unless dataset
  attribs = ["compounds", "nanoparticles", "substances", "features"]
  return "Attribute '#{params[:attribute]}' is not available. Choose one of #{attribs.join(', ')}." unless attribs.include? params[:attribute]
  out = dataset.send("#{params[:attribute]}")
  return out.to_json
end
