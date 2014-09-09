#!/usr/bin/perl
use Carp;
use strict;
use FileHandle;
use Cwd;
$/ = undef;

# Used by pushd/popd
my @push_dirs = ();

# Used by begin/end message
my @messages = ();

# Used by sys()
my $aborted = 0;

################################################################################
# Prepare
################################################################################

# Set up shell
my $verbose = 0;
$verbose = 1 if($ENV{VERBOSE} =~ /^yes$/i);

################################################################################
# Check for old mechanism
################################################################################

if(defined($ENV{MPI})) {
    begin_message("ERROR");
    print "Setting the option \"MPI\" is incompatible with the MPI thorn. Please remove the option MPI=$ENV{MPI}.\n";
    end_message();
    exit 2;
}

################################################################################
# Determine whether to build and/or search
################################################################################

my $info = undef;
my $mpi_info_set = 0;
my $mpi_dir = undef;
my $mpi_cmd = undef;
my $mpi_search = 1;
my $mpi_build = 0;
my $mpi_manual = 0;

if("$ENV{MPI_DIR}" =~ /^\s*$/) {
  message("MPI selected, but MPI_DIR is not set. Computing settings...");
  $mpi_build = 1;
  $mpi_search = 1;
} elsif(-d $ENV{MPI_DIR} or $ENV{MPI_DIR} eq "NO_BUILD") {
  $mpi_dir = $ENV{MPI_DIR};
  $mpi_search = 0;
  $mpi_build = 0;
  $mpi_manual = 1;
} elsif($ENV{MPI_DIR} eq "BUILD") {
  $mpi_build = 1;
  $mpi_search = 0;
} else {
  $mpi_build = 1;
  $mpi_search = 1;
}

################################################################################
# Search
################################################################################
if($mpi_search and !defined($mpi_cmd)) {
  $mpi_cmd = which("mpicc");
  if(defined($mpi_cmd)) {
    $mpi_dir = $mpi_cmd;
    $mpi_dir =~ s{/mpicc$}{};
    $mpi_dir =~ s{/bin$}{};
    message("Found mpicc at $mpi_cmd!");
    mpi_get_info();
  }
}

################################################################################
# Build
################################################################################

