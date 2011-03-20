require 'rubygems'
require 'httparty'
require 'active_support'
require 'active_support/hash_with_indifferent_access'
require 'active_support/inflector'

module Comm
  module Resource
    extend ActiveSupport::Concern

    included do
      attr_reader :attributes
    end

    def initialize(attributes = {})
      @path = attributes.delete(:path)
      @client = attributes.delete(:client)
      @attributes = ActiveSupport::HashWithIndifferentAccess.new(attributes)
    end

    module ClassMethods
      def resource_name
        name.split('::').last.underscore.downcase
      end

      def collection_name
        resource_name.pluralize
      end
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

    def method_missing(method, *args)
      method_name = method.to_s
      if attributes.include?(method_name)
        read_attribute(method_name)
      else
        super
      end
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

    def get(path, klass, options = {})
      data = self.class.get("#{path}.json", options)

      if data.has_key?(klass.collection_name)
        data[klass.collection_name].map{|data| build_resource(klass, path, data) }
      else
        build_resource(klass, path, data)
      end
    end

    private

    def build_resource(klass, path, data)
      data[:path] = path
      data[:client] = self
      klass.new(data)
    end
  end
end

Dir[File.expand_path(File.join(__FILE__, '..')) + '/*.rb'].each do |file|
  require file
end
