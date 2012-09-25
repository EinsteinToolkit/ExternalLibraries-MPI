#! /bin/bash

################################################################################
# Prepare
################################################################################

# Set up shell
if [ "$(echo ${VERBOSE} | tr '[:upper:]' '[:lower:]')" = 'yes' ]; then
    set -x                      # Output commands
fi
set -e                          # Abort on errors



################################################################################
# Check for old mechanism
################################################################################

if [ -n "${MPI}" ]; then
    echo 'BEGIN ERROR'
    echo "Setting the option \"MPI\" is incompatible with the MPI thorn. Please remove the option MPI=${MPI}."
    echo 'END ERROR'
    exit 1
fi



################################################################################
# Search
################################################################################

if [ -z "${MPI_DIR}" ]; then
    echo "BEGIN MESSAGE"
    echo "MPI selected, but MPI_DIR not set. Checking some places..."
    echo "END MESSAGE"
    
    FILES="include/mpi.h lib/libmpi.a"
    DIRS="/usr /usr/local /usr/local/mpi /usr/local/packages/mpi /usr/local/apps/mpi /opt/local /usr/lib/openmpi ${HOME} ${HOME}/mpi c:/packages/mpi"
    for dir in $DIRS; do
        MPI_DIR="$dir"
        for file in $FILES; do
            if [ ! -r "$dir/$file" ]; then
                unset MPI_DIR
                break
            fi
        done
        if [ -n "$MPI_DIR" ]; then
            break
        fi
    done
    
    if [ -z "$MPI_DIR" ]; then
        echo "BEGIN MESSAGE"
        echo "MPI not found"
        echo "END MESSAGE"
    else
        echo "BEGIN MESSAGE"
        echo "Found MPI in ${MPI_DIR}"
        echo "END MESSAGE"
    fi
fi



################################################################################
# Build
################################################################################

if [ -z "${MPI_DIR}"                                            \
     -o "$(echo "${MPI_DIR}" | tr '[a-z]' '[A-Z]')" = 'BUILD' ]
then
    echo "BEGIN MESSAGE"
    echo "Using bundled MPI..."
    echo "END MESSAGE"
    
    # Set locations
    THORN=MPI
    NAME=openmpi-1.6.2
    SRCDIR=$(dirname $0)
    BUILD_DIR=${SCRATCH_BUILD}/build/${THORN}
    if [ -z "${MPI_INSTALL_DIR}"]; then
        INSTALL_DIR=${SCRATCH_BUILD}/external/${THORN}
    else
        echo "BEGIN MESSAGE"
        echo "Installing MPI into ${MPI_INSTALL_DIR} "
        echo "END MESSAGE"
        INSTALL_DIR=${MPI_INSTALL_DIR}
    fi
    DONE_FILE=${SCRATCH_BUILD}/done/${THORN}
    MPI_DIR=${INSTALL_DIR}
    
    if [ -e ${DONE_FILE} -a ${DONE_FILE} -nt ${SRCDIR}/dist/${NAME}.tar.gz \
                         -a ${DONE_FILE} -nt ${SRCDIR}/configure.sh ]
    then
        echo "BEGIN MESSAGE"
        echo "MPI has already been built; doing nothing"
        echo "END MESSAGE"
    else
        echo "BEGIN MESSAGE"
        echo "Building MPI"
        echo "END MESSAGE"
        
        # Build in a subshell
        (
        exec >&2                # Redirect stdout to stderr
        if [ "$(echo ${VERBOSE} | tr '[:upper:]' '[:lower:]')" = 'yes' ]; then
            set -x              # Output commands
        fi
        set -e                  # Abort on errors
        cd ${SCRATCH_BUILD}
        
        # Set up environment
        if [ "${F90}" = "none" ]; then
            echo 'BEGIN MESSAGE'
            echo 'No Fortran 90 compiler available. Building MPI library without Fortran support.'
            echo 'END MESSAGE'
            unset FC
            unset FCFLAGS
        else
            export FC="${F90}"
            export FCFLAGS="${F90FLAGS}"
        fi
        export LDFLAGS
        unset LIBS
        unset RPATH
        if echo '' ${ARFLAGS} | grep 64 > /dev/null 2>&1; then
            export OBJECT_MODE=64
        fi
        
        echo "MPI: Preparing directory structure..."
        mkdir build external done 2> /dev/null || true
        rm -rf ${BUILD_DIR} ${INSTALL_DIR}
        mkdir ${BUILD_DIR} ${INSTALL_DIR}
        
        echo "MPI: Unpacking archive..."
        pushd ${BUILD_DIR}
        ${TAR?} xzf ${SRCDIR}/dist/${NAME}.tar.gz
        ${PATCH?} -p0 < ${SRCDIR}/dist/default_outfile.diff
        
        echo "MPI: Configuring..."
        cd ${NAME}
        ./configure --prefix=${MPI_DIR}
        
        echo "MPI: Building..."
        ${MAKE}
        
        echo "MPI: Installing..."
        ${MAKE} install
        popd
        
        echo "MPI: Cleaning up..."
        rm -rf ${BUILD_DIR}
        
        date > ${DONE_FILE}
        echo "MPI: Done."
        
        )
        
        if (( $? )); then
            echo 'BEGIN ERROR'
            echo 'Error while building MPI. Aborting.'
            echo 'END ERROR'
            exit 1
        fi
    fi
    
fi



################################################################################
# Configure Cactus
################################################################################

# Set options

if [ "${MPI_DIR}" != '/usr' -a "${MPI_DIR}" != '/usr/local' ]; then
    : ${MPI_INC_DIRS="${MPI_DIR}/include"}
    : ${MPI_LIB_DIRS="${MPI_DIR}/lib"}
fi
: ${MPI_LIBS='mpi mpi_cxx'}

# Pass options to Cactus

echo "BEGIN DEFINE"
echo "CCTK_MPI 1"
echo "HAVE_MPI 1"
echo "END DEFINE"

echo "BEGIN MAKE_DEFINITION"
echo "CCTK_MPI     = 1"
echo "HAVE_MPI     = 1"
echo "MPI_DIR      = ${MPI_DIR}"
echo "MPI_INC_DIRS = ${MPI_INC_DIRS}"
echo "MPI_LIB_DIRS = ${MPI_LIB_DIRS}"
echo "MPI_LIBS     = ${MPI_LIBS}"
echo "END MAKE_DEFINITION"

echo 'INCLUDE_DIRECTORY $(MPI_INC_DIRS)'
echo 'LIBRARY_DIRECTORY $(MPI_LIB_DIRS)'
echo 'LIBRARY           $(MPI_LIBS)'
