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
    error("Setting the option \"MPI\" is incompatible with the MPI thorn. Please remove the option MPI=$ENV{MPI}.",2);
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

my @mpicxx_names = ("mpic++","mpiCC","mpicxx","mpicxx-openmpi-mp","mpicc");

if(!is_set("MPI_DIR")) {
  message("MPI selected, but MPI_DIR is not set. Computing settings...");
  $mpi_build = 1;
  $mpi_search = 1;
} elsif($ENV{MPI_DIR} eq "NO_BUILD") {
  $mpi_dir = $ENV{MPI_DIR};
  $mpi_build = 0;
  $mpi_search = 1;
} elsif($ENV{MPI_DIR} eq "BUILD") {
  $mpi_build = 1;
  $mpi_search = 0;
} elsif($ENV{MPI_DIR} eq "NONE") {
  $mpi_build = 0;
  $mpi_search = 0;
  $mpi_info_set = 1;
  $mpi_dir = '';
  $info = '';
} else {
  if(!-d $ENV{MPI_DIR}) {
    message("MPI_DIR is set to a directory that does not exist (MPI_DIR=$ENV{MPI_DIR}); continuing anyway");
  }
  $mpi_dir = $ENV{MPI_DIR};
  $mpi_build = 0;
  $mpi_search = 0;
  if(is_set("MPI_INC_DIRS") or is_set("MPI_LIB_DIRS") or is_set("MPI_LIBS")) {
    # If some of the MPI variables are set, this is a completely
    # manual configuration.
    $mpi_manual = 1;
  } else {
    # If none of the MPI variables are set, check for the compiler
    # wrapper under MPI_DIR
    $mpi_manual = 0;
    for my $name (@mpicxx_names) {
      my $full_name = "$ENV{MPI_DIR}/bin/$name";
      if(-x $full_name) {
        $mpi_cmd = $full_name;
        last;
      }
    }
    if(defined($mpi_cmd)) {
      message("Found mpi compiler wrapper at $mpi_cmd!");
      mpi_get_info();
    } else {
      message("No mpi compiler wrapper found beneath MPI_DIR (MPI_DIR=$ENV{MPI_DIR})");
    }
  }
}

################################################################################
# Search
################################################################################
if($mpi_search and !defined($mpi_cmd)) {
  for my $name (@mpicxx_names) {
    last if(defined($mpi_cmd));
    $mpi_cmd = which($name);
  }
  if(defined($mpi_cmd)) {
    $mpi_dir = $mpi_cmd;
    $mpi_dir =~ s{/mpi(c\+\+|CC|cc|cxx)[^/]*$}{};
    $mpi_dir =~ s{/bin$}{};
    message("Found mpi compiler wrapper at $mpi_cmd!");
    mpi_get_info();
  }
}

################################################################################
# Build
################################################################################

