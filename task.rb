DEFAULT_TASK_MAX_DURATION = 36000
module OpenTox

  # Class for handling asynchronous tasks
  class Task

    attr_accessor :pid, :observer_pid

    def metadata
      super true # always update metadata
    end

    def self.task_uri
      Task.new.uri
    end

    def self.run(description, creator=nil, uri=nil)

      task = Task.new uri
      #task[RDF::OT.created_at] = DateTime.now
      #task[RDF::OT.hasStatus] = "Running"
      #task[RDF::DC.description] = description.to_s
      #task[RDF::DC.creator] = creator.to_s
      #task[RDF::OT.percentageCompleted] = "0"
      #task.put
      pid = fork do
        begin
          #task.completed yield
        rescue => e
          # wrap non-opentox-errors first
          #e = OpenTox::Error.new(500,e.message,nil,e.backtrace) unless e.is_a?(OpenTox::Error)
          #$logger.error "error in task #{task.uri} created by #{creator}" # creator is not logged because error is logged when thrown
          #RestClientWrapper.put(File.join(task.uri,'Error'),{:errorReport => e.to_ntriples},{:content_type => 'text/plain'})
          #task.kill
        end
      end
      Process.detach(pid)
      #task.pid = pid

      # watch if task has been cancelled 
      #observer_pid = fork do
      #  task.wait
      #  begin
      #    Process.kill(9,task.pid) if task.cancelled?
      #  rescue
      #    $logger.warn "Could not kill process of task #{task.uri}, pid: #{task.pid}"
      #  end
      #end
      #Process.detach(observer_pid)
      #task.observer_pid = observer_pid
      #task
      pid

    end

    def kill
      Process.kill(9,@pid)
      Process.kill(9,@observer_pid)
    rescue # no need to raise an exception if processes are not running
    end

    def description
      self.[](RDF::DC.description)
    end

    def creator
      self.[](RDF::DC.creator)
    end
    
    def cancel
      kill
      self.[]=(RDF::OT.hasStatus, "Cancelled")
      self.[]=(RDF::OT.finished_at, DateTime.now)
      put
    end

    def completed(uri)
      self.[]=(RDF::OT.resultURI, uri)
      self.[]=(RDF::OT.hasStatus, "Completed")
      self.[]=(RDF::OT.finished_at, DateTime.now)
      self.[]=(RDF::OT.percentageCompleted, "100")
      put
    end

    # waits for a task, unless time exceeds or state is no longer running
    def wait
      start_time = Time.new
      due_to_time = start_time + DEFAULT_TASK_MAX_DURATION
      dur = 0.2
      while running? 
        sleep dur
        dur = [[(Time.new - start_time)/20.0,0.3].max,300.0].min
        request_timeout_error "max wait time exceeded ("+DEFAULT_TASK_MAX_DURATION.to_s+"sec), task: '"+@uri.to_s+"'" if (Time.new > due_to_time)
      end
    end

  end

  def code
    RestClientWrapper.get(@uri).code.to_i
  end

  # get only header for status requests
  def running?
    code == 202 
  end

  def cancelled?
    code == 503
  end

  def completed?
    code == 200
  end

  def error?
    code >= 400 and code != 503
  end

  [:hasStatus, :resultURI, :created_at, :finished_at, :percentageCompleted].each do |method|
    define_method method do
      response = self.[](RDF::OT[method])
      response = self.[](RDF::OT1[method]) unless response  # API 1.1 compatibility
      response
    end
  end

  # Check status of a task
  # @return [String] Status
  def status
    self[RDF::OT.hasStatus]
  end

  def error_report
    get
    report = {}
    query = RDF::Query.new({
      :report => {
        RDF.type  => RDF::OT.ErrorReport,
        :property => :value,
      }
    })
    query.execute(@rdf).each do |solution|
      report[solution.property] = solution.value.to_s
    end
    report
  end

  #TODO: subtasks (only for progress in validation)
  class SubTask
    
    def initialize(task, min, max)
      #TODO add subtask code
    end

    def self.create(task, min, max)
      if task
        SubTask.new(task, min, max)
      else
        nil
      end
    end
    
    def waiting_for(task_uri)
      #TODO add subtask code
    end
    
    def progress(pct)
      #TODO add subtask code
    end
    
    def running?()
      #TODO add subtask code
    end
  end

end
