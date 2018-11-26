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
  if Task.where(id: params[:id]).exists?
    task = Task.find params[:id]
    halt 404, "Dataset with id: #{params[:id]} not found." unless task.percent == 100
    $logger.debug task.inspect
    response['Content-Type'] = "text/csv"
    m = Model::Validation.find task.model_id
    dataset = Batch.find task.dataset_id
    @ids = dataset.ids
    warnings = dataset.warnings.blank? ? nil : dataset.warnings.join("\n")
    unless warnings.nil?
      @parse = []
      warnings.split("\n").each do |warning|
        if warning =~ /^Cannot/
          smi = warning.split("SMILES compound").last.split("at").first
          line = warning.split("SMILES compound").last.split("at line").last.split("of").first.strip.to_i
          @parse << "Cannot parse SMILES compound#{smi}at line #{line} of #{dataset.source.split("/").last}\n"
        end
      end
      keys_array = []
      warnings.split("\n").each do |warning|
        if warning =~ /^Duplicate/
          text = warning.split("ID").first
          numbers = warning.split("ID").last.split("and")
          keys_array << numbers.collect{|n| n.strip.to_i}
        end
      end
      @dups = {}
      keys_array.each do |keys|
        keys.each do |key|
          @dups[key] = "Duplicate compound at ID #{keys.join(" and ")}\n"
        end
      end
    end
    $logger.debug "dups: #{@dups}"
    endpoint = "#{m.endpoint}_(#{m.species})"
    tempfile = Tempfile.new
    header = task.csv
    lines = []
    $logger.debug task.predictions
    task.predictions[m.id.to_s].each_with_index do |hash,idx|
      identifier = hash.keys[0]
      prediction_id = hash.values[0]
      # add duplicate warning at the end of a line if ID matches
      if @dups[idx+1]
        if prediction_id.is_a? BSON::ObjectId
          if @ids.blank?
            lines << "#{idx+1},#{identifier},#{Prediction.find(prediction_id).csv.tr("\n","")},#{@dups[idx+1]}"
          else
            lines << "#{idx+1},#{@ids[idx]},#{identifier},#{Prediction.find(prediction_id).csv.tr("\n","")},#{@dups[idx+1]}"
          end
        else
          if @ids.blank?
            lines << "#{idx+1},#{identifier},\n"
          else
            lines << "#{idx+1},#{@ids[idx]}#{identifier},\n"
          end
        end
      else
        if prediction_id.is_a? BSON::ObjectId
          if @ids.blank?
            lines << "#{idx+1},#{identifier},#{Prediction.find(prediction_id).csv}"
          else
            lines << "#{idx+1},#{@ids[idx]},#{identifier},#{Prediction.find(prediction_id).csv}"
          end
        else
          if @ids.blank?
            lines << "#{idx+1},#{identifier},\n"
          else
            lines << "#{idx+1},#{@ids[idx]}#{identifier},\n"
          end
        end
      end
    end
    (@parse && !@parse.blank?) ? tempfile.write(header+lines.join("")+"\n"+@parse.join("\n")) : tempfile.write(header+lines.join(""))
    #tempfile.write(header+lines.join(""))
    tempfile.rewind
    ########################
=begin
    header = task.csv
    lines = []
    task.predictions.each_with_index do |result,idx|
      identifier = result[0]
      prediction_id = result[1]
      prediction = Prediction.find prediction_id
      lines << "#{idx+1},#{identifier},#{prediction.csv.tr("\n","")}"
    end
    return header+lines.join("\n")
=end
    return tempfile.read
  else
    dataset = Dataset.find :id => params[:id]
    halt 400, "Dataset with id: #{params[:id]} not found." unless dataset
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
end

# Get a dataset attribute. One of compounds, nanoparticles, substances, features 
get "/dataset/:id/:attribute/?" do
  if Task.where(id: params[:id]).exists?
    halt 400, "No attributes selection available for dataset with id: #{params[:id]}.".to_json
  end
  dataset = Dataset.find :id => params[:id]
  halt 400,  "Dataset with id: #{params[:id]} not found." unless dataset
  attribs = ["compounds", "nanoparticles", "substances", "features"]
  return "Attribute '#{params[:attribute]}' is not available. Choose one of #{attribs.join(', ')}." unless attribs.include? params[:attribute]
  out = dataset.send("#{params[:attribute]}")
  return out.to_json
end
