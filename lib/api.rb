# route to swagger API file
get "/api/api.json" do
  response['Content-Type'] = "application/json"
  api_file = File.join("api", "api.json")
  bad_request_error "API Documentation in Swagger JSON is not implemented." unless File.exists?(api_file)
  api_hash = JSON.parse(File.read(api_file))
  api_hash["host"] = request.env['HTTP_HOST']
  return api_hash.to_json
end
