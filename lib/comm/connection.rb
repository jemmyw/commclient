require 'rubygems'
require 'uri'
require 'httparty'
require 'active_model'
require 'active_support'
require 'active_support/hash_with_indifferent_access'
require 'active_support/inflector'
require 'active_support/core_ext/kernel/singleton_class'

module Comm
  def get_class(name)
    "Comm::#{name.to_s.singularize.classify}".constantize rescue nil 
  end
  module_function :get_class

  module ResourceArray
    extend ActiveSupport::Concern

    included do
      attr_accessor :klass, :path, :connection
    end

    def path=(value)
      @path = value

      each do |resource|
        resource.collection_path = value
      end
    end

    def connection=(value)
      @connection = value

      each do |resource|
        resource.connection = value
      end
    end

    def find(*args)
      if block_given?
        super
      else
        value = URI.encode(args.first)
        
        connection.get("#{path}/#{value}", klass, {}).tap do |resource|
          resource.collection_path = path if resource.respond_to?(:collection_path=)
        end
      end
    end

    def create(attributes = {})
      klass.new(attributes).tap do |object|
        object.collection_path = path
        object.connection = connection
        object.save
      end
    end
  end

  module Resource
    extend ActiveSupport::Concern
    include ActiveModel::Validations

    included do
      attr_reader :attributes
      attr_accessor :collection_path, :connection
      class_eval "undef id"
    end

    def initialize(attributes = {})
      @connection = attributes.delete(:connection)
      @attributes = ActiveSupport::HashWithIndifferentAccess.new(attributes)
    end

    module ClassMethods
      def resource_name
        name.split('::').last.underscore.downcase
      end

      def collection_name
        resource_name.pluralize
      end

      def collection_path
        "/#{collection_name}"
      end

      def create(attributes = {})
        new(attributes).save
      end
    end

    def resource_path
      "/#{self.class.collection_name}/#{id}"
    end

    def collection_path
      @collection_path ||= self.class.collection_path
    end

    def has_attribute?(name)
      @attributes.has_key?(name)
    end

    def read_attribute(name)
      @attributes[name]
    end

    def write_attribute(name, value)
      @attributes[name] = value
    end

    def [](name)
      read_attribute(name)
    end

    def []=(name, value)
      write_attribute(name, value)
    end

    def new_record?
      !has_attribute?(:id)
    end

    def save
      new_record? ? create : update
    end

    def reload
      unless new_record?
        @attributes = connection.get(resource_path, self.class, {}).attributes
      end

      self
    end

    def method_missing(method, *args)
      method_name = method.to_s
      if attributes.include?(method_name)
        read_attribute(method_name)
      elsif klass = Comm.get_class(method)
        connection.get("#{resource_path}/#{method}", klass, {})
      else
        super
      end
    end

    private

    def create
      data = connection.post(collection_path, self.class, attributes)

      if data.success?
        @attributes = HashWithIndifferentAccess.new(data)
        true
      else
        data.each do |key, value|
          errors.add(key, value)
        end

        false
      end
    end

    def update
      puts "updating..."
    end
  end

  class Connection
    include HTTParty

    base_uri "http://txtmanager.heroku.com/api"

    def initialize(token, password, uri = 'http://txtmanager.heroku.com')
      self.class.base_uri "#{uri}/api"
      self.class.basic_auth token, password
    end

    def method_missing(method, *args)
      klass = ('Comm::' + method.to_s.singularize.classify).constantize rescue nil

      if klass
        get("/#{method}", klass, {})
      else
        super
      end
    end

    def post(path, klass, attributes, options = {})
      options[:body] = {klass.resource_name => attributes.to_hash}
      self.class.post("#{path}.json", options)
    end

    def get(path, klass, options = {})
      data = self.class.get("#{path}.json", options)

      if data.has_key?(klass.collection_name)
        build_array(klass, data[klass.collection_name], path)
      else
        build_resource(klass, data)
      end
    end

    private

    def build_array(klass, data, path)
      data.map{|data| build_resource(klass, data)}.tap do |ary|
        ary.singleton_class.class_eval "include Comm::ResourceArray"
        ary.klass = klass
        ary.path = path
        ary.connection = self
      end
    end

    def build_resource(klass, data)
      klass.new(data).tap do |resource|
        resource.connection = self
      end
    end
  end
end

Dir[File.expand_path(File.join(__FILE__, '..')) + '/*.rb'].each do |file|
  require file
end
