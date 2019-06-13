# Get a list of all possible reports to prediction models
# @param [Header] Accept one of text/uri-list,
# @return [text/uri-list] list of all prediction models
get "/api/report/?" do
  models = Model::Validation.all
  case @accept
  when "text/uri-list"
    uri_list = models.collect{|model| uri("/api/report/#{model.model_id}")}
    return uri_list.join("\n") + "\n"
  when "application/json"
    models = JSON.parse models.to_json
    list = []
    models.each{|m| list << uri("/api/report/#{m["_id"]["$oid"]}")}
    return list.to_json
  else
    halt 400, "Mime type #{@accept} is not supported."
  end
end

get "/api/report/:id/?" do
  case @accept
  when "application/xml"
    report = qmrf_report params[:id]
    return report.to_xml
  else
    halt 400, "Mime type #{@accept} is not supported."
  end

end
