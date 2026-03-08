//
//  oci_stub.h - Oracle OCI stub header
//  Swift-compatible bridge: real Oracle Instant Client provides the implementation.
//
#ifndef _OCI_STUB_H_
#define _OCI_STUB_H_

#include <stdint.h>

// Basic OCI types
typedef int32_t sword;
typedef uint32_t ub4;
typedef uint16_t ub2;
typedef uint8_t ub1;
typedef int32_t sb4;
typedef int16_t sb2;
typedef int8_t sb1;
typedef char OraText;
typedef unsigned char oraub8_t;
typedef int64_t orasb8_t;

// OCI Return codes
#define OCI_SUCCESS            0
#define OCI_SUCCESS_WITH_INFO  1
#define OCI_NO_DATA          100
#define OCI_ERROR             -1
#define OCI_INVALID_HANDLE    -2
#define OCI_NEED_DATA         99
#define OCI_STILL_EXECUTING   -3123

// OCI Handle types
#define OCI_HTYPE_ENV         1
#define OCI_HTYPE_ERROR       2
#define OCI_HTYPE_SVCCTX      3
#define OCI_HTYPE_STMT        4
#define OCI_HTYPE_SERVER      8
#define OCI_HTYPE_SESSION     9
#define OCI_HTYPE_AUTHINFO   12

// OCI Descriptor types
#define OCI_DTYPE_PARAM      53

// OCI Attribute types
#define OCI_ATTR_SERVER       6
#define OCI_ATTR_SESSION      7
#define OCI_ATTR_USERNAME    22
#define OCI_ATTR_PASSWORD    23
#define OCI_ATTR_DATA_TYPE   24
#define OCI_ATTR_DATA_SIZE   25
#define OCI_ATTR_NAME        26
#define OCI_ATTR_PRECISION   27
#define OCI_ATTR_SCALE       28
#define OCI_ATTR_IS_NULL     29
#define OCI_ATTR_ROW_COUNT   30
#define OCI_ATTR_NUM_COLS    31
#define OCI_ATTR_PARAM_COUNT 32

// OCI Data types
#define SQLT_CHR      1    // VARCHAR2
#define SQLT_NUM      2    // NUMBER
#define SQLT_INT      3    // INTEGER
#define SQLT_FLT      4    // FLOAT
#define SQLT_STR      5    // NULL-terminated STRING
#define SQLT_LNG      8    // LONG
#define SQLT_RID     11    // ROWID
#define SQLT_DAT     12    // DATE
#define SQLT_BIN     23    // RAW
#define SQLT_LBI     24    // LONG RAW
#define SQLT_AFC     96    // CHAR
#define SQLT_AVC     97    // CHARZ
#define SQLT_IBFLOAT  100  // Binary FLOAT (BINARY_FLOAT)
#define SQLT_IBDOUBLE 101  // Binary DOUBLE (BINARY_DOUBLE)
#define SQLT_RDD    104    // ROWID descriptor
#define SQLT_NTY    108    // Named type (Object type, VARRAY, nested table)
#define SQLT_CLOB   112    // CLOB
#define SQLT_BLOB   113    // BLOB
#define SQLT_BFILEE 114    // BFILE
#define SQLT_TIMESTAMP       187  // TIMESTAMP
#define SQLT_TIMESTAMP_TZ    188  // TIMESTAMP WITH TIME ZONE
#define SQLT_INTERVAL_YM     189  // INTERVAL YEAR TO MONTH
#define SQLT_INTERVAL_DS     190  // INTERVAL DAY TO SECOND
#define SQLT_TIMESTAMP_LTZ   232  // TIMESTAMP WITH LOCAL TIME ZONE

// OCI Credentials
#define OCI_CRED_RDBMS  1
#define OCI_CRED_EXT    2

// OCI Mode flags
#define OCI_DEFAULT      0x00000000
#define OCI_THREADED     0x00000001
#define OCI_OBJECT       0x00000002
#define OCI_COMMIT_ON_SUCCESS  0x00000020
#define OCI_DESCRIBE_ONLY      0x00000010
#define OCI_STMT_SCROLLABLE_READONLY 0x00000008

