find_package(Fcitx5Core 5.0 REQUIRED)
find_package(Fcitx5Utils REQUIRED)

add_library(lingjian MODULE
    lingjian.cpp
)

set_target_properties(lingjian PROPERTIES
    PREFIX ""
)

target_link_libraries(lingjian
    PRIVATE
        Fcitx5::Core
        Fcitx5::Utils
        lingjian_core
)

target_include_directories(lingjian PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_compile_definitions(lingjian PRIVATE
    LINGJIAN_PKGDATADIR="${FCITX_INSTALL_PKGDATADIR}/lingjian"
)

configure_file(lingjian-addon.conf.in lingjian-addon.conf @ONLY)
configure_file(lingjian-im.conf.in lingjian-im.conf @ONLY)

install(TARGETS lingjian
    DESTINATION "${FCITX_INSTALL_ADDONDIR}")

install(FILES "${CMAKE_CURRENT_BINARY_DIR}/lingjian-addon.conf"
    DESTINATION "${FCITX_INSTALL_PKGDATADIR}/addon"
    RENAME "lingjian.conf")

install(FILES "${CMAKE_CURRENT_BINARY_DIR}/lingjian-im.conf"
    DESTINATION "${FCITX_INSTALL_PKGDATADIR}/inputmethod"
    RENAME "lingjian.conf")

install(FILES "${CMAKE_SOURCE_DIR}/data/pinyin_dict.txt"
    DESTINATION "${FCITX_INSTALL_PKGDATADIR}/lingjian")
