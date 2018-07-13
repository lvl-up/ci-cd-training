require 'octokit'
require 'netrc'
require 'yaml'
module Commands
  class Track < Thor
    attr_reader :github_client, :tracks

    def initialize(args = [],
                   options = {},
                   config = {},
                   api_endpoint = nil,
                   tracks_yaml = "#{__dir__}/../../../../../tracks.yml")
      super(args, options, config)
      @github_client ||= begin
        client_options = { netrc: true }
        client_options[:api_endpoint] = api_endpoint if api_endpoint
        Octokit::Client.new(client_options)
      end
      @tracks = YAML.safe_load(File.read(tracks_yaml))['tracks']
    end

    desc 'start TRACK_NAME', 'start a track'
    option :fork, desc: 'the account/repo of your fork'

    def start(track_name)
      validate!(track_name)

      project = create_project("Learn #{track_name}")

      todo_column = create_column(project.id, 'TODO')
      create_exercises(github_client, todo_column, track_name)

      create_column(project.id, 'in-progress')
      create_column(project.id, 'done')
    end

    # rubocop:disable Metrics/BlockLength
    no_commands do
      private

      def create_column(project_id, name)
        github_client.create_project_column(project_id, name, default_projects_options)
      end

      def create_exercises(client, todo_column, track_name)
        track(track_name)['exercises'].each do |exercise|
          name = exercise.keys.first

          issue = client.create_issue(fork, name, 'do this exercise', labels: '')
          options = default_projects_options.merge(content_id: issue.id, content_type: 'Issue')
          client.create_project_card(todo_column.id, options)
        end
      end

      def create_project(board_name)
        github_client.create_project(fork, board_name, default_projects_options)
      end

      def default_projects_options
        { accept: 'application/vnd.github.inertia-preview+json' }
      end

      def fork
        options[:fork]
      end

      def track(track_name)
        tracks.find do |track|
          track['name'] == track_name
        end
      end

      def track_exists?(track_name)
        !track(track_name).nil?
      end

      def track_names
        tracks.collect { |track| track['name'] }
      end

      def track_missing_msg(track_name)
        "Track #{track_name} not found.\nPlease choose from:#{track_names.join("\n")}"
      end

      def repo_error_msg
        "#{fork} is not a fork. Please for the CIC repo and try again"
      end

      def validate!(track_name)
        raise Thor::Error, track_missing_msg(track_name) unless track_exists?(track_name)

        repo = github_client.repo(fork)

        raise Thor::Error, repo_error_msg unless repo['fork'] == true
      end
    end

    # rubocop:enable Metrics/BlockLength
  end
end
