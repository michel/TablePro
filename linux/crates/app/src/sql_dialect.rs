use thiserror::Error;

use tablepro_core::{ColumnInfo, Value};

#[derive(Debug, Error)]
pub enum BuildSqlError {
    #[error("table has no primary key")]
    NoPrimaryKey,

    #[error("nothing to update")]
    NothingToUpdate,

    #[error("new_values length {got} does not match columns length {expected}")]
    LengthMismatch { expected: usize, got: usize },
}

pub fn quote_ident(driver_id: &str, name: &str) -> String {
    if driver_id == "mysql" {
        format!("`{}`", name.replace('`', "``"))
    } else {
        format!("\"{}\"", name.replace('"', "\"\""))
    }
}

pub fn placeholder_for(driver_id: &str, index: usize) -> String {
    if driver_id == "postgres" {
        format!("${}", index + 1)
    } else {
        "?".to_string()
    }
}

pub fn build_single_cell_update(
    driver_id: &str,
    table: &str,
    columns: &[ColumnInfo],
    original_row: &[Value],
    col_index: usize,
    new_value: Value,
) -> Result<(String, Vec<Value>), BuildSqlError> {
    let pk_indexes = collect_pk_indexes(columns);
    if pk_indexes.is_empty() {
        return Err(BuildSqlError::NoPrimaryKey);
    }
    if original_row.len() != columns.len() {
        return Err(BuildSqlError::LengthMismatch {
            expected: columns.len(),
            got: original_row.len(),
        });
    }

    let mut params: Vec<Value> = Vec::with_capacity(1 + pk_indexes.len());
    let mut placeholder_idx = 0;

    let set_clause = format!(
        "{} = {}",
        quote_ident(driver_id, &columns[col_index].name),
        placeholder_for(driver_id, placeholder_idx)
    );
    placeholder_idx += 1;
    params.push(new_value);

    let where_clause = build_where_clause(
        driver_id,
        columns,
        &pk_indexes,
        original_row,
        &mut placeholder_idx,
        &mut params,
    );

    let sql = format!(
        "UPDATE {} SET {} WHERE {}",
        quote_ident(driver_id, table),
        set_clause,
        where_clause
    );
    Ok((sql, params))
}

pub fn build_full_row_update(
    driver_id: &str,
    table: &str,
    columns: &[ColumnInfo],
    original_row: &[Value],
    new_values: &[Value],
) -> Result<(String, Vec<Value>), BuildSqlError> {
    let pk_indexes = collect_pk_indexes(columns);
    if pk_indexes.is_empty() {
        return Err(BuildSqlError::NoPrimaryKey);
    }
    if new_values.len() != columns.len() {
        return Err(BuildSqlError::LengthMismatch {
            expected: columns.len(),
            got: new_values.len(),
        });
    }
    if original_row.len() != columns.len() {
        return Err(BuildSqlError::LengthMismatch {
            expected: columns.len(),
            got: original_row.len(),
        });
    }

    let mut params: Vec<Value> = Vec::new();
    let mut placeholder_idx = 0;

    let mut set_clauses = Vec::new();
    for (i, col) in columns.iter().enumerate() {
        if col.primary_key {
            continue;
        }
        set_clauses.push(format!(
            "{} = {}",
            quote_ident(driver_id, &col.name),
            placeholder_for(driver_id, placeholder_idx)
        ));
        placeholder_idx += 1;
        params.push(new_values[i].clone());
    }
    if set_clauses.is_empty() {
        return Err(BuildSqlError::NothingToUpdate);
    }

    let where_clause = build_where_clause(
        driver_id,
        columns,
        &pk_indexes,
        original_row,
        &mut placeholder_idx,
        &mut params,
    );

    let sql = format!(
        "UPDATE {} SET {} WHERE {}",
        quote_ident(driver_id, table),
        set_clauses.join(", "),
        where_clause
    );
    Ok((sql, params))
}

fn collect_pk_indexes(columns: &[ColumnInfo]) -> Vec<usize> {
    columns
        .iter()
        .enumerate()
        .filter(|(_, c)| c.primary_key)
        .map(|(i, _)| i)
        .collect()
}

