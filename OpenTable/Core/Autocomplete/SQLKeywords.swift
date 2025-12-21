//
//  SQLKeywords.swift
//  OpenTable
//
//  Static catalogue of SQL keywords, functions, and operators
//

import Foundation

/// Static catalogue of SQL language elements for autocomplete
enum SQLKeywords {
    
    // MARK: - Keywords
    
    /// Primary SQL keywords
    static let keywords: [String] = [
        // DQL
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "AS",
        "DISTINCT", "ALL", "TOP",
        
        // Joins
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS",
        "ON", "USING",
        
        // Ordering & Grouping
        "ORDER", "BY", "ASC", "DESC", "NULLS", "FIRST", "LAST",
        "GROUP", "HAVING",
        
        // Limiting
        "LIMIT", "OFFSET", "FETCH", "NEXT", "ROWS", "ONLY",
        
        // Set operations
        "UNION", "INTERSECT", "EXCEPT", "MINUS",
        
        // Subqueries
        "IN", "EXISTS", "ANY", "SOME",
        
        // DML
        "INSERT", "INTO", "VALUES", "DEFAULT",
        "UPDATE", "SET",
        "DELETE", "TRUNCATE",
        
        // DDL
        "CREATE", "ALTER", "DROP", "RENAME", "MODIFY",
        "TABLE", "VIEW", "INDEX", "DATABASE", "SCHEMA",
        "COLUMN", "CONSTRAINT", "PRIMARY", "FOREIGN", "KEY",
        "REFERENCES", "UNIQUE", "CHECK", "DEFAULT",
        "AUTO_INCREMENT", "AUTOINCREMENT", "SERIAL",
        
        // Data types (common)
        "INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT",
        "DECIMAL", "NUMERIC", "FLOAT", "DOUBLE", "REAL",
        "VARCHAR", "CHAR", "TEXT", "BLOB", "CLOB",
        "DATE", "TIME", "DATETIME", "TIMESTAMP", "YEAR",
        "BOOLEAN", "BOOL", "BIT",
        "JSON", "JSONB", "XML",
        "UUID", "BINARY", "VARBINARY",
        
        // Conditionals
        "CASE", "WHEN", "THEN", "ELSE", "END",
        "IF", "IFNULL", "NULLIF", "COALESCE",
        
        // Comparison
        "BETWEEN", "LIKE", "ILIKE", "SIMILAR", "REGEXP", "RLIKE",
        "IS", "NULL", "TRUE", "FALSE", "UNKNOWN",
        
        // Transactions
        "BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "TRANSACTION",
        
        // Other
        "WITH", "RECURSIVE", "TEMPORARY", "TEMP", "IF",
        "CASCADE", "RESTRICT", "NO", "ACTION",
        "EXPLAIN", "ANALYZE", "DESCRIBE", "SHOW"
    ]
    
    // MARK: - Functions
    
    /// Aggregate functions
    static let aggregateFunctions: [(name: String, signature: String, doc: String)] = [
        ("COUNT", "COUNT(expr)", "Count rows or non-null values"),
        ("SUM", "SUM(expr)", "Sum of values"),
        ("AVG", "AVG(expr)", "Average of values"),
        ("MIN", "MIN(expr)", "Minimum value"),
        ("MAX", "MAX(expr)", "Maximum value"),
        ("GROUP_CONCAT", "GROUP_CONCAT(expr)", "Concatenate grouped values"),
        ("STRING_AGG", "STRING_AGG(expr, sep)", "PostgreSQL string aggregation"),
        ("ARRAY_AGG", "ARRAY_AGG(expr)", "Aggregate into array"),
    ]
    
