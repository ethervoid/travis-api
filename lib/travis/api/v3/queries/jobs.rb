module Travis::API::V3
  class Queries::Jobs < Query
    def find(build)
      sort filter(build.jobs)
    end

    def filter(list)
      list
    end
  end
end
