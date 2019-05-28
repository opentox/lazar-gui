get "/" do
  response['Content-Type'] = "text/html"
  index_file = File.join(ENV['HOME'],"swagger-ui/dist/index.html")
  File.read(index_file)
end
