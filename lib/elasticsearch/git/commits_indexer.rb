module Elasticsearch
  module Git
    module CommitsIndexer
      include Elasticsearch::Git::EncoderHelper

      extend self

      def index_commits(client, repository_id, repository_for_indexing, logger, from_rev: nil, to_rev: nil)
        from, to = Utils.parse_revs(repository_for_indexing, from_rev, to_rev)
        range = [from, to].compact.join('..')
        out, err, status = Open3.capture3("git log #{range} --format=\"%H\"", chdir: repository_for_indexing.path)

        if status.success? && err.blank?
          #TODO use rugged walker!!!
          commit_oids = out.split("\n")

          commit_oids.each_slice(BATCH_SIZE) do |batch|
            bulk_operations = batch.map do |commit|
              index_commit_operation(repository_for_indexing.lookup(commit), repository_id)
            end
            perform_bulk client, bulk_operations, repository_id, logger
          end
        end
      end

    private
      def perform_bulk(client, bulk_operations, repository_id, logger)
        ops = bulk_operations.compact
        return if ops.empty?
        responce = client.bulk body: ops
        logger.info "Bulk operations are performed for repository #{repository_id}."
      rescue => ex
        logger.warn "Error with bulk repository indexing. Reason: #{ex.message}"
      end


      def index_commit_operation(commit, repository_id)
        {
          index:  {
            _index: Elasticsearch::Git.index_name, _type: "repository", _id: "#{repository_id}_#{commit.oid}",
            data: {
              commit: {
                type: "commit",
                rid: repository_id,
                sha: commit.oid,
                author: {
                  name: commit.author[:name],
                  email: commit.author[:email],
                  time: commit.author[:time].strftime('%Y%m%dT%H%M%S%z'),
                },
                committer: {
                  name: commit.committer[:name],
                  email: commit.committer[:email],
                  time: commit.committer[:time].strftime('%Y%m%dT%H%M%S%z'),
                },
                message: encode!(commit.message)
              }
            }
          }
        }
      end
    end
  end
end