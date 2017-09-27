module Travis::API::V3
  class Queries::Repositories < Query
    params :active, :private, :starred, :slug_matches, prefix: :repository
    sortable_by :id, :github_id, :owner_name, :name, active: sort_condition(:active),
                :'default_branch.last_build' => 'builds.started_at',
                :current_build => "repositories.current_build_id %{order} NULLS LAST",
                :slug_match    => "slug_match"

    # this is a hack for a bug in AR that generates invalid query when it tries
    # to include `current_build` and join it at the same time. We don't actually
    # need the join, but it will be automatically added, because `current_build`
    # is an association. This prevents adding the join. We will probably be able
    # to remove it once we move to newer AR versions
    prevent_sortable_join :current_build
    experimental_sortable_by :current_build

    def for_member(user, **options)
      all(user: user, **options).joins(:users).where(users: user_condition(user), invalidated_at: nil)
    end

    def for_owner(owner, **options)
      filter(owner.repositories, **options)
    end

    def all(**options)
      filter(Models::Repository, **options)
    end

    def filter(list, user: nil)
      list = list.where(invalidated_at: nil)
      list = list.where(active:  bool(active))  unless active.nil?
      list = list.where(private: bool(private)) unless private.nil?
      list = list.includes(:owner) if includes? 'repository.owner'.freeze

      if user and not starred.nil?
        if bool(starred)
          list = list.joins(:stars).where(stars: { user_id: user.id })
        elsif user.starred_repository_ids.any?
          list = list.where("repositories.id NOT IN (?)", user.starred_repository_ids)
        end
      end

      if includes? 'repository.last_build'.freeze or includes? 'build'.freeze
        list = list.includes(:last_build)
        list = list.includes(last_build: :commit) if includes? 'build.commit'.freeze
      end

      if slug_matches
        query = slug_matches.strip
        sql_phrase = query.empty? ? '%' : "%#{query.split('').join('%')}%"

        query = ActiveRecord::Base.sanitize(query)

        list = list.where(["(lower(repositories.owner_name) || '/'
                              || lower(repositories.name)) LIKE ?", sql_phrase])
        list = list.select("repositories.*, similarity(lower(repositories.owner_name) || '/'
                              || lower(repositories.name), #{query}) as slug_match")
      end

      list = list.includes(default_branch: :last_build)
      list = list.includes(current_build: [:repository, :branch, :commit, :stages, :sender]) if includes? 'repository.current_build'.freeze
      list = list.includes(default_branch: { last_build: :commit }) if includes? 'build.commit'.freeze
      sort list
    end

    def sort(*args)
      if params['sort_by']
        sort_by_list = list(params['sort_by'])
        slug_match_condition = lambda { |sort_by| sort_by =~ /^slug_match/ }

        if slug_matches.nil? && sort_by_list.find(&slug_match_condition)
          warn "slug_match sort was selected, but slug_matches param is not supplied, ignoring"

          # TODO: it would be nice to have better primitives for sorting so
          # manipulation is easier than that
          params['sort_by'] = sort_by_list.reject(&slug_match_condition).join(',')
        end
      end

      super(*args)
    end
  end
end
