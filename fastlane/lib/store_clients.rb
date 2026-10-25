require 'json'
require 'open3'
require 'digest'
require_relative 'mobile_delivery'

module MobileDelivery
  # Apple exposes no binary digest. A create-only intent binds our one upload attempt
  # to its verified artifact; pre-existing builds without that intent are never adopted.
  class UploadIntent
    def initialize(manifest, platform)
      @manifest = manifest
      @repo = manifest.fetch('repository')
      @tag = "mobile-upload/#{manifest.fetch('run_id')}/#{platform}"
    end
    def api(path, payload = nil, optional: false)
      args = ['gh', 'api', "repos/#{@repo}/#{path}"]
      args += ['--method','POST','--input','-'] if payload
      out, err, status = Open3.capture3(*args, stdin_data: payload ? JSON.generate(payload) : '')
      return nil if optional && !status.success? && err.include?('(HTTP 404)')
      raise Failure, 'Upload intent API failed' unless status.success?
      JSON.parse(out)
    end
    def known?
      ref = api("git/ref/tags/#{@tag}", optional: true)
      return false unless ref
      raise Failure, 'Invalid upload intent' unless ref.dig('object','type') == 'tag'
      tag = api("git/tags/#{ref.fetch('object').fetch('sha')}")
      raise Failure, 'Upload intent mismatch' unless tag.dig('object','sha') == @manifest.fetch('source_sha') && JSON.parse(tag.fetch('message')) == @manifest
      true
    end
    def reserve!
      raise Failure, 'Upload was already attempted; use resume' if known?
      tag = api('git/tags', {tag: @tag, message: JSON.generate(@manifest), object: @manifest.fetch('source_sha'), type: 'commit'})
      api('git/refs', {ref: "refs/tags/#{@tag}", sha: tag.fetch('sha')})
    end
  end

  class AndroidStore
    def initialize(manifest, upload)
      require 'google/apis/androidpublisher_v3'
      require 'googleauth'
      @manifest, @upload = manifest, upload
      @intent = UploadIntent.new(manifest, 'android')
      @package = manifest.fetch('bundle_id')
      @build = manifest.fetch('android_build')
      @api = Google::Apis::AndroidpublisherV3::AndroidPublisherService.new
      @api.authorization = Google::Auth.get_application_default(['https://www.googleapis.com/auth/androidpublisher'])
    end
    def state
      edit = @api.insert_edit(@package)
      committed = false
      begin
        releases = @api.get_edit_track(@package, edit.id, 'internal').releases || []
        active = releases.select { |r| r.status == 'completed' }.flat_map { |r| r.version_codes || [] }.map(&:to_i)
        return :superseded if active.any? { |n| n > @build }
        bundle = (@api.list_edit_bundles(@package, edit.id).bundles || []).find { |b| b.version_code.to_i == @build }
        return @intent.known? ? :uncertain : :absent unless bundle
        return :untrusted unless bundle.sha256 == @manifest.fetch('artifact').fetch('sha256')
        return :distributed if active.include?(@build)
        track = Google::Apis::AndroidpublisherV3::Track.new(releases: [
          Google::Apis::AndroidpublisherV3::TrackRelease.new(status: 'completed', version_codes: [@build.to_s])])
        @api.update_edit_track(@package, edit.id, 'internal', track)
        @api.commit_edit(@package, edit.id)
        committed = true
        :processing
      ensure
        @api.delete_edit(@package, edit.id) unless committed
      end
    end
    def upload
      @intent.reserve!
      begin
        @upload.call
      rescue StandardError
        # A failed HTTP response may follow an accepted store write. Reconcile first.
        nil
      end
    end
  end

  class AppleStore
    def initialize(manifest, upload)
      @manifest, @upload = manifest, upload
      @intent = UploadIntent.new(manifest, 'ios')
      @app = Spaceship::ConnectAPI::App.find(manifest.fetch('bundle_id'))
      raise Failure, 'App Store Connect app is missing' unless @app
      group_id = ENV.fetch('TESTFLIGHT_INTERNAL_GROUP_ID')
      @group = @app.get_beta_groups.find { |g| g.id == group_id }
      unless @group && @group.is_internal_group && @group.has_access_to_all_builds
        raise Failure, 'Configure the internal group with automatic build access'
      end
    end
    def state
      builds = Spaceship::ConnectAPI::Build.all(app_id: @app.id,
        version: @manifest.fetch('marketing_version'), build_number: @manifest.fetch('ios_build'), platform: 'IOS')
      build = builds.first
      return @intent.known? ? :uncertain : :absent unless build
      return :untrusted unless @intent.known?
      return :invalid if build.expired || ['FAILED','INVALID'].include?(build.processing_state)
      internal_state = build.build_beta_detail&.internal_build_state
      return :processing unless build.processing_state == 'VALID' && ['READY_FOR_BETA_TESTING','IN_BETA_TESTING'].include?(internal_state)
      @group.fetch_builds.any? { |b| b.id == build.id } ? :distributed : :processing
    end
    def upload
      @intent.reserve!
      begin
        @upload.call
      rescue StandardError
        # Do not retry upload; the next state read reconciles the reserved identity.
        nil
      end
    end
  end
end
