# Install disabled by scommconnector (Flutter desktop bundling).
# Flutter sets CMAKE_INSTALL_PREFIX to $<TARGET_FILE_DIR:...>, which breaks
# third-party install() rules. The shared library is bundled via
# scommconnector_bundled_libraries instead.
