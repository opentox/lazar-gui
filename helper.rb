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

  def to_csv(m,predictions,compounds)
    model = (m != "Cramer" ? Model::Validation.find(m.to_s) : "Cramer")
    csv = ""
    if model == "Cramer"
      compounds = compounds.collect{|c| c.smiles}
      
      prediction = [Toxtree.predict(compounds, "Cramer rules"), Toxtree.predict(compounds, "Cramer rules with extensions")]
      output = {}
      output["model_name"] = "Oral toxicity (Cramer rules)"
      output["model_type"] = false
      output["model_unit"] = false
      ["measurements", "converted_measurements", "prediction_value", "converted_value", "interval", "converted_interval", "probability", "db_hit", "warnings", "info", "toxtree", "sa_prediction", "sa_matches", "confidence"].each do |key|
        output["#{key}"] = false
      end
      output["toxtree"] = true
      output["cramer_rules"] = prediction.collect{|array| array.collect{|hash| hash["Cramer rules"]}}.flatten.compact
      output["cramer_rules_extensions"] = prediction.collect{|array| array.collect{|hash| hash["Cramer rules, with extensions"]}}.flatten.compact

      # header
      csv = "ID,Endpoint,Unique SMILES,Cramer rules,Cramer rules with extensions\n"
      
      compounds.each_with_index do |smiles, idx|
        csv << "#{idx+1},#{output["model_name"]},#{smiles},"\
          "#{output["cramer_rules"][idx] != "nil" ? output["cramer_rules"][idx] : "none" },"\
          "#{output["cramer_rules_extensions"][idx] != "nil" ? output["cramer_rules_extensions"][idx] : "none"}\n"
      end

    else
      output = {}
      predictions.each_with_index do |prediction,idx|
        compound = compounds[idx]
        line = ""
        output["model_name"] = "#{model.endpoint.gsub('_', ' ')} (#{model.species})"
        output["model_type"] = model.model.class.to_s.match("Classification") ? type = "Classification" : type = "Regression"
        output["model_unit"] = (type == "Regression") ? "(#{model.unit})" : ""
        output["converted_model_unit"] = (type == "Regression") ? "#{model.unit =~ /\b(mmol\/L)\b/ ? "(mg/L)" : "(mg/kg_bw/day)"}" : ""
        ["measurements", "converted_measurements", "prediction_value", "converted_value", "interval", "converted_interval", "probability", "db_hit", "warnings", "info", "toxtree", "sa_prediction", "sa_matches", "confidence"].each do |key|
          output["#{key}"] = false
        end

        if prediction[:value]
          inApp = (prediction[:warnings].join(" ") =~ /Cannot/ ? "no" : (prediction[:warnings].join(" ") =~ /may|Insufficient/ ? "maybe" : "yes"))
          if prediction[:info] =~ /\b(identical)\b/i
            prediction[:info] = "This compound was part of the training dataset. All information "\
              "from this compound was removed from the training data before the "\
              "prediction, to obtain unbiased results."
          end
          note = "\"#{prediction[:warnings].uniq.join(" ")}\""

          output["prediction_value"] = (type == "Regression") ? "#{prediction[:value].delog10.signif(3)}" : "#{prediction[:value]}"
          output["converted_value"] = "#{compound.mmol_to_mg(prediction[:value].delog10).signif(3)}" if type == "Regression"

          output["db_hit"] = prediction[:info] if prediction[:info]
          
          if prediction[:measurements].is_a?(Array)
            output["measurements"] = (type == "Regression") ? prediction[:measurements].collect{|value| "#{value.delog10.signif(3)} (#{model.unit})"} : prediction[:measurements].collect{|value| "#{value}"}
            output["converted_measurements"] = (type == "Regression") ? prediction[:measurements].collect{|value| "#{compound.mmol_to_mg(value.delog10).signif(3)} #{model.unit =~ /mmol\/L/ ? "(mg/L)" : "(mg/kg_bw/day)"}"} : false
          else
            output["measurements"] = (type == "Regression") ? "#{prediction[:measurements].delog10.signif(3)} (#{model.unit})}" : "#{prediction[:measurements]}"
            output["converted_measurements"] = (type == "Regression") ? "#{compound.mmol_to_mg(prediction[:measurements].delog10).signif(3)} #{(model.unit =~ /\b(mmol\/L)\b/) ? "(mg/L)" : "(mg/kg_bw/day)"}" : false

          end #db_hit

          if type == "Regression"

            if !prediction[:prediction_interval].nil?
              interval = prediction[:prediction_interval]
              output['interval'] = "#{interval[1].delog10.signif(3)} - #{interval[0].delog10.signif(3)}"
              output['converted_interval'] = "#{compound.mmol_to_mg(interval[1].delog10).signif(3)} - #{compound.mmol_to_mg(interval[0].delog10).signif(3)}"
            end #prediction interval

            line += "#{idx+1},#{output['model_name']},#{compound.smiles},"\
              "\"#{prediction[:info] ? prediction[:info] : "no"}\",\"#{prediction[:measurements].join("; ") if prediction[:info]}\","\
              "#{output['prediction_value'] != false ? output['prediction_value'] : ""},"\
              "#{output['converted_value'] != false ? output['converted_value'] : ""},"\
              "#{output['interval'].split(" - ").first.strip unless output['interval'] == false},"\
              "#{output['interval'].split(" - ").last.strip unless output['interval'] == false},"\
              "#{output['converted_interval'].split(" - ").first.strip unless output['converted_interval'] == false},"\
              "#{output['converted_interval'].split(" - ").last.strip unless output['converted_interval'] == false},"\
              "#{inApp},#{note.nil? ? "" : note.chomp}\n"
          else # Classification

            # consensus mutagenicity
              
            sa_prediction = KaziusAlerts.predict(compound.smiles)
            lazar_mutagenicity = prediction
            confidence = 0
            lazar_mutagenicity_val = (lazar_mutagenicity[:value] == "non-mutagenic" ? false : true)
            if sa_prediction[:prediction] == false && lazar_mutagenicity_val == false
              confidence = 0.85
            elsif sa_prediction[:prediction] == true && lazar_mutagenicity_val == true
              confidence = 0.85 * ( 1 - sa_prediction[:error_product] )
            elsif sa_prediction[:prediction] == false && lazar_mutagenicity_val == true
              confidence = 0.11
            elsif sa_prediction[:prediction] == true && lazar_mutagenicity_val == false
              confidence = ( 1 - sa_prediction[:error_product] ) - 0.57
            end
            output['sa_prediction'] = sa_prediction
            output['sa_matches'] = sa_prediction[:matches].collect{|a| a.first}.join("; ") unless sa_prediction[:matches].blank?
            output['confidence'] = confidence.signif(3)
            output['model_name'] = "Lazar #{model.endpoint.gsub('_', ' ').downcase} (#{model.species}):"
            output['probability'] = prediction[:probabilities] ? prediction[:probabilities].collect{|k,v| "#{k}: #{v.signif(3)}"} : false

            line += "#{idx+1},Consensus mutagenicity,#{compound.smiles},"\
              "\"#{prediction[:info] ? prediction[:info] : "no"}\",\"#{prediction[:measurements].join("; ") if prediction[:info]}\","\
              "#{sa_prediction[:prediction] == false ? "non-mutagenic" : "mutagenic"},"\
              "#{output['confidence']},#{output['sa_matches'] != false ? "\"#{output['sa_matches']}\"" : "none"},"\
              "#{output['prediction_value']},"\
              "#{output['probability'][0] != false ? output['probability'][0].split(":").last : ""},"\
              "#{output['probability'][1] != false ? output['probability'][1].split(":").last : ""},"\
              "#{inApp},#{note.nil? ? "" : note}\n"

          end
          
          output["warnings"] = prediction[:warnings] if prediction[:warnings]

        else #no prediction value
          inApp = "no"
          if prediction[:info] =~ /\b(identical)\b/i
            prediction[:info] = "This compound was part of the training dataset. All information "\
              "from this compound was removed from the training data before the "\
              "prediction, to obtain unbiased results."
          end
          note = "\"#{prediction[:warnings].join(" ")}\""

          output["warnings"] = prediction[:warnings]
          output["info"] = prediction[:info] if prediction[:info]

          if type == "Regression"
            line += "#{idx+1},#{output['model_name']},#{compound.smiles},#{prediction[:info] ? prediction[:info] : "no"},"\
              "#{prediction[:measurements] if prediction[:info]},,,,,,,"+ [inApp,note].join(",")+"\n"
          else
            line += "#{idx+1},Consensus mutagenicity,#{compound.smiles},#{prediction[:info] ? prediction[:info] : "no"},"\
              "#{prediction[:measurements] if prediction[:info]},,,,,,,"+ [inApp,note].join(",")+"\n"
          end

        end
        csv += line
      end
      $logger.debug csv
      csv
    end
  end

end
