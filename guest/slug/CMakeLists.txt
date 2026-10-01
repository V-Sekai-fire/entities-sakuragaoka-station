cmake_minimum_required(VERSION 3.16)
project(sakuragaoka_slug C CXX)

# slug.elf: the port's canvas-texture compute (guest/slug/main.cpp, slug_api.cpp) on slughorn
# (3-interactor/slughorn, main: ThorVG SVG loader + sw engine, Clipper2, earcut).
#
# Two trees from this one file:
#  - riscv64 (build.sh passes the sysroot's toolchain file): slug.elf, a godot-sandbox guest,
#    installed at the port root next to its slug.elf.uid (res://slug.elf, core/slug/guest.gd).
#  - host (no toolchain file): slug_native, the same slug_api.cpp under a native harness
#    (tests/native.cpp) that loads every addons/sakuragaoka_station/slug/svg/<key>.svg.
#
# Modelled on 1-transport/meshing-pen/CMakeLists.txt.

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The port lives at 4-entities/sakuragaoka-station; WEFT_ROOT is the manifest checkout's root.
set(WEFT_ROOT "${CMAKE_SOURCE_DIR}/../../../.." CACHE PATH "Root of the manifest checkout")
get_filename_component(WEFT_ROOT "${WEFT_ROOT}" ABSOLUTE)
set(PORT_ROOT "${CMAKE_SOURCE_DIR}/../.." CACHE PATH "The port's project root (res://)")
get_filename_component(PORT_ROOT "${PORT_ROOT}" ABSOLUTE)
set(SLUGHORN_ROOT "${WEFT_ROOT}/3-interactor/slughorn" CACHE PATH "slughorn checkout (main)")
set(GUEST_RUNTIME_ROOT ${WEFT_ROOT}/2-contract/guest-runtime)

set(SLUG_RISCV OFF)
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "riscv64")
	set(SLUG_RISCV ON)
endif()

# A committed ELF names neither the machine nor the checkout it was built in.
if(SLUG_RISCV)
	add_compile_options("-ffile-prefix-map=${CMAKE_SOURCE_DIR}/=" "-ffile-prefix-map=${SLUGHORN_ROOT}/=slughorn/")
endif()

# ---- slughorn (+ ThorVG, Clipper2, earcut) -------------------------------------------------------
# Only what the guest uses: no serial (nlohmann), no NanoSVG, no FreeType, no msdfgen. ThorVG is
# built single-threaded (SLUGHORN_THORVG_THREADS=OFF): the sandbox has no threads to give it.
foreach(opt SLUGHORN_SERIAL SLUGHORN_NANOSVG SLUGHORN_FREETYPE SLUGHORN_SDF SLUGHORN_BLEND2D
		SLUGHORN_RENDER_PARALLEL SLUGHORN_BUILD_TESTS SLUGHORN_BUILD_EXAMPLES SLUGHORN_THORVG_THREADS)
	set(${opt} OFF CACHE BOOL "" FORCE)
endforeach()
foreach(opt SLUGHORN_THORVG SLUGHORN_CLIPPER2 SLUGHORN_TESSELLATE SLUGHORN_MESHOPT)
	set(${opt} ON CACHE BOOL "" FORCE)
endforeach()
set(SLUGHORN_MESHOPTIMIZER_DIR "${WEFT_ROOT}/2-contract/meshoptimizer" CACHE PATH "" FORCE)
add_subdirectory(${SLUGHORN_ROOT} slughorn EXCLUDE_FROM_ALL)

# No FMA contraction anywhere: rv64gc has FMA and x86-64 baseline does not, so with contraction the
# ELF and the native harness (the parity oracle) would round differently and bake different
# triangle counts (same rule as lasso.cmake / ggml-rd's CPU fallback).
set(SLUG_FP_FLAGS "")
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
	set(SLUG_FP_FLAGS -ffp-contract=off)
	foreach(lib slughorn slughorn_thorvg slughorn_clipper2 slughorn_meshopt)
		target_compile_options(${lib} PRIVATE ${SLUG_FP_FLAGS})
	endforeach()
endif()

if(SLUG_RISCV)
	# slughorn's own -Werror set is for its CI hosts; the cross build keeps it (it is clean) but
	# ThorVG / Clipper2 already build warning-free (-w) as vendored code.
	set(DOWNLOAD_RUNTIME_API OFF CACHE BOOL "" FORCE)
	add_subdirectory(${GUEST_RUNTIME_ROOT}/vendor/sandbox-api/cmake sandbox_api)

	# The libraries build at sandbox-api's -march/-mabi too (same ABI, lp64d).
	foreach(lib slughorn slughorn_thorvg slughorn_clipper2 slughorn_meshopt)
		target_compile_options(${lib} PRIVATE $<TARGET_PROPERTY:sandbox_api,INTERFACE_COMPILE_OPTIONS>)
	endforeach()

	add_library(slug_core STATIC slug_api.cpp)
	target_include_directories(slug_core PUBLIC ${CMAKE_SOURCE_DIR})
	target_link_libraries(slug_core PUBLIC slughorn)
	target_compile_options(slug_core PRIVATE $<TARGET_PROPERTY:sandbox_api,INTERFACE_COMPILE_OPTIONS> ${SLUG_FP_FLAGS})

	# A host refuses a guest built for the other real_t, so DOUBLE_PRECISION=ON is slug.double.elf.
	set(SLUG_ELF_NAME slug.elf)
	if(DOUBLE_PRECISION)
		set(SLUG_ELF_NAME slug.double.elf)
	endif()

	add_sandbox_program(slug main.cpp)
	target_link_libraries(slug PRIVATE slug_core -lm -lstdc++)
	add_custom_command(TARGET slug POST_BUILD
		COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:slug> ${PORT_ROOT}/${SLUG_ELF_NAME}
		COMMENT "Installing ${SLUG_ELF_NAME} at the port root"
	)
else()
	add_library(slug_core STATIC slug_api.cpp)
	target_include_directories(slug_core PUBLIC ${CMAKE_SOURCE_DIR})
	target_link_libraries(slug_core PUBLIC slughorn)
	target_compile_options(slug_core PRIVATE ${SLUG_FP_FLAGS})

	add_executable(slug_native tests/native.cpp)
	target_link_libraries(slug_native PRIVATE slug_core)
	target_compile_definitions(slug_native PRIVATE SLUG_SVG_DIR="${PORT_ROOT}/addons/sakuragaoka_station/slug/svg")
endif()
