require "elasticsearch/git/version"
require "elasticsearch/git/model"
require "elasticsearch/git/repository"
require "elasticsearch/git/blobs_indexer"
require "elasticsearch/git/commits_indexer"
require "elasticsearch/git/utils"

module Elasticsearch
  module Git
    BATCH_SIZE = 300

    mattr_accessor :base_index_name

    self.base_index_name = 'repository'

    class << self
      def index_name
        [base_index_name, index_name_suffix].compact.join('_')
      end

      def index_name_suffix
        return unless defined?(::Rails)
        ::Rails.env.to_s
      end
    end
  end
end

