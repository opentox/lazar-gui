helpers do

  def is_authorized(uri, action)
    if OpenTox::Authorization.server && session[:subjectid] != nil
      return OpenTox::Authorization.authorized?(uri, action, session[:subjectid])
    else
      return true
    end
    return false
  end

  def is_aluist
    OpenTox::Authorization.list_user_groups(session[:username], session[:subjectid]).include?("aluist")
  end

  def hide_link(destination)
    @link_id = 0 unless @link_id
    @link_id += 1
    haml :js_link, :locals => {:name => "hide", :destination => destination, :method => "hide"}, :layout => false
  end

  def toggle_link(destination,name)
    @link_id = 0 unless @link_id
    @link_id += 1
    haml :js_link, :locals => {:name => name, :destination => destination, :method => "toggle"}, :layout => false
  end

  def sort(descriptors,value_map)
    features = {:activating => [], :deactivating => [], :pc_features => []}
    if descriptors.kind_of?(Array)
      descriptors.each do |d|
        if !value_map.empty?
          features[:activating] << {:smarts => d[OT.smarts],:p_value => d[OT.pValue]} if d[OT.effect] == 2
          features[:deactivating] << {:smarts => d[OT.smarts],:p_value => d[OT.pValue]} if d[OT.effect] == 1
        else
          if d[OT.effect] =~ TRUE_REGEXP 
            features[:activating] << {:smarts => d[OT.smarts],:p_value => d[OT.pValue]} 
          elsif d[OT.effect] =~ FALSE_REGEXP 
            features[:deactivating] << {:smarts => d[OT.smarts],:p_value => d[OT.pValue]} 
          end
        end
      end
    else
      descriptors.each do |d,v|
        features[:pc_features] << {:feature => d, :value => v}
      end
    end
    features
  end

  def compound_image(compound,descriptors,value_map)
    haml :compound_image, :locals => {:compound => compound, :features => sort(descriptors,value_map)}, :layout => false
  end
  
  def activity_markup(activity,value_map)
    if value_map and !value_map.empty?
      if value_map.size == 2
        activity = value_map.index(activity) if value_map.has_value? activity
        if activity.to_i == 2
          haml ".active #{value_map[activity]}", :layout => false
        elsif activity.to_i == 1
          haml ".inactive #{value_map[activity]}", :layout => false
        else
          haml ".other #{activity.to_s}", :layout => false
        end
      else
        haml ".other #{activity.to_s}", :layout => false
      end
    elsif OpenTox::Algorithm::numeric? activity
      haml ".other #{sprintf('%.03g', activity.to_f)}", :layout => false
    else
      haml ".other #{activity.to_s}", :layout => false
    end
=begin
    case activity.class.to_s
    when /Float/
      haml ".other #{sprintf('%.03g', activity)}", :layout => false
    when /String/
      case activity
      when "true"
        haml ".active active", :layout => false
      when "false"
        haml ".inactive inactive", :layout => false
      else
        haml ".other #{activity.to_s}", :layout => false
      end
    else 
      if activity #true
        haml ".active active", :layout => false
      elsif !activity # false
        haml ".inactive inactive", :layout => false
      else
        haml ".other #{activity.to_s}", :layout => false
      end
    end
=end
  end

  def neighbors_navigation
    @page = 0 unless @page
    haml :neighbors_navigation, :layout => false
  end

  def models_navigation
    @page = 0 unless @page
    haml :models_navigation, :layout => false
  end

  def models_navigation_bottom
    @page = 0 unless @page
    haml :models_navigation_bottom, :layout => false
  end

  def endpoint_option_list(max_time=3600)
    out = ""
    tmpfile = File.join(TMP_DIR, 'endpoint_option_list')
    if File.exists? tmpfile
      if Time.now-File.mtime(tmpfile) <= max_time
        f = File.open(tmpfile, 'r+')
        f.each{|line| out << line}
        return out
      else
        File.unlink(tmpfile)
      end
    end
    result = endpoint_selection()
    if result.lines.count > 3
      f = File.new(tmpfile,'w')
      f.print result
      f.close
    end
    result
  end

  def endpoint_level(endpoint="Endpoints", level=1)
    results = OpenTox::Ontology::Echa.echa_endpoints(endpoint) rescue results = []
    out = ""
    out += "<ul id='list_#{endpoint}' class='endpoint level_#{level}'>\n" if results.size > 0
    results.each do |result|
      r = result.split(',')
      endpointname = CGI.escape(r.first.split("#").last).gsub(".","")
      title = r[1..r.size-1].to_s
      out += "  <li class='level_#{level}'><input type='radio' name='endpoint' value='#{result}' id='#{endpointname}' class='endpoint_list' /><label for='#{endpointname}' id='label_#{endpointname}'>#{title.gsub("\"","")}</label>\n"
      out += endpoint_level(endpointname, level + 1)
      out += "</li>\n"
    end
    out += "</ul>\n" if results.size > 0
    return out
  end

  def endpoint_selection()
    out = "<span id='endpoint_label'></span><input type='button' id='endpoint_list_button' value='Select endpoint' /> \n
    <div id='div_endpoint'>\n"
    out += "<b>Please select:</b>\n"
    out += endpoint_level
    js = ""
    out += "</div>\n"
    return out
  end

  def logmmol_to_mg(value ,mw)
    mg = round_to((10**(-1.0*round_to(value.to_f, 2))*(mw.to_f*1000)),4)
    return mg
  end

  def logmg_to_mg(value)
    mg = round_to(10**round_to(value.to_f, 2),4)
    return mg
  end

  def ptd50_to_td50(value ,mw)
    td50 = round_to((10**(-1.0*round_to(value.to_f, 2))*(mw.to_f*1000)),4)
    return td50   
  end

  def round_to(value, deci)
    rounded = (value.to_f*(10**deci)).round / (10**deci).to_f
    return rounded
  end

  def calc_mw(compound_uri)
    ds = OpenTox::Dataset.new()
    ds.save(@subjectid)
    ds.add_compound(compound_uri)
    ds.save(@subjectid)
    mw_algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"pc/MW")
    mw_uri = OpenTox::RestClientWrapper.post(mw_algorithm_uri, {:dataset_uri=>ds.uri})
    ds.delete(@subjectid)
    mw_ds = OpenTox::Dataset.find(mw_uri, @subjectid)
    mw = mw_ds.data_entries[compound_uri][mw_uri.to_s + "/feature/MW"].first.to_f
    mw_ds.delete(@subjectid)
    return mw 
  end

  def transform(value, compound_uri, name, haml)
    prediction_trans = nil
    model_name = name.to_s.downcase
    if model_name.include? "ptd50"
      mw = calc_mw(compound_uri)
      td50 = ptd50_to_td50(value, mw)
      prediction_trans = "TD50: #{td50}"
    elsif model_name.include? "loael"
      if model_name.include? "mol"
        mw = calc_mw(compound_uri)
        mg = logmmol_to_mg(value, mw)
        prediction_trans = "mg/kg bw/day: #{mg}"
      elsif model_name.include? "mg"
        mg = logmg_to_mg(value)
        prediction_trans = "mg/kg bw/day: #{mg}"
      end
    end
    if haml == true
      haml ".other #{prediction_trans.to_s}", :layout => false
    else
      return prediction_trans
    end
  end
end
