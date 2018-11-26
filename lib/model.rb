# Get a list of all prediction models
# @param [Header] Accept one of text/uri-list,
# @return [text/uri-list] list of all prediction models
get "/model/?" do
  models = Model::Validation.all
  case @accept
  when "text/uri-list"
    uri_list = models.collect{|model| uri("/model/#{model.id}")}
    return uri_list.join("\n") + "\n"
  when "application/json"
    models = JSON.parse models.to_json
    list = []
    models.each{|m| list << uri("/model/#{m["_id"]["$oid"]}")}
    return list.to_json
  else
    bad_request_error "Mime type #{@accept} is not supported."
  end
end

get "/model/:id/?" do
  model = Model::Validation.find params[:id]
  not_found_error "Model with id: #{params[:id]} not found." unless model
  return model.to_json
end

post "/model/:id/?" do
  if request.content_type == "application/x-www-form-urlencoded"
    identifier = params[:identifier].strip.gsub(/\A"|"\Z/,'')
    compound = Compound.from_smiles identifier
    model = Model::Validation.find params[:id]
    prediction = model.predict(compound)
    output = {:compound => {:id => compound.id, :inchi => compound.inchi, :smiles => compound.smiles},
              :model => model,
              :prediction => prediction
    }
    return 200, output.to_json
  elsif request.content_type =~ /^multipart\/form-data/ && request.content_length.to_i > 0
    @task = Task.new
    @task.save
    task = Task.run do
      m = Model::Validation.find params[:id]
      @task.update_percent(0.1)
      dataset = Batch.from_csv_file params[:fileName][:tempfile]
      compounds = dataset.compounds
      $logger.debug compounds.size
      identifiers = dataset.identifiers
      ids = dataset.ids
      type = (m.regression? ? "Regression" : "Classification")
      # add header for regression
      if type == "Regression"
        unit = (type == "Regression") ? "(#{m.unit})" : ""
        converted_unit = (type == "Regression") ? "#{m.unit =~ /\b(mmol\/L)\b/ ? "(mg/L)" : "(mg/kg_bw/day)"}" : ""
        if ids.blank?
          header = "ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements #{unit},Prediction #{unit},Prediction #{converted_unit},"\
          "Prediction Interval Low #{unit},Prediction Interval High #{unit},"\
          "Prediction Interval Low #{converted_unit},Prediction Interval High #{converted_unit},"\
          "inApplicabilityDomain,Note\n"
        else
          header = "ID,Original ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements #{unit},Prediction #{unit},Prediction #{converted_unit},"\
          "Prediction Interval Low #{unit},Prediction Interval High #{unit},"\
          "Prediction Interval Low #{converted_unit},Prediction Interval High #{converted_unit},"\
          "inApplicabilityDomain,Note\n"
        end
      end
      # add header for classification
      if type == "Classification"
        av = m.prediction_feature.accept_values
        if ids.blank?
          header = "ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements,Prediction,"\
          "predProbability #{av[0]},predProbability #{av[1]},inApplicabilityDomain,Note\n"
        else
          header = "ID,Original ID,Input,Endpoint,Unique SMILES,inTrainingSet,Measurements,Prediction,"\
          "predProbability #{av[0]},predProbability #{av[1]},inApplicabilityDomain,Note\n"
        end
      end
      # predict compounds
      p = 100.0/compounds.size
      counter = 1
      predictions = []
      compounds.each_with_index do |cid,idx|
        compound = Compound.find cid
        #$logger.debug compound.inspect
        if Prediction.where(compound: compound.id, model: m.id).exists?
          prediction_object = Prediction.find_by(compound: compound.id, model: m.id)
          prediction = prediction_object.prediction
          prediction_id = prediction_object.id
          # in case prediction object was created by single prediction
          if prediction_object.csv.blank?
            prediction_object[:csv] = prediction_to_csv(m,compound,prediction)
            prediction_object.save
          end
          # identifier
          identifier = identifiers[idx]
        else
          prediction = m.predict(compound)
          # save prediction object
          prediction_object = Prediction.new
          prediction_id = prediction_object.id
          prediction_object[:compound] = compound.id
          prediction_object[:model] = m.id
          # add additionally fields for html representation
          unless prediction[:value].blank? || type == "Classification"
            prediction[:prediction_value] = "#{prediction[:value].delog10.signif(3)} #{unit}"
            prediction["converted_prediction_value"] = "#{compound.mmol_to_mg(prediction[:value].delog10).signif(3)} #{converted_unit}"
          end
          unless prediction[:prediction_interval].blank?
            interval = prediction[:prediction_interval]
            prediction[:interval] = "#{interval[1].delog10.signif(3)} - #{interval[0].delog10.signif(3)} #{unit}"
            prediction[:converted_interval] = "#{compound.mmol_to_mg(interval[1].delog10).signif(3)} - #{compound.mmol_to_mg(interval[0].delog10).signif(3)} #{converted_unit}"
          end
          prediction["unit"] = unit
          prediction["converted_unit"] = converted_unit
          if prediction[:measurements].is_a?(Array)
            prediction["measurements_string"] = (type == "Regression") ? prediction[:measurements].collect{|value| "#{value.delog10.signif(3)} #{unit}"} : prediction[:measurements].join("</br>")
            prediction["converted_measurements"] = prediction[:measurements].collect{|value| "#{compound.mmol_to_mg(value.delog10).signif(3)} #{unit =~ /mmol\/L/ ? "(mg/L)" : "(mg/kg_bw/day)"}"} if type == "Regression"
          else
            output["measurements_string"] = (type == "Regression") ? "#{prediction[:measurements].delog10.signif(3)} #{unit}}" : prediction[:measurements]
            output["converted_measurements"] = "#{compound.mmol_to_mg(prediction[:measurements].delog10).signif(3)} #{(unit =~ /\b(mmol\/L)\b/) ? "(mg/L)" : "(mg/kg_bw/day)"}" if type == "Regression"
          end

          # store in prediction_object
          prediction_object[:prediction] = prediction
          prediction_object[:csv] = prediction_to_csv(m,compound,prediction)
          prediction_object.save

          # identifier
          identifier = identifiers[idx]
        end
        # collect prediction_object ids with identifier
        predictions << {"#{identifier}" => prediction_id}
        $logger.debug predictions.inspect
        @task.update_percent((counter*p).ceil > 100 ? 100 : (counter*p).ceil)
        counter += 1
      end
      # write csv
      @task[:csv] = header
      # write predictions
      # save task 
      # append predictions as last action otherwise they won't save
      # mongoid works with shallow copy via #dup
      @task[:predictions] = {m.id.to_s => predictions}
      @task[:dataset_id] = dataset.id
      @task[:model_id] = m.id
      @task.save
    end#main task
    tid = @task.id.to_s
    return 202, to("/task/#{tid}").to_json
  else
    bad_request_error "No accepted content type"
  end
end
