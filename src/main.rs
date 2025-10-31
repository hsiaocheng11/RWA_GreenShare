// FILE: src/main.rs
use actix_cors::Cors;
use actix_web::{web, App, HttpServer, middleware::Logger};
use dotenv::dotenv;
use env_logger::Env;
use log::info;
use std::sync::Arc;
use tokio::sync::Mutex;

mod config;
mod crypto;
mod handlers;
mod models;
mod aggregator;
mod merkle;
mod seal;

use config::Config;
use aggregator::DataAggregator;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Load environment variables
    dotenv().ok();
    
    // Initialize logger
    env_logger::init_from_env(Env::default().default_filter_or("info"));
    
    // Load configuration
    let config = Config::from_env().expect("Failed to load configuration");
    let bind_address = format!("{}:{}", config.host, config.port);
    
    info!("🚀 Starting ROFL Enclave on {}", bind_address);
    info!("📊 Aggregation window: {} seconds", config.agg_window_sec);
    info!("📁 Output directory: {}", config.output_dir);
    
    // Create output directory if it doesn't exist
    tokio::fs::create_dir_all(&config.output_dir).await?;
    
    // Initialize shared state
    let aggregator = Arc::new(Mutex::new(DataAggregator::new(config.clone())));
    
    // Start HTTP server
    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(config.clone()))
            .app_data(web::Data::new(aggregator.clone()))
            .wrap(Logger::default())
            .wrap(
                Cors::default()
                    .allow_any_origin()
                    .allow_any_method()
                    .allow_any_header()
            )
            .service(
                web::scope("/api/v1")
                    .route("/ingest", web::post().to(handlers::ingest_data))
                    .route("/health", web::get().to(handlers::health_check))
                    .route("/status", web::get().to(handlers::get_status))
                    .route("/proofs/latest", web::get().to(handlers::get_latest_proof))
                    .route("/seal", web::post().to(handlers::seal_proof))
            )
            // Legacy routes (without /api/v1 prefix)
            .route("/ingest", web::post().to(handlers::ingest_data))
            .route("/health", web::get().to(handlers::health_check))
            .route("/status", web::get().to(handlers::get_status))
            .route("/proofs/latest", web::get().to(handlers::get_latest_proof))
            .route("/seal", web::post().to(handlers::seal_proof))
    })
    .bind(&bind_address)?
    .run()
    .await
}