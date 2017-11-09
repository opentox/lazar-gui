helpers do

  def embedded_svg image, options={}
    doc = Nokogiri::HTML::DocumentFragment.parse image
    svg = doc.at_css 'svg'
    title = doc.at_css 'title'
    if options[:class].present?
      svg['class'] = options[:class]
    end
    if options[:title].present?
      title.children.remove
      text_node = Nokogiri::XML::Text.new(options[:title], doc)
      title.add_child(text_node)
    end
    doc.to_html.html_safe
  end

  def prediction_to_csv(m,c,p)
    #model = Model::Validation.find(m.to_s)
    model = m
    model_name = "#{model.endpoint.gsub('_', ' ')} (#{model.species})"
    model_unit = model.regression? ? "(#{model.unit})" : ""
    converted_model_unit = model.regression? ? "#{model.unit =~ /\b(mmol\/L)\b/ ? "(mg/L)" : "(mg/kg_bw/day)"}" : ""

    #predictions = predictions_ids.collect{|prediction_id| Prediction.find prediction_id}
    csv = ""
    compound = c#Compound.find prediction_object.compound
    prediction = p#prediction_object.prediction
    #prediction.delete_if{|k,v| k =~ /neighbors|prediction_feature_id/}
    output = {}
    line = ""
    output["model_name"] = model_name
    output["model_unit"] = model_unit
    output["converted_model_unit"] = converted_model_unit

    if prediction[:value]
      inApp = (prediction[:warnings].join(" ") =~ /Cannot/ ? "no" : (prediction[:warnings].join(" ") =~ /may|Insufficient/ ? "maybe" : "yes"))
      if prediction[:info] =~ /\b(identical)\b/i
        prediction[:info] = "This compound was part of the training dataset. All information "\
          "from this compound was removed from the training data before the "\
          "prediction to obtain unbiased results."
      end
      note = "\"#{prediction[:warnings].uniq.join(" ")}\""

      output["prediction_value"] = model.regression? ? "#{prediction[:value].delog10.signif(3)}" : "#{prediction[:value]}"
      output["converted_value"] = model.regression? ? "#{compound.mmol_to_mg(prediction[:value].delog10).signif(3)}" : nil

      if prediction[:measurements].is_a?(Array)
        output["measurements"] = model.regression? ? prediction[:measurements].collect{|value| "#{value.delog10.signif(3)}"} : prediction[:measurements].collect{|value| "#{value}"}
        output["converted_measurements"] = model.regression? ? prediction[:measurements].collect{|value| "#{compound.mmol_to_mg(value.delog10).signif(3)}"} : false
      else
        output["measurements"] = model.regression? ? "#{prediction[:measurements].delog10.signif(3)}" : "#{prediction[:measurements]}"
        output["converted_measurements"] = model.regression? ? "#{compound.mmol_to_mg(prediction[:measurements].delog10).signif(3)}" : false

      end #db_hit

      if model.regression?

        if !prediction[:prediction_interval].blank?
          interval = prediction[:prediction_interval]
          output['interval'] = []
          output['converted_interval'] = []
          output['interval'] << interval[1].delog10.signif(3)
          output['interval'] << interval[0].delog10.signif(3)
          output['converted_interval'] << compound.mmol_to_mg(interval[1].delog10).signif(3)
          output['converted_interval'] << compound.mmol_to_mg(interval[0].delog10).signif(3)
        end #prediction interval

        line += "#{output['model_name']},#{compound.smiles},"\
          "\"#{prediction[:info] ? prediction[:info] : "no"}\",\"#{output['measurements'].join("; ") if prediction[:info]}\","\
          "#{!output['prediction_value'].blank? ? output['prediction_value'] : ""},"\
          "#{!output['converted_value'].blank? ? output['converted_value'] : ""},"\
          "#{!prediction[:prediction_interval].blank? ? output['interval'].first : ""},"\
          "#{!prediction[:prediction_interval].blank? ? output['interval'].last : ""},"\
          "#{!prediction[:prediction_interval].blank? ? output['converted_interval'].first : ""},"\
          "#{!prediction[:prediction_interval].blank? ? output['converted_interval'].last : ""},"\
          "#{inApp},#{note.nil? ? "" : note.chomp}\n"
      else # Classification

        if !prediction[:probabilities].blank?
          output['probabilities'] = []
          prediction[:probabilities].each{|k,v| output['probabilities'] << v.signif(3)}
        end

        line += "Consensus mutagenicity,#{compound.smiles},"\
          "\"#{prediction[:info] ? prediction[:info] : "no"}\",\"#{output['measurements'].join("; ") if prediction[:info]}\","\
          "#{prediction['Consensus prediction']},"\
          "#{prediction['Consensus confidence']},"\
          "#{prediction['Structural alerts for mutagenicity']},"\
          "#{output['prediction_value']},"\
          "#{!prediction[:probabilities].blank? ? output['probabilities'].first : ""},"\
          "#{!prediction[:probabilities].blank? ? output['probabilities'].last : ""},"\
          "#{inApp},#{note.nil? ? "" : note}\n"

      end
      
      output['warnings'] = prediction[:warnings] if prediction[:warnings]

    else #no prediction value
      inApp = "no"
      if prediction[:info] =~ /\b(identical)\b/i
        prediction[:info] = "This compound was part of the training dataset. All information "\
          "from this compound was removed from the training data before the "\
          "prediction to obtain unbiased results."
      end
      note = "\"#{prediction[:warnings].join(" ")}\""

      output['warnings'] = prediction[:warnings]
      output['info'] = prediction[:info] if prediction[:info]

      if model.regression?
        line += "#{output['model_name']},#{compound.smiles},#{prediction[:info] ? prediction[:info] : "no"},"\
          "#{prediction[:measurements].collect{|m| m.delog10.signif(3)}.join("; ") if prediction[:info]},,,,,,,"+ [inApp,note].join(",")+"\n"
      else
        line += "Consensus mutagenicity,#{compound.smiles},#{prediction[:info] ? prediction[:info] : "no"},"\
          "#{prediction[:measurements].join("; ") if prediction[:info]},,,,,,,"+ [inApp,note].join(",")+"\n"
      end

    end
    csv += line
    # output
    csv
  end

end
