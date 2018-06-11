# Get all substances
get "/substance/?" do
  substances = Substance.all
  case @accept
  when "text/uri-list"
    uri_list = substances.collect{|substance| uri("/substance/#{substance.id}")}
    return uri_list.join("\n") + "\n"
  when "application/json"
    substances = JSON.parse substances.to_json
    substances.each_index do |idx|
      substances[idx][:URI] = uri("/substance/#{substances[idx]["_id"]["$oid"]}")
    end
    return substances.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

# Get a substance
get "/substance/:id/?" do
  case @accept
  when "application/json"
    substance = Substance.find :id => params[:id]
    not_found_error "Substance with id: #{params[:id]} not found." unless substance
    substance[:URI] = uri("/substance/#{substance.id}")
    return substance.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end
