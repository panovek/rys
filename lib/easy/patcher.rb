module Easy
  class Patcher

    mattr_accessor :paths
    self.paths = []

    mattr_accessor :patches
    self.patches = []

    def self.add(klass_to_patch, &block)
      patches << [klass_to_patch, block]
      self
    end

    def self.reload_patches
      patches.clear
      paths.each do |path|
        pattern = File.join(path, '**', '*.rb')
        Dir.glob(pattern){|f| load(f) }
      end
    end

    def self.apply
      patches.each do |klass_to_patch, block|
        klass_to_patch = klass_to_patch.constantize

        dsl = Easy::PatcherDSL.new
        dsl.instance_eval(&block)
        result = dsl._result

        # Constants which are not defined in Rails are not
        # removed. So ancestors remains. Solutions is keep
        # them but remove their content.
        klass_to_patch.ancestors.each do |ancestor|
          if ancestor.is_a?(Easy::PatchModule)
            ancestor.remove_patch_methods
          end
        end

        result[:included].each do |included|
          klass_to_patch.class_eval(&included)
        end

        result[:instance_methods].each do |options, block|
          mod = Easy::PatchModule.new(&block)

          if options[:feature]
            # Save original methods
            method_list = mod.instance_methods.map{|m| [m, "#{m}_#{SecureRandom.hex}"] }
            method_list.each do |m, aliased_m|
              klass_to_patch.send(:alias_method, aliased_m, m)
            end
          end

          klass_to_patch.prepend(mod)

          if options[:feature]
            mod = Easy::PatchModule.new do
              method_list.each do |m, aliased_m|
                define_method(m) do |*args, &block|
                  if ::Easy::Feature.active?(options[:feature])
                    super(*args, &block)
                  else
                    # method(__method__).super_method.super_method.call(*args, &block)
                    __send__(aliased_m, *args, &block)
                  end
                end
              end
            end

            klass_to_patch.prepend(mod)
          end

        end
      end

    end

  end
end

module Easy
  class PatcherDSL

    def initialize
      @_included = []
      @_instance_methods = []
      @_class_methods = []
    end

    def _result
      {
        included: @_included,
        instance_methods: @_instance_methods,
        class_methods: @_class_methods
      }
    end

    def included(&block)
      @_included << block
    end

    def instance_methods(**options, &block)
      @_instance_methods << [options, block]
    end

    def class_methods(**options, &block)
      @_class_methods << [options, block]
    end

  end
end

module Easy
  class PatchModule < Module

    def remove_patch_methods
      instance_methods.each do |met|
        remove_method met
      end
    end

  end
end
