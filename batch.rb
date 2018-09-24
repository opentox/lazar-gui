require 'csv'
require 'tempfile'

def has_tab?(line)
  !!(line =~ /\t/)
end

module OpenTox

  class Batch

    include OpenTox
    include Mongoid::Document
    include Mongoid::Timestamps
    store_in collection: "batch"
    field :name,  type: String
    field :source,  type: String
    field :identifiers, type: Array
    field :ids, type: Array
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
        # check delimiter
        line = File.readlines(file).first
        if has_tab?(line)
          table = CSV.read file, :col_sep => "\t", :skip_blanks => true, :encoding => 'windows-1251:utf-8'
        else
          table = CSV.read file, :skip_blanks => true, :encoding => 'windows-1251:utf-8'
        end
        batch = self.new(:source => source, :name => name, :identifiers => [], :ids => [], :compounds => [])

        # original IDs
        if table[0][0] =~ /ID/i
          @original_ids = table.collect{|row| row.shift}
          @original_ids.shift
        end
        
        # features
        feature_names = table.shift.collect{|f| f.strip}
        warnings << "Duplicated features in table header." unless feature_names.size == feature_names.uniq.size
        compound_format = feature_names.shift.strip
        unless compound_format =~ /SMILES|InChI/i
          File.delete file
          bad_request_error "'#{compound_format}' is not a supported compound format in the header. " \
          "Accepted formats: SMILES, InChI. Please take a look on the help page."
        end
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
          identifier = vals.shift.strip.gsub(/^'|'$/,"")
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
          # collect only for present compounds
          unless compound.nil?
            batch.identifiers << identifier
            batch.compounds << compound.id
            batch.ids << @original_ids[i] if @original_ids
          else
            batch.warnings << "Cannot parse #{compound_format} compound '#{identifier}' at line #{i+2} of #{source}."
          end
        end
        batch.compounds.duplicates.each do |duplicate|
          $logger.debug "Duplicates found in #{name}."
          dup = Compound.find duplicate
          positions = []
          batch.compounds.each_with_index do |co,i|
            c = Compound.find co
            if !c.blank? and c.inchi and c.inchi == dup.inchi
              positions << i+1
            end
          end
          batch.warnings << "Duplicate compound at ID #{positions.join(' and ')}."
        end
        batch.save
      end
      batch
    end

  end

end
