module Comm
  class Database
    include Comm::Resource

    def records
      fetch_records(:all)
    end

    private

    def fetch_records(m, options = {})
      query = options[:conditions] || {}
      query[:page] = options[:page] || 1

      ary = ProxyArray.new do
        data = connection.class.get("#{resource_path}/records.json", :query => query)
        data["records"]
      end
    end
  end
end
