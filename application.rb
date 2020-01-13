require 'rdiscount'
require_relative 'qmrf_report.rb'
require_relative 'task.rb'
require_relative 'helper.rb'
require_relative 'rest-client-wrapper-helper.rb'
include OpenTox
PUBCHEM_CID_URI = PUBCHEM_URI.split("/")[0..-3].join("/")+"/compound/"

[
  "aa.rb",
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

configure :production do
  STDOUT.sync = true  
  $logger = Logger.new(STDOUT)
end

configure :development do
  STDOUT.sync = true  
  $logger = Logger.new(STDOUT)
  $logger.level = Logger::DEBUG
end

before do
  # use this hostname method instead to('/')
  # allowes to set https for xhr requests
  #$host_with_port = request.host =~ /localhost/ ? request.host_with_port : request.host
  $host_with_port = request.host_with_port
  $paths = [
  "/",
  "api",
  "authenticate",
  "compound",
  "dataset",
  "endpoint",
  "feature",
  "model",
  "report",
  "substance",
  "swagger",
  "validation"]
  if request.path == "/" || $paths.include?(request.path.split("/")[1])
    @accept = request.env['HTTP_ACCEPT'].split(",").first
    response['Content-Type'] = @accept
    auths = ["compound","dataset","endpoint","feature","model","report","substance","validation"]
    if auths.include?(request.path.split("/")[1])
      valid = Authorization.is_token_valid(request.env['HTTP_SUBJECTID'])
      halt 401, "Unauthorized." unless valid
    end
  else
    @version = File.read("VERSION").chomp
  end
end

not_found do
  redirect to('/predict')
end

error do
  # API errors
  if request.path.split("/")[1] == "api" || $paths.include?(request.path.split("/")[2])
    @accept = request.env['HTTP_ACCEPT']
    response['Content-Type'] = @accept
    @accept == "text/plain" ? request.env['sinatra.error'] : request.env['sinatra.error'].to_json
  # batch dataset error
  elsif request.env['sinatra.error.params']['batchfile'] && request.env['REQUEST_METHOD'] == "POST"
    @error = request.env['sinatra.error']
    response['Content-Type'] = "text/html"
    status 200
    return haml :error
  # basic error
  else
    @error = request.env['sinatra.error']
    return haml :error
  end
end

# https://github.com/britg/sinatra-cross_origin#responding-to-options
options "*" do
  response.headers["Allow"] = "HEAD,GET,PUT,POST,DELETE,OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept"
  200
end

get '/predict/?' do
  # handle user click on back button while batch prediction
  if params[:tpid]
    begin
      Process.kill(9,params[:tpid].to_i) if !params[:tpid].blank?
    rescue
      nil
    end
    # remove data helper method
    remove_task_data(params[:tpid])
  end
  # regular request on '/predict' page
  @models = OpenTox::Model::Validation.all
  @endpoints = @models.collect{|m| m.endpoint}.sort.uniq
  @models.count > 0 ? (haml :predict) : (haml :info)
end

get '/predict/modeldetails/:model' do
  model = OpenTox::Model::Validation.find params[:model]
  training_dataset = model.model.training_dataset
  data_entries = training_dataset.data_entries
  crossvalidations = model.crossvalidations
  if model.classification?
    crossvalidations.each do |cv|
      File.open(File.join('public', "#{cv.id}.png"), 'w') do |file|
        file.write(cv.probability_plot(format: "png"))
      end unless File.exists? File.join('public', "#{cv.id}.png")
    end
  else
    crossvalidations.each do |cv|
      File.open(File.join('public', "#{cv.id}.png"), 'w') do |file|
        file.write(cv.correlation_plot(format: "png"))
      end unless File.exists? File.join('public', "#{cv.id}.png")
    end
  end

  response['Content-Type'] = "text/html"
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
  dataset = Dataset.find_by(:name=>params[:name])
  csv = File.read dataset.source
  name = params[:name] + ".csv"
  t = Tempfile.new
  t << csv
  t.rewind
  response['Content-Type'] = "text/csv"
  send_file t.path, :filename => name, :type => "text/csv", :disposition => "attachment"
end

# download batch predicton file
get '/predict/batch/download/?' do
  task = Task.find params[:tid]
  dataset = Dataset.find task.dataset_id
  name = dataset.name + ".csv"
  t = Tempfile.new
  # to_prediction_csv takes too much time; use task.csv instead which is the same
  #t << dataset.to_prediction_csv
  t << task.csv
  t.rewind
  response['Content-Type'] = "text/csv"
  send_file t.path, :filename => "#{Time.now.strftime("%Y-%m-%d")}_lazar_batch_prediction_#{name}", :type => "text/csv", :disposition => "attachment"
end

post '/predict/?' do
  # process batch prediction
  unless params[:fileselect].blank?
    if params[:fileselect][:filename] !~ /\.csv$/
      raise "Wrong file extension for '#{params[:fileselect][:filename]}'. Please upload a CSV file."
    end
    @filename = params[:fileselect][:filename]
    File.open('tmp/' + @filename, "w") do |f|
      f.write(params[:fileselect][:tempfile].read)
    end
    # check CSV structure by parsing and header check
    csv = CSV.read File.join("tmp", @filename)
    header = csv.shift
    accepted = ["SMILES","InChI"]
    raise "CSV header does not include 'SMILES' or 'InChI'. Please read the <a href='https://dg.in-silico.ch/predict/help' rel='external'> HELP </a> page." unless header.any?(/smiles|inchi/i)
    @models = params[:selection].keys.join(",")
    return haml :upload
  end

  unless params[:batchfile].blank?
    dataset = Dataset.from_csv_file File.join("tmp", params[:batchfile])
    raise "No compounds in Dataset. Please read the <a href='https://dg.in-silico.ch/predict/help' rel='external'> HELP </a> page." if dataset.compounds.size == 0
    response['Content-Type'] = "application/json"
    return {:dataset_id => dataset.id.to_s, :models => params[:models]}.to_json
  end

  unless params[:models].blank?
    dataset = Dataset.find params[:dataset_id]
    @compounds_size = dataset.compounds.size
    @models = params[:models].split(",")
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
        prediction_dataset = model.predict dataset
        t.update_percent(70)
        t[:dataset_id] = prediction_dataset.id
        t.update_percent(75)
        prediction[model_id] = prediction_dataset.id.to_s
        t.update_percent(80)
        t[:predictions] = prediction
        t.update_percent(90)
        t[:csv] = prediction_dataset.to_prediction_csv
        t.update_percent(100)
        t.save
      end
    end
    maintask[:subTasks] = @tasks.collect{|t| t.id}
    maintask.save
    @pid = maintask.pid
    response['Content-Type'] = "text/html"
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
  # returns task progress in percent
  if params[:turi]
    task = Task.find(params[:turi].to_s)
    response['Content-Type'] = "application/json"
    return JSON.pretty_generate(:percent => task.percent)
  # kills task process id
  elsif params[:ktpid]
    begin
      Process.kill(9,params[:ktpid].to_i) if !params[:ktpid].blank?
    rescue
      nil
    end
    #remove_task_data(params[:ktpid]) deletes also the source file
    response['Content-Type'] = "application/json"
    return JSON.pretty_generate(:ktpid => params[:ktpid])
  # returns task details
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
      string += "<th class=\"fit\">#{h}</th>"
    end
    string += "</tr>"
    string += "<tr>"
    csv[pageNumber].each_with_index do |line,idx|
      if idx == cansmi
        c = Compound.from_smiles line
        string += "<td class=\"fit\">#{line}</br>" \
                  "<a class=\"btn btn-link\" data-id=\"link\" " \
                  "data-remote=\"#{to("/prediction/#{c.id}/details")}\" data-toggle=\"modal\" " \
                  "href=#details>" \
                  "#{embedded_svg(c.svg, title: "click for details")}" \
                  "</td>"
      else
        string += "<td nowrap>#{line.numeric? && line.include?(".") ? line.to_f.signif(3) : (line.nil? ? line : line.gsub(" ","<br />"))}</td>"
      end
    end
    string += "</tr>"
    string += "</table></td>"
    response['Content-Type'] = "application/json"
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

get '/predict/license' do
  @license = RDiscount.new(File.read("LICENSE.md")).to_html
  haml :license, :layout => false
end

get '/predict/faq' do
  @faq = RDiscount.new(File.read("FAQ.md")).to_html
  haml :faq#, :layout => false
end

get '/predict/help' do
  haml :help
end

get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

# for swagger representation
get '/api/swagger-ui.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  scss :style
end

get '/IST_logo_s.png' do
  redirect to('/images/IST_logo_s.png')
end
