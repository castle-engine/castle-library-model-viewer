cmake_minimum_required(VERSION 3.5)

project(cpp_winapi_library_tester LANGUAGES CXX)

add_executable(cpp_winapi_library_tester
    main.cpp
    ../../castlelib_c_loader.cpp
    ../../castleengine.h
)

if(WIN32)
    set_target_properties(cpp_winapi_library_tester PROPERTIES WIN32_EXECUTABLE TRUE)
    target_link_libraries(cpp_winapi_library_tester PRIVATE opengl32)

    if(MINGW OR CYGWIN)
        target_link_options(cpp_winapi_library_tester PRIVATE -mwindows)
    endif()

    # The example expects castleengine.dll to be available next to the executable.
    add_custom_command(TARGET cpp_winapi_library_tester POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/../../castleengine.dll"
            "$<TARGET_FILE_DIR:cpp_winapi_library_tester>"
    )
endif()