// OCI Statement types
#define OCI_STMT_SELECT  1
#define OCI_STMT_UPDATE  2
#define OCI_STMT_DELETE  3
#define OCI_STMT_INSERT  4
#define OCI_STMT_CREATE  5
#define OCI_STMT_DROP    6
#define OCI_STMT_ALTER   7
#define OCI_STMT_BEGIN   8
#define OCI_STMT_DECLARE 9

// OCI Fetch orientation
#define OCI_FETCH_NEXT  2

// Opaque handle types — placeholder bodies for Swift UnsafeMutablePointer compatibility
struct OCIEnv { char _placeholder; };
typedef struct OCIEnv OCIEnv;

struct OCIError { char _placeholder; };
typedef struct OCIError OCIError;

struct OCISvcCtx { char _placeholder; };
typedef struct OCISvcCtx OCISvcCtx;

struct OCIStmt { char _placeholder; };
typedef struct OCIStmt OCIStmt;

struct OCIServer { char _placeholder; };
typedef struct OCIServer OCIServer;

struct OCISession { char _placeholder; };
typedef struct OCISession OCISession;

struct OCIDefine { char _placeholder; };
typedef struct OCIDefine OCIDefine;

struct OCIParam { char _placeholder; };
typedef struct OCIParam OCIParam;

struct OCIAuthInfo { char _placeholder; };
typedef struct OCIAuthInfo OCIAuthInfo;

// --- OCI Function Prototypes ---

// Environment
sword OCIEnvCreate(OCIEnv **envhpp, ub4 mode, const void *ctxp,
                   const void *(*malfp)(void *, size_t),
                   const void *(*ralfp)(void *, void *, size_t),
                   void (*mfreefp)(void *, void *),
                   size_t xtramem_sz, void **usrmempp);

// Handle allocation/free
sword OCIHandleAlloc(const void *parenth, void **hndlpp, ub4 type,
                     size_t xtramem_sz, void **usrmempp);
sword OCIHandleFree(void *hndlp, ub4 type);

// Attribute get/set
sword OCIAttrGet(const void *trgthndlp, ub4 trghndltyp,
                 void *attributep, ub4 *sizep, ub4 attrtype,
                 OCIError *errhp);
sword OCIAttrSet(void *trgthndlp, ub4 trghndltyp,
                 void *attributep, ub4 size, ub4 attrtype,
                 OCIError *errhp);

// Server attach/detach
sword OCIServerAttach(OCIServer *srvhp, OCIError *errhp,
                      const OraText *dblink, sb4 dblink_len, ub4 mode);
sword OCIServerDetach(OCIServer *srvhp, OCIError *errhp, ub4 mode);

// Session begin/end
sword OCISessionBegin(OCISvcCtx *svchp, OCIError *errhp,
                      OCISession *usrhp, ub4 creession, ub4 mode);
sword OCISessionEnd(OCISvcCtx *svchp, OCIError *errhp,
                    OCISession *usrhp, ub4 mode);

// Statement prepare/execute/fetch
sword OCIStmtPrepare(OCIStmt *stmtp, OCIError *errhp,
                     const OraText *stmt, ub4 stmt_len,
                     ub4 language, ub4 mode);
sword OCIStmtExecute(OCISvcCtx *svchp, OCIStmt *stmtp, OCIError *errhp,
                     ub4 iters, ub4 rowoff, const void *snap_in,
                     void *snap_out, ub4 mode);
sword OCIStmtFetch2(OCIStmt *stmtp, OCIError *errhp, ub4 nrows,
                    ub2 orientation, sb4 fetchOffset, ub4 mode);

// Define by position (for SELECT result binding)
sword OCIDefineByPos(OCIStmt *stmtp, OCIDefine **defnpp, OCIError *errhp,
                     ub4 position, void *valuep, sb4 value_sz,
                     ub2 dty, void *indp, ub2 *rlenp, ub2 *rcodep,
                     ub4 mode);

// Parameter descriptor
sword OCIParamGet(const void *hndlp, ub4 htype, OCIError *errhp,
                  void **parmdpp, ub4 pos);

// Transaction
sword OCITransCommit(OCISvcCtx *svchp, OCIError *errhp, ub4 flags);
sword OCITransRollback(OCISvcCtx *svchp, OCIError *errhp, ub4 flags);

// Error info
sword OCIErrorGet(void *hndlp, ub4 recordno, OraText *sqlstate,
                  sb4 *errcodep, OraText *bufp, ub4 bufsiz, ub4 type);

#endif // _OCI_STUB_H_
