use keepass_core::{VaultError, VaultService};

#[tokio::test]
async fn opens_configured_kdbx_fixture() {
    let (Ok(path), Ok(password)) = (
        std::env::var("KEEPASS_RS_TEST_KDBX"),
        std::env::var("KEEPASS_RS_TEST_PASSWORD"),
    ) else {
        return;
    };

    let vault = VaultService.open_local(&path, &password).await.unwrap();
    assert!(!vault.group_tree().id.is_empty());
}

#[tokio::test]
async fn wrong_password_returns_clear_error() {
    let (Ok(path), Ok(_password)) = (
        std::env::var("KEEPASS_RS_TEST_KDBX"),
        std::env::var("KEEPASS_RS_TEST_PASSWORD"),
    ) else {
        return;
    };

    let err = VaultService
        .open_local(&path, "this-is-clearly-the-wrong-password")
        .await
        .unwrap_err();

    let msg = err.to_string();
    assert!(
        msg.contains("KeePass") || msg.contains("key") || msg.contains("Incorrect"),
        "expected a credential-related error, got: {msg}"
    );
}

#[tokio::test]
async fn missing_file_returns_clear_error() {
    let err = VaultService
        .open_local("/nonexistent/path/to/database.kdbx", "irrelevant")
        .await
        .unwrap_err();

    assert!(matches!(err, VaultError::Io(_)));
    let msg = err.to_string();
    assert!(
        msg.contains("No such file") || msg.contains("not found"),
        "expected a file-not-found error, got: {msg}"
    );
}
