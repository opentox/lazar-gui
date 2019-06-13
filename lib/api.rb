get "/api" do
  api_file = File.join("api", "api.json")
  halt 400, "API Documentation in Swagger JSON is not implemented." unless File.exists?(api_file)
  case @accept
  when "text/html"
    response['Content-Type'] = "text/html"
    index_file = File.join(ENV['HOME'],"swagger-ui/dist/index.html")
    File.read(index_file)
  when "application/json"
    response['Content-Type'] = "application/json"
    api_hash = JSON.parse(File.read(api_file))
    api_hash["host"] = request.env['HTTP_HOST']
    return api_hash.to_json
  else
    halt 400, "unknown MIME type '#{@accept}'"
  end
end

get "/api/api.json" do
  response['Content-Type'] = "text/html"
  index_file = File.join(ENV['HOME'],"swagger-ui/dist/index.html")
  File.read(index_file)
end
