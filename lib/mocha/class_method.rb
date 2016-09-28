require 'mocha/ruby_version'
require 'metaclass'

module Mocha
  class ClassMethod
    PrependedModule = Class.new(Module)

    attr_reader :stubbee, :method_name

    def initialize(stubbee, method_name)
      @stubbee = stubbee
      @original_method = nil
      @original_visibility = nil
      @method_name = PRE_RUBY_V19 ? method_name.to_s : method_name.to_sym
    end

    def stub
      hide_original_method
      define_new_method
    end

    def unstub
      remove_new_method
      restore_original_method
      mock.unstub(method_name.to_sym)
      return if mock.any_expectations?
      reset_mocha
    end

    def mock
      stubbee.mocha
    end

    def reset_mocha
      stubbee.reset_mocha
    end

    def hide_original_method
      return unless (@original_visibility = method_visibility(method_name))
      begin
        if RUBY_V2_PLUS
          use_prepended_module_for_stub_method
        else
          store_original_method
          if original_method_defined_on_stubbee?
            remove_original_method_from_stubbee
          end
        end
      # rubocop:disable Lint/HandleExceptions
      rescue NameError
        # deal with nasties like ActiveRecord::Associations::AssociationProxy
      end
      # rubocop:enable Lint/HandleExceptions
    end

    def define_new_method
      stub_method_owner.class_eval(*stub_method_definition)
      return unless @original_visibility
      Module.instance_method(@original_visibility).bind(stub_method_owner).call(method_name)
    end

    def remove_new_method
      stub_method_owner.send(:remove_method, method_name)
    end

    def restore_original_method
      return if RUBY_V2_PLUS
      if original_method_defined_on_stubbee?
        if PRE_RUBY_V19
          original_method_in_scope = original_method
          default_stub_method_owner.send(:define_method, method_name) do |*args, &block|
            original_method_in_scope.call(*args, &block)
          end
        else
          default_stub_method_owner.send(:define_method, method_name, original_method)
        end
      end
      return unless @original_visibility
      Module.instance_method(@original_visibility).bind(stubbee.__metaclass__).call(method_name)
    end

    def matches?(other)
      return false unless other.class == self.class
      (stubbee.object_id == other.stubbee.object_id) && (method_name == other.method_name)
    end

    alias_method :==, :eql?

    def to_s
      "#{stubbee}.#{method_name}"
    end

    def method_visibility(method_name)
      symbol = method_name.to_sym
      metaclass = default_stub_method_owner

      (metaclass.public_method_defined?(symbol) && :public) ||
        (metaclass.protected_method_defined?(symbol) && :protected) ||
        (metaclass.private_method_defined?(symbol) && :private)
    end

    private

    attr_reader :original_method

    def store_original_method
      @original_method = stubbee._method(method_name)
    end

    def original_method_defined_on_stubbee?
      original_method && original_method.owner == default_stub_method_owner
    end

    def remove_original_method_from_stubbee
      default_stub_method_owner.send(:remove_method, method_name)
    end

    def use_prepended_module_for_stub_method
      @stub_method_owner = PrependedModule.new
      default_stub_method_owner.__send__ :prepend, @stub_method_owner
    end

    def stub_method_definition
      method_implementation = <<-CODE
      def #{method_name}(*args, &block)
        mocha.method_missing(:#{method_name}, *args, &block)
      end
      CODE
      [method_implementation, __FILE__, __LINE__ - 4]
    end

    def stub_method_owner
      @stub_method_owner ||= default_stub_method_owner
    end

    def default_stub_method_owner
      stubbee.__metaclass__
    end
  end
end
