# Disposable simulator-only host. Production Swift sources and the same-checkout
# Flutter artifacts are reused; only bundle/group identities are synthetic.
require 'xcodeproj'
require 'fileutils'
root = File.expand_path('../..', __dir__)
output = File.join(root, 'build/ios-member-source-probe')
products = File.join(root, 'build/ios-provider-gate/Build/Products/Debug-local-iphonesimulator')
production = Xcodeproj::Project.open(File.join(root, 'ios/Runner.xcodeproj'))
provider = production.targets.find { |target| target.name == 'CredentialProvider' }
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.new(File.join(output, 'MemberProbe.xcodeproj'))
host = project.new_target(:application, 'SyntheticMemberHost', :ios, '14.0')
extension = project.new_target(:app_extension, 'CredentialProvider', :ios, '14.0')
host.add_dependency(extension)
copy = host.new_copy_files_build_phase('Embed synthetic extension')
copy.dst_subfolder_spec = '13'
copy.add_file_reference(extension.product_reference, true).settings = {'ATTRIBUTES' => ['CodeSignOnCopy']}
host.source_build_phase.add_file_reference(project.main_group.new_file(File.join(__dir__, 'Host.swift')))
host.source_build_phase.add_file_reference(project.main_group.new_file(File.join(root, 'ios/AutoFillBridge/Classes/SharedMemberSourceFence.swift')))
provider.source_build_phase.files.each do |file|
  extension.source_build_phase.add_file_reference(project.main_group.new_file(file.file_ref.real_path.to_s))
end
%w[source.json vault_member_sync.db].each do |file|
  host.resources_build_phase.add_file_reference(project.main_group.new_file(File.join(output, 'fixture', file)))
end
localizations = project.main_group.new_variant_group('Localizable.strings')
%w[en pl].each do |locale|
  reference = localizations.new_file(File.join(root, "ios/CredentialProvider/#{locale}.lproj/Localizable.strings"))
  reference.name = locale
end
extension.resources_build_phase.add_file_reference(localizations)
frameworks = Dir[File.join(products, 'CredentialProvider.appex/Frameworks/*.framework')] + [
  File.join(products, 'sodium_libs/sodium_libs.framework'),
  File.join(products, 'sqflite_darwin/sqflite_darwin.framework'),
  File.join(products, 'XCFrameworkIntermediates/sodium_libs/libsodium.framework')
]
embed = extension.new_copy_files_build_phase('Embed runtime frameworks')
embed.dst_subfolder_spec = '10'
frameworks.each do |path|
  raise "Build production simulator artifacts first: #{path}" unless File.directory?(path)
  reference = project.main_group.new_file(path)
  extension.frameworks_build_phase.add_file_reference(reference) if %w[Flutter.framework sodium_libs.framework sqflite_darwin.framework libsodium.framework].include?(File.basename(path))
  embed.add_file_reference(reference, true).settings = {'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy']}
end
[host, extension].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => target == host ? 'invalid.example.productionruntime' : 'invalid.example.productionruntime.extension',
      'APP_GROUP_IDENTIFIER' => 'group.invalid.example.productionruntime',
      'INFOPLIST_FILE' => target == host ? File.join(__dir__, 'Host.plist') : File.join(root, 'ios/CredentialProvider/Info.plist'),
      'CODE_SIGN_ENTITLEMENTS' => target == host ? File.join(__dir__, 'Host.entitlements') : File.join(root, 'ios/CredentialProvider/CredentialProvider.entitlements'),
      'CODE_SIGN_IDENTITY' => '-', 'CODE_SIGNING_ALLOWED' => 'YES',
      'SWIFT_VERSION' => '5.0', 'IPHONEOS_DEPLOYMENT_TARGET' => '14.0',
      'SUPPORTED_PLATFORMS' => 'iphonesimulator', 'TARGETED_DEVICE_FAMILY' => '1,2',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
      'FRAMEWORK_SEARCH_PATHS' => frameworks.map { |path| File.dirname(path) }.uniq,
      'APPLICATION_EXTENSION_API_ONLY' => target == extension ? 'YES' : 'NO',
      'CURRENT_PROJECT_VERSION' => '1', 'MARKETING_VERSION' => '1.0',
      'OTHER_LDFLAGS' => ['$(inherited)', '-lsqlite3'],
      'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO'
    })
  end
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.set_launch_target(host)
scheme.save_as(project.path, 'SyntheticMemberHost', true)
