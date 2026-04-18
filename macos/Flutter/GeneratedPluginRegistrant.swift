//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import flutter_secure_storage_macos
import google_sign_in_ios
import local_auth_darwin
import package_info_plus
import posthog_flutter
import share_plus
import sodium_libs

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  FlutterSecureStoragePlugin.register(with: registry.registrar(forPlugin: "FlutterSecureStoragePlugin"))
  FLTGoogleSignInPlugin.register(with: registry.registrar(forPlugin: "FLTGoogleSignInPlugin"))
  LocalAuthPlugin.register(with: registry.registrar(forPlugin: "LocalAuthPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  PosthogFlutterPlugin.register(with: registry.registrar(forPlugin: "PosthogFlutterPlugin"))
  SharePlusMacosPlugin.register(with: registry.registrar(forPlugin: "SharePlusMacosPlugin"))
  SodiumLibsPlugin.register(with: registry.registrar(forPlugin: "SodiumLibsPlugin"))
}