if($mpi_build and !$mpi_info_set) {
  # check for required tools. Do this here so that we don't require them when
  # using the system library
  unless(defined($ENV{TAR}) and $ENV{TAR} =~ /\S/ and -x which($ENV{TAR})) {
    begin_message("ERROR");
    print "ENV{TAR}=$ENV{TAR}\n";
    print "Could not find tar command. Please make sure that (gnu) tar is present\n";
    print "and that the TAR variable is set to its location.\n";
    end_message();
    exit 3;
  }
  unless(defined($ENV{PATCH}) and $ENV{PATCH} =~ /\S/ and -x which($ENV{PATCH})) {
    begin_message("ERROR");
    print "Could not find patch command. Please make sure that (gnu) patch is present\n";
    print "and that the PATCH variable is set to its location.\n";
    end_message();
    exit 4;
  }

  # Set locations
  my $THORN="MPI";
  my $NAME="openmpi-1.6.5";
  #my $NAME=openmpi-1.7.1
  my $INSTALL_DIR = undef;
  my $BUILD_DIR = undef;
  my $SRCDIR = $0;
  $SRCDIR =~ s{(.*)/.*}{$1};
  ${BUILD_DIR}=$ENV{SCRATCH_BUILD}."/build/".${THORN};
  if(defined($ENV{MPI_INSTALL_DIR}) and $ENV{MPI_INSTALL_DIR} =~ /\S/) {
    $INSTALL_DIR = "$ENV{MPI_INSTALL_DIR}/${THORN}";
  } else {
    $INSTALL_DIR = "$ENV{SCRATCH_BUILD}/external/${THORN}";
  }
  message("Installing MPI into ${INSTALL_DIR}");
  my $DONE_FILE=${INSTALL_DIR}."/done_".${THORN};
  $mpi_dir=${INSTALL_DIR};

  # Setting $mpi_cmd enables the generic
  # search method below to configure the
  # various MPI variables.
  $mpi_cmd=$mpi_dir."/bin/mpicc";

  if(-r ${DONE_FILE}) {
    message("MPI has already been built; doing nothing");
  } else {
    message("Building MPI");
    message("Using bundled MPI...");

    chdir($ENV{SCRATCH_BUILD});

# Set up environment
# Disable ccache: remove "ccache" and all options that follow
# Note: we can use only basic sed regexps here
#export CC=$(echo '' ${CC} '' |
#    sed -e 's/ ccache  *\(-[^ ]*  *\)*/ /g;s/^ //;s/ $//')
#export CXX=$(echo '' ${CXX} '' |
#    sed -e 's/ ccache  *\(-[^ ]*  *\)*/ /g;s/^ //;s/ $//')
    $ENV{CC} =~ s/ ccache .*//;
    $ENV{CXX} =~ s/ ccache .*//;
    if($ENV{F90} =~ /none/) {
      message("No Fortran 90 compiler available. Building MPI library without Fortran support.");
      $ENV{FC}=undef;
      $ENV{FCFLAGS}=undef;
    } else {
      $ENV{FC} = $ENV{F90};
      $ENV{FCFLAGS} = $ENV{F90FLAGS};
    }
    $ENV{LIBS}=undef;
    $ENV{RPATH}=undef;
    if($ENV{ARFLAGS} =~ /64/) {
      $ENV{OBJECT_MODE}="64";
    }

    message("MPI: Preparing directory structure...");
    mkdir("external");
    mkdir("done");
    sys("rm -rf ${BUILD_DIR} ${INSTALL_DIR}");
    mkdir(${BUILD_DIR});
    mkdir(${INSTALL_DIR});
    fatal_message("${INSTALL_DIR} does not exist.",6) unless(-e ${INSTALL_DIR});
    fatal_message("${INSTALL_DIR} is not a directory.",6) unless(-d ${INSTALL_DIR});
    fatal_message("${INSTALL_DIR} is not readabile.",7) unless(-r ${INSTALL_DIR});
    fatal_message("${INSTALL_DIR} is not writeable.",8) unless(-w ${INSTALL_DIR});
    fatal_message("${INSTALL_DIR} is not executable.",8) unless(-x ${INSTALL_DIR});
    $mpi_dir = $ENV{MPI_DIR} = ${INSTALL_DIR};

    message("MPI: Unpacking archive...");
    pushd(${BUILD_DIR});
    sys("$ENV{TAR} xzf ${SRCDIR}/dist/${NAME}.tar.gz");
    sys("$ENV{PATCH} -p0 < ${SRCDIR}/dist/default_outfile-1.6.5.patch");
    chdir(${NAME});
    sys("$ENV{PATCH} -p0 < ${SRCDIR}/dist/cuda_build_fix__svn29754");

    message("MPI: Configuring...");
# Cannot have a memory manager with a static library on some
# systems (e.g. Linux); see
# <http://www.open-mpi.org/faq/?category=mpi-apps#static-mpi-apps>
    sys("./configure --prefix=$mpi_dir --without-memory-manager --without-libnuma --enable-shared=no --enable-static=yes");

    message("MPI: Building...");
    sys("$ENV{MAKE}");

    message("MPI: Installing...");
    sys("$ENV{MAKE} install");
    popd();

    message("MPI: Cleaning up...");
    sys("rm -rf ${BUILD_DIR}");

    sys("date > ${DONE_FILE}");
    message("MPI: Done.");
  }
  mpi_get_info();
}

################################################################################
# Configure MPI options
################################################################################

