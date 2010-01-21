# YamlSeeder
require 'yaml'
require 'erb'

class YamlSeeder < Hash
  DEFAULT_FILTER_RE = /\.ya?ml$/
  
  @@record_cache = Hash.new
  @@yaml_cache = Hash.new
  @@seedfile_directory = ""
  
  def self.seed(seedfile_directory, table_names, class_names = {})
    @@seedfile_directory = seedfile_directory
    table_names = [table_names].flatten.map { |n| n.to_s }

    # deletes the table name from the fetching list if it's cached already:
    table_names_to_fetch = table_names.reject { |table_name| model_is_cached?(table_name) }
    
    unless table_names_to_fetch.empty?
      yaml_rows_map = {}

      yaml_rows = table_names_to_fetch.map do |table_name|
        yaml_rows_map[table_name] = YamlSeeder.new(File.split(table_name.to_s).last, class_names[table_name.to_sym], File.join(seedfile_directory, table_name.to_s))
      end
      
      @@yaml_cache.update(yaml_rows_map)
      
      yaml_rows.each do |row| 
        row.insert_records
      end

    end    
  end
  
  def self.model_is_cached?(table_name)
    @@record_cache.has_key?(table_name)
  end
  
  def initialize(table_name, class_name, seedfile_path, file_filter = DEFAULT_FILTER_RE)
    @table_name, @seedfile_path, @file_filter = table_name, seedfile_path, file_filter
    @name = table_name # preserve seed base name
    
    @class_name = class_name ||
                  (ActiveRecord::Base.pluralize_table_names ? @table_name.singularize.camelize : @table_name.camelize)
    @table_name = "#{ActiveRecord::Base.table_name_prefix}#{@table_name}#{ActiveRecord::Base.table_name_suffix}"
    @table_name = class_name.table_name if class_name.respond_to?(:table_name)
    
    read_yaml_seed_files
  end
  
  def insert_records
    each do |label, row|

      if model_class && model_class < ActiveRecord::Base

        # If STI is used, find the correct subclass for association reflection
        reflection_class =
          if row.include?(inheritance_column_name)
            row[inheritance_column_name].constantize rescue model_class
          else
            model_class
          end

        reflection_class.reflect_on_all_associations.each do |association|
          case association.macro
          when :belongs_to
            
            # if there's a belong-to association, find the id of the foreign key in the loaded associations.
            # if it's not in the loaded associations, then load it. get it's id, and set the foreign key to it.
            
            # Do not replace association name with association foreign key if they are named the same
            fk_name = (association.options[:foreign_key] || "#{association.name}_id").to_s

            if association.name.to_s != fk_name && value = row.delete(association.name.to_s)
              if association.options[:polymorphic]
                if value.sub!(/\s*\(([^\)]*)\)\s*$/, "")
                  target_type = $1
                  target_type_name = (association.options[:foreign_type] || "#{association.name}_type").to_s

                  # support polymorphic belongs_to as "label (Type)"
                  row[target_type_name] = target_type
                end
              end
              
              if @@record_cache.has_key?(association.name.to_s.pluralize)
                # load the appropriate association
                assoc_records = @@record_cache[association.name.to_s.pluralize]
                row[fk_name] = assoc_records[value].id
              else
                # they aren't loaded yet, so do the recursive thing, loading it.
                YamlSeeder.seed(@@seedfile_directory, association.name.to_s.pluralize)
                
                # the record cache will now contain what we need
                assoc_records = @@record_cache[association.name.to_s.pluralize]
                row[fk_name] = assoc_records[value].id
              end
            end
          end
        end
      end

      @myobject = model_class.create (row)      
      records_in_table = @@record_cache.has_key?(@table_name) ? @@record_cache[@table_name] : Hash.new
      records_in_table[label] = @myobject
      @@record_cache[@table_name] = records_in_table
      
    end
  end
  
  private
  def read_yaml_seed_files
    yaml_string = ""
    Dir["#{@seedfile_path}/**/*.yml"].select { |f| test(?f, f) }.each do |subseed_path|
      yaml_string << IO.read(subseed_path)
    end
    yaml_string << IO.read(yaml_file_path)

    if yaml = parse_yaml_string(yaml_string)
      # If the file is an ordered map, extract its children.
      yaml_value =
        if yaml.respond_to?(:type_id) && yaml.respond_to?(:value)
          yaml.value
        else
          [yaml]
        end

      yaml_value.each do |seed|
        raise YamlSeeder::FormatError, "Bad data for #{@class_name} seed named #{seed}" unless seed.respond_to?(:each)
        seed.each do |name, data|
          unless data
            raise YamlSeeder::FormatError, "Bad data for #{@class_name} seed named #{name} (nil)"
          end

          self[name] = data
        end
      end
    end
  end
  
  class YamlSeederError < StandardError #:nodoc:
  end

  class FormatError < YamlSeederError #:nodoc:
  end
  
  def parse_yaml_string(seed_content)
    YAML::load(erb_render(seed_content))
  rescue => error
    raise YamlSeeder::FormatError, "a YAML error occurred parsing #{yaml_file_path}. Please note that YAML must be consistently indented using spaces. Tabs are not allowed. Please have a look at http://www.yaml.org/faq.html\nThe exact error was:\n  #{error.class}: #{error}"
  end
  
  def yaml_file_path
    "#{@seedfile_path}.yml"
  end
  
  def inheritance_column_name
    @inheritance_column_name ||= model_class && model_class.inheritance_column
  end

  def erb_render(seed_content)
    ERB.new(seed_content).result
  end
  
  def model_class
    unless defined?(@model_class)
      @model_class =
        if @class_name.nil? || @class_name.is_a?(Class)
          @class_name
        else
          @class_name.constantize rescue nil
        end
    end

    @model_class
  end
end