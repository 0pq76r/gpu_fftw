#####
# Cross compilation vars
####

MAKEFLAGS=-j4
RPIARCH=armv7l-unknown-linux-gnueabihf
RPIDIR=~/x-tools/$(RPIARCH)
RPISYSROOT=~/x-tools/$(RPIARCH)/$(RPIARCH)/sysroot
RPICXX=$(RPIDIR)/bin/$(RPIARCH)-g++
RPICC=$(RPIDIR)/bin/$(RPIARCH)-gcc
RPICXXFLAGS=-mcpu=cortex-a53 -mfpu=neon-fp-armv8 -mfloat-abi=hard -O3 -ffast-math \
                    -pipe -fstack-protector --param=ssp-buffer-size=4
RPILDFLAGS=-Wl,-O1,--sort-common,--as-needed,-z,relro

#####
# Regular variables
#####
# See https://gcc.gnu.org/wiki/Visibility for the visibility flag
VISIBILITY= -fvisibility=hidden
CC        = $(RPICC)
CXX       = $(RPICXX)
CFLAGS   += $(RPICXXFLAGS) -std=c99 -Wall -g $(VISIBILITY)
CXXFLAGS += $(RPICXXFLAGS) -std=c++11 -Wall -g  $(VISIBILITY) -fvisibility-inlines-hidden
RELVER    = 1
TARGETLIBS= libgpufftw.so libgpufftwf.so
TARGETEXES= gpu_fftw
SHARED_SRC= gpu_fftw_util.c \
				hello_fft/mailbox.c \
			  	hello_fft/mailbox.c \
			  	hello_fft/gpu_fft.c \
				hello_fft/gpu_fft_base.c \
				hello_fft/gpu_fft_twiddles.c \
				hello_fft/gpu_fft_shaders.c
MAIN_SRC  =

#Skip cross-compiling if the x-tools directory is not present in $HOME
ifneq ($(shell test -d ~/x-tools && echo xcompile),xcompile)
	CC=gcc
	CXX=g++
endif

#TODO: security risk
#RPATH=-Wl,-rpath,'$$ORIGIN/.'
RPATH=

# $(1) - C prefix: fftwf for float and fftw for double
# $(2) - Fortran prefix: s for float and d for double
instantiate=sed -e 's/FPREFIX/$(2)/g' -e 's/PREFIX/$(1)/g' $(3) > $(4)
make_so=$(CC) $(CFLAGS) -shared -fpic -Wl,-soname,libgpu$(1).so -o $@ $^ -ldl -l$(2)

.PHONY: all vsn.h clean fft_update
.NOTPARALLEL: fft_update

all: $(TARGETLIBS) $(TARGETEXES)

########################################################
# Fetch current hello_fft
########################################################
./hello_fft/%.c:
	$(MAKE) fft_update

########################################################
# Shared libs and main executable
########################################################

# Build C source files from the template
# fftw  -> double precission
# fftwf -> single (float) precission
gpu_fftw.c: gpu_fftw.c.template
	$(call instantiate,fftw,d,$<,$@)

gpu_fftwf.c: gpu_fftw.c.template
	$(call instantiate,fftwf,s,$<,$@)

# double precision shared lib
libgpufftw.so.1: gpu_fftw.c $(SHARED_SRC)
	$(call make_so,fftw,fftw3)

libgpufftw.so: libgpufftw.so.$(RELVER)
	ln -sf $< $@

# single precision shared lib
libgpufftwf.so.1: gpu_fftwf.c $(SHARED_SRC)
	$(call make_so,fftwf,fftw3f)

libgpufftwf.so: libgpufftwf.so.$(RELVER)
	ln -sf $< $@

# main executable
vsn.h:
	 VSN="`git describe --always --tags --abbrev=1 | sed 's/^v//'`"; \
		  echo "#define GPU_FFTW_VSN \"$$VSN\"" > vsn.h

gpu_fftw: gpu_fftw_main.cpp vsn.h libgpufftw.so libgpufftwf.so
	$(CXX) $(CXXFLAGS) $(RPATH) -o $@ $< $(MAIN_SRC) -L. -lfftw3f

########################################################
# Clean, update hello_fft from upstream
########################################################
fft_update:
	mkdir -p hello_fft
	cd hello_fft
	svn checkout https://github.com/raspberrypi/firmware/trunk/opt/vc/src/hello_pi/hello_fft

clean:
	rm -f gpu_fftw.c gpu_fftwf.c $(TARGETEXES) *~ **/*~
	for i in $(TARGETLIBS); do \
		rm -f $$i; \
	done

test: gpu_fftw
	LD_PRELOAD="./libgpufftwf.so" GPU_FFTW_DEBUG=7 valgrind --quiet --leak-check=full ./gpu_fftw -t

