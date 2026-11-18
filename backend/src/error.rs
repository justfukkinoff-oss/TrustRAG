use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Authentication error: {0}")]
    Auth(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Forbidden: {0}")]
    Forbidden(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Internal error: {0}")]
    Internal(#[from] anyhow::Error),

    #[error("Local state error: {0}")]
    LocalState(String),
}

impl AppError {
    fn error_code(&self) -> &'static str {
        match self {
            AppError::Auth(_) => "AUTH_ERROR",
            AppError::NotFound(_) => "NOT_FOUND",
            AppError::Forbidden(_) => "FORBIDDEN",
            AppError::BadRequest(_) => "BAD_REQUEST",
            AppError::Conflict(_) => "CONFLICT",
            AppError::Database(_) => "DATABASE_ERROR",
            AppError::Internal(_) => "INTERNAL_ERROR",
            AppError::LocalState(_) => "LOCAL_STATE_ERROR",
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            AppError::Auth(msg) => (StatusCode::UNAUTHORIZED, msg.clone()),
            AppError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            AppError::Forbidden(msg) => (StatusCode::FORBIDDEN, msg.clone()),
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            AppError::Conflict(msg) => (StatusCode::CONFLICT, msg.clone()),
            AppError::Database(e) => {
                let err_str = e.to_string();
                tracing::error!(
                    error.kind = "database",
                    error.detail = %e,
                    "Database error occurred"
                );
                let user_msg = classify_db_error(&err_str);
                (StatusCode::INTERNAL_SERVER_ERROR, user_msg)
            }
            AppError::Internal(e) => {
                tracing::error!(
                    error.kind = "internal",
                    error.detail = %e,
                    error.chain = ?e.chain().skip(1).collect::<Vec<_>>(),
                    "Internal error occurred"
                );
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal error".into())
            }
            AppError::LocalState(msg) => {
                tracing::warn!(
                    error.kind = "local_state",
                    error.detail = %msg,
                    "Local state error"
                );
                (StatusCode::CONFLICT, msg.clone())
            }
        };

        let error_code = self.error_code();
        tracing::warn!(
            http.status = status.as_u16(),
            error.code = error_code,
            error.message = %message,
            "Request error response"
        );

        let body = serde_json::json!({
            "error": message,
            "code": error_code,
        });
        (status, axum::Json(body)).into_response()
    }
}

fn classify_db_error(err: &str) -> String {
    if err.contains("FOREIGN KEY constraint failed") {
        "The current logged in user does not match the local database. Please log in again or reset the local data.".into()
    } else if err.contains("no such table") || err.contains("no such column") {
        "The local database version is too old and incompatible with the current application version. Please reset the local database in settings or reinstall the app".into()
    } else if err.contains("UNIQUE constraint failed") {
        "Data conflict: record already exists".into()
    } else if err.contains("database is locked") {
        "The database is busy, please try again later".into()
    } else {
        "Database error".into()
    }
}
