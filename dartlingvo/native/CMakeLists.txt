cmake_minimum_required(VERSION 3.10)
project(lsd_decoder C)

set(CMAKE_C_STANDARD 11)

if(MSVC)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /O2 /W3")
else()
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -Wall -fvisibility=hidden")
endif()

add_library(lsd_decoder SHARED lsd_c_wrapper.c)

if(WIN32)
    set_target_properties(lsd_decoder PROPERTIES SUFFIX ".dll")
elseif(APPLE)
    set_target_properties(lsd_decoder PROPERTIES SUFFIX ".dylib")
else()
    set_target_properties(lsd_decoder PROPERTIES SUFFIX ".so")
endif()
