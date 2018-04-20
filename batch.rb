require 'csv'
require 'tempfile'

module OpenTox

  class Batch

    include OpenTox
    include Mongoid::Document
    include Mongoid::Timestamps
    store_in collection: "batch"
    field :name,  type: String
    field :source,  type: String
    field :identifiers, type: Array
    field :compounds, type: Array
    field :warnings, type: Array, default: []

    def self.from_csv_file file
      source = file
      name = File.basename(file,".*")
      batch = self.find_by(:source => source, :name => name)
      if batch
        $logger.debug "Skipping import of #{file}, it is already in the database (id: #{batch.id})."
      else
        $logger.debug "Parsing #{file}."
        table = CSV.read file, :skip_blanks => true, :encoding => 'windows-1251:utf-8'
        batch = self.new(:source => source, :name => name, :identifiers => [], :compounds => [])
        
        # features
        feature_names = table.shift.collect{|f| f.strip}
        warnings << "Duplicated features in table header." unless feature_names.size == feature_names.uniq.size
        compound_format = feature_names.shift.strip
        bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: SMILES, InChI." unless compound_format =~ /SMILES|InChI/i
        numeric = []
        features = []
        # guess feature types
        feature_names.each_with_index do |f,i|
          metadata = {:name => f}
          values = table.collect{|row| val=row[i+1].to_s.strip; val.blank? ? nil : val }.uniq.compact
          types = values.collect{|v| v.numeric? ? true : false}.uniq
          feature = nil
          if values.size == 0 # empty feature
          elsif  values.size > 5 and types.size == 1 and types.first == true # 5 max classes
            numeric[i] = true
            feature = NumericFeature.find_or_create_by(metadata)
          else
            metadata["accept_values"] = values
            numeric[i] = false
            feature = NominalFeature.find_or_create_by(metadata)
          end
          features << feature if feature
        end
        
        table.each_with_index do |vals,i|
          identifier = vals.shift.strip
          batch.identifiers << identifier
          begin
            case compound_format
            when /SMILES/i
              compound = OpenTox::Compound.from_smiles(identifier)
            when /InChI/i
              compound = OpenTox::Compound.from_inchi(identifier)
            end
          rescue 
            compound = nil
          end
          if compound.nil? # compound parsers may return nil
            #warn "Cannot parse #{compound_format} compound '#{identifier}' at line #{i+2} of #{source}, all entries are ignored."
            batch.compounds  << "Cannot parse #{compound_format} compound '#{identifier}' at line #{i+2} of #{source}."
            next
          end
          batch.compounds << compound.id
        end
        batch.save
      end
      batch
    end

  end

end
