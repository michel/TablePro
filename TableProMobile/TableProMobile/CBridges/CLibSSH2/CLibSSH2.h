#ifndef CLibSSH2_h
#define CLibSSH2_h

#include <libssh2.h>
#include <libssh2_sftp.h>
#include <libssh2_publickey.h>

// Wrapper functions for libssh2 macros (Swift cannot call C macros directly)

static inline LIBSSH2_SESSION *tablepro_libssh2_session_init(void) {
    return libssh2_session_init();
}

static inline int tablepro_libssh2_session_disconnect(LIBSSH2_SESSION *session,
                                                      const char *description) {
    return libssh2_session_disconnect(session, description);
}

static inline ssize_t tablepro_libssh2_channel_read(LIBSSH2_CHANNEL *channel,
                                                    char *buf,
                                                    size_t buflen) {
    return libssh2_channel_read(channel, buf, buflen);
}

static inline ssize_t tablepro_libssh2_channel_write(LIBSSH2_CHANNEL *channel,
                                                     const char *buf,
                                                     size_t buflen) {
    return libssh2_channel_write(channel, buf, buflen);
}

#endif
