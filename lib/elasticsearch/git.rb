require "elasticsearch/git/version"
require "elasticsearch/git/model"
require "elasticsearch/git/repository"
require "elasticsearch/git/blobs_indexer"
require "elasticsearch/git/commits_indexer"
require "elasticsearch/git/utils"

module Elasticsearch
  module Git
    BATCH_SIZE = 50
  end
end

