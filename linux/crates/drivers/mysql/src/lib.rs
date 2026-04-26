use std::str::FromStr;
use std::time::Duration;

use async_trait::async_trait;
use sqlx::mysql::{MySql, MySqlConnectOptions, MySqlPoolOptions, MySqlRow};
use sqlx::{Column, Pool, Row, TypeInfo};

use tablepro_core::{
    ColumnInfo, ConnectOptions, Connection, DatabaseDriver, DriverError, ExecResult, QueryResult, TableInfo, Value,
};

pub struct MysqlDriver;

#[async_trait]
impl DatabaseDriver for MysqlDriver {
    fn id(&self) -> &'static str {
        "mysql"
    }

    fn display_name(&self) -> &'static str {
        "MySQL"
    }

    fn default_port(&self) -> u16 {
        3306
    }

    async fn connect(&self, opts: ConnectOptions) -> Result<Box<dyn Connection>, DriverError> {
        let url = format!(
            "mysql://{}:{}@{}:{}/{}",
            opts.username, opts.password, opts.host, opts.port, opts.database,
        );
        let mysql_opts = MySqlConnectOptions::from_str(&url).map_err(map_sqlx_error)?;
        let pool = MySqlPoolOptions::new()
            .max_connections(4)
            .acquire_timeout(Duration::from_secs(5))
            .connect_with(mysql_opts)
            .await
            .map_err(map_sqlx_error)?;
        Ok(Box::new(MysqlConnection { pool }))
    }
}

struct MysqlConnection {
    pool: Pool<MySql>,
}

#[async_trait]
impl Connection for MysqlConnection {
    async fn list_tables(&self) -> Result<Vec<TableInfo>, DriverError> {
        let rows = sqlx::query(
            "SELECT table_schema, table_name
             FROM information_schema.tables
             WHERE table_schema = DATABASE()
             ORDER BY table_name",
        )
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(rows
            .into_iter()
            .map(|r| TableInfo {
                schema: Some(r.get::<String, _>(0)),
                name: r.get::<String, _>(1),
            })
            .collect())
    }

    async fn fetch_columns(&self, table: &str) -> Result<Vec<ColumnInfo>, DriverError> {
        let rows = sqlx::query(
            "SELECT column_name, data_type, is_nullable, column_key
             FROM information_schema.columns
             WHERE table_schema = DATABASE() AND table_name = ?
             ORDER BY ordinal_position",
        )
        .bind(table)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(rows
            .into_iter()
            .map(|r| ColumnInfo {
                name: r.get::<String, _>(0),
                data_type: r.get::<String, _>(1),
                nullable: r.get::<String, _>(2) == "YES",
                primary_key: r.get::<String, _>(3) == "PRI",
            })
            .collect())
    }

    async fn fetch_rows(&self, table: &str, offset: u64, limit: u64) -> Result<QueryResult, DriverError> {
        let safe = table.replace('`', "");
        let sql = format!("SELECT * FROM `{safe}` LIMIT {limit} OFFSET {offset}");
        self.query(&sql).await
    }

    async fn query(&self, sql: &str) -> Result<QueryResult, DriverError> {
        let rows = sqlx::query(sql).fetch_all(&self.pool).await.map_err(map_sqlx_error)?;
        if rows.is_empty() {
            return Ok(QueryResult {
                columns: Vec::new(),
                rows: Vec::new(),
            });
        }
        let columns: Vec<ColumnInfo> = rows[0]
            .columns()
            .iter()
            .map(|c| ColumnInfo {
                name: c.name().to_string(),
                data_type: c.type_info().name().to_string(),
                nullable: true,
                primary_key: false,
            })
            .collect();
        let data: Vec<Vec<Value>> = rows
            .iter()
            .map(|r| (0..columns.len()).map(|i| extract_value(r, i)).collect())
            .collect();
        Ok(QueryResult { columns, rows: data })
    }

    async fn execute(&self, sql: &str) -> Result<ExecResult, DriverError> {
        let res = sqlx::query(sql).execute(&self.pool).await.map_err(map_sqlx_error)?;
        Ok(ExecResult {
            rows_affected: res.rows_affected(),
        })
    }