    /// Date/Time functions
    static let dateTimeFunctions: [(name: String, signature: String, doc: String)] = [
        ("NOW", "NOW()", "Current date and time"),
        ("CURRENT_TIMESTAMP", "CURRENT_TIMESTAMP", "Current timestamp"),
        ("CURRENT_DATE", "CURRENT_DATE", "Current date"),
        ("CURRENT_TIME", "CURRENT_TIME", "Current time"),
        ("CURDATE", "CURDATE()", "Current date (MySQL)"),
        ("CURTIME", "CURTIME()", "Current time (MySQL)"),
        ("SYSDATE", "SYSDATE()", "System date (MySQL)"),
        ("UTC_TIMESTAMP", "UTC_TIMESTAMP()", "Current UTC timestamp"),
        ("UTC_DATE", "UTC_DATE()", "Current UTC date"),
        ("UTC_TIME", "UTC_TIME()", "Current UTC time"),
        ("DATE", "DATE(expr)", "Extract date part"),
        ("TIME", "TIME(expr)", "Extract time part"),
        ("YEAR", "YEAR(date)", "Extract year"),
        ("MONTH", "MONTH(date)", "Extract month"),
        ("DAY", "DAY(date)", "Extract day"),
        ("HOUR", "HOUR(time)", "Extract hour"),
        ("MINUTE", "MINUTE(time)", "Extract minute"),
        ("SECOND", "SECOND(time)", "Extract second"),
        ("DAYOFWEEK", "DAYOFWEEK(date)", "Day of week (1=Sunday)"),
        ("DAYOFMONTH", "DAYOFMONTH(date)", "Day of month"),
        ("DAYOFYEAR", "DAYOFYEAR(date)", "Day of year"),
        ("WEEK", "WEEK(date)", "Week number"),
        ("QUARTER", "QUARTER(date)", "Quarter (1-4)"),
        ("DATE_ADD", "DATE_ADD(date, INTERVAL)", "Add interval to date"),
        ("DATE_SUB", "DATE_SUB(date, INTERVAL)", "Subtract interval from date"),
        ("DATEDIFF", "DATEDIFF(date1, date2)", "Difference in days"),
        ("TIMESTAMPDIFF", "TIMESTAMPDIFF(unit, t1, t2)", "Difference in specified unit"),
        ("DATE_FORMAT", "DATE_FORMAT(date, format)", "Format date"),
        ("STR_TO_DATE", "STR_TO_DATE(str, format)", "Parse string to date"),
        ("UNIX_TIMESTAMP", "UNIX_TIMESTAMP(date)", "Unix timestamp"),
        ("FROM_UNIXTIME", "FROM_UNIXTIME(ts)", "Date from Unix timestamp"),
    ]
    
    /// String functions
    static let stringFunctions: [(name: String, signature: String, doc: String)] = [
        ("CONCAT", "CONCAT(str1, str2, ...)", "Concatenate strings"),
        ("CONCAT_WS", "CONCAT_WS(sep, str1, ...)", "Concatenate with separator"),
        ("SUBSTRING", "SUBSTRING(str, start, len)", "Extract substring"),
        ("SUBSTR", "SUBSTR(str, start, len)", "Extract substring"),
        ("LEFT", "LEFT(str, len)", "Left part of string"),
        ("RIGHT", "RIGHT(str, len)", "Right part of string"),
        ("LENGTH", "LENGTH(str)", "String length in bytes"),
        ("CHAR_LENGTH", "CHAR_LENGTH(str)", "String length in characters"),
        ("UPPER", "UPPER(str)", "Convert to uppercase"),
        ("LOWER", "LOWER(str)", "Convert to lowercase"),
        ("TRIM", "TRIM(str)", "Remove leading/trailing spaces"),
        ("LTRIM", "LTRIM(str)", "Remove leading spaces"),
        ("RTRIM", "RTRIM(str)", "Remove trailing spaces"),
        ("REPLACE", "REPLACE(str, from, to)", "Replace occurrences"),
        ("REVERSE", "REVERSE(str)", "Reverse string"),
        ("REPEAT", "REPEAT(str, count)", "Repeat string"),
        ("LPAD", "LPAD(str, len, pad)", "Left pad string"),
        ("RPAD", "RPAD(str, len, pad)", "Right pad string"),
        ("INSTR", "INSTR(str, substr)", "Position of substring"),
        ("LOCATE", "LOCATE(substr, str)", "Position of substring"),
        ("POSITION", "POSITION(substr IN str)", "Position of substring"),
        ("FORMAT", "FORMAT(number, decimals)", "Format number"),
        ("SPACE", "SPACE(n)", "Return n spaces"),
        ("ASCII", "ASCII(str)", "ASCII code of first char"),
        ("CHAR", "CHAR(n)", "Character from ASCII code"),
        ("MD5", "MD5(str)", "MD5 hash"),
        ("SHA1", "SHA1(str)", "SHA1 hash"),
        ("SHA2", "SHA2(str, bits)", "SHA2 hash"),
    ]
    
