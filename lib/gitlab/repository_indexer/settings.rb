module Gitlab
  module RepositoryIndexer
    module Settings
      extend self

      def settings
        {
          analysis: {
            analyzer: {
              human_analyzer: {
                type: 'custom',
                tokenizer: 'human_tokenizer',
                filter: %w(lowercase asciifolding human_ngrams)
              },
              path_analyzer: {
                type: 'custom',
                tokenizer: 'path_tokenizer',
                filter: %w(lowercase asciifolding path_ngrams)
              },
              sha_analyzer: {
                type: 'custom',
                tokenizer: 'sha_tokenizer',
                filter: %w(lowercase asciifolding sha_ngrams)
              },
              code_analyzer: {
                type: 'custom',
                tokenizer: 'standard',
                filter: %w(lowercase asciifolding code_stemmer)
              }
            },
            tokenizer: {
              sha_tokenizer: {
                type: "edgeNGram",
                min_gram: 8,
                max_gram: 40,
                token_chars: %w(letter digit)
              },
              human_tokenizer: {
                type: "NGram",
                min_gram: 1,
                max_gram: 20,
                token_chars: %w(letter digit)
              },
              path_tokenizer: {
                type: 'path_hierarchy',
                reverse: true
              },
            },
            filter: {
              human_ngrams: {
                type: "NGram",
                min_gram: 1,
                max_gram: 20
              },
              sha_ngrams: {
                type: "edgeNGram",
                min_gram: 8,
                max_gram: 40
              },
              path_ngrams: {
                type: "edgeNGram",
                min_gram: 3,
                max_gram: 15
              },
              code_stemmer: {
                type: "stemmer",
                name: "minimal_english"
              }
            }
          }
        }
      end

      def mappings
        {
          repository: {
            _timestamp: {
              enabled:true
            },
            properties: {
              blob: {
                properties: {
                  commit_sha: {
                    type: "string",
                    index_options: "offsets",
                    analyzer: "code_analyzer"
                  },
                  content: {
                    type: "string",
                    index_options: "offsets",
                    analyzer: "code_analyzer"
                  },
                  id: {
                    type: "string",
                    index_options: "offsets",
                    analyzer: "human_analyzer"
                  },
                  language: {
                    type: "string",
                    index: "not_analyzed"
                  },
                  oid: {
                    type: "string",
                    index_options: "offsets",
                    analyzer: "code_analyzer"
                  },
                  path: {
                    type: "string",
                    analyzer: "path_analyzer"
                  },
                  rid: {
                    type: "string",
                    index: "not_analyzed"
                  }
                }
              },
              commit: {
                properties: {
                  author: {
                    properties: {
                      email: {
                        type: "string",
                        index_options: "offsets",
                        analyzer: "code_analyzer"
                      },
                      name: {
                        type: "string",
                        index_options: "offsets",
                        analyzer: "code_analyzer"
                      },
                      time: {
                        type: "date",
                        format: "dateOptionalTime"
                      }
                    }
                  },
                  commiter: {
                    properties: {
                      email: {
                        type: "string",
                        index_options: "offsets",
                        analyzer: "code_analyzer"
                      },
                      name: {
                        type: "string",
                        index_options: "offsets",
                        analyzer: "code_analyzer"
                      },
                      time: {
                        type: "date",
                        format: "dateOptionalTime"
                      }
                    }
                  },
                  id: {
                    type: "string",
                    index_options: "offsets",
                    analyzer: "human_analyzer"
                  },
                  message: {
                    type: "string",
                    index_options: "offsets",
                    analyzer: "code_analyzer"
                  },
                  rid: {
                    type: "string",
                    index: "not_analyzed"
                  },
                  sha: {
                    type: "string",
                    index_options: "offsets",
                    analyzer: "code_analyzer"
                  }
                }
              }
            }
          }
        }
      end
    end
  end
end