    async fn execute_params(&self, sql: &str, params: &[Value]) -> Result<ExecResult, DriverError> {
        let mut q = sqlx::query(sql);
        for p in params {
            q = match p {
                Value::Null => q.bind(Option::<&str>::None),
                Value::Bool(b) => q.bind(*b),
                Value::Int(i) => q.bind(*i),
                Value::Float(f) => q.bind(*f),
                Value::Text(s) => q.bind(s.clone()),
                Value::Bytes(b) => q.bind(b.clone()),
                Value::Date(d) => q.bind(*d),
                Value::Time(t) => q.bind(*t),
                Value::DateTime(dt) => q.bind(*dt),
                Value::TimestampTz(ts) => q.bind(*ts),
                Value::Decimal(d) => q.bind(*d),
                Value::Uuid(u) => q.bind(u.to_string()),
                Value::Json(j) => q.bind(j.clone()),
            };
        }
        let res = q.execute(&self.pool).await.map_err(map_sqlx_error)?;
        Ok(ExecResult {
            rows_affected: res.rows_affected(),
        })
    }

    async fn ping(&self) -> Result<(), DriverError> {
        sqlx::query("SELECT 1")
            .execute(&self.pool)
            .await
            .map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn close(self: Box<Self>) -> Result<(), DriverError> {
        self.pool.close().await;
        Ok(())
    }
}

fn extract_value(row: &MySqlRow, idx: usize) -> Value {
    let type_name = row.columns()[idx].type_info().name().to_ascii_uppercase();
    match type_name.as_str() {
        "TINYINT" | "SMALLINT" | "INT" | "MEDIUMINT" | "BIGINT" => {
            row.try_get::<i64, _>(idx).map(Value::Int).unwrap_or(Value::Null)
        }
        "FLOAT" | "DOUBLE" => row.try_get::<f64, _>(idx).map(Value::Float).unwrap_or(Value::Null),
        "DECIMAL" | "NUMERIC" => row
            .try_get::<rust_decimal::Decimal, _>(idx)
            .map(Value::Decimal)
            .unwrap_or(Value::Null),
        "BOOLEAN" => row.try_get::<bool, _>(idx).map(Value::Bool).unwrap_or(Value::Null),
        "DATE" => row
            .try_get::<chrono::NaiveDate, _>(idx)
            .map(Value::Date)
            .unwrap_or(Value::Null),
        "TIME" => row
            .try_get::<chrono::NaiveTime, _>(idx)
            .map(Value::Time)
            .unwrap_or(Value::Null),
        "DATETIME" => row
            .try_get::<chrono::NaiveDateTime, _>(idx)
            .map(Value::DateTime)
            .unwrap_or(Value::Null),
        "TIMESTAMP" => row
            .try_get::<chrono::DateTime<chrono::Utc>, _>(idx)
            .map(Value::TimestampTz)
            .unwrap_or(Value::Null),
        "JSON" => row
            .try_get::<serde_json::Value, _>(idx)
            .map(Value::Json)
            .unwrap_or(Value::Null),
        "BLOB" | "TINYBLOB" | "MEDIUMBLOB" | "LONGBLOB" | "VARBINARY" | "BINARY" => {
            row.try_get::<Vec<u8>, _>(idx).map(Value::Bytes).unwrap_or(Value::Null)
        }
        _ => row.try_get::<String, _>(idx).map(Value::Text).unwrap_or(Value::Null),
    }
}

fn map_sqlx_error(err: sqlx::Error) -> DriverError {
    use sqlx::Error::*;
    match err {
        Database(e) => DriverError::Query {
            message: e.message().to_string(),
            sqlstate: e.code().map(|c| c.to_string()),
        },
        Io(e) if e.kind() == std::io::ErrorKind::ConnectionRefused => DriverError::ConnectionRefused,
        Tls(e) => DriverError::Tls(e.to_string()),
        PoolClosed | PoolTimedOut => DriverError::Disconnected,
        other => DriverError::Internal(format!("{other}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn driver_metadata() {
        let d = MysqlDriver;
        assert_eq!(d.id(), "mysql");
        assert_eq!(d.display_name(), "MySQL");
        assert_eq!(d.default_port(), 3306);
    }

    #[test]
    fn map_io_refused_returns_connection_refused() {
        let err = sqlx::Error::Io(std::io::Error::from(std::io::ErrorKind::ConnectionRefused));
        assert!(matches!(map_sqlx_error(err), DriverError::ConnectionRefused));
    }
}
