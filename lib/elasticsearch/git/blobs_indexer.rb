module Elasticsearch
  module Git
    module BlobsIndexer
      extend self

      def index_blobs(client, index_name, repository_id, repository_for_indexing, logger, from_rev: nil, to_rev: nil)
        from, to = Utils.parse_revs(repository_for_indexing, from_rev, to_rev)

        diff = repository_for_indexing.diff(from, to)

        diff.each_delta.each_slice(BATCH_SIZE) do |slice|
          bulk_operations = slice.map do |delta|
            if delta.status == :deleted
              next if delta.old_file[:mode].to_s(8) == "160000"
              b = LiteBlob.new(repository_for_indexing, delta.old_file)
              delete_blob_operation(b, repository_id, index_name)
            else
              next if delta.new_file[:mode].to_s(8) == "160000"
              b = LiteBlob.new(repository_for_indexing, delta.new_file)
              index_blob_operation(b, to, repository_id, index_name)
            end
          end

          perform_bulk client, bulk_operations, repository_id, logger
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

      def delete_blob_operation(blob, repository_id, index_name)
        return unless blob.text?
        { delete: { _index: index_name, _type: "repository", _id: "#{repository_id}_#{blob.path}" } }
      end

      def index_blob_operation(blob, target_sha, repository_id, index_name)
        return unless can_index_blob?(blob)
        {
          index:  {
            _index: index_name, _type: "repository", _id: "#{repository_id}_#{blob.path}",
            data: {
              blob: {
                type: "blob",
                oid: blob.id,
                rid: repository_id,
                content: blob.data,
                commit_sha: target_sha,
                path: blob.path,
                language: blob.language ? blob.language.name : "Text"
              }
            }
          }
        }
      end

      # Index text-like files which size less 1.mb
      def can_index_blob?(blob)
        blob.text? && (blob.size && blob.size.to_i < 1048576)
      end
    end
  end
end