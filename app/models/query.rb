# Holds logic to process an uploaded CSV file with query results
# Holds a reference to a virtual ORM model that can be used to manipulate the imported data
class Query
  require 'find'
  # This enables the use of Query as a database-backed model (see http://www.datamapper.org/)
  include DataMapper::Resource
  storage_names[:default] = 'queries'

  # Properties set here are instance variables that can be saved to the database
  property :id, Serial
  property :created_at, DateTime
  property :filename, String

  # Makes accessors for instance variables that won't be saved to the database
  attr_accessor :images
  attr_accessor :missing_images
  attr_accessor :reference_images
  attr_accessor :missing_reference_images
  attr_accessor :matches

  # Constructs a database-backed Query object
  def initialize(args = {:filename => nil, :tempfile => nil})
    @filename = args.delete(:filename)
    @images = []
    @missing_images = []
    @reference_images = []
    @missing_reference_images = []
    @matches = {}
    if(@filename)
      import_file = File.join(absolute_import_dir, @filename)
      if File.exists?(import_file)
        @table_class = CsvImporter.load_class(CsvImporter.table_name(@filename))
      else
        FileUtils.mkdir absolute_import_dir unless File.directory?(absolute_import_dir)
        FileUtils.mv args[:tempfile].path, import_file
        @table_class = CsvImporter.new(import_file).table_class
      end
    end
    find_images
    calculate_matches
  end

  # Returns absolute path to directory where data files will be imported to
  def absolute_import_dir
    File.join(Merb.root, File.join("public", relative_import_dir))
  end

  # Returns relative path to directory where data files will be imported to
  def relative_import_dir
    "/uploads/#{CsvImporter.table_name(@filename)}"
  end

  # Collects:
  # * compared images on the filesystem into @images
  # * compared images not found on the filesystem into @missing_images
  # * reference images on the filesystem into @reference_images
  # * reference images not found on the filesystem into @missing_reference_images
  def find_images
    rows = @table_class.all
    rows.each do | row |
      # Collects each first column (image compared to the next) of each row
      if image_exists?(row.image_filename)
        @images << row.image_filename
      else
        @missing_images << row.image_filename
      end
      # Collects each column name (image to compare to)
      if(row == rows.last)
        row.instance_variables.each do | column |
          # Filter out the intance variables we set up ourselves
          unless ['@id', '@repository','@image_filename','@original_values', '@new_record','@collection', '@updated_at'].include? column
            filename = locate_image(column.gsub(/@/,''))
            if image_exists?(filename)
              @reference_images << filename
            else
              @missing_reference_images << filename
            end
          end
        end
      end
    end
  end

  def locate_image(partial_filename)
    Find.find(absolute_images_path) do |f|
      filename = f.gsub(absolute_images_path, '')
      unless filename.nil? || filename.match(/^\..*$/)
        if filename.match(/\.(jpg|jpeg|png|JPG|JPEG|PNG)$/)
          if filename.match(partial_filename)
            return filename
          end
        end
      end
    end
    return partial_filename
  end

  # Calculates highest scoring match for each image
  def calculate_matches
    rows = @table_class.all
    rows.each do | row |
      highest_score = 0
      best_match = ""
      row.instance_variables.each do | column |
        unless ['@id', '@repository','@image_filename','@original_values', '@new_record','@collection', '@updated_at'].include? column
          if row.instance_variable_get(column) > highest_score
            highest_score = row.instance_variable_get(column)
            best_match = column.gsub(/@/, '')
          end
        end
      end
      @matches[row.image_filename.to_sym] = {:image_filename => locate_image(best_match), :accuracy => highest_score}
    end
  end

  # Returns absolute path for uploaded images, derived from @filename
  def absolute_images_path
    File.join(absolute_import_dir, "images")
  end

  # Returns relative path for uploaded images, derived from @filename
  def relative_images_path
    File.join(relative_import_dir, "images")
  end

  # Returns true if filename exists in folder pointed to by images_path
  def image_exists?(filename)
    File.exists?(File.join(absolute_images_path, filename))
  end

  # Returns true if all images are present at the correct location. Otherwise, returns false.
  def all_images_exist?
    return false if @missing_images.size > 0
    return false if @missing_reference_images.size > 0
    return true
  end

end