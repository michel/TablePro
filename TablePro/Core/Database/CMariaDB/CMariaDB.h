//
//  CMariaDB.h
//  TablePro
//
//  C bridging header for libmariadb (MariaDB Connector/C)
//  Install: brew install mariadb-connector-c
//

#ifndef CMariaDB_h
#define CMariaDB_h

// Use absolute path to avoid Xcode Build Settings dependency
// This path is for Apple Silicon Macs with Homebrew
#include "/opt/homebrew/opt/mariadb-connector-c/include/mariadb/mysql.h"

#endif /* CMariaDB_h */
