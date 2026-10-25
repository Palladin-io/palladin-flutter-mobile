require 'minitest/autorun'
require_relative '../lib/mobile_delivery'

class MobileDeliveryTest < Minitest::Test
  class Store
    attr_reader :uploads
    def initialize(states)
      @states = states
      @uploads = 0
    end
    def state
      @states.length > 1 ? @states.shift : @states.first
    end
    def upload
      @uploads += 1
    end
  end

  def deliver(states, resume: false)
    store = Store.new(states)
    status = MobileDelivery.deliver(store, attempts: 3, pause: -> {})
    [status, store.uploads]
  end

  def test_new_upload_waits_for_distribution
    assert_equal ['distributed',1], deliver([:absent,:processing,:distributed])
  end
  def test_resume_never_duplicates_upload
    assert_equal ['distributed',0], deliver([:processing,:distributed],resume: true)
  end
  def test_unknown_preexisting_binary_is_not_claimed
    assert_raises(MobileDelivery::Failure) { deliver([:untrusted]) }
  end
  def test_processing_timeout_is_not_success
    assert_raises(MobileDelivery::Failure) { deliver([:processing],resume: true) }
  end
  def test_superseded_does_not_upload
    assert_equal ['superseded',0], deliver([:superseded],resume: true)
  end
  def test_missing_original_upload_is_not_retried_blindly
    assert_raises(MobileDelivery::Failure) { deliver([:uncertain],resume: true) }
  end
  def test_resume_can_upload_when_no_previous_attempt_exists
    assert_equal ['distributed',1], deliver([:absent,:distributed],resume: true)
  end
  def test_uncertain_attempt_never_reuploads
    assert_raises(MobileDelivery::Failure) { deliver([:uncertain],resume: true) }
  end
  def test_failed_processing_does_not_upload
    assert_raises(MobileDelivery::Failure) { deliver([:invalid],resume: true) }
  end
end

require 'minitest/mock'
require 'ostruct'
require 'spaceship'
require 'google/apis/androidpublisher_v3'
require 'googleauth'
require_relative '../lib/store_clients'

