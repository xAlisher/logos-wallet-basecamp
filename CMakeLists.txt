cmake_minimum_required(VERSION 3.14)
project(WalletPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    # ── Nix builder path ────────────────────────────────────────────────────────
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
    logos_module(
        NAME logos_wallet
        SOURCES
            src/plugin/WalletPlugin.h
            src/plugin/WalletPlugin.cpp
        INCLUDE_DIRS
            src
    )
else()
    # ── Local dev path (cmake -B build && cmake --build build) ─────────────────
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_AUTOMOC ON)
    set(CMAKE_INCLUDE_CURRENT_DIR ON)

    list(PREPEND CMAKE_PREFIX_PATH "$ENV{HOME}/Qt/6.9.3/gcc_64")
    find_package(Qt6 REQUIRED COMPONENTS Core Qml Network)
    qt_standard_project_setup()

    if(DEFINED ENV{LOGOS_LIBLOGOS_HEADERS})
        set(LOGOS_LIBLOGOS_HEADERS "$ENV{LOGOS_LIBLOGOS_HEADERS}")
    else()
        set(LOGOS_LIBLOGOS_HEADERS
            "/nix/store/092zxk8qbm9zxqigq1z0a5l901a068cz-logos-liblogos-headers-0.1.0/include")
    endif()

    if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
        set(LOGOS_CPP_SDK "$ENV{LOGOS_CPP_SDK_ROOT}")
    else()
        set(LOGOS_CPP_SDK
            "/nix/store/047dmhc4gi7yib02i1fbwidxpksqvcc2-logos-cpp-sdk")
    endif()

    add_library(logos_wallet_plugin MODULE
        src/plugin/WalletPlugin.h
        src/plugin/WalletPlugin.cpp
    )
    set_target_properties(logos_wallet_plugin PROPERTIES
        PREFIX ""
        OUTPUT_NAME "logos_wallet_plugin"
    )
    target_include_directories(logos_wallet_plugin PRIVATE
        src
        "${LOGOS_LIBLOGOS_HEADERS}"
        "${LOGOS_CPP_SDK}/include"
        "${LOGOS_CPP_SDK}/include/cpp"
        "${LOGOS_CPP_SDK}/include/core"
    )
    target_link_libraries(logos_wallet_plugin PRIVATE
        Qt6::Core
        Qt6::Qml
        Qt6::Network
        "${LOGOS_CPP_SDK}/lib/liblogos_sdk.a"
        dl pthread
    )

    # ── Tests ──────────────────────────────────────────────────────────────────
    enable_testing()
    find_package(Qt6 REQUIRED COMPONENTS Test)

    add_executable(test_wallet_plugin
        tests/test_wallet_plugin.cpp
        tests/logos_api_stub.cpp
        src/plugin/WalletPlugin.h
        src/plugin/WalletPlugin.cpp
        "${LOGOS_CPP_SDK}/include/cpp/logos_api.h"
    )
    target_include_directories(test_wallet_plugin PRIVATE
        src
        "${LOGOS_LIBLOGOS_HEADERS}"
        "${LOGOS_CPP_SDK}/include"
        "${LOGOS_CPP_SDK}/include/cpp"
        "${LOGOS_CPP_SDK}/include/core"
    )
    target_link_libraries(test_wallet_plugin PRIVATE
        Qt6::Core
        Qt6::Test
        Qt6::Network
        dl pthread
    )
    add_test(NAME test_wallet_plugin COMMAND test_wallet_plugin)

    # ── Install paths ──────────────────────────────────────────────────────────
    set(LOGOS_APP_DATA "$ENV{HOME}/.local/share/Logos/LogosApp")
    set(WALLET_MODULE_DIR "${LOGOS_APP_DATA}/modules/logos_wallet")
    set(WALLET_UI_DIR     "${LOGOS_APP_DATA}/plugins/wallet_ui")

    install(CODE "
        set(_modules_dir \"\\$ENV{DESTDIR}${LOGOS_APP_DATA}/modules\")
        file(GLOB _old \"\${_modules_dir}/logos_wallet*\")
        foreach(_dir \${_old})
            file(REMOVE_RECURSE \"\${_dir}\")
        endforeach()
    ")

    install(TARGETS logos_wallet_plugin LIBRARY DESTINATION "${WALLET_MODULE_DIR}")
    install(FILES
        modules/logos_wallet/manifest.json
        modules/logos_wallet/metadata.json
        DESTINATION "${WALLET_MODULE_DIR}"
    )
    install(FILES
        plugins/wallet_ui/manifest.json
        plugins/wallet_ui/metadata.json
        plugins/wallet_ui/variant
        DESTINATION "${WALLET_UI_DIR}"
    )
    install(FILES
        plugins/wallet_ui/qml/Main.qml
        DESTINATION "${WALLET_UI_DIR}/qml"
    )
    install(FILES
        assets/icons/wallet.png
        DESTINATION "${WALLET_UI_DIR}/icons"
    )

    # Patch RUNPATH so Qt libs resolve correctly when loaded from LogosApp AppImage
    find_program(PATCHELF_EXECUTABLE patchelf)
    if(PATCHELF_EXECUTABLE)
        install(CODE "
            set(_plugin \"${WALLET_MODULE_DIR}/logos_wallet_plugin.so\")
            set(_build_so \"${CMAKE_BINARY_DIR}/logos_wallet_plugin.so\")
            if(EXISTS \"\${_plugin}\")
                execute_process(
                    COMMAND bash -c \"ldd '\${_build_so}' | grep nix/store | awk '{print \\\$3}' | xargs -I{} dirname {} | sort -u | tr '\\n' ':' | sed 's/:$//'\"
                    OUTPUT_VARIABLE _nix_paths
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                )
                set(_qt_lib \"\$ENV{HOME}/Qt/6.9.3/gcc_64/lib\")
                set(_rpath \"\\\$ORIGIN:\${_nix_paths}:\${_qt_lib}:/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu\")
                execute_process(
                    COMMAND ${PATCHELF_EXECUTABLE} --set-rpath \"\${_rpath}\" \"\${_plugin}\"
                )
                message(STATUS \"Patched RUNPATH on logos_wallet_plugin.so\")
            endif()
        ")
    endif()

    # Mirror to LogosBasecamp
    install(CODE "
        set(_mod_src \"${WALLET_MODULE_DIR}\")
        set(_mod_dst \"\$ENV{HOME}/.local/share/Logos/LogosBasecamp/modules/logos_wallet\")
        file(COPY \"\${_mod_src}/\" DESTINATION \"\${_mod_dst}\")

        set(_ui_src \"${WALLET_UI_DIR}\")
        set(_ui_dst \"\$ENV{HOME}/.local/share/Logos/LogosBasecamp/plugins/wallet_ui\")
        file(GLOB _ui_files \"\${_ui_src}/*\")
        foreach(_f \${_ui_files})
            file(COPY \"\${_f}\" DESTINATION \"\${_ui_dst}\")
        endforeach()
        message(STATUS \"Mirror to LogosBasecamp complete\")
    ")
endif()
