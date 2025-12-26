//
//  CLibPQ.h
//  TablePro
//
//  C bridging header for libpq (PostgreSQL C API)
//  Install: brew install libpq
//

#ifndef CLibPQ_h
#define CLibPQ_h

// Use absolute path to avoid Xcode Build Settings dependency
// This path is for Apple Silicon Macs with Homebrew
#include "/opt/homebrew/opt/libpq/include/libpq-fe.h"

#endif /* CLibPQ_h */
