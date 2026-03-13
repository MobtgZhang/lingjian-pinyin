cmake_minimum_required(VERSION 3.16)
project(LingJianPinyin VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 所有目标启用 PIC，确保静态库能链接到共享库（fcitx5 addon）
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(BUILD_UI "Build standalone UI process" ON)
option(BUILD_FCITX5 "Build Fcitx5 input method addon" ON)

if(BUILD_FCITX5)
    find_package(Fcitx5Core 5.0 QUIET)
    if(NOT Fcitx5Core_FOUND)
        message(WARNING
            "Fcitx5Core not found. Install libfcitx5core-dev (Ubuntu/Debian) "
            "or fcitx5-devel (Fedora). Skipping fcitx5 addon build.")
        set(BUILD_FCITX5 OFF)
    else()
        message(STATUS "Fcitx5 found — will build input method addon")
        message(STATUS "  FCITX_INSTALL_ADDONDIR   = ${FCITX_INSTALL_ADDONDIR}")
        message(STATUS "  FCITX_INSTALL_PKGDATADIR = ${FCITX_INSTALL_PKGDATADIR}")
    endif()
endif()

add_subdirectory(src)
