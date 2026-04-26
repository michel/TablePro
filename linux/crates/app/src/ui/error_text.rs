use tablepro_core::DriverError;

use crate::sql_dialect::BuildSqlError;

pub fn build_sql_message(error: &BuildSqlError) -> String {
    match error {
        BuildSqlError::NoPrimaryKey => "This table has no primary key. Use the modal Edit dialog instead.".into(),
        BuildSqlError::NothingToUpdate => "No changes to save.".into(),
        BuildSqlError::LengthMismatch { expected, got } => {
            format!("Internal column count mismatch (expected {expected}, got {got}).")
        }
    }
}

#[allow(dead_code)]
pub fn driver_message(error: &DriverError) -> String {
    match error {
        DriverError::ConnectionRefused => "Could not reach the database. Is it running?".into(),
        DriverError::AuthFailed => "Username or password is wrong.".into(),
        DriverError::Tls(detail) => format!("TLS handshake failed: {detail}"),
        DriverError::Query {
            message,
            sqlstate: Some(s),
        } => format!("Query failed (SQLSTATE {s}): {message}"),
        DriverError::Query { message, .. } => format!("Query failed: {message}"),
        DriverError::Disconnected => "The connection was closed. Try reconnecting.".into(),
        DriverError::Internal(detail) => format!("Internal driver error: {detail}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_sql_messages_have_actionable_advice() {
        let nopk = build_sql_message(&BuildSqlError::NoPrimaryKey);
        assert!(nopk.contains("Edit dialog"));
        let nothing = build_sql_message(&BuildSqlError::NothingToUpdate);
        assert!(nothing.contains("No changes"));
        let mismatch = build_sql_message(&BuildSqlError::LengthMismatch { expected: 3, got: 2 });
        assert!(mismatch.contains("expected 3"));
        assert!(mismatch.contains("got 2"));
    }

    #[test]
    fn driver_messages_include_sqlstate_when_present() {
        let with_state = driver_message(&DriverError::Query {
            message: "duplicate key".into(),
            sqlstate: Some("23505".into()),
        });
        assert!(with_state.contains("23505"));
        let without = driver_message(&DriverError::Query {
            message: "syntax error".into(),
            sqlstate: None,
        });
        assert!(!without.contains("SQLSTATE"));
        assert!(without.contains("syntax error"));
    }

    #[test]
    fn driver_message_for_simple_variants() {
        assert!(driver_message(&DriverError::ConnectionRefused).contains("Could not reach"));
        assert!(driver_message(&DriverError::AuthFailed).contains("wrong"));
        assert!(driver_message(&DriverError::Disconnected).contains("Try reconnecting"));
    }
}