class StoreClientsTest < Minitest::Test
  def manifest
    {'repository'=>'Palladin-io/palladin-flutter-mobile','run_id'=>42,'source_sha'=>'a'*40,
     'bundle_id'=>'io.palladin.mobile','android_build'=>2,'ios_build'=>'1.0.2',
     'marketing_version'=>'0.1.0','artifact'=>{'sha256'=>'c'*64,'name'=>'app.aab'}}
  end

  class PlayApi
    attr_accessor :authorization, :versions, :bundle, :deleted, :promoted, :committed
    def initialize
      @versions = [2]
      @bundle = OpenStruct.new(version_code: 2,sha256: 'c'*64)
    end
    def insert_edit(*) = OpenStruct.new(id: 'edit')
    def get_edit_track(*) = OpenStruct.new(releases: [OpenStruct.new(status:'completed',version_codes:@versions)])
    def list_edit_bundles(*) = OpenStruct.new(bundles: [@bundle].compact)
    def delete_edit(*) = @deleted = true
    def update_edit_track(package, edit, track, body)
      @promoted = [track, body.releases.first.status, body.releases.first.version_codes]
    end
    def commit_edit(*) = @committed = true
  end

  def with_android
    api=PlayApi.new
    Google::Apis::AndroidpublisherV3::AndroidPublisherService.stub(:new,api) do
      Google::Auth.stub(:get_application_default,Object.new) do
        yield MobileDelivery::AndroidStore.new(manifest,-> {}),api
      end
    end
  end

  def test_android_compares_binary_digest
    with_android do |store,api|
      assert_equal :distributed,store.state
      api.bundle.sha256='d'*64
      assert_equal :untrusted,store.state
      assert api.deleted
    end
  end

  def test_android_promotes_verified_existing_bundle_without_upload
    with_android do |store,api|
      api.versions=[]
      assert_equal :processing,store.state
      assert_equal ['internal','completed',['2']],api.promoted
      assert api.committed
      refute api.deleted
    end
  end

  def test_android_newer_completed_build_wins
    with_android do |store,api|
      api.versions=[3]
      assert_equal :superseded,store.state
    end
  end

  def test_apple_already_distributed_build_reconciles_with_real_models
    ENV['TESTFLIGHT_INTERNAL_GROUP_ID']='group'
    detail=Spaceship::ConnectAPI::BuildBetaDetail.new('detail', {'internalBuildState'=>'IN_BETA_TESTING'})
    build=Spaceship::ConnectAPI::Build.new('build', {'processingState'=>'VALID','expired'=>false})
    build.build_beta_detail=detail
    group=OpenStruct.new(id:'group',is_internal_group:true,has_access_to_all_builds:true)
    group.define_singleton_method(:fetch_builds) { [build] }
    app=OpenStruct.new(id:'app')
    app.define_singleton_method(:get_beta_groups) { [group] }
    intent=Object.new
    intent.define_singleton_method(:known?) { true }
    MobileDelivery::UploadIntent.stub(:new,intent) do
      Spaceship::ConnectAPI::App.stub(:find,app) do
        Spaceship::ConnectAPI::Build.stub(:all,[build]) do
          store=MobileDelivery::AppleStore.new(manifest,-> { flunk 'must not upload' })
          assert_equal :distributed,store.state
          detail.internal_build_state='MISSING_EXPORT_COMPLIANCE'
          assert_equal :processing,store.state
          detail.internal_build_state='READY_FOR_BETA_TESTING'
          group.define_singleton_method(:fetch_builds) { [] }
          assert_equal :processing,store.state
        end
      end
    end
  ensure
    ENV.delete('TESTFLIGHT_INTERNAL_GROUP_ID')
  end

  def test_apple_rejects_external_or_nonautomatic_group
    ENV['TESTFLIGHT_INTERNAL_GROUP_ID']='group'
    group=OpenStruct.new(id:'group',is_internal_group:false,has_access_to_all_builds:true)
    app=Object.new
    app.define_singleton_method(:get_beta_groups) { [group] }
    Spaceship::ConnectAPI::App.stub(:find,app) do
      assert_raises(MobileDelivery::Failure) { MobileDelivery::AppleStore.new(manifest,-> {}) }
      group.is_internal_group=true; group.has_access_to_all_builds=false
      assert_raises(MobileDelivery::Failure) { MobileDelivery::AppleStore.new(manifest,-> {}) }
    end
  ensure
    ENV.delete('TESTFLIGHT_INTERNAL_GROUP_ID')
  end
end

require 'tmpdir'
class LaneContractTest < Minitest::Test
  class Harness
    attr_reader :options
    def lane(name, &block) = @lane = block
    def run = instance_exec(&@lane)
    def upload_to_play_store(**options) = @options = options
  end
  def test_play_upload_never_weakens_review_settings
    keys=%w[RELEASE_MANIFEST RELEASE_ARTIFACT MOBILE_DISTRIBUTION_ENABLED DELIVERY_RESULT GOOGLE_APPLICATION_CREDENTIALS]
    original=keys.to_h { |key| [key,ENV[key]] }
    Dir.mktmpdir do |dir|
      path=File.join(dir,'manifest.json')
      File.write(path,JSON.generate({'artifact_platform'=>'android','bundle_id'=>'io.example.app','run_id'=>1,'marketing_version'=>'1.0.0'}))
      ENV.update('RELEASE_MANIFEST'=>path,'RELEASE_ARTIFACT'=>File.join(dir,'app.aab'),
        'MOBILE_DISTRIBUTION_ENABLED'=>'true','DELIVERY_RESULT'=>File.join(dir,'result.json'),
        'GOOGLE_APPLICATION_CREDENTIALS'=>File.join(dir,'credentials.json'))
      harness=Harness.new
      lane_path=File.expand_path('../Fastfile',__dir__)
      harness.instance_eval(File.read(lane_path),lane_path)
      adapter=->(_manifest,upload) { upload.call; Object.new }
      MobileDelivery::AndroidStore.stub(:new,adapter) do
        MobileDelivery.stub(:deliver,'distributed') { harness.run }
      end
      assert_equal 'internal',harness.options[:track]
      assert_equal 'completed',harness.options[:release_status]
      assert_equal false,harness.options[:rescue_changes_not_sent_for_review]
    end
  ensure
    original.each { |key,value| value ? ENV[key]=value : ENV.delete(key) }
  end
end
