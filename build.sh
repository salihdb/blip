#!/usr/bin/env bash
version=opt
clean=1
relink=
out=
compiler=
silent="-s"
tests=1
if [ -z "$D_HOME" ] ; then
    D_HOME=$HOME
fi
while [ $# -gt 0 ]
do
    case $1 in
        --help)
            echo "usage: build [--version x] [--quick] [--d-home dHome] [--tango-home tangoHome] "
            echo "           [--verbose] [--build-dir buildDir]"
            echo ""
            echo "  builds mainDFile.d linking tango, blip and all needed libs (lapack, bz2,...)"
            echo "  --version x     builds version x (typically opt or dbg)"
            echo "  --quick         no clean before rebuilding"
            echo "  --verbose       verbose building"
            echo "  --d-home x      uses x as d home (default $D_HOME )"
            echo "  --tango-home x  uses x as tango home"
            echo "  --no-tests      does not compile "
            echo "  --build-dir X   uses X as build dir (you *really* want to use a local"
            echo "                  filesystem like /tmp/$USER/build for building if possible)"
            echo ""
            echo "The script uses '$'DC as compiler if set"
            echo "or the first compiler found if not set."
            exit 0
            ;;
        --version)
          shift
          version=$1
            ;;
        --quick)
            clean=
            ;;
        --verbose)
            silent=
            ;;
        --d-home)
            shift
            D_HOME=$1
            ;;
        --tango-home)
            shift
            TANGO_HOME=$1
            ;;
        --no-tests)
            tests=0
            ;;
        *)
            die "unexpected argument $1"
            break
            ;;
    esac
    shift
done
if [ -z "$TANGO_HOME" ] ; then
    TANGO_HOME=$D_HOME/tango
fi

if [ -z "$compiler" ]; then
    compiler=`$TANGO_HOME/build/tools/guessCompiler.sh --path $DC`
fi
compShort=`$TANGO_HOME/build/tools/guessCompiler.sh $compiler`
if [ "$version" == "opt" ]; then
    libExt=
else
    libExt="-$version"
fi
case $compShort in
    dmd)
    linkFlag="-L"
    extra_libs_comp="-defaultlib=tango-base-${compShort}"
    ;;
    ldc)
    linkFlag="-L="
    extra_libs_comp=
    ;;
    *)
    die "unsupported compiler"
esac
case `uname` in
  Darwin)
  extra_libs_os="${linkFlag}-framework ${linkFlag}Accelerate ${linkFlag}-lz ${linkFlag}-lbz2"
  ;;
  Linux)
  extra_libs_os="${linkFlag}-lgoto2 ${linkFlag}-ldl ${linkFlag}-lz ${linkFlag}-lbz2"
  ;;
  *)
  die "unknown platform, you need to set extra_libs_os"
esac
extra_libs_opt="${linkFlag}-ltango-user-${compShort} $extra_libs_os $extra_libs_comp"
extra_libs_dbg="${linkFlag}-ltango-user-${compShort}-dbg $extra_libs_os $extra_libs_comp"
case $version in
    opt)
    extra_libs="$extra_libs_opt"
    ;;
    dbg)
    extra_libs="$extra_libs_dbg"
    ;;
    *)
    echo "unknown version, guessing extra_libs"
    extra_libs="${linkFlag}-ltango-user-${compShort}-${version} $extra_libs_os $extra_libs_comp"
esac

if [ -n "$clean" ]; then
    make $silent distclean
fi
rm libblip-*
make $silent EXTRA_LIBS="$extra_libs_opt" VERSION=opt lib
make $silent EXTRA_LIBS="$extra_libs_dbg" VERSION=dbg lib
if [ -n "$tests" ] ; then
    make $silent EXTRA_LIBS="$extra_libs" VERSION=$version
fi
installDir=`dirname $compiler`/../lib
echo "cp libblip-* $installDir"
cp libblip-* $installDir
