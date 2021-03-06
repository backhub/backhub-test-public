require 'mkmf'

RbConfig::MAKEFILE_CONFIG['CC'] = ENV['CC'] if ENV['CC']

$CFLAGS << " #{ENV["CFLAGS"]}"
$CFLAGS << " -g"
$CFLAGS << " -O3" unless $CFLAGS[/-O\d/]
$CFLAGS << " -Wall -Wno-comment"

def sys(cmd)
  puts " -- #{cmd}"
  unless ret = xsystem(cmd)
    raise "ERROR: '#{cmd}' failed"
  end
  ret
end

def windows?
  RbConfig::CONFIG['host_os'] =~ /mswin|mingw/
end

if !(MAKE = find_executable('gmake') || find_executable('make'))
  abort "ERROR: GNU make is required to build gitfetch."
end

CWD = File.expand_path(File.dirname(__FILE__))
LIBGIT2_DIR = File.join(CWD, '..', 'vendor', 'libgit2')

if !find_executable('cmake')
  abort "ERROR: CMake is required to build libgit2."
end

if !windows? && !find_executable('pkg-config')
  abort "ERROR: pkg-config is required to build libgit2."
end

Dir.chdir(LIBGIT2_DIR) do
  Dir.mkdir("build") if !Dir.exists?("build")

  Dir.chdir("build") do
    puts Dir.pwd
    # On Windows, Ruby-DevKit is MSYS-based, so ensure to use MSYS Makefiles.
    generator = "-G \"MSYS Makefiles\"" if windows?
    sys("cmake .. -DBUILD_CLAR=OFF -DTHREADSAFE=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS=-fPIC -DCMAKE_BUILD_TYPE=RelWithDebInfo #{generator}")
    sys(MAKE)

    # "normal" libraries (and libgit2 builds) get all these when they build but we're doing it
    # statically so we put the libraries in by hand. It's important that we put the libraries themselves
    # in $LIBS or the final linking stage won't pick them up
    if windows?
      $LDFLAGS << " " + "-L#{Dir.pwd}/deps/winhttp"
      $LIBS << " -lwinhttp -lcrypt32 -lrpcrt4 -lole32"
    else
      pcfile = File.join(LIBGIT2_DIR, "build", "libgit2.pc")
      $LDFLAGS << " " + `pkg-config --libs --static #{pcfile}`.strip
    end
  end
end

# Prepend the vendored libgit2 build dir to the $DEFLIBPATH.
#
# By default, $DEFLIBPATH includes $(libpath), which usually points
# to something like /usr/lib for system ruby versions (not those
# installed through rbenv or rvm).
#
# This was causing system-wide libgit2 installations to be preferred
# over of our vendored libgit2 version when building rugged.
#
# By putting the path to the vendored libgit2 library at the front of
# $DEFLIBPATH, we can ensure that our bundled version is always used.
$DEFLIBPATH.unshift("#{LIBGIT2_DIR}/build")
dir_config('git2', "#{LIBGIT2_DIR}/include", "#{LIBGIT2_DIR}/build")

unless have_library 'git2' and have_header 'git2.h'
  abort "ERROR: Failed to build libgit2"
end

# Do the work
create_makefile('gitfetch')