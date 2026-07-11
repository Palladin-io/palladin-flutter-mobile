Pod::Spec.new do |s|
  s.name             = 'PalladinAutoFillBridge'
  s.version          = '1.0.0'
  s.summary          = 'Encrypted native cache bridge for Palladin AutoFill.'
  s.homepage         = 'https://palladin.io'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Palladin' => 'engineering@palladin.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '14.0'
  s.swift_version    = '5.0'
  s.dependency 'Flutter'
  s.frameworks = 'AuthenticationServices', 'CryptoKit', 'Security'
end