if($mpi_build and !$mpi_info_set) {
  # check for required tools. Do this here so that we don't require
  # them when using the system library
  unless(defined($ENV{TAR}) and $ENV{TAR} =~ /\S/ and -x which($ENV{TAR})) {
  error(
      "ENV{TAR}=$ENV{TAR}\n" .
      "Could not find tar command. Please make sure that (gnu) tar is present\n" .
      "and that the TAR variable is set to its location.\n",3);
  }
  unless(defined($ENV{PATCH}) and $ENV{PATCH} =~ /\S/ and -x which($ENV{PATCH})) {
    error(
        "Could not find patch command. Please make sure that (gnu) patch is present\n" .
        "and that the PATCH variable is set to its location.\n",4);
  }

  # Set locations
  my $THORN="MPI";
  my $NAME="openmpi-1.6.5";
  #my $NAME=openmpi-1.7.1
  my $INSTALL_DIR = undef;
  my $BUILD_DIR = undef;
  my $SRCDIR = $0;
  $SRCDIR =~ s{(.*)/.*}{$1};
  ${BUILD_DIR}="$ENV{SCRATCH_BUILD}/build/${THORN}";
  if(defined($ENV{MPI_INSTALL_DIR}) and $ENV{MPI_INSTALL_DIR} =~ /\S/) {
    $INSTALL_DIR = "$ENV{MPI_INSTALL_DIR}/${THORN}";
  } else {
    $INSTALL_DIR = "$ENV{SCRATCH_BUILD}/external/${THORN}";
  }
  message("Installing MPI into ${INSTALL_DIR}");
  my $DONE_FILE="$ENV{SCRATCH_BUILD}/done/${THORN}";
  $mpi_dir=${INSTALL_DIR};

  # Setting $mpi_cmd enables the generic
  # search method below to configure the
  # various MPI variables.
  $mpi_cmd="$mpi_dir/bin/mpicc";

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
    error("${INSTALL_DIR} does not exist.",6) unless(-e ${INSTALL_DIR});
    error("${INSTALL_DIR} is not a directory.",6) unless(-d ${INSTALL_DIR});
    error("${INSTALL_DIR} is not readabile.",7) unless(-r ${INSTALL_DIR});
    error("${INSTALL_DIR} is not writeable.",8) unless(-w ${INSTALL_DIR});
    error("${INSTALL_DIR} is not executable.",8) unless(-x ${INSTALL_DIR});
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
  my @incdirs = ();
  my @libdirs = ();
  my @libs = ();
  while($info =~ /\s-I\s*(\S+)/g) {
    push @incdirs, $1;
  }
  while($info =~ /\s-L\s*(\S+)/g) {
    push @libdirs, $1;
  }
  while($info =~ /\s-l(\S+)/g) {
    push @libs, $1;
  }

  $ENV{MPI_DIR}=$mpi_dir;
  $ENV{MPI_INC_DIRS}=join(" ",@incdirs);
  $ENV{MPI_LIB_DIRS}=join(" ",@libdirs);
  $ENV{MPI_LIBS}=join(" ",@libs);

  message("Successfully configured MPI.");
} elsif($mpi_manual) {
  my @incdirs = ();
  my @libdirs = ();
  my @libs = ();
  if (is_set("MPI_INC_DIRS")) {
    push @incdirs, $ENV{MPI_INC_DIRS};
  } else {
    push @incdirs, $ENV{MPI_DIR} . "/include";
  }
  if (is_set("MPI_LIB_DIRS")) {
    push @libdirs, $ENV{MPI_LIB_DIRS};
  } else {
    push @libdirs, $ENV{MPI_DIR} . "/lib64";
    push @libdirs, $ENV{MPI_DIR} . "/lib";
  }
  if (is_set("MPI_LIBS")) {
    push @libs, $ENV{MPI_LIBS};
  } else {
    # do nothing
  }

  $ENV{MPI_INC_DIRS}=join(" ",@incdirs);
  $ENV{MPI_LIB_DIRS}=join(" ",@libdirs);
  $ENV{MPI_LIBS}=join(" ",@libs);

  message("MPI was manually configured.");
} else {
  error("MPI could not be configured: neither automatic nor manual configuration succeeded",5);
}

################################################################################
# Configure Cactus
################################################################################

# Strip standard paths
$ENV{MPI_INC_DIRS} = strip_inc_dirs($ENV{MPI_INC_DIRS});
$ENV{MPI_LIB_DIRS} = strip_lib_dirs($ENV{MPI_LIB_DIRS});

# Pass options to Cactus

begin_message("DEFINE");
print "CCTK_MPI 1\n";
# print "HAVE_MPI 1\n";
end_message();

begin_message("MAKE_DEFINITION");
print "CCTK_MPI     = 1\n";
# print "HAVE_MPI     = 1\n";
print "MPI_DIR      = $ENV{MPI_DIR}\n";
print "MPI_INC_DIRS = $ENV{MPI_INC_DIRS}\n";
print "MPI_LIB_DIRS = $ENV{MPI_LIB_DIRS}\n";
print "MPI_LIBS     = $ENV{MPI_LIBS}\n";
end_message();

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
    my $full_cmd = "$path/$cmd";
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

sub error {
  my ($msg,$errno) = @_;
  $msg =~ s/\n$//;
  begin_message("ERROR");
  print $msg,"\n";
  end_message("ERROR");
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
sub is_set {
  my $var = shift;
  return (defined($ENV{$var}) and !($ENV{$var} =~ /^\s*$/));
}

sub strip_inc_dirs {
  my $dirlist = shift;
  my @dirs = split / /, $dirlist;
  map { s{//}{/}g } @dirs;
  @dirs = grep { !m{^/(usr/(local/)?)?include/?$} } @dirs;
  return join ' ', @dirs;
}
sub strip_lib_dirs {
  my $dirlist = shift;
  my @dirs = split / /, $dirlist;
  map { s{//}{/}g } @dirs;
  @dirs = grep { !m{^/(usr/(local/)?)?lib(64?)/?$} } @dirs;
  return join ' ', @dirs;
}