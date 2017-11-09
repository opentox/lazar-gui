module OpenTox

  class Prediction

    include OpenTox
    include Mongoid::Document
    include Mongoid::Timestamps
    store_in collection: "predictions"
    field :compound, type: BSON::ObjectId
    field :model, type: BSON::ObjectId
    field :prediction, type: Hash, default:{}
    field :csv, type: String

    attr_accessor :compound, :model, :prediction, :csv

    def compound
      self[:compound]
    end
    
    def model
      self[:model]
    end
    
    def prediction
      self[:prediction]
    end

    def csv
      self[:csv]
    end

  end

end

