require 'rdiscount'
require_relative 'qmrf_report.rb'
require_relative 'task.rb'
require_relative 'helper.rb'
include OpenTox

[
  "api.rb",
  "compound.rb",
  "dataset.rb",
  "endpoint.rb",
  "feature.rb",
  "model.rb",
  "report.rb",
  "substance.rb",
  "swagger.rb",
  "validation.rb"
].each{ |f| require_relative "./lib/#{f}" }

configure :production, :development do
  STDOUT.sync = true  
  $logger = Logger.new(STDOUT)
  $logger.level = Logger::DEBUG
  enable :reloader
  also_reload './helper.rb'
  also_reload './qmrf_report.rb'
  [
    "api.rb",
    "compound.rb",
    "dataset.rb",
    "endpoint.rb",
    "feature.rb",
    "model.rb",
    "report.rb",
    "substance.rb",
    "swagger.rb",
    "validation.rb"
  ].each{ |f| also_reload "./lib/#{f}" }
end

before do
  $paths = [
  "api",
  "compound",
  "dataset",
  "endpoint",
  "feature",
  "model",
  "report",
  "substance",
  "swagger",
  "validation"]
  if request.path.split("/")[1] == "api" || $paths.include?(request.path.split("/")[2])
    @accept = request.env['HTTP_ACCEPT'].split(",").first
    response['Content-Type'] = @accept
  else
    @version = File.read("VERSION").chomp
  end
end

not_found do
  redirect to('/predict')
end

error do
  if request.path.split("/")[1] == "api" || $paths.include?(request.path.split("/")[2])
    @accept = request.env['HTTP_ACCEPT']
    response['Content-Type'] = @accept
    @accept == "text/plain" ? request.env['sinatra.error'] : request.env['sinatra.error'].to_json
  else
    @error = request.env['sinatra.error']
    haml :error
  end
end

# https://github.com/britg/sinatra-cross_origin#responding-to-options
options "*" do
  response.headers["Allow"] = "HEAD,GET,PUT,POST,DELETE,OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept"
  200
end

get '/predict/?' do
  @models = OpenTox::Model::Validation.all
  @endpoints = @models.collect{|m| m.endpoint}.sort.uniq
  @models.count > 0 ? (haml :predict) : (haml :info)
end

get '/predict/modeldetails/:model' do
  model = OpenTox::Model::Validation.find params[:model]
  training_dataset = model.model.training_dataset
  data_entries = training_dataset.data_entries
  crossvalidations = OpenTox::Validation::RepeatedCrossValidation.find(model.repeated_crossvalidation_id).crossvalidations

  return haml :model_details, :layout=> false, :locals => {:model => model, 
                                                           :crossvalidations => crossvalidations, 
                                                           :training_dataset => training_dataset,
                                                           :data_entries => data_entries
  }
end

get "/predict/report/:id/?" do
  prediction_model = Model::Validation.find params[:id]
  bad_request_error "model with id: '#{params[:id]}' not found." unless prediction_model
  report = qmrf_report params[:id]
  # output
  t = Tempfile.new
  t << report.to_xml
  name = prediction_model.species.sub(/\s/,"-")+"-"+prediction_model.endpoint.downcase.sub(/\s/,"-")
  send_file t.path, :filename => "QMRF_report_#{name.gsub!(/[^0-9A-Za-z]/, '_')}.xml", :type => "application/xml", :disposition => "attachment"
end

get '/predict/jme_help/?' do
  File.read(File.join('views','jme_help.html'))
end

# download training dataset
get '/predict/dataset/:name' do
  response['Content-Type'] = "text/csv"
  dataset = Dataset.find_by(:name=>params[:name])
  csv = dataset.to_csv
  t = Tempfile.new
  t << csv
  name = params[:name] + ".csv"
  send_file t.path, :filename => name, :type => "text/csv", :disposition => "attachment"
end

# download batch predicton file
get '/predict/batch/download/?' do
  task = Task.find params[:tid]
  prediction_dataset = Dataset.find task.dataset_id
  filename = prediction_dataset.name
  tempfile = Tempfile.new
  tempfile << prediction_dataset.to_csv
  tempfile.rewind
  response['Content-Type'] = "text/csv"
  send_file tempfile, :filename => "#{Time.now.strftime("%Y-%m-%d")}_lazar_batch_prediction_#{filename}.csv", :type => "text/csv", :disposition => "attachment"
