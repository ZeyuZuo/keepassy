use clap::{Args, Parser, Subcommand};
use keepass_core::{VaultError, VaultService, VaultSession, WebDavConfig, WebDavCredentials};
use std::path::PathBuf;

#[derive(Debug, Parser)]
#[command(name = "keepass-rs")]
#[command(about = "Debug CLI for the keepass-rs backend core")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    Local {
        #[command(subcommand)]
        command: LocalCommand,
    },
    Webdav {
        #[command(subcommand)]
        command: WebDavCommand,
    },
}

#[derive(Debug, Subcommand)]
enum LocalCommand {
    Tree(LocalFileArgs),
    Entries(LocalEntriesArgs),
    Show(LocalEntryArgs),
}

#[derive(Debug, Subcommand)]
enum WebDavCommand {
    Tree(WebDavArgs),
}

#[derive(Debug, Args)]
struct LocalFileArgs {
    #[arg(long)]
    file: PathBuf,
    #[arg(long)]
    keyfile: Option<PathBuf>,
}

#[derive(Debug, Args)]
struct LocalEntriesArgs {
    #[arg(long)]
    file: PathBuf,
    #[arg(long)]
    keyfile: Option<PathBuf>,
    #[arg(long, value_name = "UUID")]
    group: String,
}

#[derive(Debug, Args)]
struct LocalEntryArgs {
    #[arg(long)]
    file: PathBuf,
    #[arg(long)]
    keyfile: Option<PathBuf>,
    #[arg(long, value_name = "UUID")]
    entry: String,
}

#[derive(Debug, Args)]
struct WebDavArgs {
    #[arg(long)]
    url: String,
    #[arg(long)]
    keyfile: Option<PathBuf>,
    #[arg(long, env = "KEEPASS_RS_WEBDAV_USERNAME")]
    username: Option<String>,
    #[arg(long, env = "KEEPASS_RS_WEBDAV_PASSWORD")]
    webdav_password: Option<String>,
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let service = VaultService;

    let result = run_command(&service, cli.command).await;

    if let Err(err) = result {
        eprintln!("error: {err}");
        std::process::exit(1);
    }
}

async fn run_command(service: &VaultService, command: Command) -> Result<(), VaultError> {
    match command {
        Command::Local { command } => match command {
            LocalCommand::Tree(args) => {
                let vault = open_local_session(service, &args.file, args.keyfile.as_ref()).await?;
                print_json(vault.group_tree())?;
            }
            LocalCommand::Entries(args) => {
                let vault = open_local_session(service, &args.file, args.keyfile.as_ref()).await?;
                print_json(vault.entries_for_group(&args.group)?)?;
            }
            LocalCommand::Show(args) => {
                let vault = open_local_session(service, &args.file, args.keyfile.as_ref()).await?;
                print_json(&vault.entry_detail(&args.entry)?)?;
            }
        },
        Command::Webdav { command } => match command {
            WebDavCommand::Tree(args) => {
                let mut config = WebDavConfig::new(&args.url)?;
                match (args.username, args.webdav_password) {
                    (Some(username), Some(password)) => {
                        config =
                            config.with_credentials(WebDavCredentials::new(username, password));
                    }
                    (None, None) => {}
                    _ => {
                        return Err(VaultError::Storage(
                            "both WebDAV username and password must be provided".to_string(),
                        ));
                    }
                };
                let vault = open_webdav_session(service, config, args.keyfile.as_ref()).await?;
                print_json(vault.group_tree())?;
            }
        },
    }

    Ok(())
}

async fn open_local_session(
    service: &VaultService,
    file: &PathBuf,
    keyfile: Option<&PathBuf>,
) -> Result<VaultSession, VaultError> {
    let password = read_master_password()?;
    match keyfile {
        Some(path) => {
            let bytes = read_keyfile(path).await?;
            service.open_local_with_keyfile(file, password, bytes).await
        }
        None => service.open_local(file, password).await,
    }
}

async fn open_webdav_session(
    service: &VaultService,
    config: WebDavConfig,
    keyfile: Option<&PathBuf>,
) -> Result<VaultSession, VaultError> {
    let password = read_master_password()?;
    match keyfile {
        Some(path) => {
            let bytes = read_keyfile(path).await?;
            service
                .open_webdav_with_keyfile(config, password, bytes)
                .await
        }
        None => service.open_webdav(config, password).await,
    }
}

async fn read_keyfile(path: &PathBuf) -> Result<Vec<u8>, VaultError> {
    tokio::fs::read(path).await.map_err(VaultError::Io)
}

fn read_master_password() -> Result<String, VaultError> {
    match std::env::var("KEEPASS_RS_PASSWORD") {
        Ok(password) => Ok(password),
        Err(std::env::VarError::NotPresent) => rpassword::prompt_password("Master password: ")
            .map_err(|err| VaultError::Storage(err.to_string())),
        Err(err) => Err(VaultError::Storage(err.to_string())),
    }
}

fn print_json<T: serde::Serialize + ?Sized>(value: &T) -> Result<(), VaultError> {
    let json =
        serde_json::to_string_pretty(value).map_err(|err| VaultError::Storage(err.to_string()))?;
    println!("{json}");
    Ok(())
}
