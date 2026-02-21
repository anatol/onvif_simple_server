# Set HAVE_WOLFSSL or HAVE_MBEDTLS variable if you want to use WOLFSSL or
# MBEDTLS instead of LIBTOMCRYPT

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S), Darwin)
    GC_SECTIONS = -Wl,-dead_strip
    RT_LIB =
else
    GC_SECTIONS = -Wl,--gc-sections
    RT_LIB = -lrt
endif

OBJECTS_O = onvif_simple_server.o device_service.o media_service.o media2_service.o ptz_service.o events_service.o deviceio_service.o fault.o conf.o utils_zlib.o log.o ezxml_wrapper.o ezxml/ezxml.o
OBJECTS_N = onvif_notify_server.o conf.o utils.o log.o ezxml_wrapper.o ezxml/ezxml.o
OBJECTS_W = wsd_simple_server.o utils.o log.o ezxml_wrapper.o ezxml/ezxml.o
ifdef HAVE_WOLFSSL
INCLUDE = -DHAVE_WOLFSSL -ffunction-sections -fdata-sections
LIBS_O = $(GC_SECTIONS) -lwolfssl -lz -ljson-c -lpthread $(RT_LIB)
LIBS_N = $(GC_SECTIONS) -lwolfssl -ljson-c -lpthread $(RT_LIB)
else
ifdef HAVE_MBEDTLS
INCLUDE = -DHAVE_MBEDTLS -ffunction-sections -fdata-sections
LIBS_O = $(GC_SECTIONS) -lmbedcrypto -lz -ljson-c -lpthread $(RT_LIB)
LIBS_N = $(GC_SECTIONS) -lmbedcrypto -ljson-c -lpthread $(RT_LIB)
else
INCLUDE = -ffunction-sections -fdata-sections
LIBS_O = $(GC_SECTIONS) -ltomcrypt -lz -ljson-c -lpthread $(RT_LIB)
LIBS_N = $(GC_SECTIONS) -ltomcrypt -ljson-c -lpthread $(RT_LIB)
endif
endif
LIBS_W = $(GC_SECTIONS)

ifdef USE_ZLIB
DUSE_ZLIB = -DUSE_ZLIB
endif

ifeq ($(UNAME_S), Darwin)
    INCLUDE += -I/opt/homebrew/include
    LIBS_O += -L/opt/homebrew/lib
    LIBS_N += -L/opt/homebrew/lib
    LIBS_W += -L/opt/homebrew/lib
endif

ifeq ($(STRIP), )
    STRIP=echo
endif

all: onvif_simple_server onvif_notify_server wsd_simple_server

log.o: log.c $(HEADERS)
	$(CC) -c $< -std=c99 -fPIC -Os $(INCLUDE) -o $@

utils_zlib.o: utils.c $(HEADERS)
	$(CC) -c $< $(DUSE_ZLIB) -fPIC -Os $(INCLUDE) -o $@

%.o: %.c $(HEADERS)
	$(CC) -c $< -fPIC -Os $(INCLUDE) -o $@

onvif_simple_server: $(OBJECTS_O)
	$(CC) $(OBJECTS_O) $(LIBS_O) -fPIC -Os -o $@
	$(STRIP) $@

onvif_notify_server: $(OBJECTS_N)
	$(CC) $(OBJECTS_N) $(LIBS_N) -fPIC -Os -o $@
	$(STRIP) $@

wsd_simple_server: $(OBJECTS_W)
	$(CC) $(OBJECTS_W) $(LIBS_W) -fPIC -Os -o $@
	$(STRIP) $@

.PHONY: clean

clean:
	rm -f onvif_simple_server
	rm -f onvif_notify_server
	rm -f wsd_simple_server
	rm -f $(OBJECTS_O)
	rm -f $(OBJECTS_N)
	rm -f $(OBJECTS_W)
