module Elasticsearch
  module Git
    module Utils
      extend self

      def parse_revs(repository_for_indexing, from_rev, to_rev)
        from = if index_new_branch?(from_rev)
                 if to_rev == repository_for_indexing.last_commit.oid
                   nil
                 else
                   merge_base(to_rev)
                 end
               else
                 from_rev
               end

        return from, to_rev
      end

      def index_new_branch?(from)
        from == '0000000000000000000000000000000000000000'
      end
    end
  end
end