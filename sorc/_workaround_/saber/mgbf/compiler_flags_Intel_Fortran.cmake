# (C) Copyright 2019 UCAR
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

####################################################################
# FLAGS COMMON TO ALL BUILD TYPES
####################################################################

####################################################################
# RELEASE FLAGS
####################################################################

#cltorg set( CMAKE_Fortran_FLAGS_RELEASE "-O3 -ip -unroll -inline -no-heap-arrays" )
set( CMAKE_Fortran_FLAGS_RELEASE "-O3 -ip -unroll -inline -no-heap-arrays -fpp" )

####################################################################
# DEBUG FLAGS
####################################################################

#cltorg set( CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g -check bounds -traceback -warn -heap-arrays -fpe-all=0 -fpe:0 -check all" )
set( CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g -check bounds -traceback -warn -heap-arrays -fpe-all=0 -fpe:0 -check all -fpp" )

####################################################################
# BIT REPRODUCIBLE FLAGS
####################################################################

set( CMAKE_Fortran_FLAGS_BIT     "-O2 -ip -ipo -unroll -inline -no-heap-arrays" )

####################################################################
# LINK FLAGS
####################################################################

set( CMAKE_Fortran_LINK_FLAGS    "" )

####################################################################

# Meaning of flags
# ----------------
# todo