end

post '/predict/?' do
  # process batch prediction
  if !params[:fileselect].blank?
    if params[:fileselect][:filename] !~ /\.csv$/
      bad_request_error "Wrong file extension for '#{params[:fileselect][:filename]}'. Please upload a CSV file."
    end
    @filename = params[:fileselect][:filename]
    File.open('tmp/' + params[:fileselect][:filename], "w") do |f|
      f.write(params[:fileselect][:tempfile].read)
    end
    input = Dataset.from_csv_file File.join("tmp", params[:fileselect][:filename])
    $logger.debug "Processing '#{params[:fileselect][:filename]}'"
    @compounds_size = input.compounds.size
    @models = params[:selection].keys
    @tasks = []
    @models.each{|m| t = Task.new; t.save; @tasks << t}
    @predictions = {}

    maintask = Task.run do
      @models.each_with_index do |model_id,idx|
        t = @tasks[idx]
        t.update_percent(1)
        prediction = {}
        model = Model::Validation.find model_id
        t.update_percent(10)
        prediction_dataset = model.predict input
        t[:dataset_id] = prediction_dataset.id
        t.update_percent(90)
        prediction[model_id] = prediction_dataset.id.to_s
        t[:predictions] = prediction
        t[:csv] = prediction_dataset.to_csv
        t.update_percent(100)
        t.save
      end
    end
    @pid = maintask.pid
    return haml :batch
  else
    # single compound prediction
    # validate identifier input
    if !params[:identifier].blank?
      @identifier = params[:identifier].strip
      $logger.debug "input:#{@identifier}"
      # get compound from SMILES
      begin
        @compound = Compound.from_smiles @identifier
      rescue
        @error = "'#{@identifier}' is not a valid SMILES string." unless @compound
        return haml :error
      end
      @models = []
      @predictions = []
      params[:selection].keys.each do |model_id|
        model = Model::Validation.find model_id
        @models << model
        prediction = model.predict(@compound)
        @predictions << prediction
      end
      haml :prediction
    end
  end
end

get '/prediction/task/?' do
  if params[:turi]
    task = Task.find(params[:turi].to_s)
    return JSON.pretty_generate(:percent => task.percent)
  elsif params[:predictions]
    task = Task.find(params[:predictions])
    pageSize = params[:pageSize].to_i - 1
    pageNumber= params[:pageNumber].to_i - 1
    csv = CSV.parse(task.csv)
    header = csv.shift
    string = "<td><table class=\"table table-bordered\">"
    # find canonical smiles column
    cansmi = 0
    header.each_with_index do |h,idx|
      cansmi = idx if h =~ /Canonical SMILES/
      string += "<th>#{h}</th>"
    end
    string += "</tr>"
    string += "<tr>"
    csv[pageNumber].each_with_index do |line,idx|
      if idx == cansmi
        c = Compound.from_smiles line
        string += "<td>#{line}</br>" \
                  "<a class=\"btn btn-link\" data-id=\"link\" " \
                  "data-remote=\"#{to("/prediction/#{c.id}/details")}\" data-toggle=\"modal\" " \
                  "href=#details>" \
                  "#{embedded_svg(c.svg, title: "click for details")}" \
                  "</td>"
      else
        string += "<td>#{line.numeric? && line.include?(".") ? line.to_f.signif(3) : line}</td>"
      end
    end
    string += "</tr>"
    string += "</table></td>"
    return JSON.pretty_generate(:prediction => [string])
  end
end

# get individual compound details
get '/prediction/:neighbor/details/?' do
  @compound = OpenTox::Compound.find params[:neighbor]
  @smiles = @compound.smiles
  begin
    @names = @compound.names.nil? ? "No names for this compound available." : @compound.names
  rescue
    @names = "No names for this compound available."
  end
  @inchi = @compound.inchi

  haml :details, :layout => false
end

get '/license' do
  @license = RDiscount.new(File.read("LICENSE.md")).to_html
  haml :license, :layout => false
end

get '/predict/faq' do
  @faq = RDiscount.new(File.read("FAQ.md")).to_html
  haml :faq#, :layout => false
end

get '/help' do
  haml :help
end

get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

# for swagger representation
get '/swagger-ui.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

get '/IST_logo_s.png' do
  redirect to('/images/IST_logo_s.png')
end