    /// Numeric functions
    static let numericFunctions: [(name: String, signature: String, doc: String)] = [
        ("ABS", "ABS(n)", "Absolute value"),
        ("ROUND", "ROUND(n, decimals)", "Round to decimals"),
        ("FLOOR", "FLOOR(n)", "Round down"),
        ("CEIL", "CEIL(n)", "Round up"),
        ("CEILING", "CEILING(n)", "Round up"),
        ("TRUNCATE", "TRUNCATE(n, decimals)", "Truncate to decimals"),
        ("MOD", "MOD(n, m)", "Modulo"),
        ("POW", "POW(x, y)", "Power"),
        ("POWER", "POWER(x, y)", "Power"),
        ("SQRT", "SQRT(n)", "Square root"),
        ("EXP", "EXP(n)", "e^n"),
        ("LOG", "LOG(n)", "Natural logarithm"),
        ("LOG10", "LOG10(n)", "Base-10 logarithm"),
        ("LOG2", "LOG2(n)", "Base-2 logarithm"),
        ("SIGN", "SIGN(n)", "Sign of number (-1, 0, 1)"),
        ("RAND", "RAND()", "Random number 0-1"),
        ("GREATEST", "GREATEST(v1, v2, ...)", "Greatest value"),
        ("LEAST", "LEAST(v1, v2, ...)", "Least value"),
    ]
    
    /// Null handling functions
    static let nullFunctions: [(name: String, signature: String, doc: String)] = [
        ("COALESCE", "COALESCE(v1, v2, ...)", "First non-null value"),
        ("IFNULL", "IFNULL(expr, alt)", "Return alt if expr is null"),
        ("NULLIF", "NULLIF(expr1, expr2)", "Null if expr1 = expr2"),
        ("NVL", "NVL(expr, alt)", "Return alt if expr is null (Oracle)"),
        ("ISNULL", "ISNULL(expr)", "Check if null"),
    ]
    
    /// Type conversion functions
    static let conversionFunctions: [(name: String, signature: String, doc: String)] = [
        ("CAST", "CAST(expr AS type)", "Convert to type"),
        ("CONVERT", "CONVERT(expr, type)", "Convert to type"),
        ("BINARY", "BINARY(str)", "Convert to binary string"),
    ]
    
    /// Window functions
    static let windowFunctions: [(name: String, signature: String, doc: String)] = [
        ("ROW_NUMBER", "ROW_NUMBER() OVER(...)", "Sequential row number"),
        ("RANK", "RANK() OVER(...)", "Rank with gaps"),
        ("DENSE_RANK", "DENSE_RANK() OVER(...)", "Rank without gaps"),
        ("NTILE", "NTILE(n) OVER(...)", "Divide into n groups"),
        ("LAG", "LAG(expr, offset, default) OVER(...)", "Previous row value"),
        ("LEAD", "LEAD(expr, offset, default) OVER(...)", "Next row value"),
        ("FIRST_VALUE", "FIRST_VALUE(expr) OVER(...)", "First value in partition"),
        ("LAST_VALUE", "LAST_VALUE(expr) OVER(...)", "Last value in partition"),
        ("NTH_VALUE", "NTH_VALUE(expr, n) OVER(...)", "Nth value in partition"),
        ("PERCENT_RANK", "PERCENT_RANK() OVER(...)", "Relative rank (0-1)"),
        ("CUME_DIST", "CUME_DIST() OVER(...)", "Cumulative distribution"),
    ]
    