fn build_where_clause(
    driver_id: &str,
    columns: &[ColumnInfo],
    pk_indexes: &[usize],
    original_row: &[Value],
    placeholder_idx: &mut usize,
    params: &mut Vec<Value>,
) -> String {
    let mut clauses = Vec::with_capacity(pk_indexes.len());
    for pk_col in pk_indexes {
        clauses.push(format!(
            "{} = {}",
            quote_ident(driver_id, &columns[*pk_col].name),
            placeholder_for(driver_id, *placeholder_idx)
        ));
        *placeholder_idx += 1;
        params.push(original_row[*pk_col].clone());
    }
    clauses.join(" AND ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn col(name: &str, pk: bool) -> ColumnInfo {
        ColumnInfo {
            name: name.into(),
            data_type: "text".into(),
            nullable: false,
            primary_key: pk,
        }
    }

    #[test]
    fn quote_ident_dialect() {
        assert_eq!(quote_ident("postgres", "users"), "\"users\"");
        assert_eq!(quote_ident("sqlite", "users"), "\"users\"");
        assert_eq!(quote_ident("mysql", "users"), "`users`");
    }

    #[test]
    fn quote_ident_doubles_embedded_delimiter() {
        assert_eq!(quote_ident("postgres", "foo\"bar"), "\"foo\"\"bar\"");
        assert_eq!(quote_ident("mysql", "foo`bar"), "`foo``bar`");
    }

    #[test]
    fn placeholder_dialect() {
        assert_eq!(placeholder_for("postgres", 0), "$1");
        assert_eq!(placeholder_for("postgres", 2), "$3");
        assert_eq!(placeholder_for("sqlite", 0), "?");
        assert_eq!(placeholder_for("mysql", 5), "?");
    }

    #[test]
    fn single_cell_update_postgres() {
        let columns = vec![col("id", true), col("name", false)];
        let original = vec![Value::Int(7), Value::Text("alice".into())];
        let (sql, params) =
            build_single_cell_update("postgres", "u", &columns, &original, 1, Value::Text("bob".into())).unwrap();
        assert_eq!(sql, "UPDATE \"u\" SET \"name\" = $1 WHERE \"id\" = $2");
        assert_eq!(params, vec![Value::Text("bob".into()), Value::Int(7)]);
    }

    #[test]
    fn single_cell_update_mysql() {
        let columns = vec![col("id", true), col("name", false)];
        let original = vec![Value::Int(7), Value::Text("alice".into())];
        let (sql, params) =
            build_single_cell_update("mysql", "u", &columns, &original, 1, Value::Text("bob".into())).unwrap();
        assert_eq!(sql, "UPDATE `u` SET `name` = ? WHERE `id` = ?");
        assert_eq!(params, vec![Value::Text("bob".into()), Value::Int(7)]);
    }

    #[test]
    fn single_cell_update_sqlite() {
        let columns = vec![col("id", true), col("v", false)];
        let original = vec![Value::Int(1), Value::Text("a".into())];
        let (sql, _) =
            build_single_cell_update("sqlite", "t", &columns, &original, 1, Value::Text("b".into())).unwrap();
        assert_eq!(sql, "UPDATE \"t\" SET \"v\" = ? WHERE \"id\" = ?");
    }

    #[test]
    fn single_cell_update_no_pk() {
        let columns = vec![col("a", false), col("b", false)];
        let original = vec![Value::Int(1), Value::Int(2)];
        let err = build_single_cell_update("sqlite", "t", &columns, &original, 0, Value::Int(9)).unwrap_err();
        assert!(matches!(err, BuildSqlError::NoPrimaryKey));
    }

    #[test]
    fn single_cell_update_composite_pk() {
        let columns = vec![col("a", true), col("b", true), col("c", false)];
        let original = vec![Value::Int(1), Value::Int(2), Value::Text("x".into())];
        let (sql, params) =
            build_single_cell_update("postgres", "t", &columns, &original, 2, Value::Text("y".into())).unwrap();
        assert_eq!(sql, "UPDATE \"t\" SET \"c\" = $1 WHERE \"a\" = $2 AND \"b\" = $3");
        assert_eq!(params.len(), 3);
    }

    #[test]
    fn full_row_update_skips_pk() {
        let columns = vec![col("id", true), col("name", false), col("age", false)];
        let original = vec![Value::Int(3), Value::Text("a".into()), Value::Int(20)];
        let new_values = vec![Value::Int(3), Value::Text("b".into()), Value::Int(21)];
        let (sql, params) = build_full_row_update("mysql", "p", &columns, &original, &new_values).unwrap();
        assert_eq!(sql, "UPDATE `p` SET `name` = ?, `age` = ? WHERE `id` = ?");
        assert_eq!(params.len(), 3);
        assert_eq!(params[2], Value::Int(3));
    }

    #[test]
    fn full_row_update_length_mismatch() {
        let columns = vec![col("id", true), col("v", false)];
        let original = vec![Value::Int(1), Value::Int(2)];
        let new_values = vec![Value::Int(1)];
        let err = build_full_row_update("postgres", "t", &columns, &original, &new_values).unwrap_err();
        assert!(matches!(err, BuildSqlError::LengthMismatch { expected: 2, got: 1 }));
    }
}
