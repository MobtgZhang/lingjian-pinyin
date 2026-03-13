find_package(Qt6 COMPONENTS Widgets REQUIRED)

set(CMAKE_AUTOMOC ON)

add_executable(lingjian_ui
    main.cpp
    candidate_view.cpp
    candidate_view.h
    status_bar.cpp
    status_bar.h
    status_bar_menu.cpp
    status_bar_menu.h
    theme_manager.cpp
    theme_manager.h
    skin_loader.cpp
    skin_loader.h
    skin_selector.cpp
    skin_selector.h
    input_widget.cpp
    input_widget.h
)

target_link_libraries(lingjian_ui
    PRIVATE
        Qt6::Widgets
        lingjian_core
)

target_include_directories(lingjian_ui
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
)