    /// JSON functions (MySQL/PostgreSQL)
    static let jsonFunctions: [(name: String, signature: String, doc: String)] = [
        ("JSON_EXTRACT", "JSON_EXTRACT(json, path)", "Extract value from JSON"),
        ("JSON_OBJECT", "JSON_OBJECT(key, value, ...)", "Create JSON object"),
        ("JSON_ARRAY", "JSON_ARRAY(val1, val2, ...)", "Create JSON array"),
        ("JSON_KEYS", "JSON_KEYS(json)", "Get JSON object keys"),
        ("JSON_LENGTH", "JSON_LENGTH(json)", "Get JSON length"),
        ("JSON_TYPE", "JSON_TYPE(json)", "Get JSON value type"),
        ("JSON_VALID", "JSON_VALID(json)", "Check if valid JSON"),
        ("JSON_CONTAINS", "JSON_CONTAINS(json, val)", "Check if JSON contains value"),
        ("JSON_SET", "JSON_SET(json, path, val)", "Set value in JSON"),
        ("JSON_INSERT", "JSON_INSERT(json, path, val)", "Insert into JSON"),
        ("JSON_REPLACE", "JSON_REPLACE(json, path, val)", "Replace in JSON"),
        ("JSON_REMOVE", "JSON_REMOVE(json, path)", "Remove from JSON"),
        ("JSON_UNQUOTE", "JSON_UNQUOTE(json)", "Unquote JSON string"),
    ]
    
    /// All functions combined
    static var allFunctions: [(name: String, signature: String, doc: String)] {
        aggregateFunctions + dateTimeFunctions + stringFunctions +
        numericFunctions + nullFunctions + conversionFunctions +
        windowFunctions + jsonFunctions
    }
    
    // MARK: - Operators
    
    /// Comparison operators
    static let operators: [(symbol: String, doc: String)] = [
        ("=", "Equal to"),
        ("<>", "Not equal to"),
        ("!=", "Not equal to"),
        ("<", "Less than"),
        (">", "Greater than"),
        ("<=", "Less than or equal"),
        (">=", "Greater than or equal"),
        ("<=>", "Null-safe equal (MySQL)"),
    ]
    
    // MARK: - Snippets (Templates)
    
