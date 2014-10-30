module Gitlab
  module RepositoryIndexer
    module Client
      CLIENT_KEY = :gitlab_elasticsearch_client

      extend self

      def client
        Thread.current[CLIENT_KEY] ||= Elasticsearch::Client.new
      end

      def client=(client_object)
        Thread.current[CLIENT_KEY] = client_object
      end
    end
  end
end
