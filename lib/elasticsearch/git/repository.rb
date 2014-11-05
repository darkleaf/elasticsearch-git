require 'active_support/concern'
require 'active_model'
require 'elasticsearch'
require 'elasticsearch/git/model'
require 'elasticsearch/git/encoder_helper'
require 'elasticsearch/git/lite_blob'
require 'rugged'

module Elasticsearch
  module Git
    module Repository
      extend ActiveSupport::Concern

      included do
        include Elasticsearch::Git::Model

        mapping _timestamp: { enabled: true } do
          indexes :blob do
            indexes :id,          type: :string, index_options: 'offsets', search_analyzer: :human_analyzer,  index_analyzer: :human_analyzer
            indexes :rid,         type: :string, index: :not_analyzed
            indexes :oid,         type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,   index_analyzer: :code_analyzer
            indexes :commit_sha,  type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,   index_analyzer: :code_analyzer
            indexes :path,        type: :string, search_analyzer: :path_analyzer,   index_analyzer: :path_analyzer
            indexes :content,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,   index_analyzer: :code_analyzer
            indexes :language,    type: :string, index: :not_analyzed
          end

          indexes :commit do
            indexes :id,          type: :string, index_options: 'offsets', search_analyzer: :human_analyzer,  index_analyzer: :human_analyzer
            indexes :rid,         type: :string, index: :not_analyzed
            indexes :sha,         type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer

            indexes :author do
              indexes :name,      type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :email,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :time,      type: :date, format: :basic_date_time_no_millis
            end

            indexes :commiter do
              indexes :name,      type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :email,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :time,      type: :date, format: :basic_date_time_no_millis
            end

            indexes :message,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
          end
        end

        # Indexing all text-like blobs in repository
        #
        # All data stored in global index
        # Repository can be selected by 'rid' field
        # If you want - this field can be used for store 'project' id
        #
        # blob {
        #   id - uniq id of blob from all repositories
        #   oid - blob id in repository
        #   content - blob content
        #   commit_sha - last actual commit sha
        # }
        #
        # For search from blobs use type 'blob'
        def index_blobs(from_rev: nil, to_rev: repository_for_indexing.last_commit.oid)
          BlobsIndexer.index_blobs(__elasticsearch__.client, self.class.index_name, repository_id, repository_for_indexing, logger, from_rev: from_rev, to_rev: to_rev)
        end

        # Indexing all commits in repository
        #
        # All data stored in global index
        # Repository can be filtered by 'rid' field
        # If you want - this field can be used git store 'project' id
        #
        # commit {
        #  sha - commit sha
        #  author {
        #    name - commit author name
        #    email - commit author email
        #    time - commit time
        #  }
        #  commiter {
        #    name - committer name
        #    email - committer email
        #    time - commit time
        #  }
        #  message - commit message
        # }
        #
        # For search from commits use type 'commit'
        def index_commits(from_rev: nil, to_rev: repository_for_indexing.last_commit.oid)
          CommitsIndexer.index_commits(__elasticsearch__.client, self.class.index_name, repository_id, repository_for_indexing, logger, from_rev: from_rev, to_rev: to_rev)
        end

        def search(query, type: :all, page: 1, per: 20, options: {})
          options[:repository_id] = repository_id if options[:repository_id].nil?
          self.class.search(query, type: type, page: page, per: per, options: options)
        end

        # Repository id used for identity data from different repositories
        # Update this value if need
        def set_repository_id id = nil
          @repository_id = id || path_to_repo
        end

        # For Overwrite
        def repository_id
          @repository_id
        end

        # For Overwrite
        def self.repositories_count
          10
        end

        unless defined?(path_to_repo)
          def path_to_repo
            if @path_to_repo.blank?
              raise NotImplementedError, 'Please, define "path_to_repo" method, or set "path_to_repo" via "repository_for_indexing" method'
            else
              @path_to_repo
            end
          end
        end

        def repository_for_indexing(repo_path = "")
          return @rugged_repo_indexer if defined? @rugged_repo_indexer

          @path_to_repo ||= repo_path
          set_repository_id
          @rugged_repo_indexer = Rugged::Repository.new(@path_to_repo)
        end

        def client_for_indexing
          @client_for_indexing ||= Elasticsearch::Client.new log: true
        end

        def self.search(query, type: :all, page: 1, per: 20, options: {})
          results = { blobs: [], commits: []}
          case type.to_sym
          when :all
            results[:blobs] = search_blob(query, page: page, per: per, options: options)
            results[:commits] = search_commit(query, page: page, per: per, options: options)
          when :blob
            results[:blobs] = search_blob(query, page: page, per: per, options: options)
          when :commit
            results[:commits] = search_commit(query, page: page, per: per, options: options)
          end

          results
        end

        def logger
          @logger ||= Logger.new(STDOUT)
        end

        private

        def merge_base(to_rev)
          head_sha = repository_for_indexing.last_commit.oid
          repository_for_indexing.merge_base(to_rev, head_sha)
        end
      end

      module ClassMethods
        def search_commit(query, page: 1, per: 20, options: {})
          page ||= 1

          fields = %w(message^10 sha^5 author.name^2 author.email^2 committer.name committer.email).map {|i| "commit.#{i}"}

          query_hash = {
            query: {
              filtered: {
                query: {
                  multi_match: {
                    fields: fields,
                    query: "#{query}",
                    operator: :or
                  }
                },
              },
            },
            facets: {
              commitRepositoryFaset: {
                terms: {
                  field: "commit.rid",
                  all_terms: true,
                  size: repositories_count
                }
              }
            },
            size: per,
            from: per * (page - 1)
          }

          if query.blank?
            query_hash[:query][:filtered][:query] = { match_all: {}}
            query_hash[:track_scores] = true
          end

          if options[:repository_id]
            query_hash[:query][:filtered][:filter] ||= { and: [] }
            query_hash[:query][:filtered][:filter][:and] << {
              terms: {
                "commit.rid" => [options[:repository_id]].flatten
              }
            }
          end

          if options[:highlight]
            es_fields = fields.map { |field| field.split('^').first }.inject({}) do |memo, field|
              memo[field.to_sym] = {}
              memo
            end

            query_hash[:highlight] = {
                pre_tags: ["gitlabelasticsearch→"],
                post_tags: ["←gitlabelasticsearch"],
                fields: es_fields
            }
          end

          options[:order] = :default if options[:order].blank?
          order = case options[:order].to_sym
                  when :recently_indexed
                    { _timestamp: { order: :desc, mode: :min } }
                  when :last_indexed
                    { _timestamp: { order: :asc,  mode: :min } }
                  else
                    {}
                  end

          query_hash[:sort] = order.blank? ? [:_score] : [order, :_score]

          res = self.__elasticsearch__.search(query_hash)
          {
            results: res.results,
            total_count: res.size,
            repositories: res.response["facets"]["commitRepositoryFaset"]["terms"]
          }
        end

        def search_blob(query, type: :all, page: 1, per: 20, options: {})
          page ||= 1

          query_hash = {
            query: {
              filtered: {
                query: {
                  match: {
                    'blob.content' => {
                      query: "#{query}",
                      operator: :and
                    }
                  }
                }
              }
            },
            facets: {
              languageFacet: {
                terms: {
                  field: :language,
                  all_terms: true,
                  size: 20
                }
              },
              blobRepositoryFaset: {
                terms: {
                  field: :rid,
                  all_terms: true,
                  size: repositories_count
                }
              }
            },
            size: per,
            from: per * (page - 1)
          }

          if options[:repository_id]
            query_hash[:query][:filtered][:filter] ||= { and: [] }
            query_hash[:query][:filtered][:filter][:and] << {
              terms: {
                "blob.rid" => [options[:repository_id]].flatten
              }
            }
          end

          if options[:language]
            query_hash[:query][:filtered][:filter] ||= { and: [] }
            query_hash[:query][:filtered][:filter][:and] << {
              terms: {
                "blob.language" => [options[:language]].flatten
              }
            }
          end

          options[:order] = :default if options[:order].blank?
          order = case options[:order].to_sym
                  when :recently_indexed
                    { _timestamp: { order: :desc, mode: :min } }
                  when :last_indexed
                    { _timestamp: { order: :asc, mode: :min } }
                  else
                    {}
                  end

          query_hash[:sort] = order.blank? ? [:_score] : [order, :_score]

          if options[:highlight]
            query_hash[:highlight] = {
              pre_tags: ["gitlabelasticsearch→"],
              post_tags: ["←gitlabelasticsearch"],
              fields: {
                "blob.content" => {},
                "type" => "fvh",
                "boundary_chars" => "\n"
              }
            }
          end

          res = self.__elasticsearch__.search(query_hash)

          {
            results: res.results,
            total_count: res.size,
            languages: res.response["facets"]["languageFacet"]["terms"],
            repositories: res.response["facets"]["blobRepositoryFaset"]["terms"]
          }
        end

        def search_file_names(query, page: 1, per: 20, options: {})
          query_hash = {
              fields: ['blob.path'],
              query: {
                  fuzzy: {
                      "repository.blob.path" => { value: query }
                  },
              },
              filter: {
                  term: {
                      "repository.blob.rid" => [options[:repository_id]].flatten
                  }
              },
              size: per,
              from: per * (page - 1)
          }

          self.__elasticsearch__.search(query_hash)
        end
      end
    end
  end
end