    /// Common SQL query snippets/templates
    static let snippets: [(name: String, template: String, doc: String)] = [
        // SELECT templates
        ("SELECT * FROM", "SELECT * FROM ", "Select all columns from table"),
        ("SELECT COUNT", "SELECT COUNT(*) FROM ", "Count rows in table"),
        ("SELECT DISTINCT", "SELECT DISTINCT  FROM ", "Select unique values"),
        ("SELECT TOP", "SELECT TOP 10 * FROM ", "Select top N rows"),
        ("SELECT WHERE", "SELECT * FROM  WHERE ", "Select with condition"),
        ("SELECT JOIN", "SELECT * FROM  INNER JOIN  ON ", "Select with join"),
        ("SELECT GROUP BY", "SELECT , COUNT(*) FROM  GROUP BY ", "Select with grouping"),
        ("SELECT ORDER BY", "SELECT * FROM  ORDER BY  ASC", "Select with ordering"),
        
        // Pagination
        ("SELECT LIMIT", "SELECT * FROM  LIMIT 10", "Select with limit"),
        ("SELECT LIMIT OFFSET", "SELECT * FROM  LIMIT 10 OFFSET 0", "Select with pagination"),
        
        // INSERT templates
        ("INSERT INTO", "INSERT INTO  (, ) VALUES (, )", "Insert new row"),
        ("INSERT SELECT", "INSERT INTO  SELECT * FROM ", "Insert from select"),
        ("INSERT MULTIPLE", "INSERT INTO  (, ) VALUES\n    (, ),\n    (, )", "Insert multiple rows"),
        
        // UPDATE templates
        ("UPDATE SET", "UPDATE  SET  =  WHERE ", "Update rows"),
        
        // DELETE templates
        ("DELETE FROM", "DELETE FROM  WHERE ", "Delete rows"),
        ("TRUNCATE TABLE", "TRUNCATE TABLE ", "Delete all rows (fast)"),
        
        // DDL templates
        ("CREATE TABLE", "CREATE TABLE  (\n    id INT PRIMARY KEY,\n    \n)", "Create new table"),
        ("ALTER TABLE ADD", "ALTER TABLE  ADD COLUMN  ", "Add column to table"),
        ("ALTER TABLE DROP", "ALTER TABLE  DROP COLUMN ", "Drop column from table"),
        ("DROP TABLE", "DROP TABLE IF EXISTS ", "Drop table"),
        
        // INDEX templates
        ("CREATE INDEX", "CREATE INDEX  ON  ()", "Create index"),
        ("DROP INDEX", "DROP INDEX ", "Drop index"),
        
        // Transaction templates
        ("BEGIN TRANSACTION", "BEGIN TRANSACTION;\n\nCOMMIT;", "Transaction block"),
        
        // CTE template
        ("WITH CTE", "WITH cte AS (\n    SELECT * FROM \n)\nSELECT * FROM cte", "Common Table Expression"),
        
        // CASE template
        ("CASE WHEN", "CASE\n    WHEN  THEN \n    ELSE \nEND", "Conditional expression"),
        
        // Subquery templates
        ("EXISTS SELECT", "EXISTS (SELECT 1 FROM  WHERE )", "Existence check"),
        ("NOT EXISTS", "NOT EXISTS (SELECT 1 FROM  WHERE )", "Non-existence check"),
        ("IN SELECT", "IN (SELECT  FROM  WHERE )", "Subquery in IN clause"),
        
        // Null handling
        ("COALESCE", "COALESCE(, )", "First non-null value"),
        ("IFNULL", "IFNULL(, )", "Replace null with default"),
        ("IS NULL", "IS NULL", "Check for NULL"),
        ("IS NOT NULL", "IS NOT NULL", "Check for non-NULL"),
        
        // Window function templates
        ("ROW_NUMBER OVER", "ROW_NUMBER() OVER (ORDER BY )", "Row numbering"),
        ("RANK OVER", "RANK() OVER (PARTITION BY  ORDER BY )", "Ranking with gaps"),
        ("LAG OVER", "LAG(, 1) OVER (ORDER BY )", "Previous row value"),
        ("SUM OVER", "SUM() OVER (PARTITION BY )", "Running total"),
        
        // Join templates
        ("LEFT JOIN ON", "LEFT JOIN  ON . = .", "Left outer join"),
        ("INNER JOIN ON", "INNER JOIN  ON . = .", "Inner join"),
        
        // MySQL specific
        ("ON DUPLICATE KEY", "INSERT INTO  () VALUES ()\nON DUPLICATE KEY UPDATE  = VALUES()", "Upsert (MySQL)"),
    ]
    
    // MARK: - Completion Items
    
    /// Get all keyword completion items
    static func keywordItems() -> [SQLCompletionItem] {
        keywords.map { SQLCompletionItem.keyword($0) }
    }
    
    /// Get all function completion items
    static func functionItems() -> [SQLCompletionItem] {
        allFunctions.map { fn in
            SQLCompletionItem.function(fn.name, signature: fn.signature, documentation: fn.doc)
        }
    }
    
    /// Get all operator completion items
    static func operatorItems() -> [SQLCompletionItem] {
        operators.map { op in
            SQLCompletionItem.operator(op.symbol, documentation: op.doc)
        }
    }
    
    /// Get all snippet completion items
    static func snippetItems() -> [SQLCompletionItem] {
        snippets.map { snippet in
            SQLCompletionItem.snippet(snippet.name, template: snippet.template, documentation: snippet.doc)
        }
    }
}
