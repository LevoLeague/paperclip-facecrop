require File.expand_path('../face_crop', __FILE__)

module Paperclip
  class FaceCrop < Paperclip::Thumbnail

    @@debug = false
    @@max_scale_out = 2.5

    #cattr_accessor :classifiers
    cattr_accessor :debug
    cattr_accessor :max_scale_out

    def self.detectors=(detectors)
      @@detectors = detectors.map do |name, options|
        #require File.expand_path("../detectors/#{name}", __FILE__)
        detector_class = "FaceCrop::Detector::#{name}".constantize
        detector = detector_class.new(options)
      end
    end

    def initialize(file, options = {}, attachment = nil)
      super(file, options, attachment)
      @source_geometry = (options[:file_geometry_parser] || Paperclip::Geometry).from_file(file)

      raise "No detectors were defined" if @@detectors.nil?

      faces_regions = []
      faces_parts_regions = []

      @@detectors.each do |detector|
        begin
          faces_regions += detector.detect(file.path)
        rescue Exception => e
          puts e
          Rails.logger.error(e)
        end
      end


      x_coords, y_coords, widths, heights = [], [], [], []

      faces_regions.each do |region|
        x_coords << region.top_left.x << region.bottom_right.x
        y_coords << region.top_left.y << region.bottom_right.y
        widths << region.width
        heights << region.height
      end

      @has_faces = faces_regions.size > 0

      if @has_faces
        @top_left_x = x_coords.min
        @top_left_y = y_coords.min
        @bottom_right_x = x_coords.max
        @bottom_right_y = y_coords.max

        @bound_geometry = Paperclip::Geometry.new(@bottom_right_x - @top_left_x, @bottom_right_y - @top_left_y)

        @top_padding_available = @top_left_y
        @bottom_padding_available = @source_geometry.height - @bottom_right_y
        @max_y_padding = [@top_padding_available,@bottom_padding_available].min

        @left_padding_available = @top_left_x
        @right_padding_available = @source_geometry.width - @bottom_right_x
        @max_x_padding = [@left_padding_available,@right_padding_available].min

        if @@debug
          parameters = []
          parameters << "-stroke" << "green"
          parameters << "-fill" << "none"
          parameters << faces_regions.map {|r| "-stroke #{r.color} -draw 'rectangle #{r.top_left.x},#{r.top_left.y} #{r.bottom_right.x},#{r.bottom_right.y}'"}
          parameters << ":source"
          parameters << ":dest"
          parameters = parameters.flatten.compact.join(" ").strip.squeeze(" ")

          Paperclip.run("convert", parameters, :source => "#{File.expand_path(file.path)}", :dest => "#{File.expand_path(file.path)}")
        end


      end
    end


    def transformation_command
      return super unless @has_faces

      # puts "TL: #{@top_left_x},#{@top_left_y}"
      # puts "BR: #{@bottom_right_x},#{@bottom_right_y}"
      # puts "BG: #{@bound_geometry} @ #{@top_left_x},#{@top_left_y}"

      # pad as much as possible toward aspect ratio

      width_padding = height_padding = 0

      if @bound_geometry.aspect > @target_geometry.aspect
        needed_y_padding = (@target_geometry.aspect * @bound_geometry.width - @bound_geometry.height) / 2
        if needed_y_padding > @max_y_padding
          height_padding = @max_y_padding
        else
          height_padding = needed_y_padding
        end
      elsif @bound_geometry.aspect < @target_geometry.aspect
        needed_x_padding = (@target_geometry.aspect * @bound_geometry.height - @bound_geometry.width) / 2
        if needed_x_padding > @max_x_padding
          width_padding = @max_x_padding
        else
          width_padding = needed_x_padding
        end
      end

      # scale out as much as possible but not more than max

      padded_geometry = Paperclip::Geometry.new(@bound_geometry.width + 2*width_padding,@bound_geometry.height + 2*height_padding)
      padded_x = @top_left_x - width_padding
      padded_y = @top_left_y - height_padding
      # puts "PG: #{padded_geometry} @ #{padded_x},#{padded_y}"

      left_extra_padding_available = padded_x
      right_extra_padding_available = @source_geometry.width - @bottom_right_x - width_padding
      max_extra_x_padding = [left_extra_padding_available,right_extra_padding_available].min

      top_extra_padding_available = padded_y
      bottom_extra_padding_available = @source_geometry.height - @bottom_right_y - height_padding
      max_extra_y_padding = [top_extra_padding_available,bottom_extra_padding_available].min

      # puts "ME: #{max_extra_x_padding},#{max_extra_y_padding}"

      if (max_extra_x_padding / padded_geometry.aspect) > max_extra_y_padding
        max_scaled_x_padding = max_extra_y_padding * padded_geometry.aspect
        max_scaled_y_padding = max_extra_y_padding
      else
        max_scaled_x_padding = max_extra_x_padding
        max_scaled_y_padding = max_extra_x_padding / padded_geometry.aspect
      end

      # puts "MS: #{max_scaled_x_padding},#{max_scaled_y_padding}"

      if ((max_scaled_x_padding * 2 + padded_geometry.width) / padded_geometry.width) > @@max_scale_out
        max_scaled_x_padding = (@@max_scale_out * padded_geometry.width - padded_geometry.width) / 2
        max_scaled_y_padding = (@@max_scale_out * padded_geometry.height - padded_geometry.height) / 2
      end

      # puts "MS-max: #{max_scaled_x_padding},#{max_scaled_y_padding}"

      # set geometry of first crop

      cropped_geometry = Paperclip::Geometry.new(padded_geometry.width + 2*max_scaled_x_padding, padded_geometry.height + 2*max_scaled_y_padding)
      cropped_x = padded_x - max_scaled_x_padding
      cropped_y = padded_y - max_scaled_y_padding

      faces_crop = "%dx%d+%d+%d" % [cropped_geometry.width, cropped_geometry.height, cropped_x, cropped_y]
      trans = []
      trans << "-crop" << %["#{faces_crop}"] << "+repage"

      # transform first crop to our target

      scale, crop = cropped_geometry.transformation_to(@target_geometry, crop?)
      trans << "-resize" << %["#{scale}"] unless scale.nil? || scale.empty?
      trans << "-crop" << %["#{crop}"] << "+repage" if crop

      trans
    end

  end
end