if($mpi_info_set) {
  my @libdirs = ();
  my @incdirs = ();
  my @libs = ();
  while($info =~ /\s-L\s*(\S+)/g) {
    push @libdirs, $1;
  }
  while($info =~ /\s-I\s*(\S+)/g) {
    push @incdirs, $1;
  }
  while($info =~ /\s-l(\w+)/g) {
    push @libs, $1;
  }

  $ENV{MPI_DIR}=$mpi_dir;
  $ENV{MPI_INC_DIRS}=join(" ",@incdirs);
  $ENV{MPI_LIB_DIRS}=join(" ",@libdirs);
  $ENV{MPI_LIBS}=join(" ",@libs);

  message("Successfully configured MPI.");
} elsif($mpi_manual) {
  message("MPI was manually configured.");
} else {
  message("MPI could not be configured.");
  exit 5;
}

################################################################################
# Configure Cactus
################################################################################

# Pass options to Cactus

begin_message("DEFINE");
print "CCTK_MPI 1\n";
print "HAVE_MPI 1\n";
end_message();

begin_message("MAKE_DEFINITION");
print "CCTK_MPI     = 1\n";
print "HAVE_MPI     = 1\n";
print "MPI_DIR      = $ENV{MPI_DIR}\n";
print "MPI_INC_DIRS = $ENV{MPI_INC_DIRS}\n";
print "MPI_LIB_DIRS = $ENV{MPI_LIB_DIRS}\n";
print "MPI_LIBS     = $ENV{MPI_LIBS}\n";
end_message();

# These must be magic
print "INCLUDE_DIRECTORY \$(MPI_INC_DIRS)\n";
print "LIBRARY_DIRECTORY \$(MPI_LIB_DIRS)\n";
print "LIBRARY           \$(MPI_LIBS)\n";

################################################################################
# Functions
################################################################################

sub pushd {
  push @push_dirs, Cwd::getcwd();
  chdir(shift);
}
sub popd {
  chdir(shift @push_dirs);
}
sub which {
  my $cmd = shift;
  for my $path (split(/:/,$ENV{PATH})) {
    my $full_cmd = $path."/".$cmd;
    if(-x $full_cmd) {
      return $full_cmd;
    }
  }
  return undef;
}

sub sys {
  my $cmd = shift;
  return unless($aborted == 0);
  $aborted = system("$cmd 1>&2");
}

sub mpi_get_info {
  my $fd = new FileHandle;
  open($fd,"$mpi_cmd -compile_info 2>/dev/null|");
  $info = <$fd>;
  close($fd);
  if($info eq "") {
    open($fd,"$mpi_cmd --showme 2>/dev/null|");
    $info = <$fd>;
    close($fd);
  }
  if($info eq "") {
    # The command, mpicc, is quite often a shell script.
    # Run it with -x to trace, and find the compile command.
    open($fd,"sh -x $mpi_cmd /dev/null 2>/dev/null|");
    my $contents = <$fd>;
    if($contents =~ /\w+cc.*-I\/.*-lmpi.*/) {
      $info = $&;
    }
  }
  if($info =~ /^\s*$/) {
    $mpi_info_set = 0;
  } else {
    $mpi_info_set = 1;
  }
}

sub fatal_message {
  my ($msg,$errno) = @_;
  message($msg);
  exit $errno;
}
sub message {
  my $msg = shift;
  $msg =~ s/\n$//;
  begin_message();
  print $msg,"\n";
  end_message();
}
sub begin_message {
  my $msg = shift;
  my $oldmsg = "";
  $msg = "MESSAGE" unless(defined($msg));
  $oldmsg = $messages[$#messages] if($#messages >= 0);
  push @messages, $msg;
  Carp::carp() unless(defined($msg));
  Carp::carp() unless(length($msg)>3);
  unless($oldmsg eq $msg) {
    print "END $oldmsg\n" unless($oldmsg eq "");
    print "BEGIN $msg\n";
  }
}
sub end_message {
  my $msg = pop @messages;
  my $oldmsg = "";
  $oldmsg = $messages[$#messages] if($#messages >= 0);
  Carp::carp() unless(defined($msg));
  Carp::carp() unless(length($msg)>3);
  unless($oldmsg eq $msg) {
    print "END $msg\n";
    print "BEGIN $oldmsg\n" unless($oldmsg eq "");
  }
}
