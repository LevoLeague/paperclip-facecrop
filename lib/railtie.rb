module FaceCrop
  class Railtie < Rails::Railtie
    initializer "paperclip-facecrop.extend_has_attachment" do
      raise "Paperclip needed" unless defined?(Paperclip)
      ActiveSupport.on_load :active_record do
           
        class ActiveRecord::Base
          module Paperclip::FaceCrop::WithCache
            def has_attached_file(name, args)
              super(name, args)
              send("after_#{name}_post_process", lambda { FaceCrop::Detector::Cache.clear })
            end
          end

          prepend Paperclip::FaceCrop::WithCache
        end
      end
      
    end
  end
end