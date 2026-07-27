#
# scommconnector macOS — builds libdatachannel via CMake and links it into the app.
#
Pod::Spec.new do |s|
  s.name             = 'scommconnector'
  s.version          = '1.0.0'
  s.summary          = 'SComm Connector libdatachannel FFI'
  s.description      = 'Native libdatachannel for SComm Connector'
  s.homepage         = 'https://github.com/scomm-ai/connect_sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'SComm' => 'dev@scomm.ai' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.swift_version = '5.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'OTHER_LDFLAGS' => '$(inherited) -lc++ -force_load "${PODS_TARGET_SRCROOT}/../build/apple/lib/libdatachannel.a"',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../third_party/libdatachannel/include"',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../build/apple/lib"'
  }

  s.script_phase = {
    :name => 'Build libdatachannel (macOS)',
    :script => 'cd "${PODS_TARGET_SRCROOT}/.." && bash tool/build_libdatachannel_apple.sh macos "${CONFIGURATION}"',
    :execution_position => :before_compile
  }
end
