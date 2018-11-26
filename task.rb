DEFAULT_TASK_MAX_DURATION = 36000

module OpenTox

  class Task

    include OpenTox
    include Mongoid::Document
    include Mongoid::Timestamps
    store_in collection: "tasks"
    field :pid, type: Integer
    field :percent, type: Float, default: 0
    field :predictions, type: Hash, default:{}
    field :csv, type: String
    field :dataset_id, type: BSON::ObjectId
    field :model_id, type: BSON::ObjectId

    attr_accessor :pid, :percent, :predictions, :csv, :dataset_id, :model_id

    def pid
      self[:pid]
    end
    
    def percent
      self[:percent]
    end
    
    def predictions
      self[:predictions]
    end

    def csv
      self[:csv]
    end
    
    def dataset_id
      self[:dataset_id]
    end
    
    def model_id
      self[:model_id]
    end
    
    def update_percent(percent)
      self[:percent] = percent
      save
    end

    def self.run
      task = Task.new #uri
      pid = fork do
        yield
      end
      Process.detach(pid)
      task[:pid] = pid
      task.save
      task
    end

  end

end

