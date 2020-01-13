get "/" do
  response['Content-Type'] = "text/html"
  index_file = File.join(ENV['HOME'],"swagger-ui/dist/index.html")
  halt 400, "API Documentation in Swagger JSON is not implemented." unless File.exists?(index_file)
  File.read(index_file)
end
