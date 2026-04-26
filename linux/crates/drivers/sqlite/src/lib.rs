use std::str::FromStr;
use std::time::Duration;

use async_trait::async_trait;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions, SqliteRow};
use sqlx::{Column, Pool, Row, Sqlite, TypeInfo};

use tablepro_core::{
    ColumnInfo, ConnectOptions, Connection, DatabaseDriver, DriverError, ExecResult, QueryResult, TableInfo, Value,
};

pub struct SqliteDriver;

#[async_trait]
impl DatabaseDriver for SqliteDriver {
    fn id(&self) -> &'static str {
        "sqlite"
    }

    fn display_name(&self) -> &'static str {
        "SQLite"
    }

    fn default_port(&self) -> u16 {
        0
    }

    async fn connect(&self, opts: ConnectOptions) -> Result<Box<dyn Connection>, DriverError> {
        let url = if opts.database.is_empty() || opts.database == ":memory:" {
            "sqlite::memory:".to_string()
        } else {
            format!("sqlite:{}", opts.database)
        };
        let connect_opts = SqliteConnectOptions::from_str(&url)
            .map_err(map_sqlx_error)?
            .create_if_missing(true);
        let pool = SqlitePoolOptions::new()
            .max_connections(4)
            .acquire_timeout(Duration::from_secs(5))
            .connect_with(connect_opts)
            .await
            .map_err(map_sqlx_error)?;
        Ok(Box::new(SqliteConnection { pool }))
    }
}

struct SqliteConnection {
    pool: Pool<Sqlite>,
}

#[async_trait]
impl Connection for SqliteConnection {
    async fn list_tables(&self) -> Result<Vec<TableInfo>, DriverError> {
        let rows = sqlx::query(
            "SELECT name FROM sqlite_master
             WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
             ORDER BY name",
        )
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(rows
            .into_iter()
            .map(|r| TableInfo {
                schema: None,
                name: r.get::<String, _>(0),
            })
            .collect())
    }

    async fn fetch_columns(&self, table: &str) -> Result<Vec<ColumnInfo>, DriverError> {
        let safe = table.replace('"', "");
        let sql = format!("PRAGMA table_info(\"{safe}\")");
        let rows = sqlx::query(&sql).fetch_all(&self.pool).await.map_err(map_sqlx_error)?;
        Ok(rows
            .into_iter()
            .map(|r| ColumnInfo {
                name: r.get::<String, _>(1),
                data_type: r.get::<String, _>(2),
                nullable: r.get::<i64, _>(3) == 0,
                primary_key: r.get::<i64, _>(5) > 0,
            })
            .collect())
    }

    async fn fetch_rows(&self, table: &str, offset: u64, limit: u64) -> Result<QueryResult, DriverError> {
        let safe = table.replace('"', "");
        let sql = format!("SELECT * FROM \"{safe}\" LIMIT {limit} OFFSET {offset}");
        let rows = sqlx::query(&sql).fetch_all(&self.pool).await.map_err(map_sqlx_error)?;
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

fn extract_value(row: &SqliteRow, idx: usize) -> Value {
    if let Ok(s) = row.try_get::<String, _>(idx) {
        return Value::Text(s);
    }
    if let Ok(v) = row.try_get::<i64, _>(idx) {
        return Value::Int(v);
    }
    if let Ok(v) = row.try_get::<f64, _>(idx) {
        return Value::Float(v);
    }
    if let Ok(v) = row.try_get::<bool, _>(idx) {
        return Value::Bool(v);
    }
    if let Ok(v) = row.try_get::<Vec<u8>, _>(idx) {
        return Value::Bytes(v);
    }
    Value::Null
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
    use tempfile::TempDir;

    fn opts_for(path: &str) -> ConnectOptions {
        ConnectOptions {
            database: path.to_string(),
            ..Default::default()
        }
    }

    #[tokio::test]
    async fn driver_metadata() {
        let d = SqliteDriver;
        assert_eq!(d.id(), "sqlite");
        assert_eq!(d.display_name(), "SQLite");
    }

    #[tokio::test]
    async fn connect_create_and_list_tables() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("test.db");
        let driver = SqliteDriver;
        let conn = driver.connect(opts_for(path.to_str().unwrap())).await.unwrap();
        conn.execute("CREATE TABLE foo (id INTEGER PRIMARY KEY, name TEXT)")
            .await
            .unwrap();
        conn.execute("INSERT INTO foo (name) VALUES ('a'), ('b'), ('c')")
            .await
            .unwrap();
        let tables = conn.list_tables().await.unwrap();
        assert_eq!(tables.len(), 1);
        assert_eq!(tables[0].name, "foo");
        let cols = conn.fetch_columns("foo").await.unwrap();
        assert_eq!(cols.len(), 2);
        assert_eq!(cols[0].name, "id");
        assert!(cols[0].primary_key);
        let result = conn.fetch_rows("foo", 0, 100).await.unwrap();
        assert_eq!(result.columns.len(), 2);
        assert_eq!(result.rows.len(), 3);
    }

    #[tokio::test]
    async fn fetch_rows_paginates() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("page.db");
        let driver = SqliteDriver;
        let conn = driver.connect(opts_for(path.to_str().unwrap())).await.unwrap();
        conn.execute("CREATE TABLE n (i INTEGER)").await.unwrap();
        for i in 1..=10 {
            conn.execute(&format!("INSERT INTO n VALUES ({i})")).await.unwrap();
        }
        let page = conn.fetch_rows("n", 5, 3).await.unwrap();
        assert_eq!(page.rows.len(), 3);
    }
}
