get "/api" do
  api_file = File.join("api", "api.json")
  `sed -i 's/SERVER_URI/#{request.env['HTTP_HOST']}/' #{api_file}`
  halt 400, "API Documentation in Swagger JSON is not implemented." unless File.exists?(api_file)
  case @accept
  when "text/html"
    response['Content-Type'] = "text/html"
    index_file = File.join(ENV['HOME'],"swagger-ui/dist/index.html")
    return File.read(index_file)
  when "application/json"
    redirect("/api/api.json")
  else
    halt 400, "unknown MIME type '#{@accept}'"
  end
end

get "/api/api.json" do
  api_file = File.join("api", "api.json")
  `sed -i 's/SERVER_URI/#{request.env['HTTP_HOST']}/' #{api_file}`
  case @accept
  when "text/html"
    response['Content-Type'] = "application/json"
    return File.read(api_file)
  when "application/json"
    return File.read(api_file)
  else
    halt 400, "unknown MIME type '#{@accept}'"
  end
end
