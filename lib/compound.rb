# Get a list of a single or all descriptors
# @param [Header] Accept one of text/plain, application/json
# @param [Path] Descriptor name or descriptor ID (e.G.: Openbabel.HBA1, 5755f8eb3cf99a00d8fedf2f)
# @return [text/plain, application/json] list of all prediction models
get "/compound/descriptor/?:descriptor?" do
  case @accept
  when "application/json"
    return "#{JSON.pretty_generate PhysChem::DESCRIPTORS} "  unless params[:descriptor]
    return PhysChem.find_by(:name => params[:descriptor]).to_json if PhysChem::DESCRIPTORS.include?(params[:descriptor])
    return PhysChem.find(params[:descriptor]).to_json if PhysChem.find(params[:descriptor])
  else
    return PhysChem::DESCRIPTORS.collect{|k, v| "#{k}: #{v}\n"} unless params[:descriptor]
    return PhysChem::DESCRIPTORS[params[:descriptor]] if PhysChem::DESCRIPTORS.include?(params[:descriptor])
    return "#{PhysChem.find(params[:descriptor]).name}: #{PhysChem.find(params[:descriptor]).description}" if PhysChem.find(params[:descriptor])
  end
end

post "/compound/descriptor/?" do
  bad_request_error "Missing Parameter " unless params[:identifier] && params[:descriptor]
  descriptors = params['descriptor'].split(',')
  compound = Compound.from_smiles params[:identifier]
  physchem_descriptors = []
  descriptors.each do |descriptor|
    physchem_descriptors << PhysChem.find_by(:name => descriptor)
  end
  result = compound.calculate_properties physchem_descriptors
  csv = (0..result.size-1).collect{|i| "\"#{physchem_descriptors[i].name}\",#{result[i]}"}.join("\n")
  csv = "SMILES,\"#{params[:identifier]}\"\n#{csv}" if params[:identifier]
  case @accept
  when "text/csv","application/csv"
    return csv
  when "application/json"
    result_hash = (0..result.size-1).collect{|i| {"#{physchem_descriptors[i].name}" => "#{result[i]}"}}
    data = {"compound" => {"SMILES" => "#{params[:identifier]}"}}
    data["compound"]["InChI"] = "#{compound.inchi}" if compound.inchi
    data["compound"]["results"] = result_hash
    return JSON.pretty_generate(data)
  end
end

get %r{/compound/(.+)} do |inchi|
  bad_request_error "Input parameter #{inchi} is not an InChI" unless inchi.match(/^InChI=/)
  compound = Compound.from_inchi URI.unescape(inchi)
  response['Content-Type'] = @accept
  case @accept
  when "application/json"
    return JSON.pretty_generate JSON.parse(compound.to_json)
  when "chemical/x-daylight-smiles"
    return compound.smiles
  when "chemical/x-inchi"
    return compound.inchi
  when "chemical/x-mdl-sdfile"
    return compound.sdf
  when "chemical/x-mdl-molfile"
  when "image/png"
    return compound.png
  when "image/svg+xml"
    return compound.svg
  when "text/plain"
    return "#{compound.names}\n"
  else
    return compound.inspect
  end
end