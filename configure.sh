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
    echo "Setting the option \"MPI\" is incompatible with the OpenMPI thorn. Please remove the option MPI=${MPI}."
    echo 'END ERROR'
    exit 1
fi



################################################################################
# Search
################################################################################

if [ -z "${OPENMPI_DIR}" ]; then
    echo "BEGIN MESSAGE"
    echo "OpenMPI selected, but OPENMPI_DIR not set. Checking some places..."
    echo "END MESSAGE"
    
    FILES="include/mpi.h lib/libmpi.a"
    DIRS="/usr /usr/local /usr/local/mpi /usr/local/packages/mpi /usr/local/apps/mpi /opt/local /usr/lib/openmpi ${HOME} ${HOME}/mpi c:/packages/mpi"
    for dir in $DIRS; do
        OPENMPI_DIR="$dir"
        for file in $FILES; do
            if [ ! -r "$dir/$file" ]; then
                unset OPENMPI_DIR
                break
            fi
        done
        if [ -n "$OPENMPI_DIR" ]; then
            break
        fi
    done
    
    if [ -z "$OPENMPI_DIR" ]; then
        echo "BEGIN MESSAGE"
        echo "OpenMPI not found"
        echo "END MESSAGE"
    else
        echo "BEGIN MESSAGE"
        echo "Found OpenMPI in ${OPENMPI_DIR}"
        echo "END MESSAGE"
    fi
fi



################################################################################
# Build
################################################################################

if [ -z "${OPENMPI_DIR}"                                                  \
     -o "$(echo "${OPENMPI_DIR}" | tr '[a-z]' '[A-Z]')" = 'BUILD' ]
then
    echo "BEGIN MESSAGE"
    echo "Using bundled OpenMPI..."
    echo "END MESSAGE"
    
    # Set locations
    THORN=OpenMPI
    NAME=openmpi-1.5.4
    SRCDIR=$(dirname $0)
    BUILD_DIR=${SCRATCH_BUILD}/build/${THORN}
    if [ -z "${OPENMPI_INSTALL_DIR}"]; then
        INSTALL_DIR=${SCRATCH_BUILD}/external/${THORN}
    else
        echo "BEGIN MESSAGE"
        echo "Installing OpenMPI into ${OPENMPI_INSTALL_DIR} "
        echo "END MESSAGE"
        INSTALL_DIR=${OPENMPI_INSTALL_DIR}
    fi
    DONE_FILE=${SCRATCH_BUILD}/done/${THORN}
    OPENMPI_DIR=${INSTALL_DIR}
    
    if [ -e ${DONE_FILE} -a ${DONE_FILE} -nt ${SRCDIR}/dist/${NAME}.tar.gz \
                         -a ${DONE_FILE} -nt ${SRCDIR}/configure.sh ]
    then
        echo "BEGIN MESSAGE"
        echo "OpenMPI has already been built; doing nothing"
        echo "END MESSAGE"
    else
        echo "BEGIN MESSAGE"
        echo "Building OpenMPI"
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
            echo 'No Fortran 90 compiler available. Building OpenMPI library without Fortran support.'
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
        
        echo "OpenMPI: Preparing directory structure..."
        mkdir build external done 2> /dev/null || true
        rm -rf ${BUILD_DIR} ${INSTALL_DIR}
        mkdir ${BUILD_DIR} ${INSTALL_DIR}
        
        echo "OpenMPI: Unpacking archive..."
        pushd ${BUILD_DIR}
        ${TAR} xzf ${SRCDIR}/dist/${NAME}.tar.gz
        
        echo "OpenMPI: Configuring..."
        cd ${NAME}
        ./configure --prefix=${OPENMPI_DIR}
        
        echo "OpenMPI: Building..."
        ${MAKE}
        
        echo "OpenMPI: Installing..."
        ${MAKE} install
        popd
        
        echo "OpenMPI: Cleaning up..."
        rm -rf ${BUILD_DIR}
        
        date > ${DONE_FILE}
        echo "OpenMPI: Done."
        
        )
        
        if (( $? )); then
            echo 'BEGIN ERROR'
            echo 'Error while building OpenMPI. Aborting.'
            echo 'END ERROR'
            exit 1
        fi
    fi
    
fi



################################################################################
# Configure Cactus
################################################################################

# Set options

if [ "${OPENMPI_DIR}" != '/usr' -a "${OPENMPI_DIR}" != '/usr/local' ]; then
    : ${OPENMPI_INC_DIRS="${OPENMPI_DIR}/include"}
    : ${OPENMPI_LIB_DIRS="${OPENMPI_DIR}/lib"}
fi
: ${OPENMPI_LIBS='mpi mpi_cxx'}

# Pass options to Cactus

echo "BEGIN DEFINE"
echo "CCTK_MPI     1"
echo "HAVE_MPI     1"
echo "HAVE_OPENMPI 1"
echo "END DEFINE"

echo "BEGIN MAKE_DEFINITION"
echo "CCTK_MPI     = 1"
echo "HAVE_MPI     = 1"
echo "HAVE_OPENMPI = 1"
echo "MPI_DIR      = ${OPENMPI_DIR}"
echo "MPI_INC_DIRS = ${OPENMPI_INC_DIRS}"
echo "MPI_LIB_DIRS = ${OPENMPI_LIB_DIRS}"
echo "MPI_LIBS     = ${OPENMPI_LIBS}"
echo "END MAKE_DEFINITION"

echo 'INCLUDE_DIRECTORY $(MPI_INC_DIRS)'
echo 'LIBRARY_DIRECTORY $(MPI_LIB_DIRS)'
echo 'LIBRARY           $(MPI_LIBS)'
