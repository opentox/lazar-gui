# Get all Nanoparticles
get "/nanoparticle/?" do
  nanoparticles = Nanoparticle.all
  case @accept
  when "text/uri-list"
    uri_list = nanoparticles.collect{|nanoparticle| uri("/nanoparticle/#{nanoparticle.id}")}
    return uri_list.join("\n") + "\n"
  when "application/json"
    nanoparticles = JSON.parse nanoparticles.to_json
    nanoparticles.each_index do |idx|
      nanoparticles[idx][:URI] = uri("/nanoparticle/#{nanoparticles[idx]["_id"]["$oid"]}")
    end
    return nanoparticles.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

# Get a nanoparticle
get "/nanoparticle/:id/?" do
  case @accept
  when "application/json"
    nanoparticle = Nanoparticle.find :id => params[:id]
    not_found_error "Nanoparticle with id: #{params[:id]} not found." unless nanoparticle
    nanoparticle[:URI] = uri("/nanoparticle/#{nanoparticle.id}")
    return nanoparticle.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end
